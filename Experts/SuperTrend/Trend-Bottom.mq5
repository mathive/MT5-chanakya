//+------------------------------------------------------------------+
//|                                                 Trend-Bottom.mq5 |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "1.03"

//--- Include custom header file
#include "support\GetSpread.mqh"
#include "support\OrderManagement.mqh"
#include <Trade\Trade.mqh>

//--- SuperTrend parameters (matching the indicator)
string IndicatorName = "SPRTRND"; // Objects Prefix
double ATRMultiplier = 9.0;       // ATR Multiplier
int ATRPeriod = 27;                // ATR Period
int ATRMaxBars = 10000;            // ATR Max Bars
int IndicatorShift = 0;            // Indicator shift
bool EnableNotify = false;         // Enable notifications
bool SendAlert = false;            // Send alert
bool SendApp = false;              // Send push notification
bool SendEmail = false;            // Send email
int TriggerCandle = 1;             // Trigger Candle (0=Current, 1=Previous)

//--- SuperTrend indicator handle
int SuperTrend_Handle = INVALID_HANDLE;

//--- SuperTrend signal enumeration
enum ENUM_ST_SIGNAL
{
   ST_SIGNAL_NONE = 0,    // No signal
   ST_SIGNAL_BUY = 1,     // Buy signal
   ST_SIGNAL_SELL = -1    // Sell signal
};

//+------------------------------------------------------------------+
//| Initialize SuperTrend indicator handle                          |
//+------------------------------------------------------------------+
bool InitSuperTrend()
{
   SuperTrend_Handle = iCustom(_Symbol, 0, "Supertrend", 
                               IndicatorName, ATRMultiplier, ATRPeriod, ATRMaxBars, IndicatorShift, 
                               EnableNotify, SendAlert, SendApp, SendEmail, TriggerCandle);
   
   if (SuperTrend_Handle == INVALID_HANDLE)
   {
      Print("Failed to create SuperTrend indicator handle. Error: ", GetLastError());
      return false;
   }
   
   Print("SuperTrend indicator initialized successfully");
   return true;
}

//+------------------------------------------------------------------+
//| Initialize SuperTrend indicator handle for execution timeframe  |
//+------------------------------------------------------------------+
bool InitExecutionTimeframeSuperTrend()
{
   ExecutionTimeframe_Handle = iCustom(_Symbol, tradeExecutionTimeframe, "Supertrend", 
                                       IndicatorName, ATRMultiplier, ATRPeriod, ATRMaxBars, IndicatorShift, 
                                       EnableNotify, SendAlert, SendApp, SendEmail, TriggerCandle);
   
   if (ExecutionTimeframe_Handle == INVALID_HANDLE)
   {
      Print("Failed to create execution timeframe SuperTrend indicator handle. Error: ", GetLastError());
      return false;
   }
   
   Print("Execution timeframe SuperTrend indicator initialized successfully for ", EnumToString(tradeExecutionTimeframe));
   return true;
}

//+------------------------------------------------------------------+
//| Function to get SuperTrend signal                               |
//+------------------------------------------------------------------+
ENUM_ST_SIGNAL GetSuperTrendSignal()
{
   if (SuperTrend_Handle == INVALID_HANDLE)
   {
      Print("SuperTrend handle is invalid, attempting to initialize...");
      if (!InitSuperTrend()) return ST_SIGNAL_NONE;
   }
   
   double st_direction[5];  // Get more values for better analysis
   
   // Copy TrendDirection buffer data (buffer 2)
   if (CopyBuffer(SuperTrend_Handle, 2, 0, 5, st_direction) < 5)
   {
      return ST_SIGNAL_NONE;
   }
   
   // Check if we have valid data (not EMPTY_VALUE)
   bool hasValidData = false;
   for(int i = 1; i < 5; i++)  // Start from index 1, skip current candle [0]
   {
      if(st_direction[i] != EMPTY_VALUE)
      {
         hasValidData = true;
         break;
      }
   }
   
   if(!hasValidData)
   {
      Print("SuperTrend indicator data not ready yet");
      return ST_SIGNAL_NONE;
   }
   
   ENUM_ST_SIGNAL signal = ST_SIGNAL_NONE;
   
   // Check for SELL signal (trend changes from 1 to 0)
   if (st_direction[1] == 0 && st_direction[2] == 1)
   {
      signal = ST_SIGNAL_SELL;
   }
   // Check for BUY signal (trend changes from 0 to 1)
   else if (st_direction[1] == 1 && st_direction[2] == 0)
   {
      signal = ST_SIGNAL_BUY;
   }
   
   return signal;
}

