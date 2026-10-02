//+------------------------------------------------------------------+
//|                                       EMA200_MTF_Cross_EA.mq5   |
//|                                  Copyright 2026, Antigravity AI  |
//|                                             https://mql5.com     |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Antigravity AI"
#property link      "https://mql5.com"
#property version   "7.00"
#property description "Multi-Timeframe EMA 200 Real-Time Crossover EA v7.00"
#property description "Instant Close on Cross | 1 Trade Per Candle Anti-Whipsaw Guard | Proportional Target Profit"

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\SymbolInfo.mqh>

enum ENUM_CROSS_TRIGGER
{
   CROSS_TRIGGER_INSTANT_TICK = 0, // Instant Live Crossover (Every Tick)
   CROSS_TRIGGER_CANDLE_CLOSE = 1  // Confirmed on Candle Close
};

enum ENUM_TRADE_DIRECTION
{
   TRADE_DIR_BOTH      = 0, // Both BUY & SELL
   TRADE_DIR_BUY_ONLY  = 1, // BUY Only (Longs Only)
   TRADE_DIR_SELL_ONLY = 2  // SELL Only (Shorts Only)
};

//+------------------------------------------------------------------+
//| INPUT PARAMETERS                                                 |
//+------------------------------------------------------------------+
input group "=== Trading Settings ==="
input ENUM_TRADE_DIRECTION InpTradeDirection    = TRADE_DIR_BOTH;             // Allowed Trade Direction (Both / Buy Only / Sell Only)
input double            InpLotSize            = 0.01;                       // Lot Size per Timeframe Trade
input int               InpEmaPeriod          = 200;                        // EMA Period
input ENUM_APPLIED_PRICE InpEmaPrice          = PRICE_CLOSE;                // EMA Applied Price
input ENUM_CROSS_TRIGGER InpCrossTrigger      = CROSS_TRIGGER_INSTANT_TICK; // Crossover Trigger Mode (Live Tick vs Candle Close)
input int               InpRecentCrossBars    = 4;                          // Lookback Bars (for Candle Close mode)
input int               InpMaxEmaDistancePts  = 0;                          // Max Distance from EMA in Points (0 = disabled)
input ulong             InpBaseMagic          = 200000;                     // Base Magic Number
input int               InpSlippagePoints     = 30;                         // Max Slippage (Points)

input group "=== Target Profit & Currency Settings (Always in USD $) ==="
input bool              InpEnableTfProfitTarget = true;                     // Enable Target Profit Booking
input double            InpBaseTpM2           = 10.0;                       // Base M2 Target Profit in USD ($) (Auto-scaled for all TFs)
input bool              InpIsCentAccount      = false;                      // Force USC / Cent Account Mode (Auto-detected if false)

input group "=== Timeframes to Trade ==="
input bool              InpTradeM1            = false;                      // Trade M1 (1 Minute) [Default: OFF]
input bool              InpTradeM2            = true;                       // Trade M2 (2 Minutes)
input bool              InpTradeM3            = true;                       // Trade M3 (3 Minutes)
input bool              InpTradeM4            = false;                      // Trade M4 (4 Minutes)
input bool              InpTradeM5            = true;                       // Trade M5 (5 Minutes)
input bool              InpTradeM10           = true;                       // Trade M10 (10 Minutes)
input bool              InpTradeM15           = true;                       // Trade M15 (15 Minutes)
input bool              InpTradeM30           = true;                       // Trade M30 (30 Minutes)
input bool              InpTradeH1            = true;                       // Trade H1 (1 Hour)

input group "=== Visual Settings ==="
input bool              InpShowEmaOnChart     = true;                       // Plot EMA 200 Line Directly on Chart
input bool              InpShowDashboard      = true;                       // Show On-Chart Dashboard
input int               InpDashboardX         = 20;                         // Dashboard X Position
input int               InpDashboardY         = 30;                         // Dashboard Y Position

//+------------------------------------------------------------------+
//| Timeframe Data Structure                                         |
//+------------------------------------------------------------------+
struct STimeframeBot
{
   ENUM_TIMEFRAMES period;
   string          name;
   int             minutes;
   bool            enabled;
   ulong           magic;
   int             handle;
   datetime        lastBarTime;
   datetime        lastTradedCandleTime;     // 1 trade per candle anti-whipsaw guard
   string          currentPosition;          // "BUY", "SELL", "NONE"
   double          currentPnL;
   double          lastEma;
   double          lastPrice;
   int             lastCrossSide;            // +1 = Above EMA, -1 = Below EMA, 0 = Uninitialized
   double          targetProfit;             // Auto-calculated Target Profit ($ / USC)
   int             waitingForOppositeSignal; // -1 = Normal, 0 = Waiting for SELL cross (after BUY TP), 1 = Waiting for BUY cross (after SELL TP)
};

#define TOTAL_TF 9
STimeframeBot g_bots[TOTAL_TF];

CTrade        g_trade;
CPositionInfo g_position;
CSymbolInfo   g_symbol;
int           g_chartEmaHandle = INVALID_HANDLE;
string        g_chartEmaShortName = "";
string        g_dashPrefix = "EMA200_SIMPLE_";

