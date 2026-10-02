//+------------------------------------------------------------------+
//|                                                         GOLD.mq5 |
//|                                   Copyright 2025, Your Company   |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, Your Company"
#property link      "https://www.mql5.com"
#property version   "1.00"

#include <Trade\Trade.mqh>
#include <Trade\SymbolInfo.mqh>
#include <Trade\PositionInfo.mqh>

//+------------------------------------------------------------------+
//| Enums                                                            |
//+------------------------------------------------------------------+
enum ENUM_TRADE_DIRECTION {
   TRADE_BOTH = 0,      // Both Buy and Sell
   TRADE_BUY_ONLY = 1,  // Buy Only
   TRADE_SELL_ONLY = 2  // Sell Only
};

//+------------------------------------------------------------------+
//| Order Management Functions (from OrderManagement.mqh)           |
//+------------------------------------------------------------------+
// Place a pending BUY LIMIT order using CTrade object (below current price)
bool PlaceBuyLimit(double lot_Size, double price, string comment = "", double stopLoss = 0, double takeProfit = 0)
{
   // stopLoss/takeProfit = 0 means no SL/TP
   datetime expiration = 0;
   bool result = trade.BuyLimit(lot_Size, price, _Symbol, stopLoss, takeProfit, ORDER_TIME_GTC, expiration, comment);
   if(!result)
   {
      return false;
   }
   return true;
}

// Place a pending SELL LIMIT order using CTrade object (below current price)
bool PlaceSellLimit(double lot_Size, double price, string comment = "", double stopLoss = 0, double takeProfit = 0)
{
   // stopLoss/takeProfit = 0 means no SL/TP
   datetime expiration = 0;
   bool result = trade.SellLimit(lot_Size, price, _Symbol, stopLoss, takeProfit, ORDER_TIME_GTC, expiration, comment);
   if(!result)
   {
      return false;
   }
   return true;
}

// Place a pending BUY STOP order using CTrade object (above current price for trend following)
bool PlaceBuyStop(double lot_Size, double price, string comment = "", double stopLoss = 0, double takeProfit = 0)
{
   // stopLoss/takeProfit = 0 means no SL/TP
   datetime expiration = 0;
   bool result = trade.BuyStop(lot_Size, price, _Symbol, stopLoss, takeProfit, ORDER_TIME_GTC, expiration, comment);
   if(!result)
   {
      return false;
   }
   return true;
}

//+------------------------------------------------------------------+
//| Modify an existing pending order using CTrade::OrderModify      |
//+------------------------------------------------------------------+
bool ModifyPendingOrder(ulong ticket, double newPrice, double stoploss = 0, double takeprofit = 0, ENUM_ORDER_TYPE_TIME type_time = ORDER_TIME_GTC, datetime expiration = 0, double stoplimit = 0.0)
{
   bool result = trade.OrderModify(ticket, newPrice, stoploss, takeprofit, type_time, expiration, stoplimit);
   if(!result)
   {
      return false;
   }
   return true;
}

//+------------------------------------------------------------------+
//| Cancel all pending orders for the current symbol               |
//+------------------------------------------------------------------+
void CancelAllPendingOrders()
{
   for(int i=OrdersTotal()-1; i>=0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(OrderGetString(ORDER_SYMBOL) == _Symbol)
      {
         trade.OrderDelete(ticket);
      }
   }
}

//--- Input parameters
input double   ATRMultiplier = 9;           // ATR Multiplier
input int      ATRPeriod = 27;                // ATR Period
input double   LotSize = 0.01;                // Lot Size
input int      MagicNumber = 999;          // Magic Number

input group "=== Daily Profit Settings ==="
input bool     UseDailyProfitTarget = true;   // Use Daily Profit Target
input double   DailyProfitTarget = 5000.0;      // Daily Profit Target in dollars

input group "=== Monthly Profit Settings ==="
input bool     UseMonthlyProfitTarget = false; // Use Monthly Profit Target
input double   MonthlyProfitTarget = 200.0;   // Monthly Profit Target in dollars

input group "=== Session Close Settings ==="
input bool     CloseBeforeMarketClose = true; // Close EA trades before market close
input int      MinutesBeforeMarketClose = 15; // Minutes before session close

input group "=== Profit Take Settings ==="
input bool     UseProfitTake = true;          // Use Profit Take for each trade
input double   ProfitTakeBase = 2500.0;         // Base Profit Take amount (multiplied by timeframe index)

input group "=== Loss Cut Settings ==="
input bool     UseLossCut = false;              // Use Loss Cut for each trade
input double   LossCutBase = 15.0;             // Base Loss Cut amount (multiplied by timeframe index)

input group "=== Position Entry Settings ==="
input ENUM_TRADE_DIRECTION TradeDirection = TRADE_BUY_ONLY; // Trade Direction
input bool     takePositionsAtStart = true;   // Take positions immediately (true) or use pending orders (false)
input double   spreadMultiplier = 2.5;        // Spread multiplier for pending order distance
input int      MinRetestGapPoints = 200;      // Minimum closed-bar gap from remembered line for immediate entry
input int      MaxRetestGapPoints = 400;      // Maximum closed-bar gap from remembered line for immediate entry

input group "=== Timeframe Settings ==="
input bool     Trade_M1 = true;              // Trade on 1 Minute
input bool     Trade_M2 = true;              // Trade on 2 Minutes
input bool     Trade_M3 = true;              // Trade on 3 Minutes
input bool     Trade_M5 = true;               // Trade on 5 Minutes
input bool     Trade_M10 = true;             // Trade on 10 Minutes
input bool     Trade_M15 = true;             // Trade on 15 Minutes
input bool     Trade_M30 = true;             // Trade on 30 Minutes
input bool     Trade_H1 = true;              // Trade on 1 Hour

//--- Global variables
CTrade         trade;
CSymbolInfo    symbol_info;
CPositionInfo  position_info;

// Timeframe arrays
ENUM_TIMEFRAMES timeframes[];
int            supertrend_handles[];
datetime       last_bar_times[];
int            current_trends[];
int            previous_trends[];
string         timeframe_names[];
double         last_st_line_prices[];  // Track SuperTrend line price changes
double         active_signal_line_prices[];
double         signal_entry_prices[];

// Daily profit tracking
datetime       last_profit_check_day;
bool           daily_target_reached;

// Monthly profit tracking
double         monthly_start_balance;
datetime       last_profit_check_month;
bool           monthly_target_reached;
datetime       last_session_close_day = 0;

