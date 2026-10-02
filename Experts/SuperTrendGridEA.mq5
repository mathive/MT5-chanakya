//+------------------------------------------------------------------+
//|                                             SuperTrendGridEA.mq5 |
//|                        Copyright 2026, MetaQuotes Software Corp. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MetaQuotes Software Corp."
#property link      "https://www.mql5.com"
#property version   "1.00"

#include <Trade\Trade.mqh>

//--- Enums for Inputs
enum ENUM_TRADE_DIRECTION
{
    TRADE_BOTH,      // Allow both
    TRADE_BUY_ONLY,  // only Buy
    TRADE_SELL_ONLY  // only Sell
};

//--- EA Inputs
input double LotSize = 0.01;
input ulong MagicNumber = 12345;
input int NumberOfOrders = 3;
input ENUM_TRADE_DIRECTION TradeDirection = TRADE_BOTH; // Trading direction
input ENUM_TIMEFRAMES SignalTimeframe = PERIOD_M1;      // Timeframe for the Supertrend indicator
input double MaxTotalProfit = 50000.0;                     // Maximum total profit to close all positions
input double EachOrderProfit = 25000.0;                    // Profit target for each individual order

//--- Supertrend Indicator Inputs
input int ST_ATRPeriod = 27;         // ATR Period
input double ST_ATRMultiplier = 9.0; // ATR Multiplier
input double FirstOrderPercent = 95.0;          // First order at 90-95% of the ST-to-price range
input double RemainingStartPercent = 50.0;      // Remaining orders start at 50%
input double RemainingEndPercent = 10.0;        // Remaining orders end at 10%

//--- Global variables
CTrade trade;
int supertrend_handle;
int prev_direction = -1; // -1 indicates initial state
double prev_st_price = 0.0; // Previous Supertrend line price

//--- Struct to hold pending order info for sorting
struct PendingOrderInfo
{
    ulong  ticket;
    double price;
};

int CountOpenPositions()
{
    int total_positions = 0;
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        ulong ticket = PositionGetTicket(i);
        if(ticket == 0 || !PositionSelectByTicket(ticket))
            continue;

        if(PositionGetInteger(POSITION_MAGIC) == (long)MagicNumber &&
           PositionGetString(POSITION_SYMBOL) == _Symbol)
        {
            total_positions++;
        }
    }

    return total_positions;
}

int CountPendingOrders()
{
    int total_orders = 0;
    for(int i = OrdersTotal() - 1; i >= 0; i--)
    {
        ulong ticket = OrderGetTicket(i);
        if(ticket == 0)
            continue;

        if(OrderGetInteger(ORDER_MAGIC) == (long)MagicNumber &&
           OrderGetString(ORDER_SYMBOL) == _Symbol)
        {
            total_orders++;
        }
    }

    return total_orders;
}

double GetMinDistancePrice()
{
    int stops_level = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
    int freeze_level = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL);
    int min_level_points = MathMax(stops_level, freeze_level);
    return min_level_points * _Point;
}

bool IsValidPendingPrice(const int direction, const double price)
{
    double current_ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    double current_bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    double min_distance = GetMinDistancePrice();

    if(direction == 0)
        return (price < current_ask - min_distance);
    if(direction == 1)
        return (price > current_bid + min_distance);

    return false;
}

double GetGridPercent(const int grid_index)
{
    if(grid_index <= 1)
        return FirstOrderPercent / 100.0;

    int remaining_slots = NumberOfOrders - 1;
    if(remaining_slots <= 0)
        return FirstOrderPercent / 100.0;

    if(remaining_slots == 1)
        return RemainingStartPercent / 100.0;

    double start_percent = RemainingStartPercent / 100.0;
    double end_percent = RemainingEndPercent / 100.0;
    double step = (start_percent - end_percent) / (remaining_slots - 1);
    double level_percent = start_percent - ((grid_index - 2) * step);

    return MathMax(0.0, MathMin(1.0, level_percent));
}

