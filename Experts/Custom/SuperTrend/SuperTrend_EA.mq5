//+------------------------------------------------------------------+
//|                                               SuperTrend_EA.mq5 |
//|                        Copyright 2025, MetaQuotes Software Corp. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Software Corp."
#property link      "https://www.mql5.com"
#property version   "1.00"

#include <Trade\Trade.mqh>

//--- Input parameters
input group "=== Supertrend Settings ==="
input double   ATRMultiplier = 9.0;       // ATR Multiplier
input int      ATRPeriod = 27;             // ATR Period
input int      ATRMaxBars = 10000;         // ATR Max Bars

input group "=== Trading Settings ==="
input double   LotSize = 0.1;             // Lot Size
input int      Magic = 123456;            // Magic Number
input bool     CloseOpposite = true;      // Close opposite trades on signal change
input bool     OnlyOnePosition = true;    // Only one position per direction

input group "=== Risk Management ==="
input double   StopLoss = 0;              // Stop Loss (0 = no SL)
input double   TakeProfit = 0;            // Take Profit (0 = no TP)
input bool     UseSupertrendSLTP = true;  // Use Supertrend line as SL/TP

//--- Global variables
CTrade trade;
int supertrend_handle;
double prev_trend_direction = -1;
datetime last_bar_time = 0;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    // Initialize Supertrend indicator
    supertrend_handle = iCustom(_Symbol, _Period, "Supertrend", 
                               "SPRTRND", ATRMultiplier, ATRPeriod, ATRMaxBars, 0, 
                               false, false, false, false, 1);
    
    if(supertrend_handle == INVALID_HANDLE)
    {
        Print("Error creating Supertrend indicator handle");
        return INIT_FAILED;
    }
    
    // Set trade parameters
    trade.SetExpertMagicNumber(Magic);
    trade.SetDeviationInPoints(30);
    trade.SetTypeFilling(ORDER_FILLING_FOK);
    
    Print("SuperTrend EA initialized successfully");
    return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    if(supertrend_handle != INVALID_HANDLE)
        IndicatorRelease(supertrend_handle);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
    // Check if new bar
    datetime current_bar_time = iTime(_Symbol, _Period, 0);
    if(current_bar_time == last_bar_time)
        return;
    last_bar_time = current_bar_time;
    
    // Get Supertrend values
    double trend_direction[];
    double trend_line[];
    ArraySetAsSeries(trend_direction, true);
    ArraySetAsSeries(trend_line, true);
    
    if(CopyBuffer(supertrend_handle, 2, 0, 3, trend_direction) < 3 ||
       CopyBuffer(supertrend_handle, 0, 0, 3, trend_line) < 3)
    {
        Print("Error copying Supertrend buffer data");
        return;
    }
    
    double current_trend = trend_direction[1]; // Previous completed bar
    double current_line = trend_line[1];
    
    // Check for trend change
    if(prev_trend_direction != -1 && prev_trend_direction != current_trend)
    {
        ProcessSignal(current_trend, current_line);
    }
    
    prev_trend_direction = current_trend;
    
    // Update stop losses if using Supertrend SL/TP
    if(UseSupertrendSLTP)
        UpdateStopLosses(current_trend, current_line);
}