// Spread and pending orders
double         current_spread;

double         point_value;
string         profit_label_name = "GOLD_EA_DAILY_PROFIT_LABEL";

string GetStateKey(int tf_index, string suffix)
{
    return "GOLD." + _Symbol + "." + IntegerToString(MagicNumber) + "." + timeframe_names[tf_index] + "." + suffix;
}

void SaveTimeframeState(int tf_index)
{
    GlobalVariableSet(GetStateKey(tf_index, "active_line"), active_signal_line_prices[tf_index]);
    GlobalVariableSet(GetStateKey(tf_index, "entry_price"), signal_entry_prices[tf_index]);
}

void LoadTimeframeState(int tf_index)
{
    string active_key = GetStateKey(tf_index, "active_line");
    string entry_key = GetStateKey(tf_index, "entry_price");

    if(GlobalVariableCheck(active_key))
        active_signal_line_prices[tf_index] = GlobalVariableGet(active_key);

    if(GlobalVariableCheck(entry_key))
        signal_entry_prices[tf_index] = GlobalVariableGet(entry_key);
}

void ClearTimeframeState(int tf_index)
{
    active_signal_line_prices[tf_index] = 0.0;
    signal_entry_prices[tf_index] = 0.0;
    GlobalVariableDel(GetStateKey(tf_index, "active_line"));
    GlobalVariableDel(GetStateKey(tf_index, "entry_price"));
}

void ClearAllTimeframeState()
{
    for(int i = 0; i < ArraySize(timeframes); i++)
        ClearTimeframeState(i);
}

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    // Initialize symbol info
    if(!symbol_info.Name(_Symbol))
    {
        return INIT_FAILED;
    }
    
    // Set trade parameters
    trade.SetExpertMagicNumber(MagicNumber);
    trade.SetMarginMode();
    trade.SetTypeFillingBySymbol(_Symbol);
    
    // Get point value
    point_value = _Point;
    
    // Get initial spread
    current_spread = GetSpread();
    
    // Setup timeframes based on input
    if(!SetupTimeframes())
    {
        return INIT_FAILED;
    }
    
    // Initialize daily profit tracking
    if(UseDailyProfitTarget)
        InitializeDailyProfit();

    // Initialize monthly profit tracking
    if(UseMonthlyProfitTarget)
        InitializeMonthlyProfit();

    // Set previous_trends to current trend for each timeframe to avoid trading on EA start
    for(int i = 0; i < ArraySize(timeframes); i++)
    {
        LoadTimeframeState(i);

        // Update indicator values to get current trend
        UpdateIndicatorValues(i);
        double current_st_line = GetSuperTrendLinePrice(i);
        if(active_signal_line_prices[i] <= 0.0)
            active_signal_line_prices[i] = current_st_line;
        last_st_line_prices[i] = current_st_line;
        SaveTimeframeState(i);
        previous_trends[i] = current_trends[i];
    }

    EventSetTimer(1);
    UpdateDailyProfitLabel();

    return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Setup timeframes and indicators                                  |
//+------------------------------------------------------------------+
bool SetupTimeframes()
{
    // Count enabled timeframes
    int count = 0;
    if(Trade_M1) count++;
    if(Trade_M2) count++;
    if(Trade_M3) count++;
    if(Trade_M5) count++;
    if(Trade_M10) count++;
    if(Trade_M15) count++;
    if(Trade_M30) count++;
    if(Trade_H1) count++;
    
    if(count == 0)
    {
        return false;
    }
    
    // Resize arrays
    ArrayResize(timeframes, count);
    ArrayResize(supertrend_handles, count);
    ArrayResize(last_bar_times, count);
    ArrayResize(current_trends, count);
    ArrayResize(previous_trends, count);
    ArrayResize(timeframe_names, count);
    ArrayResize(last_st_line_prices, count);
    ArrayResize(active_signal_line_prices, count);
    ArrayResize(signal_entry_prices, count);
    
    // Setup timeframes
    int index = 0;
    if(Trade_M1) { timeframes[index] = PERIOD_M1; timeframe_names[index] = "M1"; index++; }
    if(Trade_M2) { timeframes[index] = PERIOD_M2; timeframe_names[index] = "M2"; index++; }
    if(Trade_M3) { timeframes[index] = PERIOD_M3; timeframe_names[index] = "M3"; index++; }
    if(Trade_M5) { timeframes[index] = PERIOD_M5; timeframe_names[index] = "M5"; index++; }
    if(Trade_M10) { timeframes[index] = PERIOD_M10; timeframe_names[index] = "M10"; index++; }
    if(Trade_M15) { timeframes[index] = PERIOD_M15; timeframe_names[index] = "M15"; index++; }
    if(Trade_M30) { timeframes[index] = PERIOD_M30; timeframe_names[index] = "M30"; index++; }
    if(Trade_H1) { timeframes[index] = PERIOD_H1; timeframe_names[index] = "H1"; index++; }
    
    // Initialize indicators for each timeframe
    for(int i = 0; i < count; i++)
    {
        supertrend_handles[i] = iCustom(_Symbol, timeframes[i], "Supertrend", 
                                       "SPRTRND", ATRMultiplier, ATRPeriod, 10000, 0,
                                       false, false, false, false, 1);
        
        if(supertrend_handles[i] == INVALID_HANDLE)
        {
            return false;
        }
        
        last_bar_times[i] = 0;
        current_trends[i] = 0;
        previous_trends[i] = -1;
        last_st_line_prices[i] = 0;
        active_signal_line_prices[i] = 0;
        signal_entry_prices[i] = 0;
    }
    
    return true;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    EventKillTimer();
    ObjectDelete(0, profit_label_name);

    // Release all indicator handles
    for(int i = 0; i < ArraySize(supertrend_handles); i++)
    {
        if(supertrend_handles[i] != INVALID_HANDLE)
            IndicatorRelease(supertrend_handles[i]);
    }
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
    UpdateDailyProfitLabel();

    // Proper loss cut logic: use UseLossCut and LossCutBase for per-timeframe threshold
    if(UseLossCut)
    {
        for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
            if(position_info.SelectByIndex(i))
            {
                if(position_info.Symbol() == _Symbol)
                {
                    int tf_index = -1;
                    for(int j = 0; j < ArraySize(timeframes); j++)
                    {
                        if(position_info.Magic() == MagicNumber + j)
                        {
                            tf_index = j;
                            break;
                        }
                    }
                    if(tf_index != -1)
                    {
                        double loss_threshold = -LossCutBase * (tf_index + 1); // M1=-15, M2=-30, etc.
                        double floating = position_info.Profit();
                        if(floating <= loss_threshold)
                        {
                            trade.SetExpertMagicNumber(position_info.Magic());
                            trade.PositionClose(position_info.Ticket());
                        }
                    }
                }
            }
        }
    }
    // Check daily profit target (if enabled)
    if(UseDailyProfitTarget)
    {
        CheckDailyProfit();
        
        // If daily target reached, don't trade
        if(daily_target_reached)
            return;
    }
    
    // Check monthly profit target (if enabled)
    if(UseMonthlyProfitTarget)
    {
        CheckMonthlyProfit();
        
        // If monthly target reached, don't trade
        if(monthly_target_reached)
            return;
    }

    if(CheckSessionCloseWindow())
        return;
    
    // Check all enabled timeframes
    for(int i = 0; i < ArraySize(timeframes); i++)
    {
        // Check profit take for existing positions (if enabled)
        if(UseProfitTake)
            CheckProfitTake(i);

        CheckRealtimeImmediateEntry(i);
             
        // Check if new bar for this timeframe
        if(!IsNewBar(i)) continue;
        
        // Update indicator values for this timeframe
        if(!UpdateIndicatorValues(i)) continue;
        
        // Check for trend change and trade on this timeframe
        CheckTrendAndTrade(i);
    }
}

