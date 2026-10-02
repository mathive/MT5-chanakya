//+------------------------------------------------------------------+
//|                                                  renko_chart.mq5 |
//|                                  Copyright 2024, Gemini-Cli-Devs |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, Gemini-Cli-Devs"
#property link      "https://www.mql5.com"
#property version   "1.00"
#property description "This indicator draws Renko-style bricks in a separate window, tied to the main chart's time axis."

#property indicator_separate_window
#property indicator_buffers 5
#property indicator_plots   1

//--- plot Renko
#property indicator_label1  "Renko"
#property indicator_type1   DRAW_COLOR_CANDLES
#property indicator_color1  clrGreen,clrRed
#property indicator_style1  STYLE_SOLID
#property indicator_width1  1

//--- input parameters
input int InpRenkoBoxSize = 10; // Renko Box Size in points

//--- indicator buffers
double ExtOpenBuffer[];
double ExtHighBuffer[];
double ExtLowBuffer[];
double ExtCloseBuffer[];
double ExtColorBuffer[];

//+------------------------------------------------------------------+
//| Custom indicator initialization function                         |
//+------------------------------------------------------------------+
int OnInit()
  {
//--- indicator buffers mapping
   SetIndexBuffer(0, ExtOpenBuffer,  INDICATOR_DATA);
   SetIndexBuffer(1, ExtHighBuffer,  INDICATOR_DATA);
   SetIndexBuffer(2, ExtLowBuffer,   INDICATOR_DATA);
   SetIndexBuffer(3, ExtCloseBuffer, INDICATOR_DATA);
   SetIndexBuffer(4, ExtColorBuffer, INDICATOR_COLOR_INDEX);

   PlotIndexSetInteger(0, PLOT_DRAW_BEGIN, 1);
   PlotIndexSetString(0, PLOT_LABEL, "Renko");
   IndicatorSetString(INDICATOR_SHORTNAME, "Renko(" + IntegerToString(InpRenkoBoxSize) + ")");

//--- Set empty value for bars where the brick is not drawn
   PlotIndexSetDouble(0, PLOT_EMPTY_VALUE, 0);
//---
   return(INIT_SUCCEEDED);
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
   if(rates_total < 2)
      return 0;

   int limit;
   if(prev_calculated == 0)
     {
      limit = 1;
      // Initialize the first bar with the chart's open/close
      ExtOpenBuffer[0]  = open[0];
      ExtCloseBuffer[0] = close[0];
      ExtHighBuffer[0]  = high[0];
      ExtLowBuffer[0]   = low[0];
      ExtColorBuffer[0] = (close[0] > open[0]) ? 0 : 1;
     }
   else
     {
      limit = prev_calculated - 1;
     }

   double box_size = InpRenkoBoxSize * _Point;
   if(box_size <= 0) // Avoid division by zero or negative size
      return rates_total;

   for(int i = limit; i < rates_total; i++)
     {
      double prev_renko_open  = ExtOpenBuffer[i-1];
      double prev_renko_close = ExtCloseBuffer[i-1];
      
      // If previous bar was empty, use the one before it
      if(prev_renko_open == 0 && prev_renko_close == 0 && i > 1)
      {
         prev_renko_open = ExtOpenBuffer[i-2];
         prev_renko_close = ExtCloseBuffer[i-2];
      }

      double current_price = close[i];
      
      // Default: copy previous brick values
      ExtOpenBuffer[i]  = prev_renko_open;
      ExtCloseBuffer[i] = prev_renko_close;
      ExtHighBuffer[i]  = (prev_renko_close > prev_renko_open) ? prev_renko_close : prev_renko_open;
      ExtLowBuffer[i]   = (prev_renko_close > prev_renko_open) ? prev_renko_open : prev_renko_close;
      ExtColorBuffer[i] = ExtColorBuffer[i-1];

      // --- Determine previous brick direction
      double last_brick_top = MathMax(prev_renko_open, prev_renko_close);
      double last_brick_bottom = MathMin(prev_renko_open, prev_renko_close);

      // --- Trend continuation or reversal
      int move_in_bricks = (int)((current_price - last_brick_top) / box_size);

      if(move_in_bricks >= 1) // Upward movement
      {
         ExtOpenBuffer[i]  = last_brick_top;
         ExtCloseBuffer[i] = last_brick_top + box_size;
         ExtHighBuffer[i]  = ExtCloseBuffer[i];
         ExtLowBuffer[i]   = ExtOpenBuffer[i];
         ExtColorBuffer[i] = 0; // Green
      }
      else
      {
         move_in_bricks = (int)((current_price - last_brick_bottom) / box_size);
         if (move_in_bricks <= -1) // Downward movement
         {
            ExtOpenBuffer[i]  = last_brick_bottom;
            ExtCloseBuffer[i] = last_brick_bottom - box_size;
            ExtHighBuffer[i]  = ExtOpenBuffer[i];
            ExtLowBuffer[i]   = ExtCloseBuffer[i];
            ExtColorBuffer[i] = 1; // Red
         }
      }
     }
   return(rates_total);
  }
//+------------------------------------------------------------------+
