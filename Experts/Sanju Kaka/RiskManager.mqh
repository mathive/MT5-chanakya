//+------------------------------------------------------------------+
//|                                                  RiskManager.mqh |
//|                                  Copyright 2026, Sanju Kaka Algo |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Sanju Kaka Algo"
#property link      "https://www.mql5.com"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\AccountInfo.mqh>
#include "Defines.mqh"

class CRiskManager
{
private:
   CTrade            m_trade;
   CPositionInfo     m_position;
   CAccountInfo      m_account;
   
   double            m_baseLotPerThousand;
   double            m_amarvelHedgeDDPct;
   double            m_cockroachKillSwitchPct;
   int               m_coolOffHours;
   int               m_slippageBufferPoints;
   
   double            m_peakEquity;
   bool              m_killSwitchTriggered;
   datetime          m_killSwitchTriggerTime;
   bool              m_amarvelLocked[MODULE_COUNT];
   bool              m_moduleDailyKillSwitch[MODULE_COUNT];
   datetime          m_moduleKillSwitchTime[MODULE_COUNT];

public:
   CRiskManager() :
      m_baseLotPerThousand(0.01),
      m_amarvelHedgeDDPct(5.0),
      m_cockroachKillSwitchPct(20.0),
      m_coolOffHours(24),
      m_slippageBufferPoints(30),
      m_peakEquity(0.0),
      m_killSwitchTriggered(false),
      m_killSwitchTriggerTime(0)
   {
      ArrayInitialize(m_amarvelLocked, false);
      ArrayInitialize(m_moduleDailyKillSwitch, false);
      ArrayInitialize(m_moduleKillSwitchTime, 0);
      m_trade.SetDeviationInPoints(m_slippageBufferPoints);
      m_trade.SetTypeFilling(ORDER_FILLING_IOC);
   }
   
   void Init(double baseLot, double hedgeDD, double killSwitchDD, int coolOffH, int slippage)
   {
      m_baseLotPerThousand     = baseLot;
      m_amarvelHedgeDDPct      = hedgeDD;
      m_cockroachKillSwitchPct = killSwitchDD;
      m_coolOffHours           = coolOffH;
      m_slippageBufferPoints   = slippage;
      
      m_trade.SetDeviationInPoints(m_slippageBufferPoints);
      m_trade.SetAsyncMode(false);
      
      double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
      if(m_peakEquity < currentEquity)
         m_peakEquity = currentEquity;
   }
   
   //--- Calculate Fixed Lot Size (0.01 Lot)
   double CalculateLotSize(const string symbol, double fixedCustomLot = 0.01)
   {
      return NormalizeLot(symbol, 0.01);
   }
   
   //--- Normalize Lot with broker constraints
   double NormalizeLot(const string symbol, double lot)
   {
      double minLot  = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
      double maxLot  = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
      double lotStep = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
      
      if(lotStep <= 0.0) lotStep = 0.01;
      
      double normalized = MathFloor(lot / lotStep) * lotStep;
      if(normalized < minLot) normalized = minLot;
      if(normalized > maxLot) normalized = maxLot;
      
      return NormalizeDouble(normalized, 2);
   }
   
   //--- Update Peak Equity and Monitor Cockroach 80-20 Kill-Switch
   bool CheckGlobalCockroachKillSwitch(const string expertSymbol)
   {
      double balance = AccountInfoDouble(ACCOUNT_BALANCE);
      double equity  = AccountInfoDouble(ACCOUNT_EQUITY);
      
      if(equity > m_peakEquity)
         m_peakEquity = equity;
      
      // Calculate current equity drawdown relative to peak
      double drawdownPct = 0.0;
      if(m_peakEquity > 0.0)
         drawdownPct = ((m_peakEquity - equity) / m_peakEquity) * 100.0;
      
      // Trigger Cockroach 80-20 Hard Kill-Switch if Drawdown hits limit (e.g. 20%)
      if(drawdownPct >= m_cockroachKillSwitchPct && !m_killSwitchTriggered)
      {
         PrintFormat("[COCKROACH KILL-SWITCH TRIGGERED] Peak: %.2f, Current Equity: %.2f, DD: %.2f%% >= %.2f%% Limit! Liquidating all trades...",
                     m_peakEquity, equity, drawdownPct, m_cockroachKillSwitchPct);
         
         EmergencyCloseAllPositions();
         
         m_killSwitchTriggered   = true;
         m_killSwitchTriggerTime = TimeCurrent();
         return true;
      }
      
      // Handle 24-Hour Cool-Off Reset
      if(m_killSwitchTriggered)
      {
         datetime elapsed = TimeCurrent() - m_killSwitchTriggerTime;
         if(elapsed >= (datetime)(m_coolOffHours * 3600))
         {
            Print("[Risk Manager] 24-Hour Cool-Off period completed. EA re-activating for new trades.");
            m_killSwitchTriggered = false;
            m_peakEquity = AccountInfoDouble(ACCOUNT_EQUITY);
            ArrayInitialize(m_amarvelLocked, false);
         }
      }
      
      return m_killSwitchTriggered;
   }
   