//+------------------------------------------------------------------+
//| Check if new bar opened for specific timeframe                   |
//+------------------------------------------------------------------+
bool IsNewBar(int tf_index)
{
    datetime closed_bar_time[1];
    if(CopyTime(_Symbol, timeframes[tf_index], 1, 1, closed_bar_time) < 1)
    {
        return false;
    }

    if(closed_bar_time[0] != last_bar_times[tf_index])
    {
        last_bar_times[tf_index] = closed_bar_time[0];
        return true;
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| Update indicator values for specific timeframe                   |
//+------------------------------------------------------------------+
bool UpdateIndicatorValues(int tf_index)
{
    // Create local array for this timeframe
    double temp_directions[];
    ArraySetAsSeries(temp_directions, true);
    
    // Copy indicator direction buffer for this timeframe
    if(CopyBuffer(supertrend_handles[tf_index], 2, 0, 3, temp_directions) < 0)
    {
        return false;
    }
    
    // Store the current trend value in the current_trends array
    if(ArraySize(temp_directions) >= 2)
    {
        current_trends[tf_index] = (int)temp_directions[1]; // Previous completed bar
    }
    
    return true;
}

double GetMinDistancePrice()
{
    int stops_level = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
    int freeze_level = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL);
    return MathMax(stops_level, freeze_level) * _Point;
}

bool GetClosedBarClosePrice(int tf_index, double &close_price)
{
    double closes[];
    ArraySetAsSeries(closes, true);
    if(CopyClose(_Symbol, timeframes[tf_index], 1, 1, closes) < 1)
        return false;

    close_price = closes[0];
    return true;
}

bool GetPendingOrderTicketAndPrice(int magic, ENUM_ORDER_TYPE order_type, ulong &ticket, double &price)
{
    for(int i = OrdersTotal() - 1; i >= 0; i--)
    {
        ulong current_ticket = OrderGetTicket(i);
        if(current_ticket == 0 || !OrderSelect(current_ticket))
            continue;

        if(OrderGetString(ORDER_SYMBOL) == _Symbol &&
           OrderGetInteger(ORDER_MAGIC) == magic &&
           OrderGetInteger(ORDER_TYPE) == order_type)
        {
            ticket = current_ticket;
            price = OrderGetDouble(ORDER_PRICE_OPEN);
            return true;
        }
    }

    return false;
}

double GetClosedBarGapFromRememberedLine(int tf_index, int trend_direction, double entry_price)
{
    if(entry_price <= 0.0)
        return -1.0;

    double close_price = 0.0;
    if(!GetClosedBarClosePrice(tf_index, close_price))
        return -1.0;

    if(trend_direction == 0)
        return (close_price - entry_price);
    if(trend_direction == 1)
        return (entry_price - close_price);

    return -1.0;
}

bool IsGapWithinImmediateEntryRange(int tf_index, int trend_direction, double entry_price)
{
    double gap = GetClosedBarGapFromRememberedLine(tf_index, trend_direction, entry_price);
    if(gap < 0.0)
        return false;

    double min_gap = MinRetestGapPoints * _Point;
    double max_gap = MaxRetestGapPoints * _Point;
    return (gap >= min_gap && gap <= max_gap);
}

double GetCurrentGapFromRememberedLine(int trend_direction, double entry_price)
{
    if(entry_price <= 0.0)
        return -1.0;

    double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

    if(trend_direction == 0)
        return (ask - entry_price);
    if(trend_direction == 1)
        return (entry_price - bid);

    return -1.0;
}

bool IsCurrentGapWithinImmediateEntryRange(int trend_direction, double entry_price)
{
    double gap = GetCurrentGapFromRememberedLine(trend_direction, entry_price);
    if(gap < 0.0)
        return false;

    double min_gap = MinRetestGapPoints * _Point;
    double max_gap = MaxRetestGapPoints * _Point;
    return (gap >= min_gap && gap <= max_gap);
}

bool IsCurrentPriceNearRememberedLine(int trend_direction, double entry_price)
{
    if(entry_price <= 0.0)
        return false;

    double max_gap = MaxRetestGapPoints * _Point;
    double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

    if(trend_direction == 0)
        return (ask > entry_price && ask <= entry_price + max_gap);
    if(trend_direction == 1)
        return (bid < entry_price && bid >= entry_price - max_gap);

    return false;
}

bool PlaceImmediateSignalOrder(int tf_index, int trend_direction)
{
    int magic = MagicNumber + tf_index;
    double tick_value = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
    double tick_size = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
    int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
    double sl_dollar = 50.0;
    double sl_distance = (sl_dollar * tick_size) / (tick_value * LotSize);

    trade.SetExpertMagicNumber(magic);

    if(trend_direction == 0)
    {
        double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
        double sl = NormalizeDouble(ask - sl_distance, digits);
        string comment = "SuperTrend Buy " + timeframe_names[tf_index];
        bool result = trade.Buy(LotSize, _Symbol, sl, 0, 0, comment);
        if(!result)
            Print("Immediate buy failed for ", timeframe_names[tf_index], " retcode=", trade.ResultRetcode(), " message=", trade.ResultRetcodeDescription());
        return result;
    }

    if(trend_direction == 1)
    {
        double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
        double sl = NormalizeDouble(bid + sl_distance, digits);
        string comment = "SuperTrend Sell " + timeframe_names[tf_index];
        bool result = trade.Sell(LotSize, _Symbol, sl, 0, 0, comment);
        if(!result)
            Print("Immediate sell failed for ", timeframe_names[tf_index], " retcode=", trade.ResultRetcode(), " message=", trade.ResultRetcodeDescription());
        return result;
    }

    return false;
}

void CheckRealtimeImmediateEntry(int tf_index)
{
    if(signal_entry_prices[tf_index] <= 0.0)
        return;

    int trend_direction = previous_trends[tf_index];
    int magic = MagicNumber + tf_index;

    if(!IsDirectionAllowed(trend_direction))
        return;

    if(!IsCurrentGapWithinImmediateEntryRange(trend_direction, signal_entry_prices[tf_index]))
        return;

    if(trend_direction == 0)
    {
        if(IsPositionExists(magic, POSITION_TYPE_BUY))
            return;

        ulong ticket = 0;
        double order_price = 0.0;
        if(GetPendingOrderTicketAndPrice(magic, ORDER_TYPE_BUY_LIMIT, ticket, order_price))
        {
            trade.SetExpertMagicNumber(magic);
            trade.OrderDelete(ticket);
        }

        if(PlaceImmediateSignalOrder(tf_index, trend_direction))
        {
            signal_entry_prices[tf_index] = 0.0;
            SaveTimeframeState(tf_index);
        }
    }
    else if(trend_direction == 1)
    {
        if(IsPositionExists(magic, POSITION_TYPE_SELL))
            return;

        ulong ticket = 0;
        double order_price = 0.0;
        if(GetPendingOrderTicketAndPrice(magic, ORDER_TYPE_SELL_LIMIT, ticket, order_price))
        {
            trade.SetExpertMagicNumber(magic);
            trade.OrderDelete(ticket);
        }

        if(PlaceImmediateSignalOrder(tf_index, trend_direction))
        {
            signal_entry_prices[tf_index] = 0.0;
            SaveTimeframeState(tf_index);
        }
    }
}

bool PlaceRetestPendingOrder(int tf_index, int trend_direction, double entry_price)
{
    int magic = MagicNumber + tf_index;
    double min_distance = GetMinDistancePrice();
    double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
    double normalized_price = NormalizeDouble(entry_price, digits);

    trade.SetExpertMagicNumber(magic);

    if(trend_direction == 0)
    {
        if(normalized_price >= ask - min_distance)
            return false;

        string comment = "SuperTrend Buy Limit " + timeframe_names[tf_index];
        return PlaceBuyLimit(LotSize, normalized_price, comment);
    }

    if(trend_direction == 1)
    {
        if(normalized_price <= bid + min_distance)
            return false;

        string comment = "SuperTrend Sell Limit " + timeframe_names[tf_index];
        return PlaceSellLimit(LotSize, normalized_price, comment);
    }

    return false;
}

void UpdateRetestPendingOrderState(int tf_index, int trend_direction, double st_line_price)
{
    int magic = MagicNumber + tf_index;
    ENUM_ORDER_TYPE expected_type = (trend_direction == 0) ? ORDER_TYPE_BUY_LIMIT : ORDER_TYPE_SELL_LIMIT;
    ulong ticket = 0;
    double order_price = 0.0;

    if(!GetPendingOrderTicketAndPrice(magic, expected_type, ticket, order_price))
        return;

    bool should_delete = false;
    if(trend_direction == 0)
        should_delete = (st_line_price >= order_price - (_Point * 0.5));
    else if(trend_direction == 1)
        should_delete = (st_line_price <= order_price + (_Point * 0.5));

    if(should_delete)
    {
        trade.SetExpertMagicNumber(magic);
        trade.OrderDelete(ticket);
        signal_entry_prices[tf_index] = 0.0;
        SaveTimeframeState(tf_index);
    }
}

//+------------------------------------------------------------------+
//| Check if position exists for specific magic and type             |
//+------------------------------------------------------------------+
bool IsPositionExists(int magic, ENUM_POSITION_TYPE type)
{
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        if(position_info.SelectByIndex(i))
        {
            if(position_info.Magic() == magic && position_info.Symbol() == _Symbol && position_info.PositionType() == type)
                return true;
        }
    }
    return false;
}

