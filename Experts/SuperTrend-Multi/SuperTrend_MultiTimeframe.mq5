//+------------------------------------------------------------------+
//|                                   SuperTrend_MultiTimeframe.mq5 |
//|                        Copyright 2025, MetaQuotes Software Corp. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
//| ENHANCED DRAWDOWN/PROFIT PROTECTION FEATURES:                   |
//| - Max Loss Protection: When MaxOverallLoss is reached,          |
//|   immediately closes all positions and cancels ALL pending      |
//|   orders, then waits for 30M SuperTrend change before resuming  |
//| - Max Profit Protection: When MaxOverallProfit is reached,      |
//|   immediately closes all positions and cancels ALL pending      |
//|   orders, then waits for 30M SuperTrend change before resuming  |
//| - Robust Order Cancellation: Double-verification ensures all    |
//|   pending orders are cancelled when limits are hit              |
//| - Detailed Logging: Full transparency of protection triggers    |
//|   and trend change detection for resume conditions              |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Software Corp."
#property link      "https://www.mql5.com"
#property version   "1.02"

#include <Trade\Trade.mqh>
#include "support\GetSpread.mqh"
static datetime last_candle_time = 0;

//--- Input parameters
input group "=== Main Settings ==="
input double   LotSize = 0.01;             // Lot Size per order
input int      Magic = 123456;            // Magic Number

input group "=== Supertrend Settings ==="
input double   ATRMultiplier = 9.0;       // ATR Multiplier
input int      ATRPeriod = 27;             // ATR Period
input int      ATRMaxBars = 10000;         // ATR Max Bars

input group "=== Order Control ==="
input bool     ResetCompletionOnStart = false;  // Reset completion status on EA start
input double   ProfitTarget = 0.0;             // Base profit target in USD for M1 timeframe (0 = unlimited)
input double   ProfitIncrementFactor = 0.0;     // Factor to increase profit target for each higher timeframe
input double   OrderBufferMultiplier = 1.0;     // Multiplier for order distance from SuperTrend line

input group "=== Risk Management ==="
input bool     CancelOrdersBeforeWeekend = true; // Cancel pending orders before weekend close
input double   MaxOverallLoss = 100.0;          // Maximum overall loss in USD before closing all positions
input bool     EnableMaxLossProtection = true;   // Enable maximum loss protection
input double   MaxOverallProfit = 360.0;          // Maximum overall profit in USD before closing all positions (0 = unlimited)
input bool     EnableMaxProfitProtection = true; // Enable maximum profit protection


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
double current_spread = 0.0;

// Timeframe enumeration
ENUM_TIMEFRAMES timeframes[] = {PERIOD_M1, PERIOD_M2, PERIOD_M3, PERIOD_M5, PERIOD_M10, PERIOD_M15};
string tf_names[] = {"M1", "M2", "M3", "M5", "M10", "M15"};
int tf_handles[6];

// Profit targets for each timeframe (calculated in OnInit)
double tf_profit_targets[6];

// Order tracking
struct TimeframeOrder
{
    ulong ticket;
    bool is_active;
    double last_line_price;
    double last_order_price;
    ENUM_ORDER_TYPE order_type;
};

TimeframeOrder tf_orders[6];

// CSV tracking for order completion status and profit targets
string csv_filename = "SuperTrend_Orders_" + _Symbol + "_" + IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN)) + ".csv";
bool timeframe_completed[6] = {false, false, false, false, false, false};
bool profit_targets_loaded = false; // Flag to track if we loaded profit targets from CSV

// Weekend close protection variables
bool is_market_closed = false;
datetime weekend_close_time = 0;

// Max loss protection variables
bool max_loss_hit = false;
double current_session_loss = 0.0;
datetime max_loss_hit_time = 0;

// Max profit protection variables
bool max_profit_hit = false;
double current_session_profit = 0.0;
datetime max_profit_hit_time = 0;