   //--- Emergency Liquidation of ALL Open Positions Across Symbols & Magics
   void EmergencyCloseAllPositions()
   {
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket > 0 && m_position.SelectByTicket(ticket))
         {
            m_trade.SetDeviationInPoints(m_slippageBufferPoints * 3); // Extra slippage tolerance for fast exit
            bool closed = false;
            for(int retry = 0; retry < 5; retry++)
            {
               if(m_trade.PositionClose(ticket))
               {
                  PrintFormat("[Kill-Switch] Successfully closed ticket %I64d at market price.", ticket);
                  closed = true;
                  break;
               }
               Sleep(100);
            }
            if(!closed)
               PrintFormat("[Kill-Switch ERROR] Failed to close ticket %I64d. Code: %d", ticket, GetLastError());
         }
      }
   }
   
   //--- Amarvel Hedging Logic & Phase B Basket Recovery Unlocking
   void CheckAmarvelHedging(const string symbol, ulong magic, int moduleIndex)
   {
      if(moduleIndex < 0 || moduleIndex >= MODULE_COUNT) return;
      
      ulong hedgeMagic = MAGIC_HEDGE_BASE + (magic % 1000);
      double totalModuleBuyLots  = 0.0;
      double totalModuleSellLots = 0.0;
      double totalFloatingPnL    = 0.0;
      int tradeCount             = 0;
      
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket > 0 && m_position.SelectByTicket(ticket))
         {
            if(m_position.Symbol() == symbol && (m_position.Magic() == magic || m_position.Magic() == hedgeMagic))
            {
               totalFloatingPnL += m_position.Profit() + m_position.Swap();
               tradeCount++;
               if(m_position.PositionType() == POSITION_TYPE_BUY)
                  totalModuleBuyLots += m_position.Volume();
               else if(m_position.PositionType() == POSITION_TYPE_SELL)
                  totalModuleSellLots += m_position.Volume();
            }
         }
      }
      
      // Phase B: If module is currently Amarvel Locked, check if net hedged pair is back to profit or break-even
      if(m_amarvelLocked[moduleIndex])
      {
         if(tradeCount > 0 && totalFloatingPnL >= 0.0) // Recovered to Break-Even / Positive!
         {
            PrintFormat("[AMARVEL RECOVERY] Module %I64d Hedged Pair recovered to net profit: +$%.2f. Unlocking and closing hedged basket...",
                        magic, totalFloatingPnL);
                        
            for(int i = PositionsTotal() - 1; i >= 0; i--)
            {
               ulong ticket = PositionGetTicket(i);
               if(ticket > 0 && m_position.SelectByTicket(ticket))
               {
                  if(m_position.Symbol() == symbol && (m_position.Magic() == magic || m_position.Magic() == hedgeMagic))
                  {
                     m_trade.PositionClose(ticket);
                  }
               }
            }
            m_amarvelLocked[moduleIndex] = false;
            PrintFormat("[AMARVEL UNLOCKED] Module %I64d unlocked successfully with zero drawdown!", magic);
         }
         return;
      }
      
      double equity = AccountInfoDouble(ACCOUNT_EQUITY);
      if(equity <= 0.0) return;
      
      double moduleDDPct = 0.0;
      if(totalFloatingPnL < 0.0)
         moduleDDPct = (MathAbs(totalFloatingPnL) / equity) * 100.0;
      
      // Phase A: If module drawdown hits 5%, trigger Amarvel Equal & Opposite Hedge Freeze
      if(moduleDDPct >= m_amarvelHedgeDDPct)
      {
         double netVolume = totalModuleBuyLots - totalModuleSellLots;
         
         if(netVolume > 0.0)
         {
            // Net long: Open matching SELL hedge
            double hedgeLot = NormalizeLot(symbol, netVolume);
            m_trade.SetExpertMagicNumber(hedgeMagic);
            if(m_trade.Sell(hedgeLot, symbol, 0, 0, 0, "Amarvel Hedge Lock"))
            {
               m_amarvelLocked[moduleIndex] = true;
               PrintFormat("[AMARVEL HEDGE LOCK] Module %I64d hit %.2f%% DD. Opened %.2f SELL Hedge to freeze P&L (+ - = 0).",
                           magic, moduleDDPct, hedgeLot);
            }
         }
         else if(netVolume < 0.0)
         {
            // Net short: Open matching BUY hedge
            double hedgeLot = NormalizeLot(symbol, MathAbs(netVolume));
            m_trade.SetExpertMagicNumber(hedgeMagic);
            if(m_trade.Buy(hedgeLot, symbol, 0, 0, 0, "Amarvel Hedge Lock"))
            {
               m_amarvelLocked[moduleIndex] = true;
               PrintFormat("[AMARVEL HEDGE LOCK] Module %I64d hit %.2f%% DD. Opened %.2f BUY Hedge to freeze P&L (+ - = 0).",
                           magic, moduleDDPct, hedgeLot);
            }
         }
      }
   }
   
   //--- Check Daily 20% Kill-Switch per Module
   bool CheckModuleDailyKillSwitch(const string symbol, ulong magic, int moduleIndex)
   {
      if(moduleIndex < 0 || moduleIndex >= MODULE_COUNT) return false;
      
      // Auto-reset daily kill-switch after cool-off
      if(m_moduleDailyKillSwitch[moduleIndex])
      {
         if(TimeCurrent() - m_moduleKillSwitchTime[moduleIndex] >= (datetime)(m_coolOffHours * 3600))
         {
            PrintFormat("[Module Reset] Module %I64d daily kill-switch expired. Re-enabled for trading.", magic);
            m_moduleDailyKillSwitch[moduleIndex] = false;
         }
         else
         {
            return true; // Still killed for the day
         }
      }
      
      double totalFloatingPnL = 0.0;
      int count = 0;
      
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket > 0 && m_position.SelectByTicket(ticket))
         {
            if(m_position.Symbol() == symbol && m_position.Magic() == magic)
            {
               totalFloatingPnL += (m_position.Profit() + m_position.Swap());
               count++;
            }
         }
      }
      
      double equity = AccountInfoDouble(ACCOUNT_EQUITY);
      if(equity <= 0.0 || count == 0) return false;
      
      double moduleDDPct = 0.0;
      if(totalFloatingPnL < 0.0)
         moduleDDPct = (MathAbs(totalFloatingPnL) / equity) * 100.0;
      
      // If individual module floating loss hits 20%, trigger Module Kill-Switch
      if(moduleDDPct >= m_cockroachKillSwitchPct)
      {
         PrintFormat("[MODULE 20%% KILL-SWITCH] Module %I64d hit %.2f%% Drawdown (>= %.2f%% limit). Closing all its %d positions and disabling for the day!",
                     magic, moduleDDPct, m_cockroachKillSwitchPct, count);
                     
         for(int i = PositionsTotal() - 1; i >= 0; i--)
         {
            ulong ticket = PositionGetTicket(i);
            if(ticket > 0 && m_position.SelectByTicket(ticket))
            {
               if(m_position.Symbol() == symbol && (m_position.Magic() == magic || m_position.Magic() == (MAGIC_HEDGE_BASE + (magic % 1000))))
               {
                  m_trade.PositionClose(ticket);
               }
            }
         }
         
         m_moduleDailyKillSwitch[moduleIndex] = true;
         m_moduleKillSwitchTime[moduleIndex]  = TimeCurrent();
         return true;
      }
      
      return false;
   }
   
   //--- Check if specific module is disabled for the day
   bool IsModuleKilledForDay(int idx)
   {
      if(idx >= 0 && idx < MODULE_COUNT)
      {
         if(m_moduleDailyKillSwitch[idx])
         {
            if(TimeCurrent() - m_moduleKillSwitchTime[idx] >= (datetime)(m_coolOffHours * 3600))
            {
               m_moduleDailyKillSwitch[idx] = false;
               return false;
            }
            return true;
         }
      }
      return false;
   }
   
   //--- Getter functions for dashboard
   bool IsCoolOffActive() const { return m_killSwitchTriggered; }
   datetime GetCoolOffExpiry() const { return m_killSwitchTriggerTime + (datetime)(m_coolOffHours * 3600); }
   double GetPeakEquity() const { return m_peakEquity; }
   double GetCurrentDDPct() const
   {
      double eq = AccountInfoDouble(ACCOUNT_EQUITY);
      if(m_peakEquity <= 0.0) return 0.0;
      return ((m_peakEquity - eq) / m_peakEquity) * 100.0;
   }
   bool IsModuleAmarvelLocked(int idx) const
   {
      if(idx >= 0 && idx < MODULE_COUNT) return (m_amarvelLocked[idx] || m_moduleDailyKillSwitch[idx]);
      return false;
   }
};