//+------------------------------------------------------------------+
//| Check whether a magic number belongs to this EA                  |
//+------------------------------------------------------------------+
bool IsOurMagicNumber(long magic)
{
    for(int i = 0; i < ArraySize(timeframes); i++)
    {
        if(magic == MagicNumber + i)
            return true;
    }

    return false;
}

bool IsDirectionAllowed(int trend_direction)
{
    if(trend_direction == 0)
        return (TradeDirection != TRADE_SELL_ONLY);
    if(trend_direction == 1)
        return (TradeDirection != TRADE_BUY_ONLY);

    return false;
}

bool IsSessionCloseWindow(datetime &close_day_key)
{
    if(!CloseBeforeMarketClose || MinutesBeforeMarketClose < 0)
        return false;

    datetime now_time = TimeTradeServer();
    MqlDateTime now_struct;
    TimeToStruct(now_time, now_struct);
    int current_day_of_week = now_struct.day_of_week;

    for(uint session_index = 0; ; session_index++)
    {
        datetime from_time = 0;
        datetime to_time = 0;
        if(!SymbolInfoSessionTrade(_Symbol, (ENUM_DAY_OF_WEEK)current_day_of_week, session_index, from_time, to_time))
            break;

        MqlDateTime from_struct;
        MqlDateTime to_struct;
        TimeToStruct(from_time, from_struct);
        TimeToStruct(to_time, to_struct);

        MqlDateTime session_open = now_struct;
        session_open.hour = from_struct.hour;
        session_open.min = from_struct.min;
        session_open.sec = from_struct.sec;

        MqlDateTime session_close = now_struct;
        session_close.hour = to_struct.hour;
        session_close.min = to_struct.min;
        session_close.sec = to_struct.sec;

        datetime session_from = StructToTime(session_open);
        datetime session_to = StructToTime(session_close);
        if(session_to <= session_from)
            session_to += 24 * 60 * 60;

        if(now_time >= session_from && now_time <= session_to)
        {
            datetime trigger_time = session_to - (MinutesBeforeMarketClose * 60);
            if(now_time >= trigger_time)
            {
                MqlDateTime close_struct;
                TimeToStruct(session_to, close_struct);
                close_struct.hour = 0;
                close_struct.min = 0;
                close_struct.sec = 0;
                close_day_key = StructToTime(close_struct);
                return true;
            }
            break;
        }
    }

    close_day_key = 0;
    return false;
}