//+------------------------------------------------------------------+
//| Function to get SuperTrend signal without printing              |
//+------------------------------------------------------------------+
ENUM_ST_SIGNAL GetSuperTrendSignalSilent()
{
   if (SuperTrend_Handle == INVALID_HANDLE)
   {
      if (!InitSuperTrend()) return ST_SIGNAL_NONE;
   }
   
   double st_direction[3];
   
   if (CopyBuffer(SuperTrend_Handle, 2, 0, 3, st_direction) < 3)
   {
      return ST_SIGNAL_NONE;
   }
   
   if (st_direction[1] == 0 && st_direction[2] == 1)
      return ST_SIGNAL_SELL;
   else if (st_direction[1] == 1 && st_direction[2] == 0)
      return ST_SIGNAL_BUY;
   
   return ST_SIGNAL_NONE;
}

//+------------------------------------------------------------------+
//| Function to get SuperTrend signal from execution timeframe     |
//+------------------------------------------------------------------+
ENUM_ST_SIGNAL GetExecutionTimeframeSignal()
{
   if (ExecutionTimeframe_Handle == INVALID_HANDLE)
   {
      Print("Execution timeframe SuperTrend handle is invalid, attempting to initialize...");
      if (!InitExecutionTimeframeSuperTrend()) return ST_SIGNAL_NONE;
   }
   
   double st_direction[5];  // Get more values for better analysis
   
   // Copy TrendDirection buffer data (buffer 2)
   if (CopyBuffer(ExecutionTimeframe_Handle, 2, 0, 5, st_direction) < 5)
   {
      return ST_SIGNAL_NONE;
   }
   
   // Check if we have valid data (not EMPTY_VALUE)
   bool hasValidData = false;
   for(int i = 1; i < 5; i++)  // Start from index 1, skip current candle [0]
   {
      if(st_direction[i] != EMPTY_VALUE)
      {
         hasValidData = true;
         break;
      }
   }
   
   if(!hasValidData)
   {
      Print("Execution timeframe SuperTrend indicator data not ready yet");
      return ST_SIGNAL_NONE;
   }
   
   ENUM_ST_SIGNAL signal = ST_SIGNAL_NONE;
   
   // Check for SELL signal (trend changes from 1 to 0)
   if (st_direction[1] == 0 && st_direction[2] == 1)
   {
      signal = ST_SIGNAL_SELL;
   }
   // Check for BUY signal (trend changes from 0 to 1)
   else if (st_direction[1] == 1 && st_direction[2] == 0)
   {
      signal = ST_SIGNAL_BUY;
   }
   
   return signal;
}

//+------------------------------------------------------------------+
//| Function to get current SuperTrend trend direction              |
//+------------------------------------------------------------------+
string GetSuperTrendDirection()
{
   if (SuperTrend_Handle == INVALID_HANDLE)
   {
      if (!InitSuperTrend()) return "ERROR";
   }
   
   double st_direction[1];
   
   if (CopyBuffer(SuperTrend_Handle, 2, 0, 1, st_direction) < 1)
   {
      return "ERROR";
   }
   
   if (st_direction[0] == 0)
      return "UPTREND";
   else if (st_direction[0] == 1)
      return "DOWNTREND";
   else
      return "NEUTRAL";
}

//+------------------------------------------------------------------+
//| Cleanup SuperTrend indicator handle                             |
//+------------------------------------------------------------------+
void DeinitSuperTrend()
{
   if (SuperTrend_Handle != INVALID_HANDLE)
   {
      IndicatorRelease(SuperTrend_Handle);
      SuperTrend_Handle = INVALID_HANDLE;
      Print("SuperTrend indicator handle released");
   }
}

//+------------------------------------------------------------------+
//| Get SuperTrend indicator handle for any symbol and timeframe    |
//+------------------------------------------------------------------+
int GetSuperTrendHandle(string symbol, int timeframe)
{
   int handle = iCustom(symbol, (ENUM_TIMEFRAMES)timeframe, "Supertrend",
                        IndicatorName, ATRMultiplier, ATRPeriod, ATRMaxBars, IndicatorShift,
                        EnableNotify, SendAlert, SendApp, SendEmail, TriggerCandle);
   if(handle == INVALID_HANDLE)
   {
      Print("Failed to create SuperTrend indicator handle for ", symbol, " ", EnumToString((ENUM_TIMEFRAMES)timeframe), ". Error: ", GetLastError());
   }
   return handle;
}