double CalculateGridPrice(const int direction, const double st_price, const double current_price, const int grid_index)
{
    double percent = GetGridPercent(grid_index);
    double range = MathAbs(current_price - st_price);

    if(direction == 0)
        return NormalizeDouble(st_price + (range * percent), _Digits);
    if(direction == 1)
        return NormalizeDouble(st_price - (range * percent), _Digits);

    return 0.0;
}
//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    if(NumberOfOrders <= 0)
    {
        Print("NumberOfOrders must be greater than zero.");
        return(INIT_PARAMETERS_INCORRECT);
    }
    if(FirstOrderPercent <= 0.0 || FirstOrderPercent >= 100.0)
    {
        Print("FirstOrderPercent must be between 0 and 100.");
        return(INIT_PARAMETERS_INCORRECT);
    }
    if(RemainingStartPercent <= 0.0 || RemainingStartPercent >= 100.0 ||
       RemainingEndPercent <= 0.0 || RemainingEndPercent >= 100.0)
    {
        Print("Remaining zone percentages must be between 0 and 100.");
        return(INIT_PARAMETERS_INCORRECT);
    }
    if(RemainingStartPercent < RemainingEndPercent)
    {
        Print("RemainingStartPercent must be greater than or equal to RemainingEndPercent.");
        return(INIT_PARAMETERS_INCORRECT);
    }

    trade.SetExpertMagicNumber(MagicNumber);
    trade.SetTypeFillingBySymbol(_Symbol);

    ResetLastError();

    supertrend_handle = iCustom(_Symbol, SignalTimeframe, "\\Indicators\\Supertrend",
                             "SPRTRND",
                             ST_ATRMultiplier,
                             ST_ATRPeriod,
                             10000,
                             0,
                             false,
                             false,
                             false,
                             false,
                             1);

    if(supertrend_handle == INVALID_HANDLE)
    {
        Print("Indicator load failed. Error: ", GetLastError());
        return(INIT_FAILED);   // 🔥 VERY IMPORTANT
    }

    Print("Indicator loaded successfully!");

    //--- Refresh pending order prices on initialization
    double st_values[1];
    double st_directions[1];
    
    if(CopyBuffer(supertrend_handle, 0, 1, 1, st_values) == 1 &&
       CopyBuffer(supertrend_handle, 2, 1, 1, st_directions) == 1)
    {
        double current_st_price = st_values[0];
        int current_direction = (int)st_directions[0];
        UpdatePendingOrderPrices(current_direction, current_st_price);
    }

    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    //--- Remove pending orders only when EA is explicitly removed
    if(reason == REASON_REMOVE)
    {
        CancelAllPendingOrders();
    }

    //--- Release indicator handle
    if (supertrend_handle != INVALID_HANDLE)
    {
        IndicatorRelease(supertrend_handle);
    }
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
    //--- Check profit conditions on every tick
    CheckTakeProfit();

    //--- Process only once per closed bar of the configured signal timeframe
    static datetime last_signal_bar_time = 0;
    datetime signal_bar_time[1];
    if(CopyTime(_Symbol, SignalTimeframe, 1, 1, signal_bar_time) < 1)
    {
        Print("Error copying signal timeframe bar time. Error: ", GetLastError());
        return;
    }

    if(signal_bar_time[0] == last_signal_bar_time)
    {
        return;
    }
    last_signal_bar_time = signal_bar_time[0];

    //--- Get Supertrend direction (0 for up, 1 for down)
    double direction_buffer[2];
    // Request 2 bars, check if we actually got 2 bars to prevent out-of-bounds access
    if (CopyBuffer(supertrend_handle, 2, 1, 2, direction_buffer) < 2)
    {
        Print("Error copying Supertrend direction buffer. Error: ", GetLastError());
        return;
    }
    int current_direction = (int)direction_buffer[0];
    int previous_candle_direction = (int)direction_buffer[1];
    
    //--- Get the Supertrend line value for the last completed bar
    double st_value_buffer[1];
    // Request 1 bar, check if we actually got 1 bar
    if (CopyBuffer(supertrend_handle, 0, 1, 1, st_value_buffer) < 1)
    {
        Print("Error copying Supertrend value buffer. Error: ", GetLastError());
        return;
    }
    double current_st_price = st_value_buffer[0];

    //--- On the first run, initialize prev_direction and prev_st_price
    if (prev_direction == -1)
    {
        prev_direction = current_direction;
        prev_st_price = current_st_price;
        
        // Mid-signal attach: place the grid once if nothing is open yet.
        if(previous_candle_direction == current_direction)
        {
            int total_positions = CountOpenPositions();
            int total_orders = CountPendingOrders();

            if(total_positions == 0 && total_orders == 0)
            {
                // Check if trade direction is allowed
                bool can_trade = (current_direction == 0 && TradeDirection != TRADE_SELL_ONLY) ||
                                 (current_direction == 1 && TradeDirection != TRADE_BUY_ONLY);
                
                if(can_trade)
                {
                    Print("Mid-signal entry detected. Placing initial grid.");
                    PlaceGridOrders(current_direction, current_st_price);
                }
            }
        }

        return;
    }

    //--- Check for signal change
    if (current_direction != prev_direction)
    {
        Print("Supertrend signal changed from ", prev_direction, " to ", current_direction);
        CloseAllPositions(); // Close any open positions from the previous trend
        CancelAllPendingOrders(); // Cancel any remaining pending orders

        // Check if new direction is allowed before placing orders
        bool can_trade_new_direction = (current_direction == 0 && TradeDirection != TRADE_SELL_ONLY) ||
                                       (current_direction == 1 && TradeDirection != TRADE_BUY_ONLY);

        if(can_trade_new_direction)
        {
            PlaceGridOrders(current_direction, current_st_price);
        }
        else
        {
            Print("Trade direction is disabled by input settings. No new grid will be placed.");
        }

        prev_direction = current_direction;
        prev_st_price = current_st_price;
    }
    else if (MathAbs(current_st_price - prev_st_price) > (_Point * 0.5))
    {
        bool can_trade_current_direction = (current_direction == 0 && TradeDirection != TRADE_SELL_ONLY) ||
                                           (current_direction == 1 && TradeDirection != TRADE_BUY_ONLY);

        if(can_trade_current_direction)
        {
            Print("Supertrend line moved from ", prev_st_price, " to ", current_st_price, ". Updating grid.");
            UpdatePendingOrderPrices(current_direction, current_st_price);
        }

        prev_st_price = current_st_price;
    }
}
//+------------------------------------------------------------------+
//| Check profit conditions                                          |
//+------------------------------------------------------------------+
void CheckTakeProfit()
{
    // If both are 0, feature is disabled
    if(MaxTotalProfit <= 0 && EachOrderProfit <= 0) return;

    double current_total_profit = 0.0;
    
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        ulong ticket = PositionGetTicket(i);
        if(ticket > 0)
        {
            if(!PositionSelectByTicket(ticket))
                continue;

            if(PositionGetInteger(POSITION_MAGIC) == MagicNumber && PositionGetString(POSITION_SYMBOL) == _Symbol)
            {
                double profit = PositionGetDouble(POSITION_PROFIT) +
                                PositionGetDouble(POSITION_SWAP);
                
                bool closed = false;
                // Check individual profit
                if(EachOrderProfit > 0 && profit >= EachOrderProfit)
                {
                    Print("Individual profit target reached for order #", ticket, ". Profit: ", profit);
                    trade.PositionClose(ticket);
                    closed = true;
                }
                
                if(!closed)
                {
                    current_total_profit += profit;
                }
            }
        }
    }
    
    // Check total profit
    if(MaxTotalProfit > 0 && current_total_profit >= MaxTotalProfit)
    {
        Print("Max total profit target reached: ", current_total_profit, ". Closing all positions.");
        CloseAllPositions();
        CancelAllPendingOrders();
    }
}

