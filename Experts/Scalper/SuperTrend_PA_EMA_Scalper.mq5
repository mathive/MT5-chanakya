//+------------------------------------------------------------------+
//|                                  SuperTrend_PA_EMA_Scalper.mq5   |
//|                        Based on Price Action, EMA, and SuperTrend|
//|                                       Gemini Code Assist         |
//+------------------------------------------------------------------+
#property copyright "Gemini Code Assist"
#property link      ""
#property version   "1.00"

#include <Trade\Trade.mqh>

//--- Input parameters
input group  "Strategy Settings"
input int      InpEMAPeriod      = 27;      // EMA Trend Filter Period
input int      InpSTPeriod       = 10;       // SuperTrend Period
input double   InpSTMultiplier   = 3.0;      // SuperTrend Multiplier
input int      InpSTMaxBars      = 10000;    // SuperTrend Max Bars
input ENUM_TIMEFRAMES InpTimeframe = PERIOD_CURRENT; // Working Timeframe
input bool     InpCloseOnOpposite = true;    // Close opposite positions on signal

input group  "Risk Management"
input double   InpLotSize        = 0.1;      // Lot Size
input double   InpStopLossUSD    = 15.0;     // Stop Loss (USD)
input double   InpTakeProfitUSD  = 30.0;     // Take Profit (USD)
input int      InpTrailingStop   = 100;      // Trailing Stop (points)
input int      InpMagic          = 987654;   // Magic Number

//--- Global variables
CTrade         trade;
int            handleEMA;
int            handleST;
datetime       lastBarTime;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   //--- Initialize EMA
   handleEMA = iMA(_Symbol, InpTimeframe, InpEMAPeriod, 0, MODE_EMA, PRICE_CLOSE);
   if(handleEMA == INVALID_HANDLE)
     {
      Print("Failed to create EMA handle");
      return(INIT_FAILED);
     }

   //--- Initialize SuperTrend
   // Uses 'Supertrend.ex5' located in MQL5\Indicators
   // Correct inputs found in Supertrend.mq5: (string Name, double Multiplier, int Period, int MaxBars)
   ResetLastError();
   handleST = iCustom(_Symbol, InpTimeframe, "Supertrend", "ST_Scalper", InpSTMultiplier, InpSTPeriod, InpSTMaxBars);
   if(handleST == INVALID_HANDLE)
     {
      PrintFormat("Failed to create SuperTrend handle (Error %d). Expected inputs: (string, double, int, int).", GetLastError());
      return(INIT_FAILED);
     }

   trade.SetExpertMagicNumber(InpMagic);
   
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   IndicatorRelease(handleEMA);
   IndicatorRelease(handleST);
  }

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
   //--- Manage Trailing Stop on every tick
   ManageTrailingStop();

   //--- Check for New Bar to avoid signal flickering
   if(!IsNewBar()) return;

   //--- Data structures
   double emaVal[];
   double stTrend[]; // Buffer 2: 0=Up, 1=Down
   double close[], open[];
   
   ArraySetAsSeries(emaVal, true);
   ArraySetAsSeries(stTrend, true);
   ArraySetAsSeries(close, true);
   ArraySetAsSeries(open, true);

   //--- Copy Data (Index 1 is the closed bar)
   if(CopyBuffer(handleEMA, 0, 1, 1, emaVal) < 0) return;
   if(CopyBuffer(handleST, 2, 1, 1, stTrend) < 0) return; // Index 2 is TrendDirection
   if(CopyClose(_Symbol, InpTimeframe, 1, 1, close) < 0) return;
   if(CopyOpen(_Symbol, InpTimeframe, 1, 1, open) < 0) return;

   //--- Logic Conditions
   bool isUptrendST = (stTrend[0] == 0);
   bool isDowntrendST = (stTrend[0] == 1);
   bool isBullishCandle = (close[0] > open[0]);
   bool isBearishCandle = (close[0] < open[0]);
   bool priceAboveEMA = (close[0] > emaVal[0]);
   bool priceBelowEMA = (close[0] < emaVal[0]);

   //--- Check Open Positions
   if(PositionsTotal() > 0)
     {
      if(InpCloseOnOpposite)
        {
         for(int i = PositionsTotal() - 1; i >= 0; i--)
           {
            ulong ticket = PositionGetTicket(i);
            if(PositionSelectByTicket(ticket) && PositionGetInteger(POSITION_MAGIC) == InpMagic)
              {
               long type = PositionGetInteger(POSITION_TYPE);
               // Close Buy if Sell Signal
               if(type == POSITION_TYPE_BUY && priceBelowEMA && isDowntrendST && isBearishCandle)
                  trade.PositionClose(ticket);
               // Close Sell if Buy Signal
               if(type == POSITION_TYPE_SELL && priceAboveEMA && isUptrendST && isBullishCandle)
                  trade.PositionClose(ticket);
              }
           }
        }
      // If we still have positions, don't open new ones (One trade at a time per magic)
      if(PositionsTotal() > 0) return; 
     }

   //--- Entry Logic
   // Buy: Price > EMA + SuperTrend Green + Bullish Candle
   if(priceAboveEMA && isUptrendST && isBullishCandle)
     {
      double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
      double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
      if(tickValue == 0) tickValue = 1; // Prevent division by zero
      double slDist = (InpStopLossUSD * tickSize) / (tickValue * InpLotSize);
      double tpDist = (InpTakeProfitUSD * tickSize) / (tickValue * InpLotSize);

      double sl = (InpStopLossUSD > 0) ? SymbolInfoDouble(_Symbol, SYMBOL_BID) - slDist : 0;
      double tp = (InpTakeProfitUSD > 0) ? SymbolInfoDouble(_Symbol, SYMBOL_BID) + tpDist : 0;
      
      trade.Buy(InpLotSize, _Symbol, 0, sl, tp, "PA_EMA_ST Buy");
     }
   // Sell: Price < EMA + SuperTrend Red + Bearish Candle
   else if(priceBelowEMA && isDowntrendST && isBearishCandle)
     {
      double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
      double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
      if(tickValue == 0) tickValue = 1; // Prevent division by zero
      double slDist = (InpStopLossUSD * tickSize) / (tickValue * InpLotSize);
      double tpDist = (InpTakeProfitUSD * tickSize) / (tickValue * InpLotSize);

      double sl = (InpStopLossUSD > 0) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) + slDist : 0;
      double tp = (InpTakeProfitUSD > 0) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) - tpDist : 0;
      
      trade.Sell(InpLotSize, _Symbol, 0, sl, tp, "PA_EMA_ST Sell");
     }
  }

