//+------------------------------------------------------------------+
//|                                           TimeFrameSelection.mqh |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

//--- Input parameters for timeframe selection
input group "=== TIMEFRAME SELECTION ==="
input bool UseTF_M1 = true;         // Use M1 timeframe
input bool UseTF_M2 = false;        // Use M2 timeframe
input bool UseTF_M3 = false;        // Use M3 timeframe
input bool UseTF_M5 = true;         // Use M5 timeframe
input bool UseTF_M10 = false;       // Use M10 timeframe
input bool UseTF_M15 = true;        // Use M15 timeframe
input bool UseTF_M30 = false;       // Use M30 timeframe
input bool UseTF_H1 = false;        // Use H1 timeframe
input bool UseTF_H2 = false;        // Use H2 timeframe
input bool UseTF_H3 = false;        // Use H3 timeframe
input bool UseTF_H4 = false;        // Use H4 timeframe
input bool UseTF_H6 = false;        // Use H6 timeframe
input bool UseTF_H8 = false;        // Use H8 timeframe
input bool UseTF_H12 = false;       // Use H12 timeframe
input bool UseTF_D1 = false;        // Use Daily timeframe
input bool UseTF_W1 = false;        // Use Weekly timeframe
input bool UseTF_MN1 = false;       // Use Monthly timeframe

input group "=== MAJOR TIMEFRAME ==="
input ENUM_TIMEFRAMES MajorTimeframe = PERIOD_H1;  // Major timeframe (must be higher than selected timeframes)

//--- Global variables for timeframe management
ENUM_TIMEFRAMES selectedTimeframes[];
int totalSelectedTimeframes = 0;

//+------------------------------------------------------------------+
//| Get timeframe value for comparison (lower value = shorter timeframe) |
//+------------------------------------------------------------------+
int GetTimeframeValue(ENUM_TIMEFRAMES tf)
{
   switch(tf)
   {
      case PERIOD_M1:   return 1;
      case PERIOD_M2:   return 2;
      case PERIOD_M3:   return 3;
      case PERIOD_M5:   return 5;
      case PERIOD_M10:  return 10;
      case PERIOD_M15:  return 15;
      case PERIOD_M30:  return 30;
      case PERIOD_H1:   return 60;
      case PERIOD_H2:   return 120;
      case PERIOD_H3:   return 180;
      case PERIOD_H4:   return 240;
      case PERIOD_H6:   return 360;
      case PERIOD_H8:   return 480;
      case PERIOD_H12:  return 720;
      case PERIOD_D1:   return 1440;
      case PERIOD_W1:   return 10080;
      case PERIOD_MN1:  return 43200;
      default:          return 0;
   }
}

//+------------------------------------------------------------------+
//| Get timeframe name string                                        |
//+------------------------------------------------------------------+
string GetTimeframeName(ENUM_TIMEFRAMES tf)
{
   switch(tf)
   {
      case PERIOD_M1:   return "M1";
      case PERIOD_M2:   return "M2";
      case PERIOD_M3:   return "M3";
      case PERIOD_M5:   return "M5";
      case PERIOD_M10:  return "M10";
      case PERIOD_M15:  return "M15";
      case PERIOD_M30:  return "M30";
      case PERIOD_H1:   return "H1";
      case PERIOD_H2:   return "H2";
      case PERIOD_H3:   return "H3";
      case PERIOD_H4:   return "H4";
      case PERIOD_H6:   return "H6";
      case PERIOD_H8:   return "H8";
      case PERIOD_H12:  return "H12";
      case PERIOD_D1:   return "D1";
      case PERIOD_W1:   return "W1";
      case PERIOD_MN1:  return "MN1";
      default:          return "Unknown";
   }
}

