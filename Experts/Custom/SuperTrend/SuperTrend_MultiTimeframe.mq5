//+------------------------------------------------------------------+
//|                                   SuperTrend_MultiTimeframe.mq5 |
//|                        Copyright 2025, MetaQuotes Software Corp. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Software Corp."
#property link      "https://www.mql5.com"
#property version   "1.00"

#include <Trade\Trade.mqh>

//--- Input parameters
input group "=== Main Settings ==="
input double   LotSize = 0.01;             // Lot Size per order
input int      Magic = 123456;            // Magic Number
input double   SpreadMultiplier = 2.0;    // Spread multiplier for order placement buffer

input group "=== Supertrend Settings ==="
input double   ATRMultiplier = 9.0;       // ATR Multiplier
input int      ATRPeriod = 27;             // ATR Period
input int      ATRMaxBars = 10000;         // ATR Max Bars

input group "=== Order Control ==="
input bool     ResetCompletionOnStart = false;  // Reset completion status on EA start
input double   ProfitTarget = 10.0;             // Profit target in USD to close position
input double   OrderBufferMultiplier = 1.0;     // Multiplier for order distance from SuperTrend line

//--- Global variables
CTrade trade;

// SuperTrend handles for different timeframes
int st_handle_30M;  // 30-minute for trend direction
int st_handle_1M;   // 1-minute
int st_handle_2M;   // 2-minute  
int st_handle_3M;   // 3-minute
int st_handle_5M;   // 5-minute
int st_handle_10M;  // 10-minute
int st_handle_15M;  // 15-minute

// Trend tracking
double last_30m_trend = -1;
bool is_30m_bullish = false;
bool is_30m_bearish = false;

// Timeframe enumeration
ENUM_TIMEFRAMES timeframes[] = {PERIOD_M1, PERIOD_M2, PERIOD_M3, PERIOD_M5, PERIOD_M10, PERIOD_M15};
string tf_names[] = {"M1", "M2", "M3", "M5", "M10", "M15"};
int tf_handles[6];

// Order tracking
struct TimeframeOrder
{
    ulong ticket;
    bool is_active;
    double last_line_price;
    ENUM_ORDER_TYPE order_type;
};

TimeframeOrder tf_orders[6];

// CSV tracking for order completion status
string csv_filename = "SuperTrend_Orders_" + _Symbol + "_" + IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN)) + ".csv";
bool timeframe_completed[6] = {false, false, false, false, false, false};

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    // Initialize 30M SuperTrend handle for trend direction
    st_handle_30M = iCustom(_Symbol, PERIOD_M30, "Supertrend", 
                           "SPRTRND", ATRMultiplier, ATRPeriod, ATRMaxBars, 0, 
                           false, false, false, false, 1);
    
    if(st_handle_30M == INVALID_HANDLE)
    {
        Print("Error creating 30M Supertrend indicator handle");
        return INIT_FAILED;
    }
    
    // Initialize handles for all timeframes
    for(int i = 0; i < 6; i++)
    {
        tf_handles[i] = iCustom(_Symbol, timeframes[i], "Supertrend", 
                               "SPRTRND", ATRMultiplier, ATRPeriod, ATRMaxBars, 0, 
                               false, false, false, false, 1);
        
        if(tf_handles[i] == INVALID_HANDLE)
        {
            Print("Error creating ", tf_names[i], " Supertrend indicator handle");
            return INIT_FAILED;
        }
    }
    
    // Set trade parameters
    trade.SetExpertMagicNumber(Magic);
    trade.SetDeviationInPoints(30);
    trade.SetTypeFilling(ORDER_FILLING_FOK);
    
    // Initialize order tracking
    for(int i = 0; i < 6; i++)
    {
        tf_orders[i].ticket = 0;
        tf_orders[i].is_active = false;
        tf_orders[i].last_line_price = 0;
        tf_orders[i].order_type = ORDER_TYPE_BUY;
    }
    
    // Load completion status from CSV
    LoadCompletionStatusFromCSV();
    
    // Reset completion status if requested
    if(ResetCompletionOnStart)
    {
        ResetCompletionStatus();
        Print("Completion status reset as requested by input parameter");
    }
    
    // Check for existing orders from previous EA runs
    ScanExistingOrders();
    
    Print("SuperTrend Multi-Timeframe EA initialized successfully");
    return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    if(st_handle_30M != INVALID_HANDLE) IndicatorRelease(st_handle_30M);
    
    for(int i = 0; i < 6; i++)
    {
        if(tf_handles[i] != INVALID_HANDLE) 
            IndicatorRelease(tf_handles[i]);
    }
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
    // Check for executed orders and mark timeframes as completed
    CheckForExecutedOrders();
    
    // Monitor positions for profit target
    MonitorPositionsForProfitTarget();
    
    // Check 30M trend first
    if(!Check30MinuteTrend())
        return;
    
    // If trend changed, cancel all pending orders and close positions
    if(TrendChanged())
    {
        Print("30M Trend changed to: ", Get30MTrendString());
        CancelAllPendingOrders();
        CloseAllPositions();
        UpdateTrendState();
        // Reset completion status when trend changes
        ResetCompletionStatus();
    }
    
    // Update or place orders for all timeframes
    ManageTimeframeOrders();
}