//+------------------------------------------------------------------+
//| Currency & Cent Account Conversion to USD ($)                    |
//+------------------------------------------------------------------+
double GetAccountToUsdFactor()
{
   if(InpIsCentAccount)
      return 0.01;

   string accCurr = AccountInfoString(ACCOUNT_CURRENCY);
   StringToUpper(accCurr);

   if(accCurr == "USC" || accCurr == "CENT" || accCurr == "CENTS" || 
      accCurr == "USX" || accCurr == "EUX" || accCurr == "GBX" ||
      StringFind(accCurr, "CENT") >= 0 || StringFind(accCurr, "USC") >= 0 || StringFind(accCurr, "USX") >= 0)
   {
      return 0.01;
   }

   if(accCurr == "USD")
      return 1.0;

   string directPair = accCurr + "USD";
   if(SymbolInfoDouble(directPair, SYMBOL_BID) > 0)
      return SymbolInfoDouble(directPair, SYMBOL_BID);

   string inversePair = "USD" + accCurr;
   if(SymbolInfoDouble(inversePair, SYMBOL_BID) > 0)
   {
      double rate = SymbolInfoDouble(inversePair, SYMBOL_BID);
      if(rate > 0)
         return 1.0 / rate;
   }

   return 1.0;
}

double AccountToUSD(double accountAmount)
{
   return accountAmount * GetAccountToUsdFactor();
}

// Forward declarations
void CloseTfPosition(int tfIndex);
void ExecuteTfSignal(int tfIndex, ENUM_ORDER_TYPE orderType, datetime candleTime);
void CheckTfProfitTargets();
void UpdatePositionsStatus();
void RenderDashboard();
double CalculateTotalClosedPnL();
void CreateOrUpdateLabel(string name, string text, int x, int y, color clr, int fontSize, bool isBold);
void SaveBotState(int index);
void LoadBotState(int index);

//+------------------------------------------------------------------+
//| Helper to save persistent bot state                              |
//+------------------------------------------------------------------+
void SaveBotState(int index)
{
   string gvSide = StringFormat("EMA200_%s_%s_SIDE", _Symbol, g_bots[index].name);
   string gvWait = StringFormat("EMA200_%s_%s_WAIT", _Symbol, g_bots[index].name);
   string gvTct  = StringFormat("EMA200_%s_%s_TCT",  _Symbol, g_bots[index].name);
   GlobalVariableSet(gvSide, (double)g_bots[index].lastCrossSide);
   GlobalVariableSet(gvWait, (double)g_bots[index].waitingForOppositeSignal);
   GlobalVariableSet(gvTct,  (double)g_bots[index].lastTradedCandleTime);
}

//+------------------------------------------------------------------+
//| Helper to load persistent bot state                              |
//+------------------------------------------------------------------+
void LoadBotState(int index)
{
   string gvSide = StringFormat("EMA200_%s_%s_SIDE", _Symbol, g_bots[index].name);
   string gvWait = StringFormat("EMA200_%s_%s_WAIT", _Symbol, g_bots[index].name);
   string gvTct  = StringFormat("EMA200_%s_%s_TCT",  _Symbol, g_bots[index].name);
   
   if(GlobalVariableCheck(gvSide))
      g_bots[index].lastCrossSide = (int)GlobalVariableGet(gvSide);
   if(GlobalVariableCheck(gvWait))
      g_bots[index].waitingForOppositeSignal = (int)GlobalVariableGet(gvWait);
   if(GlobalVariableCheck(gvTct))
      g_bots[index].lastTradedCandleTime = (datetime)GlobalVariableGet(gvTct);
}