//+------------------------------------------------------------------+
//| Close all open positions                                         |
//+------------------------------------------------------------------+
void CloseAllPositions()
{
    Print("Closing all open positions...");
    for (int i = PositionsTotal() - 1; i >= 0; i--)
    {
        ulong ticket = PositionGetTicket(i);
        if(ticket == 0 || !PositionSelectByTicket(ticket))
            continue;

        if (PositionGetInteger(POSITION_MAGIC) == MagicNumber && PositionGetString(POSITION_SYMBOL) == _Symbol)
        {
            trade.PositionClose(ticket);
        }
    }
}

//+------------------------------------------------------------------+
//| Cancel all pending orders                                        |
//+------------------------------------------------------------------+
void CancelAllPendingOrders()
{
    Print("Canceling all pending orders...");
    for(int i = OrdersTotal() - 1; i >= 0; i--)
    {
        ulong order_ticket = OrderGetTicket(i);
        if(OrderGetInteger(ORDER_MAGIC) == MagicNumber && OrderGetString(ORDER_SYMBOL) == _Symbol)
        {
            trade.OrderDelete(order_ticket);
        }
    }
}

//+------------------------------------------------------------------+
//| Place a grid of limit orders                                     |
//+------------------------------------------------------------------+
void PlaceGridOrders(int direction, double st_price)
{
    //--- Get the close price of the last completed candle
    MqlRates rates[1];
    if (CopyRates(_Symbol, SignalTimeframe, 1, 1, rates) < 1)
    {
        Print("Error copying rates");
        return;
    }
    double current_price = rates[0].close;

    //--- Count existing open positions for this EA
    int open_positions = CountOpenPositions();

    int orders_to_place = NumberOfOrders - open_positions;
    if(orders_to_place <= 0)
    {
        Print("Maximum number of positions are already open. No new pending orders will be placed.");
        return;
    }

    //--- Normalize prices to the symbol's digits
    st_price = NormalizeDouble(st_price, _Digits);
    current_price = NormalizeDouble(current_price, _Digits);

    Print("Placing grid. Open Positions: ", open_positions, ". Orders to Place: ", orders_to_place, ". Current Price: ", current_price, ", ST Price: ", st_price);

    if (direction == 0) // --- Place Buy Limit orders (Uptrend)
    {
        Print("Placing BUY LIMIT orders.");
        
        for (int i = 1; i <= orders_to_place; i++) // Start from 1 to place orders below current price
        {
            // Calculate grid index to account for existing positions
            int grid_index = i + open_positions;
            double order_price = CalculateGridPrice(direction, st_price, current_price, grid_index);
             
             // Ensure order price is above the stop level
            if(order_price < st_price) continue;
            if(!IsValidPendingPrice(direction, order_price)) continue;
            trade.BuyLimit(LotSize, order_price, _Symbol, 0, 0, ORDER_TIME_GTC, 0, "");
        }
    }
    else if (direction == 1) // --- Place Sell Limit orders (Downtrend)
    {
        Print("Placing SELL LIMIT orders.");
        
        for (int i = 1; i <= orders_to_place; i++) // Start from 1 to place orders above current price
        {
            // Calculate grid index to account for existing positions
            int grid_index = i + open_positions;
            double order_price = CalculateGridPrice(direction, st_price, current_price, grid_index);
             
            // Ensure order price is below the stop level
            if(order_price > st_price) continue;
            if(!IsValidPendingPrice(direction, order_price)) continue;
            trade.SellLimit(LotSize, order_price, _Symbol, 0, 0, ORDER_TIME_GTC, 0, "");
        }
    }
}
//+------------------------------------------------------------------+
//| Update prices of existing pending orders                         |
//+------------------------------------------------------------------+
void UpdatePendingOrderPrices(int direction, double st_price)
{
    //--- Get the close price of the last completed candle
    MqlRates rates[1];
    if (CopyRates(_Symbol, SignalTimeframe, 1, 1, rates) < 1)
    {
        Print("Error copying rates for update");
        return;
    }
    double current_price = rates[0].close;

    //--- Count existing open positions to maintain grid structure
    int open_positions = CountOpenPositions();

    //--- Collect all pending orders for this EA into a struct array
    PendingOrderInfo pending_orders[];
    int count = 0;
    for(int i = OrdersTotal() - 1; i >= 0; i--)
    {
        ulong ticket = OrderGetTicket(i);
        if(OrderGetInteger(ORDER_MAGIC) == MagicNumber && OrderGetString(ORDER_SYMBOL) == _Symbol)
        {
            if(OrderSelect(ticket))
            {
                ArrayResize(pending_orders, count + 1);
                pending_orders[count].ticket = ticket;
                pending_orders[count].price = OrderGetDouble(ORDER_PRICE_OPEN);
                count++;
            }
        }
    }

    if(count == 0)
    {
        Print("No pending orders to update.");
        return; // Do nothing if no pending orders exist
    }

    //--- Normalize prices
    st_price = NormalizeDouble(st_price, _Digits);
    current_price = NormalizeDouble(current_price, _Digits);

    Print("Updating ", count, " pending orders.");

    //--- Sort orders by price to determine their grid position
    // Use manual sort since ArraySort with custom comparison is not supported in MQL5 for structs
    for(int i = 0; i < count; i++)
    {
        for(int j = i + 1; j < count; j++)
        {
            bool should_swap = false;
            if(direction == 0) // Uptrend, Buy Limits, sort descending (highest price first)
            {
                if(pending_orders[j].price > pending_orders[i].price) should_swap = true;
            }
            else // Downtrend, Sell Limits, sort ascending (lowest price first)
            {
                if(pending_orders[j].price < pending_orders[i].price) should_swap = true;
            }

            if(should_swap)
            {
                PendingOrderInfo temp_order = pending_orders[i];
                pending_orders[i] = pending_orders[j];
                pending_orders[j] = temp_order;
            }
        }
    }

    //--- Now update each order with its new price based on its grid position
    for(int i = 0; i < count; i++)
    {
        ulong ticket = pending_orders[i].ticket;
        double old_order_price = pending_orders[i].price;
        double new_order_price = 0;
        
        // The grid position corresponds to the sorted index + 1 + any open positions
        int grid_pos = i + 1 + open_positions;

        if (direction == 0) // --- Update Buy Limit orders
        {
            new_order_price = CalculateGridPrice(direction, st_price, current_price, grid_pos);
            if(new_order_price < st_price) continue; // Don't move order past the ST line
            if(!IsValidPendingPrice(direction, new_order_price)) continue;
        }
        else if (direction == 1) // --- Update Sell Limit orders
        {
            new_order_price = CalculateGridPrice(direction, st_price, current_price, grid_pos);
            if(new_order_price > st_price) continue; // Don't move order past the ST line
            if(!IsValidPendingPrice(direction, new_order_price)) continue;
        }

        // Modify the order only if the price has changed
        if(MathAbs(new_order_price - old_order_price) > _Point)
        {
            if(!trade.OrderModify(ticket, new_order_price, 0, 0, ORDER_TIME_GTC, 0, 0.0))
            {
                Print("Failed to modify order #", ticket, ". Error: ", GetLastError());
            }
            else
            {
                Print("Modified order #", ticket, " price from ", old_order_price, " to ", new_order_price);
            }
        }
    }
}