//+------------------------------------------------------------------+
//| Check for executed orders and mark timeframes as completed     |
//+------------------------------------------------------------------+
void CheckForExecutedOrders()
{
    for(int i = 0; i < 6; i++)
    {
        if(tf_orders[i].is_active && tf_orders[i].ticket > 0)
        {
            // Check if order still exists in pending orders
            if(!OrderExists(tf_orders[i].ticket))
            {
                // Order was executed or cancelled
                // Check if it was executed by looking for a position with our magic number
                bool order_executed = false;
                
                // Check for positions opened with our magic number
                for(int p = 0; p < PositionsTotal(); p++)
                {
                    if(PositionGetTicket(p) > 0)
                    {
                        if(PositionGetInteger(POSITION_MAGIC) == Magic &&
                           PositionGetString(POSITION_SYMBOL) == _Symbol)
                        {
                            string comment = PositionGetString(POSITION_COMMENT);
                            if(StringFind(comment, "ST_BuyStop_" + tf_names[i]) >= 0 ||
                               StringFind(comment, "ST_SellStop_" + tf_names[i]) >= 0)
                            {
                                order_executed = true;
                                break;
                            }
                        }
                    }
                }
                
                if(order_executed)
                {
                    Print("Order executed for ", tf_names[i], " - marking as COMPLETED");
                    MarkTimeframeCompleted(i);
                }
                else
                {
                    Print("Order for ", tf_names[i], " was cancelled or expired");
                }
                
                // Reset tracking
                tf_orders[i].is_active = false;
                tf_orders[i].ticket = 0;
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Monitor positions for profit target and close when reached     |
//+------------------------------------------------------------------+
void MonitorPositionsForProfitTarget()
{
    for(int i = 0; i < PositionsTotal(); i++)
    {
        if(PositionGetTicket(i) > 0)
        {
            if(PositionGetInteger(POSITION_MAGIC) == Magic &&
               PositionGetString(POSITION_SYMBOL) == _Symbol)
            {
                double profit = PositionGetDouble(POSITION_PROFIT);
                string comment = PositionGetString(POSITION_COMMENT);
                
                // Check if profit target is reached
                if(profit >= ProfitTarget)
                {
                    ulong ticket = PositionGetTicket(i);
                    
                    // Identify which timeframe this position belongs to
                    int tf_index = -1;
                    for(int tf = 0; tf < 6; tf++)
                    {
                        if(StringFind(comment, "ST_BuyStop_" + tf_names[tf]) >= 0 ||
                           StringFind(comment, "ST_SellStop_" + tf_names[tf]) >= 0)
                        {
                            tf_index = tf;
                            break;
                        }
                    }
                    
                    // Close the position
                    if(trade.PositionClose(ticket))
                    {
                        Print("Position closed at profit target: $", DoubleToString(profit, 2),
                              " for ", (tf_index >= 0 ? tf_names[tf_index] : "Unknown"));
                        
                        // Mark timeframe as available again for new trades
                        if(tf_index >= 0)
                        {
                            ResetTimeframeStatus(tf_index);
                        }
                    }
                    else
                    {
                        Print("Failed to close position. Error: ", trade.ResultRetcode());
                    }
                }
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Check 30-minute trend direction                                 |
//+------------------------------------------------------------------+
bool Check30MinuteTrend()
{
    double trend_direction[];
    ArraySetAsSeries(trend_direction, true);
    
    if(CopyBuffer(st_handle_30M, 2, 0, 2, trend_direction) < 2)
        return false;
    
    double current_30m_trend = trend_direction[1]; // Previous completed bar
    
    // Update trend flags
    is_30m_bullish = (current_30m_trend == 0);
    is_30m_bearish = (current_30m_trend == 1);
    
    return true;
}

//+------------------------------------------------------------------+
//| Check if trend changed                                          |
//+------------------------------------------------------------------+
bool TrendChanged()
{
    double trend_direction[];
    ArraySetAsSeries(trend_direction, true);
    
    if(CopyBuffer(st_handle_30M, 2, 0, 2, trend_direction) < 2)
        return false;
    
    double current_30m_trend = trend_direction[1];
    
    if(last_30m_trend != -1 && last_30m_trend != current_30m_trend)
    {
        last_30m_trend = current_30m_trend;
        return true;
    }
    
    last_30m_trend = current_30m_trend;
    return false;
}

//+------------------------------------------------------------------+
//| Update trend state                                              |
//+------------------------------------------------------------------+
void UpdateTrendState()
{
    if(is_30m_bullish)
        Print("30M Trend: BULLISH - Looking for buy opportunities");
    else if(is_30m_bearish)
        Print("30M Trend: BEARISH - Looking for sell opportunities");
}

//+------------------------------------------------------------------+
//| Manage orders for all timeframes                               |
//+------------------------------------------------------------------+
void ManageTimeframeOrders()
{
    for(int i = 0; i < 6; i++)
    {
        double trend_line[];
        double trend_direction[];
        ArraySetAsSeries(trend_line, true);
        ArraySetAsSeries(trend_direction, true);
        
        if(CopyBuffer(tf_handles[i], 0, 0, 2, trend_line) < 2 ||
           CopyBuffer(tf_handles[i], 2, 0, 2, trend_direction) < 2)
            continue;
        
        double current_line = trend_line[1];
        double tf_trend = trend_direction[1];
        
        // Determine what type of order should be placed
        bool should_have_buy_order = (is_30m_bullish && tf_trend == 0);  // 30M green AND timeframe green
        bool should_have_sell_order = (is_30m_bearish && tf_trend == 1); // 30M red AND timeframe red
        
        // Current order status
        bool has_pending_order = tf_orders[i].is_active && OrderExists(tf_orders[i].ticket);
        
        // If order was executed or cancelled, update tracking
        if(tf_orders[i].is_active && !OrderExists(tf_orders[i].ticket))
        {
            Print("Order for ", tf_names[i], " no longer exists (executed/cancelled)");
            tf_orders[i].is_active = false;
            tf_orders[i].ticket = 0;
            has_pending_order = false;
        }
        
        if(should_have_buy_order)
        {
            // Calculate spread (Ask - Bid)
            double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
            double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
            double spread = ask - bid;
            
            // Place Buy Limit order ABOVE SuperTrend line by spread distance
            // When price comes down to this level, it will buy
            double order_price = current_line + spread;
            
            if(!has_pending_order)
            {
                // Check if we need to cancel opposite type order first
                if(tf_orders[i].is_active && tf_orders[i].order_type == ORDER_TYPE_SELL_LIMIT)
                {
                    CancelOrder(i);
                }
                
                // Only place new order if no pending order exists AND timeframe not completed
                if(!HasPendingOrderForTimeframe(i) && CountOrdersForTimeframe(i) == 0 && !IsTimeframeCompleted(i))
                {
                    Print("Placing Buy Limit order for ", tf_names[i], 
                          " at ", DoubleToString(order_price, _Digits),
                          " (ST Line: ", DoubleToString(current_line, _Digits),
                          " Spread: ", DoubleToString(spread, _Digits), ")");
                    PlaceBuyLimitOrder(i, order_price, current_line);
                }
                else if(HasPendingOrderForTimeframe(i))
                {
                    Print("Skip placing Buy order for ", tf_names[i], " - order already exists");
                }
                else if(IsTimeframeCompleted(i))
                {
                    Print("Skip placing Buy order for ", tf_names[i], " - timeframe COMPLETED");
                }
            }
            else
            {
                // Check if order type matches (buy order for buy condition)
                if(tf_orders[i].order_type == ORDER_TYPE_BUY_LIMIT)
                {
                    // Check if order needs to be modified (line moved significantly)
                    if(MathAbs(current_line - tf_orders[i].last_line_price) > spread / 2)
                    {
                        // Validate new price before modification
                        if(IsValidBuyLimitPrice(order_price))
                        {
                            ModifyOrder(i, order_price);
                            tf_orders[i].last_line_price = current_line;
                        }
                        else
                        {
                            Print("Invalid buy stop price for ", tf_names[i], " - cancelling and replacing");
                            CancelOrder(i);
                        }
                    }
                }
                else
                {
                    // Wrong order type - cancel and place new one
                    CancelOrder(i);
                }
            }
        }
        else if(should_have_sell_order)
        {
            // Calculate spread (Ask - Bid)
            double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
            double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
            double spread = ask - bid;
            
            // Place Sell Limit order BELOW SuperTrend line by spread distance
            // When price comes up to this level, it will sell
            double order_price = current_line - spread;
            
            if(!has_pending_order)
            {
                // Check if we need to cancel opposite type order first
                if(tf_orders[i].is_active && tf_orders[i].order_type == ORDER_TYPE_BUY_LIMIT)
                {
                    CancelOrder(i);
                }
                
                // Only place new order if no pending order exists AND timeframe not completed
                if(!HasPendingOrderForTimeframe(i) && CountOrdersForTimeframe(i) == 0 && !IsTimeframeCompleted(i))
                {
                    Print("Placing Sell Limit order for ", tf_names[i], 
                          " at ", DoubleToString(order_price, _Digits),
                          " (ST Line: ", DoubleToString(current_line, _Digits),
                          " Spread: ", DoubleToString(spread, _Digits), ")");
                    PlaceSellLimitOrder(i, order_price, current_line);
                }
                else if(HasPendingOrderForTimeframe(i))
                {
                    Print("Skip placing Sell order for ", tf_names[i], " - order already exists");
                }
                else if(IsTimeframeCompleted(i))
                {
                    Print("Skip placing Sell order for ", tf_names[i], " - timeframe COMPLETED");
                }
            }
            else
            {
                // Check if order type matches (sell order for sell condition)
                if(tf_orders[i].order_type == ORDER_TYPE_SELL_LIMIT)
                {
                    // Check if order needs to be modified (line moved significantly)
                    if(MathAbs(current_line - tf_orders[i].last_line_price) > spread / 2)
                    {
                        // Validate new price before modification
                        if(IsValidSellLimitPrice(order_price))
                        {
                            ModifyOrder(i, order_price);
                            tf_orders[i].last_line_price = current_line;
                        }
                        else
                        {
                            Print("Invalid sell stop price for ", tf_names[i], " - cancelling and replacing");
                            CancelOrder(i);
                        }
                    }
                }
                else
                {
                    // Wrong order type - cancel and place new one
                    CancelOrder(i);
                }
            }
        }
        else
        {
            // Should not have order - cancel if exists
            if(has_pending_order)
            {
                CancelOrder(i);
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Place buy stop order                                           |
//+------------------------------------------------------------------+
void PlaceBuyLimitOrder(int tf_index, double price, double line_value)
{
    // Validate price before placing order
    if(!IsValidBuyLimitPrice(price))
    {
        Print("Cannot place Buy Limit for ", tf_names[tf_index], " - invalid price");
        return;
    }
    
    string comment = "ST_BuyLimit_" + tf_names[tf_index];
    
    if(trade.BuyLimit(LotSize, price, _Symbol, 0, 0, ORDER_TIME_GTC, 0, comment))
    {
        tf_orders[tf_index].ticket = trade.ResultOrder();
        tf_orders[tf_index].is_active = true;
        tf_orders[tf_index].last_line_price = line_value;
        tf_orders[tf_index].order_type = ORDER_TYPE_BUY_LIMIT;
        
        Print("Buy Limit order placed for ", tf_names[tf_index], 
              " at ", DoubleToString(price, _Digits),
              " (Line: ", DoubleToString(line_value, _Digits), ")");
    }
    else
    {
        Print("Failed to place Buy Limit order for ", tf_names[tf_index], 
              " Error: ", trade.ResultRetcode(), " Desc: ", trade.ResultRetcodeDescription());
    }
}

//+------------------------------------------------------------------+
//| Place sell limit order                                          |
//+------------------------------------------------------------------+
void PlaceSellLimitOrder(int tf_index, double price, double line_value)
{
    // Validate price before placing order
    if(!IsValidSellLimitPrice(price))
    {
        Print("Cannot place Sell Limit for ", tf_names[tf_index], " - invalid price");
        return;
    }
    
    string comment = "ST_SellLimit_" + tf_names[tf_index];
    
    if(trade.SellLimit(LotSize, price, _Symbol, 0, 0, ORDER_TIME_GTC, 0, comment))
    {
        tf_orders[tf_index].ticket = trade.ResultOrder();
        tf_orders[tf_index].is_active = true;
        tf_orders[tf_index].last_line_price = line_value;
        tf_orders[tf_index].order_type = ORDER_TYPE_SELL_LIMIT;
        
        Print("Sell Limit order placed for ", tf_names[tf_index], 
              " at ", DoubleToString(price, _Digits),
              " (Line: ", DoubleToString(line_value, _Digits), ")");
    }
    else
    {
        Print("Failed to place Sell Limit order for ", tf_names[tf_index],
              " Error: ", trade.ResultRetcode(), " Desc: ", trade.ResultRetcodeDescription());
    }
}

//+------------------------------------------------------------------+
//| Modify existing order                                           |
//+------------------------------------------------------------------+
void ModifyOrder(int tf_index, double new_price)
{
    if(trade.OrderModify(tf_orders[tf_index].ticket, new_price, 0, 0, ORDER_TIME_GTC, 0))
    {
        Print("Order modified for ", tf_names[tf_index], " new price: ", DoubleToString(new_price, _Digits));
    }
    else
    {
        Print("Failed to modify order for ", tf_names[tf_index], 
              " Error: ", trade.ResultRetcode(), " RetDesc: ", trade.ResultRetcodeDescription());
    }
}

//+------------------------------------------------------------------+
//| Validate buy limit price                                       |
//+------------------------------------------------------------------+
bool IsValidBuyLimitPrice(double price)
{
    // For our SuperTrend strategy, we just need basic price validation
    // The order will be placed above SuperTrend line (entry point strategy)
    return (price > 0 && price > SymbolInfoDouble(_Symbol, SYMBOL_POINT));
}

//+------------------------------------------------------------------+
//| Validate sell limit price                                      |
//+------------------------------------------------------------------+
bool IsValidSellLimitPrice(double price)
{
    // For our SuperTrend strategy, we just need basic price validation
    // The order will be placed below SuperTrend line (entry point strategy)
    return (price > 0 && price > SymbolInfoDouble(_Symbol, SYMBOL_POINT));
}

//+------------------------------------------------------------------+
//| Validate buy stop price                                        |
//+------------------------------------------------------------------+
bool IsValidBuyStopPrice(double price)
{
    double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    double min_distance = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * SymbolInfoDouble(_Symbol, SYMBOL_POINT);
    
    // Buy stop must be above current ask price + minimum distance
    bool is_valid = (price >= (ask + min_distance));
    
    if(!is_valid)
    {
        Print("Invalid Buy Stop price: ", DoubleToString(price, _Digits),
              " | Ask: ", DoubleToString(ask, _Digits),
              " | Min required: ", DoubleToString(ask + min_distance, _Digits));
    }
    
    return is_valid;
}

//+------------------------------------------------------------------+
//| Validate sell stop price                                       |
//+------------------------------------------------------------------+
bool IsValidSellStopPrice(double price)
{
    double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    double min_distance = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * SymbolInfoDouble(_Symbol, SYMBOL_POINT);
    
    // Sell stop must be below current bid price - minimum distance
    bool is_valid = (price <= (bid - min_distance));
    
    if(!is_valid)
    {
        Print("Invalid Sell Stop price: ", DoubleToString(price, _Digits),
              " | Bid: ", DoubleToString(bid, _Digits),
              " | Max allowed: ", DoubleToString(bid - min_distance, _Digits));
    }
    
    return is_valid;
}

//+------------------------------------------------------------------+
//| Cancel order for specific timeframe                            |
//+------------------------------------------------------------------+
void CancelOrder(int tf_index)
{
    if(trade.OrderDelete(tf_orders[tf_index].ticket))
    {
        Print("Order cancelled for ", tf_names[tf_index]);
        tf_orders[tf_index].is_active = false;
        tf_orders[tf_index].ticket = 0;
    }
    else
    {
        Print("Failed to cancel order for ", tf_names[tf_index],
              " Error: ", trade.ResultRetcode());
    }
}

//+------------------------------------------------------------------+
//| Cancel all pending orders                                      |
//+------------------------------------------------------------------+
void CancelAllPendingOrders()
{
    for(int i = 0; i < 6; i++)
    {
        if(tf_orders[i].is_active && OrderExists(tf_orders[i].ticket))
        {
            CancelOrder(i);
        }
        else
        {
            tf_orders[i].is_active = false;
            tf_orders[i].ticket = 0;
        }
    }
}

//+------------------------------------------------------------------+
//| Check if order exists                                          |
//+------------------------------------------------------------------+
bool OrderExists(ulong ticket)
{
    if(ticket == 0) return false;
    
    return OrderSelect(ticket);
}

//+------------------------------------------------------------------+
//| Check if pending order exists for specific timeframe          |
//+------------------------------------------------------------------+
bool HasPendingOrderForTimeframe(int tf_index)
{
    string buy_comment = "ST_BuyLimit_" + tf_names[tf_index];
    string sell_comment = "ST_SellLimit_" + tf_names[tf_index];
    
    // First check our tracking array
    if(tf_orders[tf_index].is_active && OrderExists(tf_orders[tf_index].ticket))
        return true;
    
    // Double check by scanning all pending orders
    for(int i = 0; i < OrdersTotal(); i++)
    {
        if(OrderGetTicket(i) > 0)
        {
            if(OrderGetString(ORDER_SYMBOL) == _Symbol &&
               OrderGetInteger(ORDER_MAGIC) == Magic)
            {
                string order_comment = OrderGetString(ORDER_COMMENT);
                if(StringFind(order_comment, buy_comment) >= 0 || 
                   StringFind(order_comment, sell_comment) >= 0)
                {
                    // Update our tracking if we found an order we didn't track
                    if(!tf_orders[tf_index].is_active)
                    {
                        tf_orders[tf_index].ticket = OrderGetTicket(i);
                        tf_orders[tf_index].is_active = true;
                        tf_orders[tf_index].order_type = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
                        Print("Found untracked order for ", tf_names[tf_index], " - updating tracking");
                    }
                    return true;
                }
            }
        }
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| Count pending orders for specific timeframe                   |
//+------------------------------------------------------------------+
int CountOrdersForTimeframe(int tf_index)
{
    string buy_comment = "ST_BuyLimit_" + tf_names[tf_index];
    string sell_comment = "ST_SellLimit_" + tf_names[tf_index];
    int count = 0;
    
    // Scan all pending orders
    for(int i = 0; i < OrdersTotal(); i++)
    {
        if(OrderGetTicket(i) > 0)
        {
            if(OrderGetString(ORDER_SYMBOL) == _Symbol &&
               OrderGetInteger(ORDER_MAGIC) == Magic)
            {
                string order_comment = OrderGetString(ORDER_COMMENT);
                if(StringFind(order_comment, buy_comment) >= 0 || 
                   StringFind(order_comment, sell_comment) >= 0)
                {
                    count++;
                }
            }
        }
    }
    
    if(count > 0)
    {
        Print("Found ", count, " existing orders for ", tf_names[tf_index]);
    }
    
    return count;
}

//+------------------------------------------------------------------+
//| Scan for existing orders on initialization                     |
//+------------------------------------------------------------------+
void ScanExistingOrders()
{
    Print("Scanning for existing orders...");
    
    for(int i = 0; i < OrdersTotal(); i++)
    {
        if(OrderGetTicket(i) > 0)
        {
            if(OrderGetString(ORDER_SYMBOL) == _Symbol &&
               OrderGetInteger(ORDER_MAGIC) == Magic)
            {
                string order_comment = OrderGetString(ORDER_COMMENT);
                
                // Check which timeframe this order belongs to
                for(int tf = 0; tf < 6; tf++)
                {
                    string buy_comment = "ST_BuyStop_" + tf_names[tf];
                    string sell_comment = "ST_SellStop_" + tf_names[tf];
                    
                    if(StringFind(order_comment, buy_comment) >= 0 || 
                       StringFind(order_comment, sell_comment) >= 0)
                    {
                        // Found existing order for this timeframe
                        tf_orders[tf].ticket = OrderGetTicket(i);
                        tf_orders[tf].is_active = true;
                        tf_orders[tf].order_type = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
                        tf_orders[tf].last_line_price = OrderGetDouble(ORDER_PRICE_OPEN);
                        
                        Print("Found existing order for ", tf_names[tf], 
                              " Ticket: ", tf_orders[tf].ticket,
                              " Type: ", EnumToString(tf_orders[tf].order_type));
                        break;
                    }
                }
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Close all positions                                            |
//+------------------------------------------------------------------+
void CloseAllPositions()
{
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        if(PositionGetTicket(i) > 0)
        {
            if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
               PositionGetInteger(POSITION_MAGIC) == Magic)
            {
                ulong ticket = PositionGetTicket(i);
                if(trade.PositionClose(ticket))
                    Print("Position ", ticket, " closed due to trend change");
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Get current 30M trend as string                                |
//+------------------------------------------------------------------+
string Get30MTrendString()
{
    if(is_30m_bullish) return "BULLISH";
    if(is_30m_bearish) return "BEARISH";
    return "UNKNOWN";
}

//+------------------------------------------------------------------+
//| Get current spread buffer for order placement                  |
//+------------------------------------------------------------------+
double GetSpreadBuffer()
{
    // Get current spread in points
    long spread_points = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
    
    // Convert to price
    double spread_price = spread_points * SymbolInfoDouble(_Symbol, SYMBOL_POINT);
    
    // Apply multiplier
    double buffer = spread_price * SpreadMultiplier;
    
    // Print spread info for debugging
    static datetime last_print = 0;
    if(TimeCurrent() - last_print > 60) // Print every minute
    {
        Print("Symbol: ", _Symbol, 
              " | Spread: ", spread_points, " points",
              " | Spread Price: ", DoubleToString(spread_price, _Digits),
              " | Buffer: ", DoubleToString(buffer, _Digits));
        last_print = TimeCurrent();
    }
    
    return buffer;
}

//+------------------------------------------------------------------+
//| Save timeframe completion status to CSV                        |
//+------------------------------------------------------------------+
void SaveCompletionStatusToCSV()
{
    int handle = FileOpen(csv_filename, FILE_WRITE|FILE_TXT);
    if(handle != INVALID_HANDLE)
    {
        // Write header
        string data = "Timeframe,Completed,LastUpdate\n";
        FileWriteString(handle, data);
        
        // Write status for each timeframe
        for(int i = 0; i < 6; i++)
        {
            data = tf_names[i] + "," + 
                   (timeframe_completed[i] ? "TRUE" : "FALSE") + "," +
                   TimeToString(TimeCurrent()) + "\n";
            FileWriteString(handle, data);
        }
        FileClose(handle);
        Print("Saved completion status to: ", csv_filename);
    }
    else
    {
        Print("Failed to save completion status to CSV");
    }
}

//+------------------------------------------------------------------+
//| Load timeframe completion status from CSV                      |
//+------------------------------------------------------------------+
void LoadCompletionStatusFromCSV()
{
    int handle = FileOpen(csv_filename, FILE_READ|FILE_TXT);
    if(handle != INVALID_HANDLE)
    {
        // Skip header
        string header = FileReadString(handle);
        
        for(int i = 0; i < 6; i++)
        {
            string line = FileReadString(handle);
            if(line != "")
            {
                string parts[];
                if(StringSplit(line, ',', parts) >= 2)
                {
                    timeframe_completed[i] = (parts[1] == "TRUE");
                    Print("Loaded status for ", tf_names[i], ": ", 
                          (timeframe_completed[i] ? "COMPLETED" : "PENDING"));
                }
            }
        }
        FileClose(handle);
        Print("Loaded completion status from: ", csv_filename);
    }
    else
    {
        Print("No existing CSV file found, starting fresh");
        // Initialize all as false (default)
        for(int i = 0; i < 6; i++)
            timeframe_completed[i] = false;
    }
}

//+------------------------------------------------------------------+
//| Mark timeframe as completed                                     |
//+------------------------------------------------------------------+
void MarkTimeframeCompleted(int tf_index)
{
    if(tf_index >= 0 && tf_index < 6)
    {
        timeframe_completed[tf_index] = true;
        Print("Marked ", tf_names[tf_index], " as COMPLETED");
        SaveCompletionStatusToCSV();
    }
}

//+------------------------------------------------------------------+
//| Check if timeframe is already completed                        |
//+------------------------------------------------------------------+
bool IsTimeframeCompleted(int tf_index)
{
    if(tf_index >= 0 && tf_index < 6)
    {
        return timeframe_completed[tf_index];
    }
    return false;
}

//+------------------------------------------------------------------+
//| Reset completion status (for new trading session)             |
//+------------------------------------------------------------------+
void ResetCompletionStatus()
{
    for(int i = 0; i < 6; i++)
    {
        timeframe_completed[i] = false;
    }
    SaveCompletionStatusToCSV();
    Print("Reset all timeframe completion status");
}

//+------------------------------------------------------------------+
//| Reset specific timeframe completion status                     |
//+------------------------------------------------------------------+
void ResetTimeframeStatus(int tf_index)
{
    if(tf_index >= 0 && tf_index < 6)
    {
        timeframe_completed[tf_index] = false;
        SaveCompletionStatusToCSV();
        Print("Reset ", tf_names[tf_index], " completion status - now AVAILABLE");
    }
}

//+------------------------------------------------------------------+