//+------------------------------------------------------------------+
//| Helper to initialize a single timeframe bot                      |
//+------------------------------------------------------------------+
void InitTfBot(int index, ENUM_TIMEFRAMES period, string name, int minutes, bool enabled, ulong magicOffset)
{
   g_bots[index].period                   = period;
   g_bots[index].name                     = name;
   g_bots[index].minutes                  = minutes;
   g_bots[index].enabled                  = enabled;
   g_bots[index].magic                    = InpBaseMagic + magicOffset;
   g_bots[index].handle                   = INVALID_HANDLE;
   g_bots[index].lastBarTime              = 0;
   g_bots[index].lastTradedCandleTime     = 0;
   g_bots[index].currentPosition          = "NONE";
   g_bots[index].currentPnL               = 0.0;
   g_bots[index].lastEma                  = 0.0;
   g_bots[index].lastPrice                = 0.0;
   g_bots[index].lastCrossSide            = 0;
   g_bots[index].waitingForOppositeSignal = -1;

   if(InpBaseTpM2 > 0)
      g_bots[index].targetProfit = InpBaseTpM2 * ((double)minutes / 2.0);
   else
      g_bots[index].targetProfit = 0.0;

   LoadBotState(index);
}

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   if(!g_symbol.Name(_Symbol))
   {
      Print("Error: Failed to load symbol info for ", _Symbol);
      return INIT_FAILED;
   }
   g_symbol.Refresh();

   g_trade.SetDeviationInPoints(InpSlippagePoints);
   g_trade.SetTypeFillingBySymbol(_Symbol);

   InitTfBot(0, PERIOD_M1,  "M1",  1,  InpTradeM1,  1);
   InitTfBot(1, PERIOD_M2,  "M2",  2,  InpTradeM2,  2);
   InitTfBot(2, PERIOD_M3,  "M3",  3,  InpTradeM3,  3);
   InitTfBot(3, PERIOD_M4,  "M4",  4,  InpTradeM4,  4);
   InitTfBot(4, PERIOD_M5,  "M5",  5,  InpTradeM5,  5);
   InitTfBot(5, PERIOD_M10, "M10", 10, InpTradeM10, 10);
   InitTfBot(6, PERIOD_M15, "M15", 15, InpTradeM15, 15);
   InitTfBot(7, PERIOD_M30, "M30", 30, InpTradeM30, 30);
   InitTfBot(8, PERIOD_H1,  "H1",  60, InpTradeH1,  60);

   for(int i = 0; i < TOTAL_TF; i++)
   {
      if(!g_bots[i].enabled)
         continue;

      g_bots[i].handle = iMA(_Symbol, g_bots[i].period, InpEmaPeriod, 0, MODE_EMA, InpEmaPrice);
      if(g_bots[i].handle == INVALID_HANDLE)
      {
         PrintFormat("Failed to create EMA 200 handle for %s", g_bots[i].name);
         return INIT_FAILED;
      }
   }

   UpdatePositionsStatus();

   g_symbol.RefreshRates();
   double initialPrice = (g_symbol.Bid() + g_symbol.Ask()) * 0.5;
   for(int i = 0; i < TOTAL_TF; i++)
   {
      if(!g_bots[i].enabled || g_bots[i].handle == INVALID_HANDLE)
         continue;

      double emaBuffer[1];
      if(CopyBuffer(g_bots[i].handle, 0, 0, 1, emaBuffer) > 0)
      {
         g_bots[i].lastEma = emaBuffer[0];
         g_bots[i].lastPrice = initialPrice;
         
         if(g_bots[i].currentPosition == "BUY")
            g_bots[i].lastCrossSide = 1;
         else if(g_bots[i].currentPosition == "SELL")
            g_bots[i].lastCrossSide = -1;
         else if(g_bots[i].lastCrossSide == 0)
            g_bots[i].lastCrossSide = (initialPrice >= emaBuffer[0]) ? 1 : -1;

         SaveBotState(i);
      }
   }

   if(InpShowEmaOnChart)
   {
      g_chartEmaHandle = iMA(_Symbol, _Period, InpEmaPeriod, 0, MODE_EMA, InpEmaPrice);
      if(g_chartEmaHandle != INVALID_HANDLE)
      {
         ChartIndicatorAdd(0, 0, g_chartEmaHandle);
         g_chartEmaShortName = StringFormat("EMA(%d)", InpEmaPeriod);
      }
   }

   EventSetTimer(1);
   if(InpShowDashboard)
      RenderDashboard();

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   EventKillTimer();

   for(int i = 0; i < TOTAL_TF; i++)
   {
      if(g_bots[i].handle != INVALID_HANDLE)
         IndicatorRelease(g_bots[i].handle);

      if(reason == REASON_REMOVE)
      {
         string gvSide = StringFormat("EMA200_%s_%s_SIDE", _Symbol, g_bots[i].name);
         string gvWait = StringFormat("EMA200_%s_%s_WAIT", _Symbol, g_bots[i].name);
         string gvTct  = StringFormat("EMA200_%s_%s_TCT",  _Symbol, g_bots[i].name);
         GlobalVariableDel(gvSide);
         GlobalVariableDel(gvWait);
         GlobalVariableDel(gvTct);
      }
   }

   if(g_chartEmaHandle != INVALID_HANDLE)
   {
      int totalIndicators = ChartIndicatorsTotal(0, 0);
      for(int i = totalIndicators - 1; i >= 0; i--)
      {
         string name = ChartIndicatorName(0, 0, i);
         if(StringFind(name, "MA(") >= 0 || StringFind(name, "Moving Average") >= 0 || StringFind(name, IntegerToString(InpEmaPeriod)) >= 0)
         {
            ChartIndicatorDelete(0, 0, name);
         }
      }
      IndicatorRelease(g_chartEmaHandle);
   }

   ObjectsDeleteAll(0, g_dashPrefix);
   ChartRedraw(0);
}