bool CheckSessionCloseWindow()
{
    datetime close_day_key = 0;
    if(!IsSessionCloseWindow(close_day_key))
        return false;

    if(last_session_close_day != close_day_key)
    {
        last_session_close_day = close_day_key;
        CloseAllDailyPositions();
        ClearAllTimeframeState();
    }

    return true;
}

//+------------------------------------------------------------------+
//| Timer event                                                      |
//+------------------------------------------------------------------+
void OnTimer()
{
    UpdateDailyProfitLabel();
}

//+------------------------------------------------------------------+
//| Calculate today's realized and unrealized profit for this EA     |
//+------------------------------------------------------------------+
bool IsPositionIdTracked(const ulong &position_ids[], const ulong position_id)
{
    if(position_id == 0)
        return false;

    for(int i = 0; i < ArraySize(position_ids); i++)
    {
        if(position_ids[i] == position_id)
            return true;
    }

    return false;
}

void TrackPositionId(ulong &position_ids[], const ulong position_id)
{
    if(position_id == 0 || IsPositionIdTracked(position_ids, position_id))
        return;

    int size = ArraySize(position_ids);
    ArrayResize(position_ids, size + 1);
    position_ids[size] = position_id;
}

double CalculateTodayEAProfit(double &realized_profit, double &unrealized_profit)
{
    realized_profit = 0.0;
    unrealized_profit = 0.0;

    MqlDateTime current_time;
    TimeToStruct(TimeCurrent(), current_time);
    current_time.hour = 0;
    current_time.min = 0;
    current_time.sec = 0;
    datetime current_day = StructToTime(current_time);

    if(HistorySelect(0, TimeCurrent()))
    {
        int total_deals = HistoryDealsTotal();
        ulong ea_position_ids[];

        for(int i = 0; i < total_deals; i++)
        {
            ulong ticket = HistoryDealGetTicket(i);
            if(ticket == 0)
                continue;

            if(HistoryDealGetString(ticket, DEAL_SYMBOL) != _Symbol)
                continue;

            if(IsOurMagicNumber(HistoryDealGetInteger(ticket, DEAL_MAGIC)))
                TrackPositionId(ea_position_ids, (ulong)HistoryDealGetInteger(ticket, DEAL_POSITION_ID));
        }

        for(int i = 0; i < total_deals; i++)
        {
            ulong ticket = HistoryDealGetTicket(i);
            if(ticket == 0)
                continue;

            if(HistoryDealGetString(ticket, DEAL_SYMBOL) != _Symbol)
                continue;

            if((datetime)HistoryDealGetInteger(ticket, DEAL_TIME) < current_day)
                continue;

            ulong position_id = (ulong)HistoryDealGetInteger(ticket, DEAL_POSITION_ID);
            bool is_ea_deal = IsOurMagicNumber(HistoryDealGetInteger(ticket, DEAL_MAGIC)) ||
                              IsPositionIdTracked(ea_position_ids, position_id);

            if(!is_ea_deal)
                continue;

            realized_profit += HistoryDealGetDouble(ticket, DEAL_PROFIT) +
                               HistoryDealGetDouble(ticket, DEAL_SWAP) +
                               HistoryDealGetDouble(ticket, DEAL_COMMISSION);
        }
    }

    for(int i = 0; i < PositionsTotal(); i++)
    {
        if(position_info.SelectByIndex(i))
        {
            if(position_info.Symbol() == _Symbol && IsOurMagicNumber(position_info.Magic()))
            {
                unrealized_profit += position_info.Profit() + position_info.Swap();
            }
        }
    }

    return realized_profit + unrealized_profit;
}

//+------------------------------------------------------------------+
//| Update daily profit label on chart                               |
//+------------------------------------------------------------------+
void UpdateDailyProfitLabel()
{
    double realized_profit = 0.0;
    double unrealized_profit = 0.0;
    double total_profit = CalculateTodayEAProfit(realized_profit, unrealized_profit);

    if(ObjectFind(0, profit_label_name) < 0)
    {
        ObjectCreate(0, profit_label_name, OBJ_LABEL, 0, 0, 0);
        ObjectSetInteger(0, profit_label_name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
        ObjectSetInteger(0, profit_label_name, OBJPROP_XDISTANCE, 20);
        ObjectSetInteger(0, profit_label_name, OBJPROP_YDISTANCE, 20);
    }

    string status = daily_target_reached ? " [LOCKED]" : "";
    string label_text = "EA Today: INR" + DoubleToString(total_profit, 2) +
                        " | Realized: INR" + DoubleToString(realized_profit, 2) +
                        " | Float: INR" + DoubleToString(unrealized_profit, 2) + status;

    ObjectSetString(0, profit_label_name, OBJPROP_TEXT, label_text);
    ObjectSetString(0, profit_label_name, OBJPROP_FONT, "Arial Bold");
    ObjectSetInteger(0, profit_label_name, OBJPROP_FONTSIZE, 16);
    ObjectSetInteger(0, profit_label_name, OBJPROP_COLOR,
                     daily_target_reached ? clrGold :
                     (total_profit > 0 ? clrLime : (total_profit < 0 ? clrTomato : clrBlack)));
    ObjectSetInteger(0, profit_label_name, OBJPROP_SELECTABLE, false);
    ObjectSetInteger(0, profit_label_name, OBJPROP_HIDDEN, true);
    ObjectSetInteger(0, profit_label_name, OBJPROP_BACK, false);
    ChartRedraw(0);
}

//+------------------------------------------------------------------+
//| Close all positions and pending orders for one timeframe         |
//+------------------------------------------------------------------+
void CloseTimeframeTrades(int tf_index)
{
    int magic = MagicNumber + tf_index;

    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        if(position_info.SelectByIndex(i))
        {
            if(position_info.Symbol() == _Symbol && position_info.Magic() == magic)
            {
                trade.SetExpertMagicNumber(magic);
                trade.PositionClose(position_info.Ticket());
            }
        }
    }

    for(int i = OrdersTotal() - 1; i >= 0; i--)
    {
        ulong ticket = OrderGetTicket(i);
        if(OrderSelect(ticket))
        {
            if(OrderGetString(ORDER_SYMBOL) == _Symbol && OrderGetInteger(ORDER_MAGIC) == magic)
            {
                trade.SetExpertMagicNumber(magic);
                trade.OrderDelete(ticket);
            }
        }
    }

    ClearTimeframeState(tf_index);
}