//+------------------------------------------------------------------+
//| Get SuperTrend signal (BUY/SELL/NONE) for any symbol/timeframe  |
//+------------------------------------------------------------------+
ENUM_ST_SIGNAL GetSuperTrendSignalForTimeframe(string symbol, int timeframe)
{
   int handle = GetSuperTrendHandle(symbol, timeframe);
   if(handle == INVALID_HANDLE)
      return ST_SIGNAL_NONE;
   double st_direction[3];
   if(CopyBuffer(handle, 2, 0, 3, st_direction) < 3)
   {
      IndicatorRelease(handle);
      return ST_SIGNAL_NONE;
   }
   // Get current values
   double currentValue = st_direction[1];
   ENUM_ST_SIGNAL signal = ST_SIGNAL_NONE;
   if(currentValue == 0)
      signal = ST_SIGNAL_BUY;
   else if(currentValue == 1)
      signal = ST_SIGNAL_SELL;
   IndicatorRelease(handle);
   return signal;
}

//--- Global variables
double current_spread = 0.0;
static datetime last_candle_time = 0;
static datetime last_execution_candle_time = 0;  // Track execution timeframe candle time
static ENUM_ST_SIGNAL last_signal = ST_SIGNAL_NONE;
static double last_stLinePrice = 0;
int ExecutionTimeframe_Handle = INVALID_HANDLE;  // Handle for execution timeframe SuperTrend
input bool takePositionsAtStart = true;
input double takeProfitForPosition = 220.0;  // Take profit in account currency
input double stopLossForPosition = 50.0;    // Stop loss in account currency
input bool trackMajorTrend = true;
input ENUM_TIMEFRAMES tradeWithMajorTrend = PERIOD_M15;
input ENUM_TIMEFRAMES tradeExecutionTimeframe = PERIOD_M5;  // Timeframe for trade execution signals
input double lotSize = 0.01;
input bool checkOverAllPositionsForProfit = true;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   // Get and store the current spread using the included function
   current_spread = GetSpread();
   // Initialize SuperTrend indicator
   if (!InitSuperTrend())
   {
      Print("Failed to initialize SuperTrend indicator");
      return(INIT_FAILED);
   }
   
   // Initialize execution timeframe SuperTrend indicator
   if (!InitExecutionTimeframeSuperTrend())
   {
      Print("Failed to initialize execution timeframe SuperTrend indicator");
      return(INIT_FAILED);
   }
   Sleep(1000);
   getMajorTrend();
   Comment("Expert Advisor initialized. Initial spread: ", current_spread);
   return(INIT_SUCCEEDED);
}
//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   // Clean up SuperTrend indicator handle
   DeinitSuperTrend();
   
   // Clean up execution timeframe SuperTrend indicator handle
   if (ExecutionTimeframe_Handle != INVALID_HANDLE)
   {
      IndicatorRelease(ExecutionTimeframe_Handle);
      ExecutionTimeframe_Handle = INVALID_HANDLE;
      Print("Execution timeframe SuperTrend indicator handle released");
   }
}
//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   checkProfit();
   
   // Check execution timeframe for trade signals
   datetime execution_candle_time = iTime(_Symbol, tradeExecutionTimeframe, 0);
   double stLinePrice = 0;
   
   if (execution_candle_time != last_execution_candle_time)
   {
      ENUM_ST_SIGNAL execution_signal = GetExecutionTimeframeSignal();
      double st_line[1];      
      double spread = GetSpread() * 2.5;
      int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
      datetime expiration = 0; // Good till cancel
      double stopLoss = 0;
      double takeProfit = 0;
      
      // Get SuperTrend line price from execution timeframe
      if (CopyBuffer(ExecutionTimeframe_Handle, 0, 1, 1, st_line) == 1)
      {
         stLinePrice = st_line[0];
      }
      
      int majorTrend = trackMajorTrend ? getMajorTrend() : execution_signal;
      
      if (execution_signal != ST_SIGNAL_NONE && execution_signal != last_signal)
      {
         Print("Trade signal detected on ", EnumToString(tradeExecutionTimeframe), " timeframe: ", 
               (execution_signal == ST_SIGNAL_BUY ? "BUY" : "SELL"));
         
         // Close all positions on any signal change
         // CloseAllPositions();
         if(execution_signal == ST_SIGNAL_BUY && (!trackMajorTrend || majorTrend == 1))
         {
            if(takePositionsAtStart){
               m_trade.Buy(lotSize, _Symbol, 0, stopLoss, takeProfit, "SuperTrend Buy - " + EnumToString(tradeExecutionTimeframe));
            }
            // else{
               double price = stLinePrice + spread;
               price = NormalizeDouble(price, digits);
               PlaceBuyStop(lotSize, price, "SuperTrend Buy Stop - " + EnumToString(tradeExecutionTimeframe));
            // }
         }
         else if(execution_signal == ST_SIGNAL_SELL && (!trackMajorTrend || majorTrend == -1))
         {
            if(takePositionsAtStart){
               m_trade.Sell(lotSize, _Symbol, 0, stopLoss, takeProfit, "SuperTrend Sell - " + EnumToString(tradeExecutionTimeframe));
            }
            // else{
               double price = stLinePrice - spread;
               price = NormalizeDouble(price, digits);
               PlaceSellStop(lotSize, price, "SuperTrend Sell Stop - " + EnumToString(tradeExecutionTimeframe));
            // }
         }
         last_signal = execution_signal;
      }
      else
      {
         // Update pending orders based on execution timeframe SuperTrend line
         double buyPrice = NormalizeDouble(stLinePrice + spread, digits);
         double sellPrice = NormalizeDouble(stLinePrice - spread, digits);
         if (stLinePrice != last_stLinePrice)
         {
            updateOrder(buyPrice, sellPrice);
         }
      }
      last_stLinePrice = stLinePrice;
      last_execution_candle_time = execution_candle_time;
   }
}

