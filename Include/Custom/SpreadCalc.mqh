//+------------------------------------------------------------------+
//|                                                    SpreadCalc.mqh |
//|                                         Copyright 2025, Supertrend |
//|                                                                    |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, Supertrend"
#property link      ""
#property version   "1.00"

//+------------------------------------------------------------------+
//| Simple functions to get spread between bid and ask prices          |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| Get spread in points                                              |
//+------------------------------------------------------------------+
int GetSpreadPoints(string symbol = NULL)
{
   if(symbol == NULL)
      symbol = Symbol();
   
   return (int)SymbolInfoInteger(symbol, SYMBOL_SPREAD);
}

//+------------------------------------------------------------------+
//| Get spread in price difference                                    |
//+------------------------------------------------------------------+
double GetSpread(string symbol = NULL)
{
   if(symbol == NULL)
      symbol = Symbol();
   
   double ask = SymbolInfoDouble(symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(symbol, SYMBOL_BID);
   
   return (ask - bid);
}