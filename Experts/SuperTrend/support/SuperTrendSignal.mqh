//+------------------------------------------------------------------+
//|                                              SuperTrendSignal.mqh |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

//--- SuperTrend parameters (matching the indicator)
input string IndicatorName = "SPRTRND"; // Objects Prefix
input double ATRMultiplier = 1.0;       // ATR Multiplier
input int ATRPeriod = 27;                // ATR Period
input int ATRMaxBars = 10000;            // ATR Max Bars
input int IndicatorShift = 0;            // Indicator shift
input bool EnableNotify = false;         // Enable notifications
input bool SendAlert = false;            // Send alert
input bool SendApp = false;              // Send push notification
input bool SendEmail = false;            // Send email
input int TriggerCandle = 1;             // Trigger Candle (0=Current, 1=Previous)

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