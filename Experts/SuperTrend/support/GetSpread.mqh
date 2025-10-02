//+------------------------------------------------------------------+
//|                                                    GetSpread.mqh |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

//+------------------------------------------------------------------+
//| Function to get current spread                                   |
//+------------------------------------------------------------------+
double GetSpread()
  {
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double spread = ask - bid;
   
   // Convert to points if needed
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double spread_points = spread / point;
   
//    Print("Current spread: ", spread, " (", spread_points, " points)");
   return spread;
  }

//+------------------------------------------------------------------+
//| Function to get spread in points                                 |
//+------------------------------------------------------------------+
double GetSpreadPoints()
  {
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double spread = ask - bid;
   
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double spread_points = spread / point;
   
   return spread_points;
  }

//+------------------------------------------------------------------+
//| Function to get spread without printing                         |
//+------------------------------------------------------------------+
double GetSpreadSilent()
  {
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   return (ask - bid);
  }