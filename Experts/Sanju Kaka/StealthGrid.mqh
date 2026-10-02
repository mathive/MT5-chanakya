//+------------------------------------------------------------------+
//|                                                  StealthGrid.mqh |
//|                                  Copyright 2026, Sanju Kaka Algo |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Sanju Kaka Algo"
#property link      "https://www.mql5.com"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include "Defines.mqh"

class CStealthGridEngine
{
private:
   CTrade            m_trade;
   CPositionInfo     m_position;
   
   SVirtualPosition  m_virtualPositions[];
   int               m_virtCount;
   
   bool              m_useTrailingUSD;
   double            m_targetProfitUSD;        // Target Profit in Dollars ($15.00)
   double            m_lossLimitUSD;           // Max Stop Loss in Dollars ($5.00)
   double            m_trailingStartUSD;       // Trailing Start Profit in Dollars ($10.00)
   double            m_trailingStopUSD;        // Trailing Retrace Drop in Dollars ($3.00)
   double            m_trailingStepUSD;        // Trailing Step in Dollars ($1.00)
   int               m_gridStepPoints;         // Smart Grid Step Spacing (Points)
   
   ulong             m_trackedMagics[50];
   double            m_basketPeakProfitUSD[50];
   int               m_trackedMagicCount;

public:
   CStealthGridEngine() :
      m_virtCount(0),
      m_useTrailingUSD(true),
      m_targetProfitUSD(15.0),
      m_lossLimitUSD(5.0),
      m_trailingStartUSD(10.0),
      m_trailingStopUSD(3.0),
      m_trailingStepUSD(1.0),
      m_gridStepPoints(200),
      m_trackedMagicCount(0)
   {
      ArrayResize(m_virtualPositions, 0);
      ArrayInitialize(m_trackedMagics, 0);
      ArrayInitialize(m_basketPeakProfitUSD, 0.0);
      m_trade.SetDeviationInPoints(20);
      m_trade.SetTypeFilling(ORDER_FILLING_IOC);
   }
   
   void Init(bool useTrailingUSD, double targetProfitUSD, double lossLimitUSD, 
             double trailingStartUSD, double trailingStopUSD, double trailingStepUSD, 
             int gridStepPoints)
   {
      m_useTrailingUSD   = useTrailingUSD;
      m_targetProfitUSD  = targetProfitUSD;
      m_lossLimitUSD     = lossLimitUSD;
      m_trailingStartUSD = trailingStartUSD;
      m_trailingStopUSD  = trailingStopUSD;
      m_trailingStepUSD  = trailingStepUSD;
      m_gridStepPoints   = gridStepPoints;
   }
   
   //--- Synchronize RAM array with live positions and monitor exits
   void OnTickProcess(const string symbol)
   {
      SyncPositionsWithRAM(symbol);
      ProcessVirtualExits(symbol);
      ProcessBasketClose(symbol);
   }
   
