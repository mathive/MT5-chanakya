//+------------------------------------------------------------------+
//|                                                 Renko_Custom.mq5 |
//|                                  Copyright 2026, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Gemini Code Assist"
#property link      "https://www.mql5.com"
#property version   "1.00"
#property indicator_separate_window
#property indicator_buffers 3
#property indicator_plots   2 // Only plot Open and Close. Dir is hidden to fix scaling.

//--- Inputs
input int  InpBoxSizePoints = 100;      // Box Size in Points
input int  InpDrawLimit     = 500;      // Max bricks to draw (UI)
input color InpColorUp      = clrLime;  // Up Brick Color
input color InpColorDown    = clrRed;   // Down Brick Color

//--- Buffers (for EA to read)
double BufferOpen[];
double BufferClose[];
double BufferDir[]; // 0=Buy, 1=Sell

//--- Global variables for calculation
double g_BrickHigh = 0;
double g_BrickLow = 0;
int    g_Direction = 0; // 0=Up, 1=Down

//+------------------------------------------------------------------+
//| Custom indicator initialization function                         |
//+------------------------------------------------------------------+
int OnInit()
  {
   // Set up buffers
   SetIndexBuffer(0, BufferOpen, INDICATOR_DATA);
   SetIndexBuffer(1, BufferClose, INDICATOR_DATA);
   SetIndexBuffer(2, BufferDir, INDICATOR_DATA);
   
   PlotIndexSetInteger(0, PLOT_DRAW_TYPE, DRAW_NONE);
   PlotIndexSetInteger(1, PLOT_DRAW_TYPE, DRAW_NONE);
   
   // Naming for Data Window
   PlotIndexSetString(0, PLOT_LABEL, "RenkoOpen");
   PlotIndexSetString(1, PLOT_LABEL, "RenkoClose");

   Print("Renko_Custom Indicator Loaded. BoxSize: ", InpBoxSizePoints);
   
   ArrayInitialize(BufferOpen, 0.0);
   ArrayInitialize(BufferClose, 0.0);
   ArrayInitialize(BufferDir, 0.0);
   
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Custom indicator deinitialization function                       |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   ObjectsDeleteAll(0, "Renko_");
  }

//+------------------------------------------------------------------+
//| Custom indicator iteration function                              |
//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
  {
   if(rates_total < 2) return(0);

   int start = prev_calculated - 1;
   if(start < 0)
     {
      start = 0;
      // Initialize first brick based on first bar
      g_BrickHigh = close[0];
      g_BrickLow  = close[0] - InpBoxSizePoints * Point();
      g_Direction = 0;
      
      BufferOpen[0] = g_BrickLow;
      BufferClose[0] = g_BrickHigh;
      BufferDir[0] = 0;
     }

   // Loop through bars
   for(int i = start; i < rates_total; i++)
     {
      // If we are recalculating the last bar, restore state from previous bar
      if(i > 0)
        {
         // Retrieve state from the previous calculated bar
         double prevOpen = BufferOpen[i-1];
         double prevClose = BufferClose[i-1];
         double prevDir = BufferDir[i-1];
         
         // Reconstruct high/low from open/close
         if(prevDir < 0.5) // Up (Safe comparison)
           {
            g_BrickHigh = prevClose;
            g_BrickLow  = prevOpen;
            g_Direction = 0;
           }
         else // Down
           {
            g_BrickHigh = prevOpen;
            g_BrickLow  = prevClose;
            g_Direction = 1;
           }
        }

      double price = close[i];
      double boxSize = InpBoxSizePoints * Point();
      
      // Safety check to prevent Division by Zero crash
      if(boxSize <= 0.0) 
        {
         boxSize = (InpBoxSizePoints > 0 ? InpBoxSizePoints : 100) * (Point() > 0 ? Point() : 0.0001);
        }
      
      // Calculate Bricks
      if(g_Direction == 0) // Currently Up
        {
         if(price >= g_BrickHigh + boxSize)
           {
            int numBricks = (int)((price - g_BrickHigh) / boxSize);
            g_BrickHigh += numBricks * boxSize;
            g_BrickLow  = g_BrickHigh - boxSize;
           }
         else if(price <= g_BrickLow - boxSize) // Reversal Down
           {
            int numBricks = (int)((g_BrickLow - price) / boxSize) + 1;
            g_BrickLow = g_BrickLow - (numBricks - 1) * boxSize; // New Low
            g_BrickHigh = g_BrickLow + boxSize; // New High (Open of down brick)
            g_Direction = 1;
           }
        }
      else // Currently Down
        {
         if(price <= g_BrickLow - boxSize)
           {
            int numBricks = (int)((g_BrickLow - price) / boxSize);
            g_BrickLow -= numBricks * boxSize;
            g_BrickHigh = g_BrickLow + boxSize;
           }
         else if(price >= g_BrickHigh + boxSize) // Reversal Up
           {
            int numBricks = (int)((price - g_BrickHigh) / boxSize) + 1;
            g_BrickHigh = g_BrickHigh + (numBricks - 1) * boxSize;
            g_BrickLow = g_BrickHigh - boxSize;
            g_Direction = 0;
           }
        }

      // Store state in buffers
      if(g_Direction == 0)
        {
         BufferOpen[i]  = g_BrickLow;
         BufferClose[i] = g_BrickHigh;
         BufferDir[i]   = 0;
        }
      else
        {
         BufferOpen[i]  = g_BrickHigh;
         BufferClose[i] = g_BrickLow;
         BufferDir[i]   = 1;
        }
        
      // UI: Draw Objects (Only for the last N bars to save performance)
      if(i >= rates_total - InpDrawLimit)
        {
         string name = "Renko_" + IntegerToString(i);
         // Create or update object
         if(ObjectFind(0, name) < 0) ObjectCreate(0, name, OBJ_RECTANGLE, ChartWindowFind(), 0, 0, 0, 0);
         
         ObjectSetInteger(0, name, OBJPROP_TIME, 0, time[i]);
         ObjectSetInteger(0, name, OBJPROP_TIME, 1, time[i] + PeriodSeconds());
         ObjectSetDouble(0, name, OBJPROP_PRICE, 0, BufferOpen[i]);
         ObjectSetDouble(0, name, OBJPROP_PRICE, 1, BufferClose[i]);
         ObjectSetInteger(0, name, OBJPROP_COLOR, (g_Direction == 0 ? InpColorUp : InpColorDown));
         ObjectSetInteger(0, name, OBJPROP_FILL, true);
         ObjectSetInteger(0, name, OBJPROP_BACK, true); // Draw behind candles
        }
        
      // Debug Print for the latest bar (to diagnose "no signal change")
      if(i == rates_total - 1)
        {
         static datetime last_debug = 0;
         if(time[i] > last_debug) // Print once per new bar
           {
            PrintFormat("Renko Debug | Price: %.5f | Box: %.5f | High: %.5f | Low: %.5f | Dir: %d", 
                        price, boxSize, g_BrickHigh, g_BrickLow, g_Direction);
            last_debug = time[i];
           }
        }
     }

   return(rates_total);
  }