//+------------------------------------------------------------------+
//| Collect selected timeframes and validate against major timeframe |
//+------------------------------------------------------------------+
bool CollectAndValidateTimeframes()
{
   // Clear previous selections
   ArrayFree(selectedTimeframes);
   totalSelectedTimeframes = 0;
   
   // Collect all selected timeframes
   if(UseTF_M1)   { ArrayResize(selectedTimeframes, ++totalSelectedTimeframes); selectedTimeframes[totalSelectedTimeframes-1] = PERIOD_M1; }
   if(UseTF_M2)   { ArrayResize(selectedTimeframes, ++totalSelectedTimeframes); selectedTimeframes[totalSelectedTimeframes-1] = PERIOD_M2; }
   if(UseTF_M3)   { ArrayResize(selectedTimeframes, ++totalSelectedTimeframes); selectedTimeframes[totalSelectedTimeframes-1] = PERIOD_M3; }
   if(UseTF_M5)   { ArrayResize(selectedTimeframes, ++totalSelectedTimeframes); selectedTimeframes[totalSelectedTimeframes-1] = PERIOD_M5; }
   if(UseTF_M10)  { ArrayResize(selectedTimeframes, ++totalSelectedTimeframes); selectedTimeframes[totalSelectedTimeframes-1] = PERIOD_M10; }
   if(UseTF_M15)  { ArrayResize(selectedTimeframes, ++totalSelectedTimeframes); selectedTimeframes[totalSelectedTimeframes-1] = PERIOD_M15; }
   if(UseTF_M30)  { ArrayResize(selectedTimeframes, ++totalSelectedTimeframes); selectedTimeframes[totalSelectedTimeframes-1] = PERIOD_M30; }
   if(UseTF_H1)   { ArrayResize(selectedTimeframes, ++totalSelectedTimeframes); selectedTimeframes[totalSelectedTimeframes-1] = PERIOD_H1; }
   if(UseTF_H2)   { ArrayResize(selectedTimeframes, ++totalSelectedTimeframes); selectedTimeframes[totalSelectedTimeframes-1] = PERIOD_H2; }
   if(UseTF_H3)   { ArrayResize(selectedTimeframes, ++totalSelectedTimeframes); selectedTimeframes[totalSelectedTimeframes-1] = PERIOD_H3; }
   if(UseTF_H4)   { ArrayResize(selectedTimeframes, ++totalSelectedTimeframes); selectedTimeframes[totalSelectedTimeframes-1] = PERIOD_H4; }
   if(UseTF_H6)   { ArrayResize(selectedTimeframes, ++totalSelectedTimeframes); selectedTimeframes[totalSelectedTimeframes-1] = PERIOD_H6; }
   if(UseTF_H8)   { ArrayResize(selectedTimeframes, ++totalSelectedTimeframes); selectedTimeframes[totalSelectedTimeframes-1] = PERIOD_H8; }
   if(UseTF_H12)  { ArrayResize(selectedTimeframes, ++totalSelectedTimeframes); selectedTimeframes[totalSelectedTimeframes-1] = PERIOD_H12; }
   if(UseTF_D1)   { ArrayResize(selectedTimeframes, ++totalSelectedTimeframes); selectedTimeframes[totalSelectedTimeframes-1] = PERIOD_D1; }
   if(UseTF_W1)   { ArrayResize(selectedTimeframes, ++totalSelectedTimeframes); selectedTimeframes[totalSelectedTimeframes-1] = PERIOD_W1; }
   if(UseTF_MN1)  { ArrayResize(selectedTimeframes, ++totalSelectedTimeframes); selectedTimeframes[totalSelectedTimeframes-1] = PERIOD_MN1; }
   
   // Check if at least one timeframe is selected
   if(totalSelectedTimeframes == 0)
   {
      Print("ERROR: No timeframes selected for trading. Please select at least one timeframe.");
      Alert("ERROR: No timeframes selected for trading. Please select at least one timeframe.");
      return false;
   }
   
   // Validate that major timeframe is greater than all selected timeframes
   int majorTfValue = GetTimeframeValue(MajorTimeframe);
   string invalidTimeframes = "";
   bool hasInvalidTimeframes = false;
   
   for(int i = 0; i < totalSelectedTimeframes; i++)
   {
      int selectedTfValue = GetTimeframeValue(selectedTimeframes[i]);
      if(majorTfValue <= selectedTfValue)
      {
         if(hasInvalidTimeframes) invalidTimeframes += ", ";
         invalidTimeframes += GetTimeframeName(selectedTimeframes[i]);
         hasInvalidTimeframes = true;
      }
   }
   
   if(hasInvalidTimeframes)
   {
      string errorMsg = StringFormat("ERROR: Major timeframe (%s) must be greater than all selected trading timeframes. Invalid timeframes: %s", 
                                   GetTimeframeName(MajorTimeframe), invalidTimeframes);
      Print(errorMsg);
      Alert(errorMsg);
      return false;
   }
   
   // Print successful validation
   string selectedTfList = "";
   for(int i = 0; i < totalSelectedTimeframes; i++)
   {
      if(i > 0) selectedTfList += ", ";
      selectedTfList += GetTimeframeName(selectedTimeframes[i]);
   }
   
   Print("Timeframe validation successful!");
   Print("Selected trading timeframes: ", selectedTfList);
   Print("Major timeframe: ", GetTimeframeName(MajorTimeframe));
   
   return true;
}

//+------------------------------------------------------------------+
//| Get array of selected timeframes                                |
//+------------------------------------------------------------------+
void GetSelectedTimeframes(ENUM_TIMEFRAMES &timeframes[])
{
   ArrayResize(timeframes, totalSelectedTimeframes);
   for(int i = 0; i < totalSelectedTimeframes; i++)
   {
      timeframes[i] = selectedTimeframes[i];
   }
}

//+------------------------------------------------------------------+
//| Get total count of selected timeframes                          |
//+------------------------------------------------------------------+
int GetSelectedTimeframesCount()
{
   return totalSelectedTimeframes;
}

//+------------------------------------------------------------------+
//| Get major timeframe                                             |
//+------------------------------------------------------------------+
ENUM_TIMEFRAMES GetMajorTimeframe()
{
   return MajorTimeframe;
}

//+------------------------------------------------------------------+
//| Check if a specific timeframe is selected                       |
//+------------------------------------------------------------------+
bool IsTimeframeSelected(ENUM_TIMEFRAMES tf)
{
   for(int i = 0; i < totalSelectedTimeframes; i++)
   {
      if(selectedTimeframes[i] == tf)
         return true;
   }
   return false;
}