   //--- Keep RAM storage aligned with broker positions
   void SyncPositionsWithRAM(const string symbol)
   {
      int liveTotal = PositionsTotal();
      SVirtualPosition currentLive[];
      ArrayResize(currentLive, 0);
      
      for(int i = 0; i < liveTotal; i++)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket > 0 && m_position.SelectByTicket(ticket))
         {
            if(m_position.Symbol() != symbol) continue;
            
            ulong magic = m_position.Magic();
            ENUM_POSITION_TYPE pType = m_position.PositionType();
            double openPrice = m_position.PriceOpen();
            double curPrice  = m_position.PriceCurrent();
            double curProfit = m_position.Profit() + m_position.Swap();
            
            // Check if already in RAM array
            int existingIndex = FindRAMPosition(ticket);
            
            SVirtualPosition item;
            if(existingIndex >= 0)
            {
               item = m_virtualPositions[existingIndex];
               item.volume = m_position.Volume();
               
               // Update Trailing High / Low / Peak Dollar Profit
               if(pType == POSITION_TYPE_BUY)
               {
                  if(curPrice > item.highestPrice)
                     item.highestPrice = curPrice;
               }
               else if(pType == POSITION_TYPE_SELL)
               {
                  if(curPrice < item.lowestPrice || item.lowestPrice == 0.0)
                     item.lowestPrice = curPrice;
               }
               
               if(curProfit > item.peakProfitUSD)
                  item.peakProfitUSD = curProfit;
            }
            else
            {
               // New position detected, initialize RAM tracking in Dollars
               item.ticket       = ticket;
               item.magic        = magic;
               item.symbol       = symbol;
               item.type         = pType;
               item.openPrice    = openPrice;
               item.volume       = m_position.Volume();
               item.openTime     = (datetime)m_position.Time();
               item.highestPrice = openPrice;
               item.lowestPrice  = openPrice;
               item.peakProfitUSD= MathMax(0.0, curProfit);
               item.virtualTP    = 0.0;
               item.virtualSL    = 0.0;
               item.isHedged     = false;
               item.isAmarvelLock= (magic >= MAGIC_HEDGE_BASE);
            }
            
            int sz = ArraySize(currentLive);
            ArrayResize(currentLive, sz + 1);
            currentLive[sz] = item;
         }
      }
      
      // Update internal RAM array
      int liveSize = ArraySize(currentLive);
      ArrayResize(m_virtualPositions, liveSize);
      for(int k = 0; k < liveSize; k++)
      {
         m_virtualPositions[k] = currentLive[k];
      }
      m_virtCount = liveSize;
   }
   
   //--- Evaluate Stealth Dollar Take Profit, Dollar Stop Loss, and Dollar Trailing
   void ProcessVirtualExits(const string symbol)
   {
      for(int i = m_virtCount - 1; i >= 0; i--)
      {
         SVirtualPosition pos = m_virtualPositions[i];
         if(pos.symbol != symbol) continue;
         
         bool shouldClose = false;
         string reason = "";
         double profitUSD = 0.0;
         
         if(m_position.SelectByTicket(pos.ticket))
         {
            profitUSD = m_position.Profit() + m_position.Swap();
         }
         else
         {
            continue;
         }
         
         // 1. Dollar Take Profit Hit (+$15.00)
         if(m_targetProfitUSD > 0.0 && profitUSD >= m_targetProfitUSD)
         {
            shouldClose = true;
            reason = StringFormat("Dollar TP Hit: +$%.2f (>= $%.2f)", profitUSD, m_targetProfitUSD);
         }
         // 2. Dollar Stop Loss Limit Hit (-$5.00 -> 1:3 ratio)
         else if(m_lossLimitUSD > 0.0 && profitUSD <= -m_lossLimitUSD)
         {
            shouldClose = true;
            reason = StringFormat("Dollar SL Hit: -$%.2f (<= -$%.2f)", MathAbs(profitUSD), m_lossLimitUSD);
         }
         // 3. Dynamic Dollar Trailing Stop Loss in RAM
         else if(m_useTrailingUSD && m_trailingStartUSD > 0.0 && profitUSD >= m_trailingStartUSD)
         {
            if(profitUSD > m_virtualPositions[i].peakProfitUSD)
               m_virtualPositions[i].peakProfitUSD = profitUSD;
               
            double exitThresholdUSD = m_virtualPositions[i].peakProfitUSD - m_trailingStopUSD;
            if(profitUSD <= exitThresholdUSD)
            {
               shouldClose = true;
               reason = StringFormat("Dollar Trailing SL Hit: Peak +$%.2f pulled back to +$%.2f (Drop: $%.2f)", 
                                     m_virtualPositions[i].peakProfitUSD, profitUSD, m_trailingStopUSD);
            }
         }
         
         // Execute Market Close on trigger
         if(shouldClose)
         {
            if(m_trade.PositionClose(pos.ticket))
            {
               PrintFormat("[Stealth Dollar Exit] Closed Ticket %I64d (%s) - %s", pos.ticket, EnumToString(pos.type), reason);
            }
         }
      }
   }
   
   //--- Basket Dollar Profit & Loss Close Engine (Simultaneous Exit on Dollar Target)
   void ProcessBasketClose(const string symbol)
   {
      // Group by Magic Number to evaluate basket profit in Dollars
      ulong magics[];
      int magicCount = 0;
      
      for(int i = 0; i < m_virtCount; i++)
      {
         ulong m = m_virtualPositions[i].magic;
         bool exists = false;
         for(int j = 0; j < magicCount; j++)
         {
            if(magics[j] == m) { exists = true; break; }
         }
         if(!exists)
         {
            ArrayResize(magics, magicCount + 1);
            magics[magicCount++] = m;
         }
      }
      
      for(int m = 0; m < magicCount; m++)
      {
         ulong currentMagic = magics[m];
         double basketProfitUSD = 0.0;
         int tradeCount = 0;
         
         for(int i = 0; i < PositionsTotal(); i++)
         {
            ulong ticket = PositionGetTicket(i);
            if(ticket > 0 && m_position.SelectByTicket(ticket))
            {
               if(m_position.Symbol() == symbol && m_position.Magic() == currentMagic)
               {
                  basketProfitUSD += (m_position.Profit() + m_position.Swap());
                  tradeCount++;
               }
            }
         }
         
         if(tradeCount == 0) continue;
         
         // 1. If net basket profit meets 1:3 Target Profit in Dollars ($15)
         if(m_targetProfitUSD > 0.0 && basketProfitUSD >= m_targetProfitUSD)
         {
            PrintFormat("[1:3 Dollar Basket TP] Module Magic %I64d reached Target Profit: +$%.2f (>= $%.2f). Closing %d trades in profit...",
                        currentMagic, basketProfitUSD, m_targetProfitUSD, tradeCount);
            CloseModulePositions(symbol, currentMagic, "1:3 Dollar Basket TP");
            ResetBasketPeakProfit(currentMagic);
         }
         // 2. If net basket loss reaches 1:3 Max Loss Limit in Dollars ($5)
         else if(m_lossLimitUSD > 0.0 && basketProfitUSD <= -m_lossLimitUSD)
         {
            PrintFormat("[1:3 Dollar Basket SL] Module Magic %I64d reached Loss Limit: -$%.2f (<= -$%.2f). Closing %d trades to protect capital...",
                        currentMagic, MathAbs(basketProfitUSD), m_lossLimitUSD, tradeCount);
            CloseModulePositions(symbol, currentMagic, "1:3 Dollar Basket SL");
            ResetBasketPeakProfit(currentMagic);
         }
         // 3. Dynamic Dollar Basket Trailing Exit
         else if(m_useTrailingUSD && m_trailingStartUSD > 0.0 && basketProfitUSD >= m_trailingStartUSD)
         {
            int idx = GetTrackedMagicIndex(currentMagic);
            if(basketProfitUSD > m_basketPeakProfitUSD[idx])
               m_basketPeakProfitUSD[idx] = basketProfitUSD;
               
            double exitLevelUSD = m_basketPeakProfitUSD[idx] - m_trailingStopUSD;
            if(basketProfitUSD <= exitLevelUSD)
            {
               PrintFormat("[Dollar Basket Trailing Exit] Module Magic %I64d Peak +$%.2f pulled back to +$%.2f. Closing %d trades...",
                           currentMagic, m_basketPeakProfitUSD[idx], basketProfitUSD, tradeCount);
               CloseModulePositions(symbol, currentMagic, "Dollar Basket Trailing Exit");
               m_basketPeakProfitUSD[idx] = 0.0;
            }
         }
      }
   }
   
   //--- Helper to track basket peak profit per magic
   int GetTrackedMagicIndex(ulong magic)
   {
      for(int i = 0; i < m_trackedMagicCount; i++)
      {
         if(m_trackedMagics[i] == magic) return i;
      }
      if(m_trackedMagicCount < 50)
      {
         int idx = m_trackedMagicCount++;
         m_trackedMagics[idx] = magic;
         m_basketPeakProfitUSD[idx] = 0.0;
         return idx;
      }
      return 0;
   }
   
   void ResetBasketPeakProfit(ulong magic)
   {
      for(int i = 0; i < m_trackedMagicCount; i++)
      {
         if(m_trackedMagics[i] == magic) { m_basketPeakProfitUSD[i] = 0.0; break; }
      }
   }
   
   //--- Smart Grid Spacing Check: Can we open next grid order for this module?
   bool CanOpenGridOrder(const string symbol, ulong magic, ENUM_SIGNAL_TYPE signalType)
   {
      double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
      double curBid = SymbolInfoDouble(symbol, SYMBOL_BID);
      double curAsk = SymbolInfoDouble(symbol, SYMBOL_ASK);
      
      double lastOpenPrice = 0.0;
      datetime lastOpenTime = 0;
      int count = 0;
      
      for(int i = 0; i < PositionsTotal(); i++)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket > 0 && m_position.SelectByTicket(ticket))
         {
            if(m_position.Symbol() == symbol && m_position.Magic() == magic)
            {
               count++;
               if(m_position.Time() > lastOpenTime)
               {
                  lastOpenTime  = (datetime)m_position.Time();
                  lastOpenPrice = m_position.PriceOpen();
               }
            }
         }
      }
      
      // If no positions open for this module, initial entry is allowed
      if(count == 0) return true;
      
      // If positions exist, verify Grid Step pullback distance
      if(signalType == SIGNAL_BUY)
      {
         double distancePoints = (lastOpenPrice - curAsk) / point;
         return (distancePoints >= m_gridStepPoints);
      }
      else if(signalType == SIGNAL_SELL)
      {
         double distancePoints = (curBid - lastOpenPrice) / point;
         return (distancePoints >= m_gridStepPoints);
      }
      
      return false;
   }
   
   //--- Check current position direction for a module (1=Buy, -1=Sell, 0=None)
   int GetModuleDirection(const string symbol, ulong magic)
   {
      for(int i = 0; i < PositionsTotal(); i++)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket > 0 && m_position.SelectByTicket(ticket))
         {
            if(m_position.Symbol() == symbol && m_position.Magic() == magic)
            {
               return (m_position.PositionType() == POSITION_TYPE_BUY) ? 1 : -1;
            }
         }
      }
      return 0;
   }

   //--- Close all positions for a specific module (Direction Flip)
   void CloseModulePositions(const string symbol, ulong magic, string reason = "Direction Flip")
   {
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket > 0 && m_position.SelectByTicket(ticket))
         {
            if(m_position.Symbol() == symbol && m_position.Magic() == magic)
            {
               m_trade.PositionClose(ticket);
               PrintFormat("[%s] Closed ticket %I64d for Magic %I64d", reason, ticket, magic);
            }
         }
      }
   }

   //--- Helper to find position in RAM
   int FindRAMPosition(ulong ticket)
   {
      for(int i = 0; i < m_virtCount; i++)
      {
         if(m_virtualPositions[i].ticket == ticket)
            return i;
      }
      return -1;
   }
};
