//+------------------------------------------------------------------+
//|                                                     Renko_EA.mq5 |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "1.04"

//--- Enums for indicator parameters
enum RENKO_PRICE_MODE
  {
   RENKO_MODE_CLOSE,    // Use close prices
   RENKO_MODE_HIGH_LOW  // Use high/low prices
  };

enum RENKO_BOX_SIZE_MODE
  {
   RENKO_BOX_SIZE_PIPS, // Box size in pips
   RENKO_BOX_SIZE_ATR   // Box size as a factor of ATR
  };

//--- EA Inputs
input RENKO_PRICE_MODE    InpPriceMode    = RENKO_MODE_CLOSE;       // Price mode
input RENKO_BOX_SIZE_MODE InpBoxSizeMode  = RENKO_BOX_SIZE_PIPS;      // Box size mode
input int                InpRenkoBoxSize = 10;               // Renko Box Size in points (if PIPS mode)
input int                InpAtrPeriod    = 14;               // ATR Period (if ATR mode)

//--- Global variables
int  g_RenkoHandle;
int  g_LastSignal = -1; // -1 for initial state

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   // Initialize the Renko indicator with the correct parameters
   g_RenkoHandle = iCustom(_Symbol, _Period, "Market\\Renko Chart",
                           InpPriceMode,
                           InpBoxSizeMode,
                           InpRenkoBoxSize,
                           InpAtrPeriod);

   if(g_RenkoHandle == INVALID_HANDLE)
     {
      Print("Error initializing iCustom for Renko Chart indicator. Please check the parameters and ensure the indicator is in the Market folder.");
      return(INIT_FAILED);
     }
   Print("Renko_EA initialized successfully with new parameters.");
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   if(g_RenkoHandle != INVALID_HANDLE)
      IndicatorRelease(g_RenkoHandle);
  }

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
   static datetime last_print_time = 0;
   datetime current_time = TimeCurrent();

   // Print a message every 5 seconds to show the EA is alive
   if(current_time - last_print_time >= 5)
     {
      Print("OnTick event running...");
      last_print_time = current_time;
     }

   double renkoSignalBuffer[2]; // Need 2 elements for a reliable copy

   int copied = CopyBuffer(g_RenkoHandle, 2, 0, 2, renkoSignalBuffer);
   if(copied <= 0)
     {
      // This is not necessarily an error, indicator might be calculating.
      // We can print it for debugging, but be aware it can spam the log.
      if(current_time - last_print_time >= 5) // Limit spam
         PrintFormat("Could not copy buffer data. Copied: %d, Error: %d", copied, GetLastError());
      return;
     }

   // For static arrays, the latest value is at the end of the copied block
   int currentSignal = (int)renkoSignalBuffer[1];
   
   // Log the raw signal value for debugging
   if(current_time - last_print_time >= 5)
      PrintFormat("Copied %d values. Raw signal[1]: %.2f", copied, renkoSignalBuffer[1]);

   if(currentSignal != g_LastSignal)
     {
      string signalString = (currentSignal == 0) ? "BUY" : "SELL";
      PrintFormat("Renko Signal Toggled: New signal is %s (raw value: %.2f)", signalString, renkoSignalBuffer[1]);

      g_LastSignal = currentSignal;
     }
  }
//+------------------------------------------------------------------+