//+------------------------------------------------------------------+
//| Check trend and execute trades for specific timeframe            |
//+------------------------------------------------------------------+
void CheckTrendAndTrade(int tf_index)
{
    // Get SuperTrend line price
    double st_line_price = GetSuperTrendLinePrice(tf_index);
    int magic = MagicNumber + tf_index;

    if(previous_trends[tf_index] == -1)
    {
        active_signal_line_prices[tf_index] = st_line_price;
        last_st_line_prices[tf_index] = st_line_price;
        previous_trends[tf_index] = current_trends[tf_index];
        return;
    }
    
    // If trend changed
    if(current_trends[tf_index] != previous_trends[tf_index])
    {
        double remembered_line_price = active_signal_line_prices[tf_index];

        trade.SetExpertMagicNumber(magic);
        CloseTimeframeTrades(tf_index);
        signal_entry_prices[tf_index] = 0.0;
        SaveTimeframeState(tf_index);

        // Re-check profit locks after closing the timeframe trade, because a close on this
        // signal change can push realized P&L over the daily/monthly target in the same tick.
        if(UseDailyProfitTarget)
        {
            CheckDailyProfit();
            if(daily_target_reached)
            {
                previous_trends[tf_index] = current_trends[tf_index];
                return;
            }
        }

        if(UseMonthlyProfitTarget)
        {
            CheckMonthlyProfit();
            if(monthly_target_reached)
            {
                previous_trends[tf_index] = current_trends[tf_index];
                return;
            }
        }

        if(IsDirectionAllowed(current_trends[tf_index]) && remembered_line_price > 0.0)
        {
            signal_entry_prices[tf_index] = remembered_line_price;
            SaveTimeframeState(tf_index);

            if(IsGapWithinImmediateEntryRange(tf_index, current_trends[tf_index], signal_entry_prices[tf_index]))
            {
                if(current_trends[tf_index] == 0 && !IsPositionExists(magic, POSITION_TYPE_BUY))
                {
                    PlaceImmediateSignalOrder(tf_index, current_trends[tf_index]);
                    signal_entry_prices[tf_index] = 0.0;
                    SaveTimeframeState(tf_index);
                }
                else if(current_trends[tf_index] == 1 && !IsPositionExists(magic, POSITION_TYPE_SELL))
                {
                    PlaceImmediateSignalOrder(tf_index, current_trends[tf_index]);
                    signal_entry_prices[tf_index] = 0.0;
                    SaveTimeframeState(tf_index);
                }
            }
        }

        active_signal_line_prices[tf_index] = st_line_price;
        SaveTimeframeState(tf_index);
        previous_trends[tf_index] = current_trends[tf_index];
    }
    else
    {
        if(st_line_price > 0.0)
        {
            active_signal_line_prices[tf_index] = st_line_price;
            SaveTimeframeState(tf_index);
        }

        if(signal_entry_prices[tf_index] > 0.0)
        {
            UpdateRetestPendingOrderState(tf_index, current_trends[tf_index], st_line_price);

            if(IsGapWithinImmediateEntryRange(tf_index, current_trends[tf_index], signal_entry_prices[tf_index]))
            {
                if(current_trends[tf_index] == 0 && !IsPositionExists(magic, POSITION_TYPE_BUY))
                {
                    ulong ticket = 0;
                    double order_price = 0.0;
                    if(GetPendingOrderTicketAndPrice(magic, ORDER_TYPE_BUY_LIMIT, ticket, order_price))
                    {
                        trade.SetExpertMagicNumber(magic);
                        trade.OrderDelete(ticket);
                    }

                    if(PlaceImmediateSignalOrder(tf_index, current_trends[tf_index]))
                    {
                        signal_entry_prices[tf_index] = 0.0;
                        SaveTimeframeState(tf_index);
                    }
                }
                else if(current_trends[tf_index] == 1 && !IsPositionExists(magic, POSITION_TYPE_SELL))
                {
                    ulong ticket = 0;
                    double order_price = 0.0;
                    if(GetPendingOrderTicketAndPrice(magic, ORDER_TYPE_SELL_LIMIT, ticket, order_price))
                    {
                        trade.SetExpertMagicNumber(magic);
                        trade.OrderDelete(ticket);
                    }

                    if(PlaceImmediateSignalOrder(tf_index, current_trends[tf_index]))
                    {
                        signal_entry_prices[tf_index] = 0.0;
                        SaveTimeframeState(tf_index);
                    }
                }
            }
            else if(IsCurrentPriceNearRememberedLine(current_trends[tf_index], signal_entry_prices[tf_index]))
            {
                if(current_trends[tf_index] == 0 && !IsPositionExists(magic, POSITION_TYPE_BUY))
                {
                    ulong ticket = 0;
                    double order_price = 0.0;
                    if(!GetPendingOrderTicketAndPrice(magic, ORDER_TYPE_BUY_LIMIT, ticket, order_price))
                    {
                        if(!PlaceRetestPendingOrder(tf_index, current_trends[tf_index], signal_entry_prices[tf_index]))
                            signal_entry_prices[tf_index] = 0.0;
                        SaveTimeframeState(tf_index);
                    }
                }
                else if(current_trends[tf_index] == 1 && !IsPositionExists(magic, POSITION_TYPE_SELL))
                {
                    ulong ticket = 0;
                    double order_price = 0.0;
                    if(!GetPendingOrderTicketAndPrice(magic, ORDER_TYPE_SELL_LIMIT, ticket, order_price))
                    {
                        if(!PlaceRetestPendingOrder(tf_index, current_trends[tf_index], signal_entry_prices[tf_index]))
                            signal_entry_prices[tf_index] = 0.0;
                        SaveTimeframeState(tf_index);
                    }
                }
            }
        }
    }
    
    last_st_line_prices[tf_index] = st_line_price;
}