//+------------------------------------------------------------------+
//| Check TF-Specific Profit Targets and Close in Profit             |
//+------------------------------------------------------------------+
void CheckTfProfitTargets()
{
   if(!InpEnableTfProfitTarget)
      return;

   for(int i = 0; i < TOTAL_TF; i++)
   {
      if(!g_bots[i].enabled || g_bots[i].targetProfit <= 0.0)
         continue;

      ulong magic = g_bots[i].magic;
      for(int p = PositionsTotal() - 1; p >= 0; p--)
      {
         if(g_position.SelectByIndex(p))
         {
            if(g_position.Symbol() == _Symbol && (ulong)g_position.Magic() == magic)
            {
               double posProfitAccount = g_position.Profit() + g_position.Swap() + g_position.Commission();
               double posProfitUsd = AccountToUSD(posProfitAccount);

               if(posProfitUsd >= g_bots[i].targetProfit)
               {
                  ENUM_POSITION_TYPE closedType = g_position.PositionType();
                  PrintFormat("[%s] TARGET PROFIT REACHED! Profit=$%.2f USD >= Target=$%.2f USD. Closing Ticket #%d.",
                              g_bots[i].name, posProfitUsd, g_bots[i].targetProfit, g_position.Ticket());
                  
                  if(g_trade.PositionClose(g_position.Ticket()))
                  {
                     g_bots[i].currentPosition = "NONE";
                     g_bots[i].currentPnL      = 0.0;
                     
                     if(closedType == POSITION_TYPE_BUY)
                     {
                        g_bots[i].waitingForOppositeSignal = 0; // Wait for SELL cross
                        g_bots[i].lastCrossSide = 1;
                     }
                     else if(closedType == POSITION_TYPE_SELL)
                     {
                        g_bots[i].waitingForOppositeSignal = 1; // Wait for BUY cross
                        g_bots[i].lastCrossSide = -1;
                     }
                     SaveBotState(i);
                  }
               }
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Close all positions for a specific TF                            |
//+------------------------------------------------------------------+
void CloseTfPosition(int tfIndex)
{
   ulong magic = g_bots[tfIndex].magic;
   for(int p = PositionsTotal() - 1; p >= 0; p--)
   {
      if(g_position.SelectByIndex(p))
      {
         if(g_position.Symbol() == _Symbol && (ulong)g_position.Magic() == magic)
         {
            g_trade.PositionClose(g_position.Ticket());
            PrintFormat("[%s] Closed position ticket #%d", g_bots[tfIndex].name, g_position.Ticket());
         }
      }
   }
   g_bots[tfIndex].currentPosition = "NONE";
   g_bots[tfIndex].currentPnL      = 0.0;
   SaveBotState(tfIndex);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   g_symbol.RefreshRates();
   double currentBid = g_symbol.Bid();
   double currentAsk = g_symbol.Ask();
   double currentMid = (currentBid + currentAsk) * 0.5;
   double point      = g_symbol.Point();

   UpdatePositionsStatus();
   CheckTfProfitTargets();

   for(int i = 0; i < TOTAL_TF; i++)
   {
      if(!g_bots[i].enabled || g_bots[i].handle == INVALID_HANDLE)
         continue;

      // MODE 1: INSTANT LIVE REAL-TIME CROSSOVER (1 Trade Per Candle Anti-Whipsaw Guard)
      if(InpCrossTrigger == CROSS_TRIGGER_INSTANT_TICK)
      {
         double emaBuffer[1];
         if(CopyBuffer(g_bots[i].handle, 0, 0, 1, emaBuffer) < 1)
            continue;

         double liveEma = emaBuffer[0];
         g_bots[i].lastEma   = liveEma;
         g_bots[i].lastPrice = currentMid;

         datetime currentCandleTime = iTime(_Symbol, g_bots[i].period, 0);

         if(g_bots[i].lastCrossSide == 0)
         {
            if(g_bots[i].currentPosition == "BUY")
               g_bots[i].lastCrossSide = 1;
            else if(g_bots[i].currentPosition == "SELL")
               g_bots[i].lastCrossSide = -1;
            else
               g_bots[i].lastCrossSide = (currentMid >= liveEma) ? 1 : -1;
            SaveBotState(i);
            continue;
         }

         // ==========================================================
         // CASE A: Currently holding a SELL position
         // Immediately close SELL when price crosses ABOVE EMA (Bid > liveEma)
         // ==========================================================
         if(g_bots[i].currentPosition == "SELL")
         {
            if(currentBid > liveEma)
            {
               PrintFormat("[%s] CROSS REVERSAL: Bid=%.5f crossed ABOVE EMA=%.5f. Immediately closing SELL!",
                           g_bots[i].name, currentBid, liveEma);
               CloseTfPosition(i);

               // Anti-Whipsaw 1 Position Per Candle Guard:
               // If this candle hasn't traded a new entry yet, open BUY immediately!
               // If price already traded on this candle and fluctuated back, wait for candle close!
               if(g_bots[i].lastTradedCandleTime != currentCandleTime && g_bots[i].waitingForOppositeSignal != 0 && InpTradeDirection != TRADE_DIR_SELL_ONLY)
               {
                  ExecuteTfSignal(i, ORDER_TYPE_BUY, currentCandleTime);
               }
               else
               {
                  PrintFormat("[%s] Fluctuated on SAME candle (%s) or BUY disabled. Closed SELL and waiting for candle close before fresh trade.",
                              g_bots[i].name, TimeToString(currentCandleTime));
                  g_bots[i].lastCrossSide = 1;
                  SaveBotState(i);
               }
            }
         }
         // ==========================================================
         // CASE B: Currently holding a BUY position
         // Immediately close BUY when price crosses BELOW EMA (Ask < liveEma)
         // ==========================================================
         else if(g_bots[i].currentPosition == "BUY")
         {
            if(currentAsk < liveEma)
            {
               PrintFormat("[%s] CROSS REVERSAL: Ask=%.5f crossed BELOW EMA=%.5f. Immediately closing BUY!",
                           g_bots[i].name, currentAsk, liveEma);
               CloseTfPosition(i);

               // Anti-Whipsaw 1 Position Per Candle Guard:
               if(g_bots[i].lastTradedCandleTime != currentCandleTime && g_bots[i].waitingForOppositeSignal != 1 && InpTradeDirection != TRADE_DIR_BUY_ONLY)
               {
                  ExecuteTfSignal(i, ORDER_TYPE_SELL, currentCandleTime);
               }
               else
               {
                  PrintFormat("[%s] Fluctuated on SAME candle (%s) or SELL disabled. Closed BUY and waiting for candle close before fresh trade.",
                              g_bots[i].name, TimeToString(currentCandleTime));
                  g_bots[i].lastCrossSide = -1;
                  SaveBotState(i);
               }
            }
         }
         // ==========================================================
         // CASE C: Currently NO position open (after close, TP, or start)
         // ==========================================================
         else if(g_bots[i].currentPosition == "NONE")
         {
            // 1 Position Per Candle Guard: Do not enter on a candle where a trade was already taken / reversed
            if(g_bots[i].lastTradedCandleTime != currentCandleTime)
            {
               // Price is above EMA -> Open BUY
               if(InpTradeDirection != TRADE_DIR_SELL_ONLY && currentBid > liveEma && g_bots[i].waitingForOppositeSignal != 0)
               {
                  if(g_bots[i].lastCrossSide == -1 || g_bots[i].lastBarTime != currentCandleTime)
                  {
                     if(InpMaxEmaDistancePts <= 0 || (point > 0 && (currentBid - liveEma) / point <= InpMaxEmaDistancePts))
                     {
                        PrintFormat("[%s] Fresh Crossover BUY: Bid=%.5f > EMA=%.5f on candle %s",
                                    g_bots[i].name, currentBid, liveEma, TimeToString(currentCandleTime));
                        ExecuteTfSignal(i, ORDER_TYPE_BUY, currentCandleTime);
                        g_bots[i].lastBarTime = currentCandleTime;
                     }
                  }
               }
               // Price is below EMA -> Open SELL
               else if(InpTradeDirection != TRADE_DIR_BUY_ONLY && currentAsk < liveEma && g_bots[i].waitingForOppositeSignal != 1)
               {
                  if(g_bots[i].lastCrossSide == 1 || g_bots[i].lastBarTime != currentCandleTime)
                  {
                     if(InpMaxEmaDistancePts <= 0 || (point > 0 && (liveEma - currentAsk) / point <= InpMaxEmaDistancePts))
                     {
                        PrintFormat("[%s] Fresh Crossover SELL: Ask=%.5f < EMA=%.5f on candle %s",
                                    g_bots[i].name, currentAsk, liveEma, TimeToString(currentCandleTime));
                        ExecuteTfSignal(i, ORDER_TYPE_SELL, currentCandleTime);
                        g_bots[i].lastBarTime = currentCandleTime;
                     }
                  }
               }
            }
         }
      }
      // MODE 2: CANDLE CLOSE CONFIRMATION
      else
      {
         datetime currentBarTime = iTime(_Symbol, g_bots[i].period, 0);
         if(currentBarTime == 0 || currentBarTime == g_bots[i].lastBarTime)
            continue;

         g_bots[i].lastBarTime = currentBarTime;

         int lookback = InpRecentCrossBars;
         if(lookback < 1) lookback = 1;
         int barsNeeded = lookback + 2;

         double emaBuffer[];
         ArraySetAsSeries(emaBuffer, true);
         if(CopyBuffer(g_bots[i].handle, 0, 0, barsNeeded, emaBuffer) < barsNeeded)
            continue;

         MqlRates rates[];
         ArraySetAsSeries(rates, true);
         if(CopyRates(_Symbol, g_bots[i].period, 0, barsNeeded, rates) < barsNeeded)
            continue;

         g_bots[i].lastEma   = emaBuffer[1];
         g_bots[i].lastPrice = rates[1].close;

         bool triggerBuy = false;
         bool triggerSell = false;

         for(int shift = 1; shift <= lookback; shift++)
         {
            bool crossAbove = (rates[shift + 1].close <= emaBuffer[shift + 1] && rates[shift].close > emaBuffer[shift]);
            bool crossBelow = (rates[shift + 1].close >= emaBuffer[shift + 1] && rates[shift].close < emaBuffer[shift]);

            if(crossAbove && g_bots[i].waitingForOppositeSignal != 0)
            {
               if(rates[1].close > emaBuffer[1])
               {
                  if(point > 0 && (InpMaxEmaDistancePts <= 0 || (rates[1].close - emaBuffer[1]) / point <= InpMaxEmaDistancePts))
                  {
                     triggerBuy = true;
                     g_bots[i].waitingForOppositeSignal = -1;
                     SaveBotState(i);
                     break;
                  }
               }
            }
            else if(crossBelow && g_bots[i].waitingForOppositeSignal != 1)
            {
               if(rates[1].close < emaBuffer[1])
               {
                  if(point > 0 && (InpMaxEmaDistancePts <= 0 || (emaBuffer[1] - rates[1].close) / point <= InpMaxEmaDistancePts))
                  {
                     triggerSell = true;
                     g_bots[i].waitingForOppositeSignal = -1;
                     SaveBotState(i);
                     break;
                  }
               }
            }
         }

         if(triggerBuy && InpTradeDirection != TRADE_DIR_SELL_ONLY)
            ExecuteTfSignal(i, ORDER_TYPE_BUY, currentBarTime);
         else if(triggerSell && InpTradeDirection != TRADE_DIR_BUY_ONLY)
            ExecuteTfSignal(i, ORDER_TYPE_SELL, currentBarTime);
      }
   }
}

//+------------------------------------------------------------------+
//| Timer for dashboard refresh and profit checking                  |
//+------------------------------------------------------------------+
void OnTimer()
{
   UpdatePositionsStatus();
   CheckTfProfitTargets();
   if(InpShowDashboard)
      RenderDashboard();
}

//+------------------------------------------------------------------+
//| Execute Crossover: Close opposite position on this TF and Enter  |
//+------------------------------------------------------------------+
void ExecuteTfSignal(int tfIndex, ENUM_ORDER_TYPE orderType, datetime candleTime)
{
   if(orderType == ORDER_TYPE_BUY && InpTradeDirection == TRADE_DIR_SELL_ONLY) return;
   if(orderType == ORDER_TYPE_SELL && InpTradeDirection == TRADE_DIR_BUY_ONLY) return;

   ulong magic = g_bots[tfIndex].magic;
   string tfName = g_bots[tfIndex].name;
   g_trade.SetExpertMagicNumber(magic);

   // Step 1: Close any existing opposite positions for this TF
   CloseTfPosition(tfIndex);

   // Step 2: Check if this TF already has a position in the same direction
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(g_position.SelectByIndex(i))
      {
         if(g_position.Symbol() == _Symbol && (ulong)g_position.Magic() == magic)
         {
            if((orderType == ORDER_TYPE_BUY && g_position.PositionType() == POSITION_TYPE_BUY) ||
               (orderType == ORDER_TYPE_SELL && g_position.PositionType() == POSITION_TYPE_SELL))
            {
               return;
            }
         }
      }
   }

   // Step 3: Open New Position
   g_symbol.RefreshRates();
   string comment = StringFormat("EMA200_%s", tfName);

   if(orderType == ORDER_TYPE_BUY)
   {
      double ask = g_symbol.Ask();
      if(g_trade.Buy(InpLotSize, _Symbol, ask, 0.0, 0.0, comment))
      {
         PrintFormat("[%s] Instant BUY opened at %.5f (Target TP: $%.2f)", tfName, ask, g_bots[tfIndex].targetProfit);
         g_bots[tfIndex].currentPosition      = "BUY";
         g_bots[tfIndex].lastCrossSide        = 1;
         g_bots[tfIndex].lastTradedCandleTime = candleTime;
         g_bots[tfIndex].waitingForOppositeSignal = -1;
         SaveBotState(tfIndex);
      }
      else
      {
         PrintFormat("[%s] Error opening BUY: %d - %s", tfName, g_trade.ResultRetcode(), g_trade.ResultRetcodeDescription());
      }
   }
   else if(orderType == ORDER_TYPE_SELL)
   {
      double bid = g_symbol.Bid();
      if(g_trade.Sell(InpLotSize, _Symbol, bid, 0.0, 0.0, comment))
      {
         PrintFormat("[%s] Instant SELL opened at %.5f (Target TP: $%.2f)", tfName, bid, g_bots[tfIndex].targetProfit);
         g_bots[tfIndex].currentPosition      = "SELL";
         g_bots[tfIndex].lastCrossSide        = -1;
         g_bots[tfIndex].lastTradedCandleTime = candleTime;
         g_bots[tfIndex].waitingForOppositeSignal = -1;
         SaveBotState(tfIndex);
      }
      else
      {
         PrintFormat("[%s] Error opening SELL: %d - %s", tfName, g_trade.ResultRetcode(), g_trade.ResultRetcodeDescription());
      }
   }

   UpdatePositionsStatus();
   if(InpShowDashboard)
      RenderDashboard();
}

//+------------------------------------------------------------------+
//| Update position states for each TF bot                           |
//+------------------------------------------------------------------+
void UpdatePositionsStatus()
{
   for(int i = 0; i < TOTAL_TF; i++)
   {
      g_bots[i].currentPosition = "NONE";
      g_bots[i].currentPnL      = 0.0;
      if(!g_bots[i].enabled)
         continue;

      for(int p = PositionsTotal() - 1; p >= 0; p--)
      {
         if(g_position.SelectByIndex(p))
         {
            if(g_position.Symbol() == _Symbol && (ulong)g_position.Magic() == g_bots[i].magic)
            {
               if(g_position.PositionType() == POSITION_TYPE_BUY)
                  g_bots[i].currentPosition = "BUY";
               else if(g_position.PositionType() == POSITION_TYPE_SELL)
                  g_bots[i].currentPosition = "SELL";
               
               g_bots[i].currentPnL = AccountToUSD(g_position.Profit() + g_position.Swap() + g_position.Commission());
               break;
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Render on-chart modern black box dashboard                       |
//+------------------------------------------------------------------+
void RenderDashboard()
{
   int x = InpDashboardX;
   int y = InpDashboardY;
   int rowHeight = 18;
   int totalRows = 4 + TOTAL_TF + 3;

   string bgName = g_dashPrefix + "BG";
   if(ObjectFind(0, bgName) < 0)
   {
      ObjectCreate(0, bgName, OBJ_RECTANGLE_LABEL, 0, 0, 0);
      ObjectSetInteger(0, bgName, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, bgName, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, bgName, OBJPROP_BACK, false);
   }
   ObjectSetInteger(0, bgName, OBJPROP_XDISTANCE, x - 10);
   ObjectSetInteger(0, bgName, OBJPROP_YDISTANCE, y - 8);
   ObjectSetInteger(0, bgName, OBJPROP_XSIZE, 370);
   ObjectSetInteger(0, bgName, OBJPROP_YSIZE, totalRows * rowHeight + 15);
   ObjectSetInteger(0, bgName, OBJPROP_BGCOLOR, C'18,22,30');
   ObjectSetInteger(0, bgName, OBJPROP_BORDER_COLOR, C'50,60,90');
   ObjectSetInteger(0, bgName, OBJPROP_BORDER_TYPE, BORDER_FLAT);

   CreateOrUpdateLabel(g_dashPrefix + "TITLE", "=== EMA 200 MTF CROSSOVER EA v7.00 ===", x, y, clrGold, 9, true);
   y += rowHeight + 2;

   string dirStr = (InpTradeDirection == TRADE_DIR_BUY_ONLY) ? "BUY ONLY" : (InpTradeDirection == TRADE_DIR_SELL_ONLY) ? "SELL ONLY" : "BOTH";
   string subTitle = StringFormat("%s | %s | %s | Lot: %.2f", 
                                  _Symbol, 
                                  dirStr,
                                  (InpCrossTrigger == CROSS_TRIGGER_INSTANT_TICK) ? "Instant Cross" : "Candle Close",
                                  InpLotSize);
   CreateOrUpdateLabel(g_dashPrefix + "SUB", subTitle, x, y, clrSkyBlue, 8, false);
   y += rowHeight;

   CreateOrUpdateLabel(g_dashPrefix + "DIV1", "--------------------------------------------------", x, y, clrDarkGray, 8, false);
   y += rowHeight - 4;

   for(int i = 0; i < TOTAL_TF; i++)
   {
      string rowName = g_dashPrefix + "ROW_" + IntegerToString(i);
      color rowColor = clrWhite;
      string statusText = "";

      if(!g_bots[i].enabled)
      {
         statusText = StringFormat("%-4s  DISABLED", g_bots[i].name);
         rowColor = clrDarkGray;
      }
      else if(g_bots[i].currentPosition == "BUY")
      {
         statusText = StringFormat("%-4s  BUY   %+.2f$  (Target: $%.2f)", g_bots[i].name, g_bots[i].currentPnL, g_bots[i].targetProfit);
         rowColor = (g_bots[i].currentPnL >= 0) ? clrLime : clrTomato;
      }
      else if(g_bots[i].currentPosition == "SELL")
      {
         statusText = StringFormat("%-4s  SELL  %+.2f$  (Target: $%.2f)", g_bots[i].name, g_bots[i].currentPnL, g_bots[i].targetProfit);
         rowColor = (g_bots[i].currentPnL >= 0) ? clrLime : clrTomato;
      }
      else
      {
         string waitStr = "";
         if(g_bots[i].waitingForOppositeSignal == 0)
            waitStr = " [Wait SELL]";
         else if(g_bots[i].waitingForOppositeSignal == 1)
            waitStr = " [Wait BUY]";

         string priceSide = (g_bots[i].lastCrossSide == 1) ? "Above EMA" : "Below EMA";
         statusText = StringFormat("%-4s  NONE  %s%s (Target: $%.2f)", g_bots[i].name, priceSide, waitStr, g_bots[i].targetProfit);
         rowColor = clrSilver;
      }

      CreateOrUpdateLabel(rowName, statusText, x, y, rowColor, 8, false);
      y += rowHeight;
   }

   CreateOrUpdateLabel(g_dashPrefix + "DIV2", "--------------------------------------------------", x, y, clrDarkGray, 8, false);
   y += rowHeight - 4;

   int totalPositions = 0, buyPositions = 0, sellPositions = 0;
   double totalFloatingPnL = 0.0, totalVolume = 0.0;

   for(int p = PositionsTotal() - 1; p >= 0; p--)
   {
      if(g_position.SelectByIndex(p))
      {
         if(g_position.Symbol() == _Symbol)
         {
            ulong posMagic = g_position.Magic();
            bool isOurBot = false;
            for(int b = 0; b < TOTAL_TF; b++)
            {
               if(g_bots[b].enabled && g_bots[b].magic == posMagic)
               {
                  isOurBot = true;
                  break;
               }
            }

            if(isOurBot)
            {
               totalPositions++;
               if(g_position.PositionType() == POSITION_TYPE_BUY)
                  buyPositions++;
               else
                  sellPositions++;

               totalFloatingPnL += AccountToUSD(g_position.Profit() + g_position.Swap() + g_position.Commission());
               totalVolume += g_position.Volume();
            }
         }
      }
   }

   double totalClosedPnL = CalculateTotalClosedPnL();
   double totalPnL = totalFloatingPnL + totalClosedPnL;

   string summaryPos = StringFormat("Positions: %d (B:%d S:%d | %.2f lots)", 
                                    totalPositions, buyPositions, sellPositions, totalVolume);
   CreateOrUpdateLabel(g_dashPrefix + "POS", summaryPos, x, y, clrWhite, 8, false);
   y += rowHeight;

   color floatColor = (totalFloatingPnL > 0) ? clrLime : (totalFloatingPnL < 0) ? clrTomato : clrWhite;
   color closedColor = (totalClosedPnL > 0) ? clrLime : (totalClosedPnL < 0) ? clrTomato : clrWhite;
   color totalColor = (totalPnL > 0) ? clrLime : (totalPnL < 0) ? clrTomato : clrWhite;

   string summaryFloat = StringFormat("Floating PnL :  $%.2f USD", totalFloatingPnL);
   CreateOrUpdateLabel(g_dashPrefix + "FLOAT", summaryFloat, x, y, floatColor, 9, true);
   y += rowHeight;

   string summaryClosed = StringFormat("Closed PnL   :  $%.2f USD", totalClosedPnL);
   CreateOrUpdateLabel(g_dashPrefix + "CLOSED", summaryClosed, x, y, closedColor, 9, true);
   y += rowHeight;

   string summaryTotal = StringFormat("TOTAL PnL    :  $%.2f USD", totalPnL);
   CreateOrUpdateLabel(g_dashPrefix + "TOTAL", summaryTotal, x, y, totalColor, 9, true);

   ChartRedraw(0);
}

//+------------------------------------------------------------------+
//| Calculate Total Closed PnL in USD                                |
//+------------------------------------------------------------------+
double CalculateTotalClosedPnL()
{
   if(!HistorySelect(0, TimeCurrent()))
      return 0.0;

   int totalDeals = HistoryDealsTotal();
   double totalClosedProfit = 0.0;

   for(int i = 0; i < totalDeals; i++)
   {
      ulong dealTicket = HistoryDealGetTicket(i);
      if(dealTicket > 0)
      {
         string symbol = HistoryDealGetString(dealTicket, DEAL_SYMBOL);
         ulong magic = HistoryDealGetInteger(dealTicket, DEAL_MAGIC);
         ENUM_DEAL_ENTRY entry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(dealTicket, DEAL_ENTRY);

         if(symbol == _Symbol && (entry == DEAL_ENTRY_OUT || entry == DEAL_ENTRY_INOUT || entry == DEAL_ENTRY_OUT_BY))
         {
            bool isOurMagic = false;
            for(int b = 0; b < TOTAL_TF; b++)
            {
               if(g_bots[b].enabled && g_bots[b].magic == magic)
               {
                  isOurMagic = true;
                  break;
               }
            }

            if(isOurMagic)
            {
               totalClosedProfit += HistoryDealGetDouble(dealTicket, DEAL_PROFIT);
               totalClosedProfit += HistoryDealGetDouble(dealTicket, DEAL_SWAP);
               totalClosedProfit += HistoryDealGetDouble(dealTicket, DEAL_COMMISSION);
               totalClosedProfit += HistoryDealGetDouble(dealTicket, DEAL_FEE);
            }
         }
      }
   }

   return AccountToUSD(totalClosedProfit);
}

//+------------------------------------------------------------------+
//| UI Helper: Create or Update Screen Label                         |
//+------------------------------------------------------------------+
void CreateOrUpdateLabel(string name, string text, int x, int y, color clr, int fontSize, bool isBold)
{
   if(ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_BACK, false);
      ObjectSetInteger(0, name, OBJPROP_ZORDER, 10);
   }

   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, fontSize);
   ObjectSetString(0, name, OBJPROP_FONT, isBold ? "Consolas Bold" : "Consolas");
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
   ObjectSetInteger(0, name, OBJPROP_ZORDER, 10);
}
//+------------------------------------------------------------------+
