//+------------------------------------------------------------------+
//|                                              SuperTrendLines.mqh |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

//--- Drawing parameters
input group "=== DRAWING PARAMETERS ==="
input bool DrawSuperTrendLines = true;   // Draw SuperTrend horizontal lines
input bool ShowTimeframeLabels = true;   // Show timeframe labels on lines
input int LineWidth = 2;                 // Line width
input ENUM_LINE_STYLE LineStyle = STYLE_SOLID; // Line style
input int TextFontSize = 18;              // Font size for labels
input string TextFont = "Arial";         // Font for labels

//--- Color array for different timeframes
color TimeframeColors[] = {
   clrBlue,      // For first timeframe
   clrRed,       // For second timeframe  
   clrGreen,     // For third timeframe
   clrViolet,    // For fourth timeframe
   clrPurple,    // For fifth timeframe
   clrChocolate,    // For sixth timeframe
   clrCyan,      // For seventh timeframe
   clrMagenta    // For eighth timeframe
};

//--- Global variables for line management
static datetime last_update_time = 0;

//+------------------------------------------------------------------+
//| Create or update horizontal line for SuperTrend                 |
//+------------------------------------------------------------------+
void CreateOrUpdateSuperTrendLine(string lineName, double price, color lineColor, int width = 2, ENUM_LINE_STYLE style = STYLE_SOLID)
{
   if(!DrawSuperTrendLines) return;
   
   // Delete existing line if it exists
   if(ObjectFind(0, lineName) >= 0)
   {
      ObjectDelete(0, lineName);
   }
   
   // Delete existing text label if it exists
   string textName = lineName + "_Text";
   if(ObjectFind(0, textName) >= 0)
   {
      ObjectDelete(0, textName);
   }
   
   // Create new horizontal line
   if(ObjectCreate(0, lineName, OBJ_HLINE, 0, 0, price))
   {
      ObjectSetInteger(0, lineName, OBJPROP_COLOR, lineColor);
      ObjectSetInteger(0, lineName, OBJPROP_WIDTH, width);
      ObjectSetInteger(0, lineName, OBJPROP_STYLE, style);
      ObjectSetInteger(0, lineName, OBJPROP_BACK, false);
      ObjectSetInteger(0, lineName, OBJPROP_SELECTABLE, true);
      ObjectSetInteger(0, lineName, OBJPROP_HIDDEN, false);
      ObjectSetString(0, lineName, OBJPROP_TOOLTIP, lineName + ": " + DoubleToString(price, _Digits));
   }
   
   // Create text label for the line (only if enabled)
   if(ShowTimeframeLabels)
   {
      string timeframeName = "";
      if(StringFind(lineName, "_Major_") >= 0)
      {
         // Extract timeframe name from major line
         int pos = StringFind(lineName, "_Major_") + 7;
         timeframeName = StringSubstr(lineName, pos) + "MTF";
      }
      else
      {
         // Extract timeframe name from regular line
         int pos = StringFind(lineName, "ST_Line_") + 8;
         timeframeName = StringSubstr(lineName, pos);
      }
      
      datetime currentTime = TimeCurrent();
      if(ObjectCreate(0, textName, OBJ_TEXT, 0, currentTime, price))
      {
         ObjectSetString(0, textName, OBJPROP_TEXT, timeframeName + " ST: " + DoubleToString(price, _Digits));
         ObjectSetInteger(0, textName, OBJPROP_COLOR, lineColor);
         ObjectSetInteger(0, textName, OBJPROP_FONTSIZE, TextFontSize);
         ObjectSetString(0, textName, OBJPROP_FONT, TextFont);
         ObjectSetInteger(0, textName, OBJPROP_ANCHOR, ANCHOR_LEFT);
         ObjectSetInteger(0, textName, OBJPROP_BACK, false);
         ObjectSetInteger(0, textName, OBJPROP_SELECTABLE, false);
         ObjectSetInteger(0, textName, OBJPROP_HIDDEN, false);
      }
   }
}

//+------------------------------------------------------------------+
//| Remove all SuperTrend lines                                     |
//+------------------------------------------------------------------+
void RemoveAllSuperTrendLines()
{
   // Remove all objects that start with "ST_Line_"
   int totalObjects = ObjectsTotal(0);
   for(int i = totalObjects - 1; i >= 0; i--)
   {
      string objName = ObjectName(0, i);
      if(StringFind(objName, "ST_Line_") == 0)
      {
         ObjectDelete(0, objName);
      }
   }
}

