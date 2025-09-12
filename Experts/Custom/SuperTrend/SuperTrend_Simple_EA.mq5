//+------------------------------------------------------------------+
//|                                        SuperTrend_Simple_EA.mq5 |
//|                        Copyright 2025, MetaQuotes Software Corp. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Software Corp."
#property link      "https://www.mql5.com"
#property version   "1.00"

#include <Trade\Trade.mqh>

//--- Input parameters
input double   LotSize = 0.1;             // Lot Size
input int      Magic = 123456;            // Magic Number
input bool     CloseOpposite = true;      // Close opposite trades on signal change

//--- Global variables
CTrade trade;
int supertrend_handle;
double last_signal = -1;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    // Create Supertrend indicator handle
    supertrend_handle = iCustom(_Symbol, _Period, "Supertrend");
    
    if(supertrend_handle == INVALID_HANDLE)
    {
        Print("Failed to create Supertrend indicator handle");
        return INIT_FAILED;
    }
    
    // Set trade magic number
    trade.SetExpertMagicNumber(Magic);
    
    Print("SuperTrend Simple EA initialized");
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
    // Get Supertrend signal from buffer 2 (TrendDirection)
    double signal[];
    ArraySetAsSeries(signal, true);
    
    if(CopyBuffer(supertrend_handle, 2, 0, 2, signal) < 2)
        return;
    
    double current_signal = signal[1]; // Previous completed bar
    
    // Check for signal change
    if(last_signal != -1 && last_signal != current_signal)
    {
        // Signal changed - take action
        if(current_signal == 0) // Uptrend
        {
            Print("Uptrend signal - Going LONG");
            
            if(CloseOpposite)
                CloseSellPositions();
            
            OpenBuyPosition();
        }
        else if(current_signal == 1) // Downtrend
        {
            Print("Downtrend signal - Going SHORT");
            
            if(CloseOpposite)
                CloseBuyPositions();
            
            OpenSellPosition();
        }
    }
    
    last_signal = current_signal;
}

//+------------------------------------------------------------------+
//| Open Buy Position                                               |
//+------------------------------------------------------------------+
void OpenBuyPosition()
{
    // Check if buy position already exists
    if(HasBuyPosition())
        return;
    
    double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    
    if(trade.Buy(LotSize, _Symbol, ask, 0, 0, "SuperTrend Buy"))
        Print("Buy position opened at ", ask);
    else
        Print("Failed to open buy position. Error: ", GetLastError());
}

//+------------------------------------------------------------------+
//| Open Sell Position                                              |
//+------------------------------------------------------------------+
void OpenSellPosition()
{
    // Check if sell position already exists
    if(HasSellPosition())
        return;
    
    double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    
    if(trade.Sell(LotSize, _Symbol, bid, 0, 0, "SuperTrend Sell"))
        Print("Sell position opened at ", bid);
    else
        Print("Failed to open sell position. Error: ", GetLastError());
}

//+------------------------------------------------------------------+
//| Close Buy Positions                                            |
//+------------------------------------------------------------------+
void CloseBuyPositions()
{
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        if(PositionGetTicket(i))
        {
            if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
               PositionGetInteger(POSITION_MAGIC) == Magic &&
               PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
            {
                trade.PositionClose(PositionGetTicket(i));
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Close Sell Positions                                           |
//+------------------------------------------------------------------+
void CloseSellPositions()
{
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        if(PositionGetTicket(i))
        {
            if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
               PositionGetInteger(POSITION_MAGIC) == Magic &&
               PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL)
            {
                trade.PositionClose(PositionGetTicket(i));
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Check if Buy Position Exists                                   |
//+------------------------------------------------------------------+
bool HasBuyPosition()
{
    for(int i = 0; i < PositionsTotal(); i++)
    {
        if(PositionGetTicket(i))
        {
            if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
               PositionGetInteger(POSITION_MAGIC) == Magic &&
               PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
            {
                return true;
            }
        }
    }
    return false;
}

//+------------------------------------------------------------------+
//| Check if Sell Position Exists                                  |
//+------------------------------------------------------------------+
bool HasSellPosition()
{
    for(int i = 0; i < PositionsTotal(); i++)
    {
        if(PositionGetTicket(i))
        {
            if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
               PositionGetInteger(POSITION_MAGIC) == Magic &&
               PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL)
            {
                return true;
            }
        }
    }
    return false;
}
//+------------------------------------------------------------------+