// Order management timing
datetime last_order_management_time = 0;
const int ORDER_MANAGEMENT_INTERVAL = 5; // seconds between order management cycles

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    // Initialize 30M SuperTrend handle for trend direction
    st_handle_30M = iCustom(_Symbol, PERIOD_M30, "Supertrend", 
                           "SPRTRND", ATRMultiplier, ATRPeriod, ATRMaxBars, 0, 
                           false, false, false, false, 1);
    current_spread = GetSpread();
    if(st_handle_30M == INVALID_HANDLE)
    {
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
            return INIT_FAILED;
        }
    }
    Comment("Expert Advisor initialized. Initial spread: ", current_spread);
    
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
        tf_orders[i].last_order_price = 0;
        tf_orders[i].order_type = ORDER_TYPE_BUY;
    }
    
    // Load completion status and profit targets from CSV
    LoadCompletionStatusFromCSV();
    
    // If profit targets weren't loaded from CSV, calculate them from inputs
    if(!profit_targets_loaded)
    {
        for(int i = 0; i < 6; i++)
        {
            // If ProfitTarget is 0, set all timeframes to 0 (unlimited)
            if(ProfitTarget == 0.0)
            {
                tf_profit_targets[i] = 0.0;
            }
            else
            {
                // Calculate progressive profit targets for each timeframe
                tf_profit_targets[i] = ProfitTarget * (1.0 + i * ProfitIncrementFactor);
            }
        }
        
        // Save the newly calculated profit targets to CSV for future use
        SaveCompletionStatusToCSV();
    }
    for(int i = 0; i < 6; i++)
    {
        if(tf_profit_targets[i] == 0.0)
            Print(tf_names[i], ": Unlimited profit target");
        else
            Print(tf_names[i], ": $", DoubleToString(tf_profit_targets[i], 2));
    }
    
    // Reset completion status if requested
    if(ResetCompletionOnStart)
    {
        ResetCompletionStatus();
    }
    
    // Check for existing orders from previous EA runs
    ScanExistingOrders();
    
    // Synchronize existing orders with CSV (update CSV to match broker state)
    SynchronizeOrdersWithCSV();
    
    // Initialize max loss protection
    if(EnableMaxLossProtection)
    {
        max_loss_hit = false;
        current_session_loss = 0.0;
        max_loss_hit_time = 0;
        Print("Max loss protection enabled - Threshold: $", DoubleToString(MaxOverallLoss, 2));
    }
    
    // Initialize max profit protection
    if(EnableMaxProfitProtection)
    {
        max_profit_hit = false;
        current_session_profit = 0.0;
        max_profit_hit_time = 0;
        if(MaxOverallProfit > 0.0)
            Print("Max profit protection enabled - Threshold: $", DoubleToString(MaxOverallProfit, 2));
        else
            Print("Max profit protection disabled - MaxOverallProfit set to 0 (unlimited)");
    }
    
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
            
        // Remove all TP lines when EA is stopped
        RemoveTPLine(i);
    }
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
    // Update current spread
    current_spread = GetSpread();
    
    // Check for weekend market close
    CheckForWeekendClose();
    
    // Check for executed orders and mark timeframes as completed
    CheckForExecutedOrders();
    
    // Monitor positions for profit target
    MonitorPositionsForProfitTarget();
    
    // Check max loss protection first
    CheckMaxLossProtection();
    
    // Check max profit protection
    CheckMaxProfitProtection();
    
    // If max loss or max profit hit, check if we can resume trading
    if((max_loss_hit && !CanResumeAfterMaxLoss()) || (max_profit_hit && !CanResumeAfterMaxProfit()))
    {
        // Still waiting for major trend change, don't place new orders
        static datetime last_warning = 0;
        if(TimeCurrent() - last_warning > 300) // Print warning every 5 minutes
        {
            if(max_loss_hit)
                Print("Max loss protection active - waiting for major trend change to resume trading");
            if(max_profit_hit)
                Print("Max profit protection active - waiting for major trend change to resume trading");
            last_warning = TimeCurrent();
        }
        return;
    }
    
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
    
    // Update or place orders for all timeframes (with timing protection)
    datetime current_time = TimeCurrent();
    datetime current_candle_time = iTime(_Symbol, 0, 0);
    
    if (current_candle_time != last_candle_time || 
        (current_time - last_order_management_time >= ORDER_MANAGEMENT_INTERVAL))
    {
        // Synchronize our tracking with actual broker orders before managing orders
        SynchronizeOrderTracking();
        ManageTimeframeOrders();
        last_candle_time = current_candle_time;
        last_order_management_time = current_time;
    }
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
                            if(StringFind(comment, "ST_BuyLimit_" + tf_names[i]) >= 0 ||
                               StringFind(comment, "ST_SellLimit_" + tf_names[i]) >= 0)
                            {
                                order_executed = true;
                                break;
                            }
                        }
                    }
                }
                
                if(order_executed)
                {
                    MarkTimeframeCompleted(i);
                    Print("Order executed for ", tf_names[i], " - Position opened | CSV updated");
                }
                
                // Remove TP line since order no longer exists
                RemoveTPLine(i);
                
                // Reset tracking and update CSV
                tf_orders[i].is_active = false;
                tf_orders[i].ticket = 0;
                tf_orders[i].last_order_price = 0;
                tf_orders[i].last_line_price = 0;
                
                // Update CSV to reflect order state change
                if(!order_executed) // Only update CSV here if order wasn't executed (already updated in MarkTimeframeCompleted)
                {
                    SaveCompletionStatusToCSV();
                    Print("Order removed for ", tf_names[i], " (cancelled or expired) | CSV updated");
                }
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Monitor positions for profit target and close when reached     |
//+------------------------------------------------------------------+
void MonitorPositionsForProfitTarget()
{
    // If ProfitTarget is 0, don't monitor for profit targets (unlimited profit)
    if(ProfitTarget == 0.0)
        return;
        
    for(int i = 0; i < PositionsTotal(); i++)
    {
        if(PositionGetTicket(i) > 0)
        {
            if(PositionGetInteger(POSITION_MAGIC) == Magic &&
               PositionGetString(POSITION_SYMBOL) == _Symbol)
            {
                double profit = PositionGetDouble(POSITION_PROFIT);
                string comment = PositionGetString(POSITION_COMMENT);
                double position_price = PositionGetDouble(POSITION_PRICE_OPEN);
                ENUM_POSITION_TYPE position_type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
                
                // Identify which timeframe this position belongs to
                int tf_index = -1;
                for(int tf = 0; tf < 6; tf++)
                {
                    if(StringFind(comment, "ST_BuyLimit_" + tf_names[tf]) >= 0 ||
                       StringFind(comment, "ST_SellLimit_" + tf_names[tf]) >= 0)
                    {
                        tf_index = tf;
                        break;
                    }
                }
                
                // If we found which timeframe this belongs to
                if(tf_index >= 0)
                {
                    // Calculate TP level based on position type and profit target
                    double tp_price;
                    string direction;
                    
                    if(position_type == POSITION_TYPE_BUY)
                    {
                        tp_price = position_price + (tf_profit_targets[tf_index] / (LotSize * 10)) * _Point;
                        direction = "Buy";
                    }
                    else
                    {
                        tp_price = position_price - (tf_profit_targets[tf_index] / (LotSize * 10)) * _Point;
                        direction = "Sell";
                    }
                }
                
                // Get the appropriate profit target for this timeframe
                double current_profit_target = (tf_index >= 0) ? tf_profit_targets[tf_index] : ProfitTarget;
                
                // Check if profit target is reached (only if target > 0)
                if(current_profit_target > 0.0 && profit >= current_profit_target)
                {
                    ulong ticket = PositionGetTicket(i);
                    
                    // Close the position
                    if(trade.PositionClose(ticket))
                    {                        
                        // Remove TP line for this position
                        if(tf_index >= 0)
                        {
                            RemoveTPLine(tf_index);
                            ResetTimeframeStatus(tf_index);
                        }
                    }
                }
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Monitor overall loss and close all positions if max loss hit   |
//+------------------------------------------------------------------+
void CheckMaxLossProtection()
{
    if(!EnableMaxLossProtection || max_loss_hit)
        return;
    
    double total_profit = 0.0;
    int position_count = 0;
    
    // Calculate total profit/loss across all positions
    for(int i = 0; i < PositionsTotal(); i++)
    {
        if(PositionGetTicket(i) > 0)
        {
            if(PositionGetInteger(POSITION_MAGIC) == Magic &&
               PositionGetString(POSITION_SYMBOL) == _Symbol)
            {
                total_profit += PositionGetDouble(POSITION_PROFIT);
                position_count++;
            }
        }
    }
    
    // Check if max loss threshold is breached
    if(total_profit <= -MaxOverallLoss && position_count > 0)
    {
        Print("MAX LOSS HIT! Total loss: $", DoubleToString(MathAbs(total_profit), 2), 
              " | Threshold: $", DoubleToString(MaxOverallLoss, 2));
        Print("Closing all ", position_count, " positions and cancelling pending orders");
        
        // Close all positions
        CloseAllPositions();
        
        // Cancel all pending orders
        CancelAllPendingOrders();
        
        // Mark max loss as hit and record the time
        max_loss_hit = true;
        max_loss_hit_time = TimeCurrent();
        current_session_loss = MathAbs(total_profit);
        
        // Reset completion status so new orders can be placed after recovery
        ResetCompletionStatus();
        
        Print("Current session loss recorded: $", DoubleToString(current_session_loss, 2));
    }
}

//+------------------------------------------------------------------+
//| Monitor overall profit and close all positions if max profit hit |
//+------------------------------------------------------------------+
void CheckMaxProfitProtection()
{
    if(!EnableMaxProfitProtection || MaxOverallProfit == 0.0 || max_profit_hit)
        return;
    
    double total_profit = 0.0;
    int position_count = 0;
    
    // Calculate total profit/loss across all positions
    for(int i = 0; i < PositionsTotal(); i++)
    {
        if(PositionGetTicket(i) > 0)
        {
            if(PositionGetInteger(POSITION_MAGIC) == Magic &&
               PositionGetString(POSITION_SYMBOL) == _Symbol)
            {
                total_profit += PositionGetDouble(POSITION_PROFIT);
                position_count++;
            }
        }
    }
    
    // Check if max profit threshold is reached
    if(total_profit >= MaxOverallProfit && position_count > 0)
    {
        Print("MAX PROFIT HIT! Total profit: $", DoubleToString(total_profit, 2), 
              " | Threshold: $", DoubleToString(MaxOverallProfit, 2));
        Print("Closing all ", position_count, " positions and cancelling pending orders");
        
        // Close all positions
        CloseAllPositions();
        
        // Cancel all pending orders
        CancelAllPendingOrders();
        
        // Mark max profit as hit and record the time
        max_profit_hit = true;
        max_profit_hit_time = TimeCurrent();
        current_session_profit = total_profit;
        
        // Reset completion status so new orders can be placed after recovery
        ResetCompletionStatus();
        
        Print("Max profit protection activated. Waiting for major trend change to resume trading...");
        Print("Current session profit recorded: $", DoubleToString(current_session_profit, 2));
    }
}

//+------------------------------------------------------------------+
//| Check if we can resume trading after max profit hit            |
//+------------------------------------------------------------------+
bool CanResumeAfterMaxProfit()
{
    if(!max_profit_hit)
        return true;
    
    // We need a major trend change to resume trading
    // This means the 30M trend must have changed since max profit was hit
    double trend_direction[];
    ArraySetAsSeries(trend_direction, true);
    
    if(CopyBuffer(st_handle_30M, 2, 0, 2, trend_direction) < 2)
        return false;
    
    double current_30m_trend = trend_direction[1];
    
    // Check if trend has changed since max profit
    static double trend_when_max_profit_hit = -1;
    
    // Record the trend when max profit was first hit
    if(trend_when_max_profit_hit == -1)
    {
        trend_when_max_profit_hit = current_30m_trend;
        Print("Recorded trend when max profit hit: ", (trend_when_max_profit_hit == 0 ? "BULLISH" : "BEARISH"));
        return false; // Don't resume immediately
    }
    
    // Check if trend has changed
    if(current_30m_trend != trend_when_max_profit_hit)
    {
        Print("MAJOR TREND CHANGE DETECTED after max profit!");
        Print("Previous trend: ", (trend_when_max_profit_hit == 0 ? "BULLISH" : "BEARISH"));
        Print("New trend: ", (current_30m_trend == 0 ? "BULLISH" : "BEARISH"));
        Print("Resuming trading operations...");
        
        // Reset max profit protection
        max_profit_hit = false;
        max_profit_hit_time = 0;
        trend_when_max_profit_hit = -1;
        
        return true;
    }
    
    return false; // Still waiting for trend change
}

//+------------------------------------------------------------------+
//| Check if we can resume trading after max loss hit              |
//+------------------------------------------------------------------+
bool CanResumeAfterMaxLoss()
{
    if(!max_loss_hit)
        return true;
    
    // We need a major trend change to resume trading
    // This means the 30M trend must have changed since max loss was hit
    double trend_direction[];
    ArraySetAsSeries(trend_direction, true);
    
    if(CopyBuffer(st_handle_30M, 2, 0, 2, trend_direction) < 2)
        return false;
    
    double current_30m_trend = trend_direction[1];
    
    // Check if trend has changed since max loss
    static double trend_when_max_loss_hit = -1;
    
    // Record the trend when max loss was first hit
    if(trend_when_max_loss_hit == -1)
    {
        trend_when_max_loss_hit = current_30m_trend;
        Print("Recorded trend when max loss hit: ", (trend_when_max_loss_hit == 0 ? "BULLISH" : "BEARISH"));
        return false; // Don't resume immediately
    }
    
    // Check if trend has changed
    if(current_30m_trend != trend_when_max_loss_hit)
    {
        Print("MAJOR TREND CHANGE DETECTED after max loss!");
        Print("Previous trend: ", (trend_when_max_loss_hit == 0 ? "BULLISH" : "BEARISH"));
        Print("New trend: ", (current_30m_trend == 0 ? "BULLISH" : "BEARISH"));
        Print("Resuming trading operations...");
        
        // Reset max loss protection
        max_loss_hit = false;
        max_loss_hit_time = 0;
        trend_when_max_loss_hit = -1;
        
        return true;
    }
    
    return false; // Still waiting for trend change
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
            tf_orders[i].is_active = false;
            tf_orders[i].ticket = 0;
            has_pending_order = false;
        }
        
        if(should_have_buy_order)
        {
            double min_distance = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * SymbolInfoDouble(_Symbol, SYMBOL_POINT);
            
            // Place Buy Limit order ABOVE SuperTrend line with spread buffer
            // When price comes down to this level, it will buy
            double order_price = current_line + (current_spread * OrderBufferMultiplier);
            
            // Ensure the order price meets broker minimum distance requirements
            double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
            if(order_price <= ask - min_distance)
            {
                // Price is valid, continue
            }
            else
            {
                // Adjust price to meet minimum requirements
                order_price = ask - min_distance - SymbolInfoDouble(_Symbol, SYMBOL_POINT);
            }
            
            if(!has_pending_order)
            {
                // Check if we need to cancel opposite type order first
                if(tf_orders[i].is_active && tf_orders[i].order_type == ORDER_TYPE_SELL_LIMIT)
                {
                    CancelOrder(i);
                }
                
                // Only place new order if timeframe not completed and no existing orders
                if(!IsTimeframeCompleted(i) && CountOrdersForTimeframe(i) == 0)
                {
                    PlaceBuyLimitOrder(i, order_price, current_line);
                }
            }
            else
            {
                // Check if order type matches (buy order for buy condition)
                if(tf_orders[i].order_type == ORDER_TYPE_BUY_LIMIT)
                {
                    // Check if SuperTrend line price has actually changed
                    if(current_line != tf_orders[i].last_line_price)
                    {
                        // Also check if the calculated order price is different from the last order price
                        double min_price_change = _Point * 10; // Minimum 10 points change required for buy orders
                        if(MathAbs(order_price - tf_orders[i].last_order_price) > min_price_change)
                        {
                            // Validate new price before modification
                            if(IsValidBuyLimitPrice(order_price))
                            {
                                ModifyOrder(i, order_price);
                                tf_orders[i].last_line_price = current_line;
                                tf_orders[i].last_order_price = order_price;
                            }
                            else
                            {
                                CancelOrder(i);
                            }
                        }
                        // If calculated price hasn't changed significantly, just update line price tracking
                        else
                        {
                            tf_orders[i].last_line_price = current_line;
                        }
                    }
                    // If line hasn't changed, no need to modify order
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
            double min_distance = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * SymbolInfoDouble(_Symbol, SYMBOL_POINT);
            
            // Place Sell Limit order BELOW SuperTrend line with spread buffer
            // When price comes up to this level, it will sell
            double order_price = current_line - (current_spread * OrderBufferMultiplier);
            
            // Ensure the order price meets broker minimum distance requirements
            double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
            if(order_price >= bid + min_distance)
            {
                // Price is valid, continue
            }
            else
            {
                // Adjust price to meet minimum requirements
                order_price = bid + min_distance + SymbolInfoDouble(_Symbol, SYMBOL_POINT);
            }
            
            if(!has_pending_order)
            {
                // Check if we need to cancel opposite type order first
                if(tf_orders[i].is_active && tf_orders[i].order_type == ORDER_TYPE_BUY_LIMIT)
                {
                    CancelOrder(i);
                }
                
                // Only place new order if timeframe not completed and no existing orders
                if(!IsTimeframeCompleted(i) && CountOrdersForTimeframe(i) == 0)
                {
                    PlaceSellLimitOrder(i, order_price, current_line);
                }
            }
            else
            {
                // Check if order type matches (sell order for sell condition)
                if(tf_orders[i].order_type == ORDER_TYPE_SELL_LIMIT)
                {
                    // Check if SuperTrend line price has actually changed
                    if(current_line != tf_orders[i].last_line_price)
                    {
                        // Also check if the calculated order price is different from the last order price
                        double min_price_change = _Point * 10; // Minimum 10 points change required for sell orders
                        if(MathAbs(order_price - tf_orders[i].last_order_price) > min_price_change)
                        {
                            // Validate new price before modification
                            if(IsValidSellLimitPrice(order_price))
                            {
                                ModifyOrder(i, order_price);
                                tf_orders[i].last_line_price = current_line;
                                tf_orders[i].last_order_price = order_price;
                            }
                            else
                            {
                                CancelOrder(i);
                            }
                        }
                        // If calculated price hasn't changed significantly, just update line price tracking
                        else
                        {
                            tf_orders[i].last_line_price = current_line;
                        }
                    }
                    // If line hasn't changed, no need to modify order
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
    // Safety check: don't place order if one already exists for this timeframe
    if(CountOrdersForTimeframe(tf_index) > 0)
    {
        Print("Cannot place buy order for ", tf_names[tf_index], " - order already exists");
        return;
    }
    
    // Check if timeframe is completed
    if(IsTimeframeCompleted(tf_index))
    {
        Print("Cannot place buy order for ", tf_names[tf_index], " - timeframe already completed");
        return;
    }
    
    // Validate price before placing order
    if(!IsValidBuyLimitPrice(price))
    {
        Print("Cannot place buy order for ", tf_names[tf_index], " - invalid price: ", DoubleToString(price, _Digits));
        return;
    }
    
    string comment = "ST_BuyLimit_" + tf_names[tf_index];
    
    Print("Attempting to place buy order for ", tf_names[tf_index], " at price: ", DoubleToString(price, _Digits));
    
    if(trade.BuyLimit(LotSize, price, _Symbol, 0, 0, ORDER_TIME_GTC, 0, comment))
    {
        ulong new_ticket = trade.ResultOrder();
        tf_orders[tf_index].ticket = new_ticket;
        tf_orders[tf_index].is_active = true;
        tf_orders[tf_index].last_line_price = line_value;
        tf_orders[tf_index].last_order_price = price;
        tf_orders[tf_index].order_type = ORDER_TYPE_BUY_LIMIT;
        
        // Calculate and draw TP level on chart
        double tp_price = price + (tf_profit_targets[tf_index] / (LotSize * 10)) * _Point;
        
        // Update CSV with new order information
        SaveCompletionStatusToCSV();
        
        Print("Buy Limit order placed for ", tf_names[tf_index], " - Ticket: ", new_ticket, 
              " Price: ", DoubleToString(price, _Digits), " | CSV updated"); 
    }
    else
    {
        Print("Failed to place buy order for ", tf_names[tf_index], " - Error: ", GetLastError());
    }
}

//+------------------------------------------------------------------+
//| Place sell limit order                                          |
//+------------------------------------------------------------------+
void PlaceSellLimitOrder(int tf_index, double price, double line_value)
{
    // Safety check: don't place order if one already exists for this timeframe
    if(CountOrdersForTimeframe(tf_index) > 0)
    {
        Print("Cannot place sell order for ", tf_names[tf_index], " - order already exists");
        return;
    }
    
    // Check if timeframe is completed
    if(IsTimeframeCompleted(tf_index))
    {
        Print("Cannot place sell order for ", tf_names[tf_index], " - timeframe already completed");
        return;
    }
    
    // Validate price before placing order
    if(!IsValidSellLimitPrice(price))
    {
        Print("Cannot place sell order for ", tf_names[tf_index], " - invalid price: ", DoubleToString(price, _Digits));
        return;
    }
    
    string comment = "ST_SellLimit_" + tf_names[tf_index];
    
    if(trade.SellLimit(LotSize, price, _Symbol, 0, 0, ORDER_TIME_GTC, 0, comment))
    {
        tf_orders[tf_index].ticket = trade.ResultOrder();
        tf_orders[tf_index].is_active = true;
        tf_orders[tf_index].last_line_price = line_value;
        tf_orders[tf_index].last_order_price = price;
        tf_orders[tf_index].order_type = ORDER_TYPE_SELL_LIMIT;
        
        // Calculate and draw TP level on chart
        double tp_price = price - (tf_profit_targets[tf_index] / (LotSize * 10)) * _Point;
        
        // Update CSV with new order information
        SaveCompletionStatusToCSV();
        
        Print("Sell Limit order placed for ", tf_names[tf_index], " - Ticket: ", tf_orders[tf_index].ticket, 
              " Price: ", DoubleToString(price, _Digits), " | CSV updated");
    }
    else
    {
        Print("Failed to place sell order for ", tf_names[tf_index], " - Error: ", GetLastError());
    }
}

//+------------------------------------------------------------------+
//| Modify existing order                                           |
//+------------------------------------------------------------------+
void ModifyOrder(int tf_index, double new_price)
{
    trade.OrderModify(tf_orders[tf_index].ticket, new_price, 0, 0, ORDER_TIME_GTC, 0);
}

//+------------------------------------------------------------------+
//| Validate buy limit price                                       |
//+------------------------------------------------------------------+
bool IsValidBuyLimitPrice(double price)
{
    double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    double min_distance = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * SymbolInfoDouble(_Symbol, SYMBOL_POINT);
    
    // For Buy Limit, price must be below current Ask - min_distance
    // This is a broker requirement for placing pending orders
    bool is_valid = (price <= (ask - min_distance));
    
    return is_valid;
}

//+------------------------------------------------------------------+
//| Validate sell limit price                                      |
//+------------------------------------------------------------------+
bool IsValidSellLimitPrice(double price)
{
    double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    double min_distance = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * SymbolInfoDouble(_Symbol, SYMBOL_POINT);
    
    // For Sell Limit, price must be above current Bid + min_distance
    // This is a broker requirement for placing pending orders
    bool is_valid = (price >= (bid + min_distance));
    
    return is_valid;
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
    
    return is_valid;
}

//+------------------------------------------------------------------+
//| Cancel order for specific timeframe                            |
//+------------------------------------------------------------------+
bool CancelOrder(int tf_index)
{
    ulong ticket_to_cancel = tf_orders[tf_index].ticket;
    if(trade.OrderDelete(tf_orders[tf_index].ticket))
    {
        tf_orders[tf_index].is_active = false;
        tf_orders[tf_index].ticket = 0;
        tf_orders[tf_index].last_order_price = 0;
        tf_orders[tf_index].last_line_price = 0;
        
        // Remove TP line from chart
        RemoveTPLine(tf_index);
        
        // Update CSV to reflect cancelled order
        SaveCompletionStatusToCSV();
        
        Print("Order cancelled for ", tf_names[tf_index], " - Ticket: ", ticket_to_cancel, " | CSV updated");
        return true;
    }
    else
    {
        Print("Failed to cancel order for ", tf_names[tf_index], " - Ticket: ", ticket_to_cancel, " Error: ", GetLastError());
        return false;
    }
}

//+------------------------------------------------------------------+
//| Cancel all pending orders                                      |
//+------------------------------------------------------------------+
void CancelAllPendingOrders()
{
    int cancelled_count = 0;
    
    // First, cancel orders tracked in our array
    for(int i = 0; i < 6; i++)
    {
        if(tf_orders[i].is_active && OrderExists(tf_orders[i].ticket))
        {
            if(CancelOrder(i))
                cancelled_count++;
        }
        else
        {
            tf_orders[i].is_active = false;
            tf_orders[i].ticket = 0;
            // Remove any TP lines for orders that don't exist
            RemoveTPLine(i);
        }
    }
    
    // Double-check: scan all pending orders and cancel any with our magic number
    // This ensures we don't miss any orders that might not be tracked properly
    for(int i = OrdersTotal() - 1; i >= 0; i--)
    {
        ulong ticket = OrderGetTicket(i);
        if(ticket > 0 && 
           OrderGetString(ORDER_SYMBOL) == _Symbol &&
           OrderGetInteger(ORDER_MAGIC) == Magic)
        {
            if(trade.OrderDelete(ticket))
            {
                cancelled_count++;
                Print("Additional pending order cancelled: ", ticket);
            }
        }
    }
    
    if(cancelled_count > 0)
        Print("Total pending orders cancelled: ", cancelled_count);
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
    
    return count;
}

//+------------------------------------------------------------------+
//| Scan for existing orders on initialization                     |
//+------------------------------------------------------------------+
void ScanExistingOrders()
{
    
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
                    string buy_comment = "ST_BuyLimit_" + tf_names[tf];
                    string sell_comment = "ST_SellLimit_" + tf_names[tf];
                    
                    if(StringFind(order_comment, buy_comment) >= 0 || 
                       StringFind(order_comment, sell_comment) >= 0)
                    {
                        // Found existing order for this timeframe
                        tf_orders[tf].ticket = OrderGetTicket(i);
                        tf_orders[tf].is_active = true;
                        tf_orders[tf].order_type = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
                        tf_orders[tf].last_line_price = OrderGetDouble(ORDER_PRICE_OPEN);
                        tf_orders[tf].last_order_price = OrderGetDouble(ORDER_PRICE_OPEN);
                        break;
                    }
                }
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Synchronize internal order tracking with actual broker orders   |
//+------------------------------------------------------------------+
void SynchronizeOrderTracking()
{
    // Clear any inconsistent tracking
    for(int i = 0; i < 6; i++)
    {
        // If we think we have an active order but it doesn't exist, clear it
        if(tf_orders[i].is_active && tf_orders[i].ticket > 0)
        {
            if(!OrderExists(tf_orders[i].ticket))
            {
                Print("Clearing non-existent order tracking for ", tf_names[i], " - Ticket: ", tf_orders[i].ticket);
                tf_orders[i].is_active = false;
                tf_orders[i].ticket = 0;
                tf_orders[i].last_order_price = 0;
                tf_orders[i].last_line_price = 0;
            }
        }
    }
    
    // Scan for any orders that exist but we're not tracking
    for(int order_idx = 0; order_idx < OrdersTotal(); order_idx++)
    {
        ulong ticket = OrderGetTicket(order_idx);
        if(ticket > 0 && 
           OrderGetString(ORDER_SYMBOL) == _Symbol &&
           OrderGetInteger(ORDER_MAGIC) == Magic)
        {
            string comment = OrderGetString(ORDER_COMMENT);
            
            // Check which timeframe this order belongs to
            for(int tf_idx = 0; tf_idx < 6; tf_idx++)
            {
                string expected_comment = "ST_BuyLimit_" + tf_names[tf_idx];
                string expected_sell_comment = "ST_SellLimit_" + tf_names[tf_idx];
                
                if(StringFind(comment, expected_comment) >= 0 || StringFind(comment, expected_sell_comment) >= 0)
                {
                    // If we're not tracking this order, start tracking it
                    if(tf_orders[tf_idx].ticket != ticket)
                    {
                        Print("Found untracked order for ", tf_names[tf_idx], " - Ticket: ", ticket, " - Adding to tracking");
                        tf_orders[tf_idx].ticket = ticket;
                        tf_orders[tf_idx].is_active = true;
                        tf_orders[tf_idx].last_order_price = OrderGetDouble(ORDER_PRICE_OPEN);
                        tf_orders[tf_idx].order_type = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
                    }
                    break;
                }
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Synchronize existing orders with CSV                           |
//+------------------------------------------------------------------+
void SynchronizeOrdersWithCSV()
{
    Print("Synchronizing existing orders with CSV...");
    
    int existing_orders = 0;
    for(int i = 0; i < 6; i++)
    {
        if(tf_orders[i].is_active && tf_orders[i].ticket > 0)
        {
            existing_orders++;
        }
    }
    
    if(existing_orders > 0)
    {
        Print("Found ", existing_orders, " existing orders - updating CSV to match broker state");
        SaveCompletionStatusToCSV();
    }
    else
    {
        Print("No existing orders found - CSV will be updated as new orders are placed");
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
                trade.PositionClose(ticket);
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
//| Save timeframe completion status and profit targets to CSV     |
//+------------------------------------------------------------------+
void SaveCompletionStatusToCSV()
{
    int handle = FileOpen(csv_filename, FILE_WRITE|FILE_TXT);
    if(handle != INVALID_HANDLE)
    {
        // Write header with order tracking info
        string data = "Timeframe,Completed,ProfitTarget,HasOrder,OrderTicket,OrderType,OrderPrice,LastUpdate\n";
        FileWriteString(handle, data);
        
        // Write max loss protection status first
        data = "MAX_LOSS_STATUS," + 
               (max_loss_hit ? "TRUE" : "FALSE") + "," +
               DoubleToString(current_session_loss, 2) + "," +
               "FALSE,0,NONE,0.0," +
               TimeToString(max_loss_hit_time) + "\n";
        FileWriteString(handle, data);
        
        // Write max profit protection status
        data = "MAX_PROFIT_STATUS," + 
               (max_profit_hit ? "TRUE" : "FALSE") + "," +
               DoubleToString(current_session_profit, 2) + "," +
               "FALSE,0,NONE,0.0," +
               TimeToString(max_profit_hit_time) + "\n";
        FileWriteString(handle, data);
        
        // Write status and profit target for each timeframe with order info
        for(int i = 0; i < 6; i++)
        {
            string order_type_str = "NONE";
            if(tf_orders[i].is_active)
            {
                if(tf_orders[i].order_type == ORDER_TYPE_BUY_LIMIT)
                    order_type_str = "BUY_LIMIT";
                else if(tf_orders[i].order_type == ORDER_TYPE_SELL_LIMIT)
                    order_type_str = "SELL_LIMIT";
            }
            
            data = tf_names[i] + "," + 
                   (timeframe_completed[i] ? "TRUE" : "FALSE") + "," +
                   DoubleToString(tf_profit_targets[i], 2) + "," +
                   (tf_orders[i].is_active ? "TRUE" : "FALSE") + "," +
                   IntegerToString(tf_orders[i].ticket) + "," +
                   order_type_str + "," +
                   DoubleToString(tf_orders[i].last_order_price, _Digits) + "," +
                   TimeToString(TimeCurrent()) + "\n";
            FileWriteString(handle, data);
        }
        FileClose(handle);
    }
}

//+------------------------------------------------------------------+
//| Load timeframe completion status and profit targets from CSV   |
//+------------------------------------------------------------------+
void LoadCompletionStatusFromCSV()
{
    profit_targets_loaded = false;
    
    int handle = FileOpen(csv_filename, FILE_READ|FILE_TXT);
    if(handle != INVALID_HANDLE)
    {
        // Skip header
        string header = FileReadString(handle);
        bool has_profit_target = (StringFind(header, "ProfitTarget") >= 0);
        bool has_order_tracking = (StringFind(header, "HasOrder") >= 0); // Check if new CSV format
        
        // Try to read max loss status first
        string first_line = FileReadString(handle);
        if(StringFind(first_line, "MAX_LOSS_STATUS") >= 0)
        {
            string parts[];
            int count = StringSplit(first_line, ',', parts);
            if(count >= 2)
            {
                max_loss_hit = (parts[1] == "TRUE");
                if(count >= 3)
                    current_session_loss = StringToDouble(parts[2]);
                if(count >= 4 && parts[3] != "1970.01.01 00:00:00")
                    max_loss_hit_time = StringToTime(parts[3]);
                
                Print("Loaded max loss status: ", (max_loss_hit ? "ACTIVE" : "INACTIVE"),
                      " | Session loss: $", DoubleToString(current_session_loss, 2));
            }
        }
        else
        {
            // If no max loss status found, rewind file to process this line as timeframe data
            FileSeek(handle, 0, SEEK_SET);
            FileReadString(handle); // Skip header again
        }
        
        // Try to read max profit status
        string second_line = FileReadString(handle);
        if(StringFind(second_line, "MAX_PROFIT_STATUS") >= 0)
        {
            string parts[];
            int count = StringSplit(second_line, ',', parts);
            if(count >= 2)
            {
                max_profit_hit = (parts[1] == "TRUE");
                if(count >= 3)
                    current_session_profit = StringToDouble(parts[2]);
                if(count >= 4 && parts[3] != "1970.01.01 00:00:00")
                    max_profit_hit_time = StringToTime(parts[3]);
                
                Print("Loaded max profit status: ", (max_profit_hit ? "ACTIVE" : "INACTIVE"),
                      " | Session profit: $", DoubleToString(current_session_profit, 2));
            }
        }
        
        for(int i = 0; i < 6; i++)
        {
            string line = FileReadString(handle);
            if(line != "" && StringFind(line, "MAX_LOSS_STATUS") < 0 && StringFind(line, "MAX_PROFIT_STATUS") < 0)
            {
                string parts[];
                int count = StringSplit(line, ',', parts);
                
                if(count >= 2)
                {
                    timeframe_completed[i] = (parts[1] == "TRUE");
                    
                    // Load profit targets if available in the CSV
                    if(has_profit_target && count >= 3)
                    {
                        tf_profit_targets[i] = StringToDouble(parts[2]);
                        profit_targets_loaded = true;
                    }
                    
                    // Load order information if available (new CSV format)
                    if(has_order_tracking && count >= 8)
                    {
                        bool has_order = (parts[3] == "TRUE");
                        ulong order_ticket = StringToInteger(parts[4]);
                        string order_type_str = parts[5];
                        double order_price = StringToDouble(parts[6]);
                        
                        // Only restore order info if order still exists in the system
                        if(has_order && order_ticket > 0 && OrderExists(order_ticket))
                        {
                            tf_orders[i].is_active = true;
                            tf_orders[i].ticket = order_ticket;
                            tf_orders[i].last_order_price = order_price;
                            
                            if(order_type_str == "BUY_LIMIT")
                                tf_orders[i].order_type = ORDER_TYPE_BUY_LIMIT;
                            else if(order_type_str == "SELL_LIMIT")
                                tf_orders[i].order_type = ORDER_TYPE_SELL_LIMIT;
                            
                            Print("Restored existing order for ", tf_names[i], ": Ticket ", order_ticket, 
                                  " Type: ", order_type_str, " Price: ", DoubleToString(order_price, _Digits));
                        }
                        else if(has_order && order_ticket > 0)
                        {
                            // Order was in CSV but doesn't exist anymore - clean up
                            Print("Order in CSV for ", tf_names[i], " no longer exists (Ticket: ", order_ticket, ") - cleaning up");
                        }
                    }
                    
                    Print("Loaded status for ", tf_names[i], ": ", 
                          (timeframe_completed[i] ? "COMPLETED" : "PENDING"),
                          (profit_targets_loaded ? " with profit target: $" + DoubleToString(tf_profit_targets[i], 2) : ""));
                }
            }
        }
        FileClose(handle);
        
        if(profit_targets_loaded)
            Print("Loaded completion status and profit targets from: ", csv_filename);
        else
            Print("Loaded completion status from: ", csv_filename, " (without profit targets)");
    }
    else
    {
        // Initialize all as false (default)
        for(int i = 0; i < 6; i++)
            timeframe_completed[i] = false;
        max_loss_hit = false;
        current_session_loss = 0.0;
        max_loss_hit_time = 0;
        max_profit_hit = false;
        current_session_profit = 0.0;
        max_profit_hit_time = 0;
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
    }
}

//+------------------------------------------------------------------+
//| Check for weekend market close and handle orders                |
//+------------------------------------------------------------------+
void CheckForWeekendClose()
{
    if(!CancelOrdersBeforeWeekend)
        return;
    
    MqlDateTime time_struct;
    TimeToStruct(TimeCurrent(), time_struct);
    
    // Friday and near close time (typically around 21:00-23:00 GMT depending on broker)
    if(time_struct.day_of_week == 5 && time_struct.hour >= 20 && !is_market_closed)
    {
        
        // Count pending orders
        int pending_count = 0;
        for(int i = 0; i < 6; i++)
        {
            if(tf_orders[i].is_active && OrderExists(tf_orders[i].ticket))
                pending_count++;
        }
        
        if(pending_count > 0)
        {
            CancelAllPendingOrders();
            is_market_closed = true;
            weekend_close_time = TimeCurrent();
        }
    }
    
    // If it's Sunday/Monday and market is reopening after weekend
    if(time_struct.day_of_week == 0 || time_struct.day_of_week == 1)
    {
        // If we marked as closed during weekend and it's been more than a day
        if(is_market_closed && TimeCurrent() - weekend_close_time > 86400) // 86400 seconds = 24 hours
        {
            is_market_closed = false;
        }
    }
}

//+------------------------------------------------------------------+
//| Remove Take Profit line from chart                             |
//+------------------------------------------------------------------+
void RemoveTPLine(int tf_index)
{
    
    if(tf_index < 0 || tf_index >= 6) return;
    
    // Try to delete both buy and sell TP lines for this timeframe
    string name_buy = "TP_Line_" + tf_names[tf_index] + "_Buy";
    string name_sell = "TP_Line_" + tf_names[tf_index] + "_Sell";
    
    ObjectDelete(0, name_buy);
    ObjectDelete(0, name_sell);
    
    ChartRedraw(0);
}

//+------------------------------------------------------------------+