void updateOrder(double buyPrice, double sellPrice) {
   for(int i=0; i<OrdersTotal(); i++)
   {
      ulong ticket = OrderGetTicket(i);
      if(OrderGetString(ORDER_SYMBOL) == _Symbol && OrderGetInteger(ORDER_TYPE) == ORDER_TYPE_BUY_LIMIT)
      {
         double oldPrice = OrderGetDouble(ORDER_PRICE_OPEN);
         if(MathAbs(oldPrice - buyPrice) > SymbolInfoDouble(_Symbol, SYMBOL_POINT) * 0.5)
            ModifyPendingOrder(ticket, buyPrice, 0, 0, ORDER_TIME_GTC, 0, 0.0);
      }
      if(OrderGetString(ORDER_SYMBOL) == _Symbol && OrderGetInteger(ORDER_TYPE) == ORDER_TYPE_SELL_LIMIT)
      {
         double oldPrice = OrderGetDouble(ORDER_PRICE_OPEN);
         if(MathAbs(oldPrice - sellPrice) > SymbolInfoDouble(_Symbol, SYMBOL_POINT) * 0.5)
            ModifyPendingOrder(ticket, sellPrice, 0, 0, ORDER_TIME_GTC, 0, 0.0);
      }
   }
}

void checkProfit() {
   // Skip if both TP and SL are disabled (set to 0)
   if(takeProfitForPosition == 0 && stopLossForPosition == 0)
      return;
      
   // Convert stopLoss to negative if it's positive
   double stopLoss = stopLossForPosition > 0 ? -stopLossForPosition : stopLossForPosition;
   
   if(checkOverAllPositionsForProfit) {
      // Calculate total profit across all positions
      double totalProfit = 0;
      for(int i=PositionsTotal()-1; i>=0; i--)
      {
         ulong ticket = PositionGetTicket(i);
         if(PositionGetString(POSITION_SYMBOL) == _Symbol)
         {
            totalProfit += PositionGetDouble(POSITION_PROFIT);
         }
      }
      
      // Check take profit and stop loss on total profit
      bool tpHit = (takeProfitForPosition != 0 && totalProfit >= takeProfitForPosition);
      bool slHit = (stopLossForPosition != 0 && totalProfit <= stopLoss);
      
      // Close all positions if either condition is met
      if(tpHit || slHit) {
         CloseAllPositions();
      }
      if(tpHit) {
         CancelAllPendingOrders();
      }
   }
   else {
      // Check each position's profit/loss individually
      for(int i=PositionsTotal()-1; i>=0; i--)
      {
         ulong ticket = PositionGetTicket(i);
         if(PositionGetString(POSITION_SYMBOL) == _Symbol)
         {
            double posProfit = PositionGetDouble(POSITION_PROFIT);
            
            // Check take profit if enabled
            bool tpHit = (takeProfitForPosition != 0 && posProfit >= takeProfitForPosition);
            // Check stop loss if enabled
            bool slHit = (stopLossForPosition != 0 && posProfit <= stopLoss);
            
            if(tpHit || slHit)
            {
               m_trade.PositionClose(ticket);
            }
         }
      }
   }
}

int getMajorTrend() {
   // Use SuperTrend on the higher timeframe (tradeWithMajorTrend) to determine major trend
   ENUM_ST_SIGNAL majorSignal = GetSuperTrendSignalForTimeframe(_Symbol, (int)tradeWithMajorTrend);
   
   // Convert signal to trend value
   switch(majorSignal) {
      case ST_SIGNAL_BUY:  return 1;   // Uptrend
      case ST_SIGNAL_SELL: return -1;  // Downtrend
      default:             return 0;   // No trend
   }
}
//+------------------------------------------------------------------+