//+------------------------------------------------------------------+
//| Check for New Bar                                                |
//+------------------------------------------------------------------+
bool IsNewBar()
  {
   datetime currBarTime = iTime(_Symbol, InpTimeframe, 0);
   if(lastBarTime != currBarTime)
     {
      lastBarTime = currBarTime;
      return true;
     }
   return false;
  }

//+------------------------------------------------------------------+
//| Manage Trailing Stop                                             |
//+------------------------------------------------------------------+
void ManageTrailingStop()
  {
   if(InpTrailingStop == 0) return;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket) && PositionGetInteger(POSITION_MAGIC) == InpMagic)
        {
         long type = PositionGetInteger(POSITION_TYPE);
         double currentSL = PositionGetDouble(POSITION_SL);
         double priceCurrent = PositionGetDouble(POSITION_PRICE_CURRENT);
         double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);

         if(type == POSITION_TYPE_BUY)
           {
            if(priceCurrent - PositionGetDouble(POSITION_PRICE_OPEN) > InpTrailingStop * point)
              {
               double newSL = priceCurrent - InpTrailingStop * point;
               if(newSL > currentSL + point) // Only move up
                  trade.PositionModify(ticket, newSL, PositionGetDouble(POSITION_TP));
              }
           }
         else if(type == POSITION_TYPE_SELL)
           {
            if(PositionGetDouble(POSITION_PRICE_OPEN) - priceCurrent > InpTrailingStop * point)
              {
               double newSL = priceCurrent + InpTrailingStop * point;
               if(newSL < currentSL - point || currentSL == 0) // Only move down
                  trade.PositionModify(ticket, newSL, PositionGetDouble(POSITION_TP));
              }
           }
        }
     }
  }