//+------------------------------------------------------------------+
//| Update pending orders for specific timeframe                     |
//+------------------------------------------------------------------+
void UpdateOrdersForTimeframe(int tf_index, double buyPrice, double sellPrice)
{
    int magic = MagicNumber + tf_index;
    
    for(int i = 0; i < OrdersTotal(); i++)
    {
        ulong ticket = OrderGetTicket(i);
        if(OrderSelect(ticket))
        {
            if(OrderGetString(ORDER_SYMBOL) == _Symbol && OrderGetInteger(ORDER_MAGIC) == magic)
            {
                ENUM_ORDER_TYPE order_type = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
                double oldPrice = OrderGetDouble(ORDER_PRICE_OPEN);
                
                if(order_type == ORDER_TYPE_BUY_LIMIT)
                {
                    if(MathAbs(oldPrice - buyPrice) > SymbolInfoDouble(_Symbol, SYMBOL_POINT) * 0.5)
                    {
                        trade.SetExpertMagicNumber(magic);
                        ModifyPendingOrder(ticket, buyPrice, 0, 0, ORDER_TIME_GTC, 0, 0.0);
                    }
                }
                else if(order_type == ORDER_TYPE_SELL_LIMIT)
                {
                    if(MathAbs(oldPrice - sellPrice) > SymbolInfoDouble(_Symbol, SYMBOL_POINT) * 0.5)
                    {
                        trade.SetExpertMagicNumber(magic);
                        ModifyPendingOrder(ticket, sellPrice, 0, 0, ORDER_TIME_GTC, 0, 0.0);
                    }
                }
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Get current spread                                               |
//+------------------------------------------------------------------+
double GetSpread()
{
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double spread = ask - bid;
   
   // Convert to points if needed
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double spread_points = spread / point;
   return spread;
}

//+------------------------------------------------------------------+
//| Get SuperTrend line price for timeframe                          |
//+------------------------------------------------------------------+
double GetSuperTrendLinePrice(int tf_index)
{
    double st_line[];
    ArraySetAsSeries(st_line, true);
    int copied = CopyBuffer(supertrend_handles[tf_index], 0, 1, 1, st_line);
    if(copied == 1)
    {
        return st_line[0];
    }
    return 0.0;
}

//+------------------------------------------------------------------+
//| Open sell order for specific timeframe                           |
//+------------------------------------------------------------------+
void OpenSellOrder(int tf_index)
{
    int magic = MagicNumber + tf_index; // Different magic for each timeframe
    trade.SetExpertMagicNumber(magic);
    
    // Get SuperTrend line price and calculate spread
    double st_line_price = GetSuperTrendLinePrice(tf_index);
    double spread = GetSpread() * spreadMultiplier;
    int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
    
    if(takePositionsAtStart)
    {
        // Take immediate market position
        string comment = "SuperTrend Sell " + timeframe_names[tf_index];
        if(trade.Sell(LotSize, _Symbol, 0, 0, 0, comment))
        {
        }
        else
        {
        }
    }
    
    // Always place pending order using OrderManagement logic
    if(st_line_price > 0)
    {
        double price = NormalizeDouble(st_line_price - spread, digits);
        string pending_comment = "SuperTrend Sell Limit " + timeframe_names[tf_index];
        
        PlaceSellLimit(LotSize, price, pending_comment);
    }
}

//+------------------------------------------------------------------+
//| Check profit take for specific timeframe                         |
//+------------------------------------------------------------------+
void CheckProfitTake(int tf_index)
{
    int magic = MagicNumber + tf_index;
    double profit_target = ProfitTakeBase * (tf_index + 1); // M1=15, M2=30, M3=45, etc.
    
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        if(position_info.SelectByIndex(i))
        {
            if(position_info.Symbol() == _Symbol && position_info.Magic() == magic)
            {
                double current_profit = position_info.Profit();
                
                if(current_profit >= profit_target)
                {
                    trade.SetExpertMagicNumber(magic);
                    if(trade.PositionClose(position_info.Ticket()))
                    {
                        // Cancel pending orders for this timeframe since profit target was reached
                        CancelPendingOrdersForTimeframe(tf_index);
                    }
                }
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Cancel pending orders for specific timeframe                     |
//+------------------------------------------------------------------+
void CancelPendingOrdersForTimeframe(int tf_index)
{
    int magic = MagicNumber + tf_index;
    
    for(int i = OrdersTotal() - 1; i >= 0; i--)
    {
        ulong ticket = OrderGetTicket(i);
        if(OrderSelect(ticket))
        {
            if(OrderGetString(ORDER_SYMBOL) == _Symbol && OrderGetInteger(ORDER_MAGIC) == magic)
            {
                trade.SetExpertMagicNumber(magic);
                if(trade.OrderDelete(ticket))
                {
                }
                else
                {
                }
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Close positions for specific timeframe                           |
//+------------------------------------------------------------------+
void ClosePositionsForTimeframe(int tf_index)
{
    int magic = MagicNumber + tf_index;
    
    // Close positions
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        if(position_info.SelectByIndex(i))
        {
            if(position_info.Symbol() == _Symbol && position_info.Magic() == magic)
            {
                trade.SetExpertMagicNumber(magic);
                trade.PositionClose(position_info.Ticket());
            }
        }
    }
    
    // Cancel pending orders for this timeframe (using OrderManagement logic)
    for(int i = OrdersTotal() - 1; i >= 0; i--)
    {
        ulong ticket = OrderGetTicket(i);
        if(OrderSelect(ticket))
        {
            if(OrderGetString(ORDER_SYMBOL) == _Symbol && OrderGetInteger(ORDER_MAGIC) == magic)
            {
                trade.SetExpertMagicNumber(magic);
                trade.OrderDelete(ticket);
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Initialize daily profit tracking                                 |
//+------------------------------------------------------------------+
void InitializeDailyProfit()
{
    MqlDateTime current_time;
    TimeToStruct(TimeCurrent(), current_time);
    
    // Set to start of current day
    current_time.hour = 0;
    current_time.min = 0;
    current_time.sec = 0;
    
    last_profit_check_day = StructToTime(current_time);
    daily_target_reached = false;
}

//+------------------------------------------------------------------+
//| Initialize monthly profit tracking                               |
//+------------------------------------------------------------------+
void InitializeMonthlyProfit()
{
    MqlDateTime current_time;
    TimeToStruct(TimeCurrent(), current_time);
    
    // Set to start of current month
    current_time.day = 1;
    current_time.hour = 0;
    current_time.min = 0;
    current_time.sec = 0;
    
    last_profit_check_month = StructToTime(current_time);
    monthly_start_balance = AccountInfoDouble(ACCOUNT_BALANCE);
    monthly_target_reached = false;
}

//+------------------------------------------------------------------+
//| Check daily profit and manage trading                            |
//+------------------------------------------------------------------+
void CheckDailyProfit()
{
    MqlDateTime current_time;
    TimeToStruct(TimeCurrent(), current_time);
    
    // Set to start of current day
    current_time.hour = 0;
    current_time.min = 0;
    current_time.sec = 0;
    datetime current_day = StructToTime(current_time);
    
    // Check if new day started
    if(current_day > last_profit_check_day)
    {
        // Reset for new day
        last_profit_check_day = current_day;
        daily_target_reached = false;
        ClearAllTimeframeState();
        
        return;
    }
    
    // Skip if target already reached today
    if(daily_target_reached)
        return;
    
    double realized_profit = 0.0;
    double unrealized_profit = 0.0;
    double total_daily_profit = CalculateTodayEAProfit(realized_profit, unrealized_profit);
    
    // Check if target reached (includes realized + unrealized profit from all sources)
    if(total_daily_profit >= DailyProfitTarget)
    {
        daily_target_reached = true;
        
        // Close all positions (from this EA only)
        CloseAllDailyPositions();
        ClearAllTimeframeState();
        
        // Send alert
        Alert("SuperTrend EA - Daily profit target of INR",DoubleToString(DailyProfitTarget,2),
              " reached! Total profit: INR", total_daily_profit, " (Realized: INR", realized_profit, 
              " + Unrealized: INR", unrealized_profit, "). Trading stopped for today.");
        UpdateDailyProfitLabel();
    }
}

//+------------------------------------------------------------------+
//| Check monthly profit and manage trading                          |
//+------------------------------------------------------------------+
void CheckMonthlyProfit()
{
    MqlDateTime current_time;
    TimeToStruct(TimeCurrent(), current_time);
    
    // Set to start of current month
    current_time.day = 1;
    current_time.hour = 0;
    current_time.min = 0;
    current_time.sec = 0;
    datetime current_month = StructToTime(current_time);
    
    // Check if new month started
    if(current_month > last_profit_check_month)
    {
        // Reset for new month
        last_profit_check_month = current_month;
        monthly_start_balance = AccountInfoDouble(ACCOUNT_BALANCE);
        monthly_target_reached = false;
        ClearAllTimeframeState();
        
        return;
    }
    
    // Skip if target already reached this month
    if(monthly_target_reached)
        return;
    
    // Calculate monthly profit based on overall account balance change + open positions P&L
    double current_balance = AccountInfoDouble(ACCOUNT_BALANCE);
    double realized_profit = current_balance - monthly_start_balance;
    
    // Add unrealized profit/loss from all open positions
    double unrealized_profit = 0.0;
    for(int i = 0; i < PositionsTotal(); i++)
    {
        if(position_info.SelectByIndex(i))
        {
            unrealized_profit += position_info.Profit();
        }
    }
    
    double total_monthly_profit = realized_profit + unrealized_profit;
    
    // Check if target reached (includes realized + unrealized profit from all sources)
    if(total_monthly_profit >= MonthlyProfitTarget)
    {
        monthly_target_reached = true;
        
        // Close all positions (from this EA only)
        CloseAllMonthlyPositions();
        
        // Send alert
        Alert("SuperTrend EA - Monthly profit target of INR",DoubleToString(MonthlyProfitTarget,2),
              " reached! Total profit: INR", total_monthly_profit, " (Realized: INR", realized_profit, 
              " + Unrealized: INR", unrealized_profit, "). Trading stopped for the entire month.");
    }
}

//+------------------------------------------------------------------+
//| Close all positions when daily target reached                    |
//+------------------------------------------------------------------+
void CloseAllDailyPositions()
{
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        if(position_info.SelectByIndex(i))
        {
            if(position_info.Symbol() == _Symbol)
            {
                // Check if position belongs to any of our timeframes
                bool is_our_position = false;
                for(int j = 0; j < ArraySize(timeframes); j++)
                {
                    if(position_info.Magic() == MagicNumber + j)
                    {
                        is_our_position = true;
                        break;
                    }
                }
                
                if(is_our_position)
                {
                    trade.SetExpertMagicNumber(position_info.Magic());
                    trade.PositionClose(position_info.Ticket());
                }
            }
        }
    }
    
    // Also cancel all pending orders for the day
    for(int i = OrdersTotal() - 1; i >= 0; i--)
    {
        ulong ticket = OrderGetTicket(i);
        if(OrderSelect(ticket))
        {
            if(OrderGetString(ORDER_SYMBOL) == _Symbol)
            {
                // Check if order belongs to any of our timeframes
                bool is_our_order = false;
                for(int j = 0; j < ArraySize(timeframes); j++)
                {
                    if(OrderGetInteger(ORDER_MAGIC) == MagicNumber + j)
                    {
                        is_our_order = true;
                        break;
                    }
                }
                
                if(is_our_order)
                {
                    trade.SetExpertMagicNumber(OrderGetInteger(ORDER_MAGIC));
                    trade.OrderDelete(ticket);
                }
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Close all positions when monthly target reached                  |
//+------------------------------------------------------------------+
void CloseAllMonthlyPositions()
{
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        if(position_info.SelectByIndex(i))
        {
            if(position_info.Symbol() == _Symbol)
            {
                // Check if position belongs to any of our timeframes
                bool is_our_position = false;
                for(int j = 0; j < ArraySize(timeframes); j++)
                {
                    if(position_info.Magic() == MagicNumber + j)
                    {
                        is_our_position = true;
                        break;
                    }
                }
                
                if(is_our_position)
                {
                    trade.SetExpertMagicNumber(position_info.Magic());
                    trade.PositionClose(position_info.Ticket());
                }
            }
        }
    }
    
    // Also cancel all pending orders for the month
    for(int i = OrdersTotal() - 1; i >= 0; i--)
    {
        ulong ticket = OrderGetTicket(i);
        if(OrderSelect(ticket))
        {
            if(OrderGetString(ORDER_SYMBOL) == _Symbol)
            {
                // Check if order belongs to any of our timeframes
                bool is_our_order = false;
                for(int j = 0; j < ArraySize(timeframes); j++)
                {
                    if(OrderGetInteger(ORDER_MAGIC) == MagicNumber + j)
                    {
                        is_our_order = true;
                        break;
                    }
                }
                
                if(is_our_order)
                {
                    trade.SetExpertMagicNumber(OrderGetInteger(ORDER_MAGIC));
                    trade.OrderDelete(ticket);
                }
            }
        }
    }
}
//+------------------------------------------------------------------+