//+------------------------------------------------------------------+
//| Remove all SuperTrend lines (legacy function for compatibility) |
//+------------------------------------------------------------------+
void RemoveAllSuperTrendLinesLegacy()
{
   // Get selected timeframes
   ENUM_TIMEFRAMES selectedTFs[];
   GetSelectedTimeframes(selectedTFs);
   
   // Remove lines and text labels for selected timeframes
   for(int i = 0; i < ArraySize(selectedTFs); i++)
   {
      string lineName = "ST_Line_" + GetTimeframeName(selectedTFs[i]);
      string textName = lineName + "_Text";
      
      if(ObjectFind(0, lineName) >= 0)
      {
         ObjectDelete(0, lineName);
      }
      if(ObjectFind(0, textName) >= 0)
      {
         ObjectDelete(0, textName);
      }
   }
   
   // Remove major timeframe line and text
   string majorLineName = "ST_Line_Major_" + GetTimeframeName(GetMajorTimeframe());
   string majorTextName = majorLineName + "_Text";
   
   if(ObjectFind(0, majorLineName) >= 0)
   {
      ObjectDelete(0, majorLineName);
   }
   if(ObjectFind(0, majorTextName) >= 0)
   {
      ObjectDelete(0, majorTextName);
   }
}

//+------------------------------------------------------------------+
//| Update all SuperTrend lines                                     |
//+------------------------------------------------------------------+
void UpdateSuperTrendLines()
{
   if(!DrawSuperTrendLines) return;
   
   // Get selected timeframes
   ENUM_TIMEFRAMES selectedTFs[];
   GetSelectedTimeframes(selectedTFs);
   
   // Draw lines for each selected timeframe
   for(int i = 0; i < ArraySize(selectedTFs); i++)
   {
      double stLinePrice = GetSuperTrendLineValue(_Symbol, selectedTFs[i]);
      if(stLinePrice > 0)
      {
         string lineName = "ST_Line_" + GetTimeframeName(selectedTFs[i]);
         color lineColor = TimeframeColors[i % ArraySize(TimeframeColors)];
         
         // Check if this is the major timeframe and set to black
         if(selectedTFs[i] == GetMajorTimeframe())
         {
            lineColor = clrBlack;
            lineName = "ST_Line_Major_" + GetTimeframeName(selectedTFs[i]);
         }
         
         CreateOrUpdateSuperTrendLine(lineName, stLinePrice, lineColor, LineWidth, LineStyle);
      }
   }
   
   // Draw major timeframe line if it's not in selected timeframes
   bool majorInSelected = false;
   for(int i = 0; i < ArraySize(selectedTFs); i++)
   {
      if(selectedTFs[i] == GetMajorTimeframe())
      {
         majorInSelected = true;
         break;
      }
   }
   
   if(!majorInSelected)
   {
      double majorStLinePrice = GetSuperTrendLineValue(_Symbol, GetMajorTimeframe());
      if(majorStLinePrice > 0)
      {
         string majorLineName = "ST_Line_Major_" + GetTimeframeName(GetMajorTimeframe());
         CreateOrUpdateSuperTrendLine(majorLineName, majorStLinePrice, clrBlack, LineWidth + 1, LineStyle);
      }
   }
}

//+------------------------------------------------------------------+
//| Update lines with performance optimization                      |
//+------------------------------------------------------------------+
void UpdateSuperTrendLinesOptimized()
{
   // Update SuperTrend lines only once per minute to improve performance
   datetime current_time = TimeGMT();
   if(current_time - last_update_time >= 60 || last_update_time == 0)
   {
      UpdateSuperTrendLines();
      last_update_time = current_time;
   }
}

//+------------------------------------------------------------------+
//| Force immediate update of SuperTrend lines                     |
//+------------------------------------------------------------------+
void ForceUpdateSuperTrendLines()
{
   UpdateSuperTrendLines();
   last_update_time = TimeGMT();
}

//+------------------------------------------------------------------+
//| Initialize SuperTrend lines (call in OnInit)                   |
//+------------------------------------------------------------------+
void InitializeSuperTrendLines()
{
   // Draw initial SuperTrend lines
   UpdateSuperTrendLines();
   last_update_time = TimeGMT();
}

//+------------------------------------------------------------------+
//| Cleanup SuperTrend lines (call in OnDeinit)                    |
//+------------------------------------------------------------------+
void CleanupSuperTrendLines()
{
   // Remove all SuperTrend lines
   RemoveAllSuperTrendLines();
}