//+------------------------------------------------------------------+
//| Process trading signals                                          |
//+------------------------------------------------------------------+
void ProcessSignal(double trend_direction, double trend_line)
{
    double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    
    // Uptrend signal (trend_direction = 0)
    if(trend_direction == 0)
    {
        Print("Uptrend signal detected");
        
        // Close sell positions if enabled
        if(CloseOpposite)
            ClosePositions(POSITION_TYPE_SELL);
        
        // Open buy position
        if(!OnlyOnePosition || !HasPosition(POSITION_TYPE_BUY))
        {
            double sl = 0, tp = 0;
            
            if(UseSupertrendSLTP)
                sl = trend_line;
            else if(StopLoss > 0)
                sl = ask - StopLoss * _Point;
                
            if(TakeProfit > 0 && !UseSupertrendSLTP)
                tp = ask + TakeProfit * _Point;
            
            if(trade.Buy(LotSize, _Symbol, ask, sl, tp, "SuperTrend Buy"))
                Print("Buy order opened at ", ask);
            else
                Print("Error opening buy order: ", trade.ResultRetcode());
        }
    }
    // Downtrend signal (trend_direction = 1)
    else if(trend_direction == 1)
    {
        Print("Downtrend signal detected");
        
        // Close buy positions if enabled
        if(CloseOpposite)
            ClosePositions(POSITION_TYPE_BUY);
        
        // Open sell position
        if(!OnlyOnePosition || !HasPosition(POSITION_TYPE_SELL))
        {
            double sl = 0, tp = 0;
            
            if(UseSupertrendSLTP)
                sl = trend_line;
            else if(StopLoss > 0)
                sl = bid + StopLoss * _Point;
                
            if(TakeProfit > 0 && !UseSupertrendSLTP)
                tp = bid - TakeProfit * _Point;
            
            if(trade.Sell(LotSize, _Symbol, bid, sl, tp, "SuperTrend Sell"))
                Print("Sell order opened at ", bid);
            else
                Print("Error opening sell order: ", trade.ResultRetcode());
        }
    }
}

//+------------------------------------------------------------------+
//| Close positions of specified type                               |
//+------------------------------------------------------------------+
void ClosePositions(ENUM_POSITION_TYPE type)
{
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        if(PositionGetTicket(i) > 0)
        {
            if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
               PositionGetInteger(POSITION_MAGIC) == Magic &&
               PositionGetInteger(POSITION_TYPE) == type)
            {
                ulong ticket = PositionGetTicket(i);
                if(trade.PositionClose(ticket))
                    Print("Position ", ticket, " closed");
                else
                    Print("Error closing position ", ticket, ": ", trade.ResultRetcode());
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Check if position exists                                        |
//+------------------------------------------------------------------+
bool HasPosition(ENUM_POSITION_TYPE type)
{
    for(int i = 0; i < PositionsTotal(); i++)
    {
        if(PositionGetTicket(i) > 0)
        {
            if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
               PositionGetInteger(POSITION_MAGIC) == Magic &&
               PositionGetInteger(POSITION_TYPE) == type)
            {
                return true;
            }
        }
    }
    return false;
}

//+------------------------------------------------------------------+
//| Update stop losses based on Supertrend                         |
//+------------------------------------------------------------------+
void UpdateStopLosses(double trend_direction, double trend_line)
{
    for(int i = 0; i < PositionsTotal(); i++)
    {
        if(PositionGetTicket(i) > 0)
        {
            if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
               PositionGetInteger(POSITION_MAGIC) == Magic)
            {
                ulong ticket = PositionGetTicket(i);
                ENUM_POSITION_TYPE pos_type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
                double current_sl = PositionGetDouble(POSITION_SL);
                double new_sl = 0;
                
                // Update stop loss based on trend direction
                if(pos_type == POSITION_TYPE_BUY && trend_direction == 0)
                {
                    new_sl = trend_line;
                    // Only move SL up (trailing)
                    if(new_sl > current_sl || current_sl == 0)
                    {
                        if(trade.PositionModify(ticket, new_sl, PositionGetDouble(POSITION_TP)))
                            Print("Buy position SL updated to ", new_sl);
                    }
                }
                else if(pos_type == POSITION_TYPE_SELL && trend_direction == 1)
                {
                    new_sl = trend_line;
                    // Only move SL down (trailing)
                    if(new_sl < current_sl || current_sl == 0)
                    {
                        if(trade.PositionModify(ticket, new_sl, PositionGetDouble(POSITION_TP)))
                            Print("Sell position SL updated to ", new_sl);
                    }
                }
            }
        }
    }
}
//+------------------------------------------------------------------+
