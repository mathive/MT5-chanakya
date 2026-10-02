//+------------------------------------------------------------------+
//|                                                    GoldGrid.mq5  |
//|        SuperTrend signal + SimpleGrid-style pending order grid   |
//+------------------------------------------------------------------+
#property copyright "OpenAI"
#property link      "https://www.mql5.com"
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>

enum ENUM_TRADE_DIRECTION
{
   TRADE_BOTH = 0,
   TRADE_BUY_ONLY = 1,
   TRADE_SELL_ONLY = 2
};

input group "Signal Settings"
input double   ATRMultiplier = 9.0;                 // SuperTrend ATR multiplier
input int      ATRPeriod = 27;                      // SuperTrend ATR period
input ENUM_TRADE_DIRECTION TradeDirection = TRADE_BOTH;

input group "Grid Settings"
input double   LotSize = 0.01;                      // Market and pending lot size
input int      GridGapPoints = 100;                 // Gap between pending orders in points
input int      MaxGridOrders = 10;                  // Maximum pending orders per timeframe
input bool     UpdateGridOnSTMove = true;           // Rebuild pending orders when ST line moves

input group "Profit Settings"
input bool     UseBaseProfitTake = true;            // Close the main signal order at target profit
input double   BaseProfitTarget = 15.0;             // Base signal profit target in account currency
input bool     UseGridOrderTP = true;               // Apply TP to each grid order
input int      GridTPPoints = 100;                  // Grid TP in points from each order price
input bool     UseGridMaxLoss = true;               // Cut grid basket at max loss
input double   GridMaxLoss = 2000.0;                // Grid max loss in account currency

input group "Daily Target"
input bool     UseDailyProfitTarget = false;        // Stop trading for the day after target
input double   DailyProfitTarget = 1000.0;          // Daily target in account currency

input group "Session Close"
input bool     CloseBeforeMarketClose = true;       // Close EA trades before market close
input int      MinutesBeforeMarketClose = 15;       // Minutes before session close
input int      NoGridMinutesAfterMarketOpen = 30;   // Delay grid orders after session open

input group "System"
input int      MagicNumber = 220400;                // Base magic number
input int      SlippagePoints = 3;                  // Allowed slippage in points

input group "Timeframes"
input bool     Trade_M1 = false;
input bool     Trade_M2 = true;
input bool     Trade_M3 = true;
input bool     Trade_M5 = true;
input bool     Trade_M10 = true;
input bool     Trade_M15 = true;
input bool     Trade_M30 = true;
input bool     Trade_H1 = true;

CTrade        trade;
CPositionInfo position_info;

ENUM_TIMEFRAMES g_timeframes[];
int             g_supertrend_handles[];
datetime        g_last_closed_bar_times[];
int             g_current_trends[];
int             g_previous_trends[];
double          g_last_st_prices[];
double          g_previous_st_prices[];
string          g_timeframe_names[];
double          g_active_signal_line_prices[];
double          g_signal_entry_prices[];
double          g_signal_anchor_prices[];
double          g_grid_boundary_prices[];
bool            g_grid_initialized[];
datetime        g_daily_target_day = 0;
bool            g_daily_target_reached = false;
string          g_status_label_name = "GoldGrid_Status_Label";
datetime        g_last_session_close_day = 0;
bool            g_is_testing = false;
datetime        g_last_profit_refresh_time = 0;
datetime        g_cached_history_day = 0;
int             g_cached_history_deals_total = -1;
double          g_cached_realized_profit = 0.0;
double          g_cached_unrealized_profit = 0.0;
double          g_cached_total_profit = 0.0;
double          g_cached_base_profit[];
double          g_cached_grid_profit[];
bool            g_has_base_positions[];
bool            g_has_grid_positions[];

string GetStateKey(const int tf_index, const string suffix)
{
   return "GoldGrid." + _Symbol + "." + IntegerToString(MagicNumber) + "." + g_timeframe_names[tf_index] + "." + suffix;
}

void SaveTimeframeState(const int tf_index)
{
   GlobalVariableSet(GetStateKey(tf_index, "active_line"), g_active_signal_line_prices[tf_index]);
   GlobalVariableSet(GetStateKey(tf_index, "entry_price"), g_signal_entry_prices[tf_index]);
}

void LoadTimeframeState(const int tf_index)
{
   string active_key = GetStateKey(tf_index, "active_line");
   string entry_key = GetStateKey(tf_index, "entry_price");

   if(GlobalVariableCheck(active_key))
      g_active_signal_line_prices[tf_index] = GlobalVariableGet(active_key);

   if(GlobalVariableCheck(entry_key))
      g_signal_entry_prices[tf_index] = GlobalVariableGet(entry_key);
}

void ClearTimeframeState(const int tf_index)
{
   g_active_signal_line_prices[tf_index] = 0.0;
   g_signal_entry_prices[tf_index] = 0.0;
   GlobalVariableDel(GetStateKey(tf_index, "active_line"));
   GlobalVariableDel(GetStateKey(tf_index, "entry_price"));
}

void ClearAllTimeframeState()
{
   for(int i = 0; i < ArraySize(g_timeframes); i++)
      ClearTimeframeState(i);
}

string BaseCommentPrefix()
{
   return "GoldGrid Base ";
}

string GridCommentPrefix()
{
   return "GoldGrid Grid ";
}

int GetTimeframeMultiplier(const int tf_index)
{
   return tf_index + 1;
}

double GetScaledGapPrice(const int tf_index)
{
   return GridGapPoints * GetTimeframeMultiplier(tf_index) * _Point;
}

double GetScaledBaseProfitTarget(const int tf_index)
{
   return BaseProfitTarget * GetTimeframeMultiplier(tf_index);
}

double GetScaledGridTPPriceDistance(const int tf_index)
{
   return GridTPPoints * GetTimeframeMultiplier(tf_index) * _Point;
}

int TimeframeMagic(const int tf_index)
{
   return MagicNumber + tf_index;
}

bool IsOurMagicNumber(const long magic)
{
   for(int i = 0; i < ArraySize(g_timeframes); i++)
   {
      if(magic == TimeframeMagic(i))
         return true;
   }

   return false;
}

int TimeframeIndexFromMagic(const long magic)
{
   int tf_index = (int)(magic - MagicNumber);
   if(tf_index < 0 || tf_index >= ArraySize(g_timeframes))
      return -1;

   if(TimeframeMagic(tf_index) != magic)
      return -1;

   return tf_index;
}

int CountTimeframePositions(const int tf_index)
{
   int magic = TimeframeMagic(tf_index);
   int count = 0;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;

      if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
         PositionGetInteger(POSITION_MAGIC) == magic)
      {
         count++;
      }
   }

   return count;
}

int CountTimeframeOrders(const int tf_index)
{
   int magic = TimeframeMagic(tf_index);
   int count = 0;

   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0 || !OrderSelect(ticket))
         continue;

      if(OrderGetString(ORDER_SYMBOL) == _Symbol &&
         OrderGetInteger(ORDER_MAGIC) == magic)
      {
         count++;
      }
   }

   return count;
}

bool IsDirectionAllowed(const int trend_direction)
{
   if(trend_direction == 0)
      return (TradeDirection != TRADE_SELL_ONLY);
   if(trend_direction == 1)
      return (TradeDirection != TRADE_BUY_ONLY);

   return false;
}

double GetMinDistancePrice()
{
   int stops_level = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   int freeze_level = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL);
   return MathMax(stops_level, freeze_level) * _Point;
}

bool IsOurPosition(const int magic)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;

      if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
         PositionGetInteger(POSITION_MAGIC) == magic)
      {
         return true;
      }
   }

   return false;
}

bool GetPositionPrice(const int magic, const ENUM_POSITION_TYPE type, double &price)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;

      if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
         PositionGetInteger(POSITION_MAGIC) == magic &&
         PositionGetInteger(POSITION_TYPE) == type)
      {
         price = PositionGetDouble(POSITION_PRICE_OPEN);
         return true;
      }
   }

   return false;
}

bool GetBasePositionPrice(const int tf_index, const int trend_direction, double &price)
{
   int magic = TimeframeMagic(tf_index);
   ENUM_POSITION_TYPE type = (trend_direction == 0) ? POSITION_TYPE_BUY : POSITION_TYPE_SELL;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;

      if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
         PositionGetInteger(POSITION_MAGIC) == magic &&
         PositionGetInteger(POSITION_TYPE) == type &&
         PositionCommentStartsWith(BaseCommentPrefix()))
      {
         price = PositionGetDouble(POSITION_PRICE_OPEN);
         return true;
      }
   }

   return false;
}

bool PositionCommentStartsWith(const string prefix)
{
   string comment = PositionGetString(POSITION_COMMENT);
   return (StringSubstr(comment, 0, StringLen(prefix)) == prefix);
}

bool OrderCommentStartsWith(const string prefix)
{
   string comment = OrderGetString(ORDER_COMMENT);
   return (StringSubstr(comment, 0, StringLen(prefix)) == prefix);
}

int ExtractGridLevel(const string comment)
{
   int marker_pos = StringFind(comment, "#");
   if(marker_pos < 0)
      return -1;

   string level_text = StringSubstr(comment, marker_pos + 1);
   return (int)StringToInteger(level_text);
}

double GetGridTPPrice(const int tf_index, const int trend_direction, const double order_price)
{
   if(!UseGridOrderTP || GridTPPoints <= 0)
      return 0.0;

   double tp_distance = GetScaledGridTPPriceDistance(tf_index);
   if(trend_direction == 0)
      return NormalizeDouble(order_price + tp_distance, _Digits);
   if(trend_direction == 1)
      return NormalizeDouble(order_price - tp_distance, _Digits);

   return 0.0;
}

void DeletePendingOrdersForTimeframe(const int tf_index)
{
   int magic = TimeframeMagic(tf_index);
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0 || !OrderSelect(ticket))
         continue;

      if(OrderGetString(ORDER_SYMBOL) == _Symbol &&
         OrderGetInteger(ORDER_MAGIC) == magic)
      {
         trade.SetExpertMagicNumber(magic);
         trade.OrderDelete(ticket);
      }
   }
}

void DeleteGridPendingOrdersForTimeframe(const int tf_index)
{
   int magic = TimeframeMagic(tf_index);
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0 || !OrderSelect(ticket))
         continue;

      if(OrderGetString(ORDER_SYMBOL) == _Symbol &&
         OrderGetInteger(ORDER_MAGIC) == magic &&
         OrderCommentStartsWith(GridCommentPrefix()))
      {
         trade.SetExpertMagicNumber(magic);
         trade.OrderDelete(ticket);
      }
   }
}

void ClosePositionsForTimeframe(const int tf_index)
{
   int magic = TimeframeMagic(tf_index);
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;

      if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
         PositionGetInteger(POSITION_MAGIC) == magic)
      {
         trade.SetExpertMagicNumber(magic);
         trade.PositionClose(ticket);
      }
   }
}

void CloseBasePositionsForTimeframe(const int tf_index)
{
   int magic = TimeframeMagic(tf_index);
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;

      if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
         PositionGetInteger(POSITION_MAGIC) == magic &&
         PositionCommentStartsWith(BaseCommentPrefix()))
      {
         trade.SetExpertMagicNumber(magic);
         trade.PositionClose(ticket);
      }
   }
}

void CloseGridPositionsForTimeframe(const int tf_index)
{
   int magic = TimeframeMagic(tf_index);
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;

      if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
         PositionGetInteger(POSITION_MAGIC) == magic &&
         PositionCommentStartsWith(GridCommentPrefix()))
      {
         trade.SetExpertMagicNumber(magic);
         trade.PositionClose(ticket);
      }
   }
}

void CloseAllTradesForTimeframe(const int tf_index)
{
   DeletePendingOrdersForTimeframe(tf_index);
   ClosePositionsForTimeframe(tf_index);
   ClearTimeframeState(tf_index);
}

void CloseAllEATraitsAndOrders()
{
   for(int i = 0; i < ArraySize(g_timeframes); i++)
   {
      CloseAllTradesForTimeframe(i);
      g_signal_anchor_prices[i] = 0.0;
      g_grid_boundary_prices[i] = 0.0;
      g_grid_initialized[i] = false;
   }
}

void InitializeDailyTarget()
{
   MqlDateTime current_time;
   TimeToStruct(TimeCurrent(), current_time);
   current_time.hour = 0;
   current_time.min = 0;
   current_time.sec = 0;
   g_daily_target_day = StructToTime(current_time);
   g_daily_target_reached = false;
   g_cached_history_day = g_daily_target_day;
   g_cached_history_deals_total = -1;
   g_cached_realized_profit = 0.0;
   g_cached_unrealized_profit = 0.0;
   g_cached_total_profit = 0.0;
   g_last_profit_refresh_time = 0;
}

void RefreshProfitCaches(const bool force = false)
{
   datetime now_time = TimeCurrent();
   if(!force && g_last_profit_refresh_time == now_time)
      return;

   g_last_profit_refresh_time = now_time;

   if(ArraySize(g_cached_base_profit) != ArraySize(g_timeframes))
   {
      ArrayResize(g_cached_base_profit, ArraySize(g_timeframes));
      ArrayResize(g_cached_grid_profit, ArraySize(g_timeframes));
      ArrayResize(g_has_base_positions, ArraySize(g_timeframes));
      ArrayResize(g_has_grid_positions, ArraySize(g_timeframes));
   }

   if(g_cached_history_day != g_daily_target_day)
   {
      g_cached_history_day = g_daily_target_day;
      g_cached_history_deals_total = -1;
      g_cached_realized_profit = 0.0;
   }

   if(HistorySelect(g_daily_target_day, TimeCurrent()))
   {
      int total_deals = HistoryDealsTotal();
      if(total_deals != g_cached_history_deals_total)
      {
         double realized_profit = 0.0;
         for(int i = 0; i < total_deals; i++)
         {
            ulong ticket = HistoryDealGetTicket(i);
            if(ticket == 0)
               continue;

            if(HistoryDealGetString(ticket, DEAL_SYMBOL) != _Symbol)
               continue;

            long magic = HistoryDealGetInteger(ticket, DEAL_MAGIC);
            if(!IsOurMagicNumber(magic))
               continue;

            realized_profit += HistoryDealGetDouble(ticket, DEAL_PROFIT) +
                               HistoryDealGetDouble(ticket, DEAL_SWAP) +
                               HistoryDealGetDouble(ticket, DEAL_COMMISSION);
         }

         g_cached_realized_profit = realized_profit;
         g_cached_history_deals_total = total_deals;
      }
   }

   ArrayInitialize(g_cached_base_profit, 0.0);
   ArrayInitialize(g_cached_grid_profit, 0.0);
   for(int i = 0; i < ArraySize(g_timeframes); i++)
   {
      g_has_base_positions[i] = false;
      g_has_grid_positions[i] = false;
   }

   g_cached_unrealized_profit = 0.0;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;

      if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
         IsOurMagicNumber(PositionGetInteger(POSITION_MAGIC)))
      {
         double position_profit = PositionGetDouble(POSITION_PROFIT) +
                                  PositionGetDouble(POSITION_SWAP);
         g_cached_unrealized_profit += position_profit;

         int tf_index = TimeframeIndexFromMagic(PositionGetInteger(POSITION_MAGIC));
         if(tf_index < 0)
            continue;

         if(PositionCommentStartsWith(BaseCommentPrefix()))
         {
            g_cached_base_profit[tf_index] += position_profit;
            g_has_base_positions[tf_index] = true;
         }
         else if(PositionCommentStartsWith(GridCommentPrefix()))
         {
            g_cached_grid_profit[tf_index] += position_profit;
            g_has_grid_positions[tf_index] = true;
         }
      }
   }

   g_cached_total_profit = g_cached_realized_profit + g_cached_unrealized_profit;
}

double CalculateTodayEAProfit()
{
   RefreshProfitCaches();
   return g_cached_total_profit;
}

bool CheckDailyTargetLock()
{
   if(!UseDailyProfitTarget || DailyProfitTarget <= 0.0)
      return false;

   MqlDateTime current_time;
   TimeToStruct(TimeCurrent(), current_time);
   current_time.hour = 0;
   current_time.min = 0;
   current_time.sec = 0;
   datetime current_day = StructToTime(current_time);

   if(current_day > g_daily_target_day)
   {
      g_daily_target_day = current_day;
      g_daily_target_reached = false;
      g_last_profit_refresh_time = 0;
      ClearAllTimeframeState();
      RefreshProfitCaches(true);
   }

   if(g_daily_target_reached)
      return true;

   double total_profit = CalculateTodayEAProfit();
   if(total_profit >= DailyProfitTarget)
   {
      g_daily_target_reached = true;
      CloseAllEATraitsAndOrders();
      Alert("GoldGrid daily target reached: $", DoubleToString(total_profit, 2),
            ". Trading stopped for the rest of the day.");
      return true;
   }

   return false;
}

bool IsSessionCloseWindow(datetime &close_day_key)
{
   if(!CloseBeforeMarketClose || MinutesBeforeMarketClose < 0)
      return false;

   MqlDateTime now_struct;
   TimeToStruct(TimeTradeServer(), now_struct);
   int current_day_of_week = now_struct.day_of_week;

   datetime session_from = 0;
   datetime session_to = 0;
   bool found_session = false;

   for(uint session_index = 0; ; session_index++)
   {
      datetime from_time = 0;
      datetime to_time = 0;
      if(!SymbolInfoSessionTrade(_Symbol, (ENUM_DAY_OF_WEEK)current_day_of_week, session_index, from_time, to_time))
         break;

      MqlDateTime from_struct, to_struct;
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

      session_from = StructToTime(session_open);
      session_to = StructToTime(session_close);
      if(session_to <= session_from)
         session_to += 24 * 60 * 60;

      datetime now_time = TimeTradeServer();
      if(now_time >= session_from && now_time <= session_to)
      {
         found_session = true;
         break;
      }
   }

   if(!found_session)
   {
      close_day_key = 0;
      return false;
   }

   datetime now_time = TimeTradeServer();
   datetime close_trigger_time = session_to - (MinutesBeforeMarketClose * 60);

   if(now_time >= close_trigger_time)
   {
      MqlDateTime close_struct;
      TimeToStruct(session_to, close_struct);
      close_struct.hour = 0;
      close_struct.min = 0;
      close_struct.sec = 0;
      close_day_key = StructToTime(close_struct);
      return true;
   }

   close_day_key = 0;
   return false;
}

bool CheckSessionCloseWindow()
{
   datetime close_day_key = 0;
   if(!IsSessionCloseWindow(close_day_key))
      return false;

   if(g_last_session_close_day != close_day_key)
   {
      g_last_session_close_day = close_day_key;
      CloseAllEATraitsAndOrders();
   }

   return true;
}

bool IsWithinSessionOpenCooldown()
{
   if(NoGridMinutesAfterMarketOpen <= 0)
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
         datetime cooldown_end = session_from + (NoGridMinutesAfterMarketOpen * 60);
         return (now_time < cooldown_end);
      }
   }

   return false;
}

void UpdateChartStatusLabel()
{
   double total_profit = CalculateTodayEAProfit();
   string remaining_text = "N/A";

   if(UseDailyProfitTarget && DailyProfitTarget > 0.0)
   {
      double remaining = DailyProfitTarget - total_profit;
      if(remaining < 0.0)
         remaining = 0.0;
      remaining_text = "$" + DoubleToString(remaining, 2);
   }

   if(ObjectFind(0, g_status_label_name) < 0)
   {
      ObjectCreate(0, g_status_label_name, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, g_status_label_name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, g_status_label_name, OBJPROP_XDISTANCE, 12);
      ObjectSetInteger(0, g_status_label_name, OBJPROP_YDISTANCE, 18);
      ObjectSetInteger(0, g_status_label_name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, g_status_label_name, OBJPROP_HIDDEN, true);
   }

   string status = "";
   if(g_daily_target_reached)
      status = " | DAILY LOCKED";
   else
   {
      datetime close_day_key = 0;
      if(IsSessionCloseWindow(close_day_key))
         status = " | SESSION CLOSE";
   }

   string label_text = "GoldGrid PnL: $" + DoubleToString(total_profit, 2) +
                       " | Remaining: " + remaining_text + status;

   color text_color = clrBlack;
   if(g_daily_target_reached)
      text_color = clrGold;
   else if(total_profit > 0.0)
      text_color = clrLime;
   else if(total_profit < 0.0)
      text_color = clrTomato;

   ObjectSetString(0, g_status_label_name, OBJPROP_TEXT, label_text);
   ObjectSetString(0, g_status_label_name, OBJPROP_FONT, "Arial Bold");
   ObjectSetInteger(0, g_status_label_name, OBJPROP_FONTSIZE, 14);
   ObjectSetInteger(0, g_status_label_name, OBJPROP_COLOR, text_color);
   ChartRedraw(0);
}

bool CheckBaseProfitTake(const int tf_index)
{
   if(!UseBaseProfitTake || BaseProfitTarget <= 0.0)
      return false;

   RefreshProfitCaches();

   if(g_has_base_positions[tf_index] && g_cached_base_profit[tf_index] >= GetScaledBaseProfitTarget(tf_index))
   {
      DeletePendingOrdersForTimeframe(tf_index);
      CloseBasePositionsForTimeframe(tf_index);
      ClearTimeframeState(tf_index);
      g_signal_anchor_prices[tf_index] = 0.0;
      g_grid_boundary_prices[tf_index] = 0.0;
      g_grid_initialized[tf_index] = false;
      return true;
   }

   return false;
}

bool CheckGridMaxLoss(const int tf_index)
{
   if(!UseGridMaxLoss || GridMaxLoss <= 0.0)
      return false;

   RefreshProfitCaches();

   if(g_has_grid_positions[tf_index] && g_cached_grid_profit[tf_index] <= (-GridMaxLoss))
   {
      DeleteGridPendingOrdersForTimeframe(tf_index);
      CloseGridPositionsForTimeframe(tf_index);
      g_grid_initialized[tf_index] = false;
      return true;
   }

   return false;
}

bool SetupTimeframes()
{
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
      return false;

   ArrayResize(g_timeframes, count);
   ArrayResize(g_supertrend_handles, count);
   ArrayResize(g_last_closed_bar_times, count);
   ArrayResize(g_current_trends, count);
   ArrayResize(g_previous_trends, count);
   ArrayResize(g_last_st_prices, count);
   ArrayResize(g_previous_st_prices, count);
   ArrayResize(g_timeframe_names, count);
   ArrayResize(g_active_signal_line_prices, count);
   ArrayResize(g_signal_entry_prices, count);
   ArrayResize(g_signal_anchor_prices, count);
   ArrayResize(g_grid_boundary_prices, count);
   ArrayResize(g_grid_initialized, count);

   int index = 0;
   if(Trade_M1)  { g_timeframes[index] = PERIOD_M1;  g_timeframe_names[index] = "M1";  index++; }
   if(Trade_M2)  { g_timeframes[index] = PERIOD_M2;  g_timeframe_names[index] = "M2";  index++; }
   if(Trade_M3)  { g_timeframes[index] = PERIOD_M3;  g_timeframe_names[index] = "M3";  index++; }
   if(Trade_M5)  { g_timeframes[index] = PERIOD_M5;  g_timeframe_names[index] = "M5";  index++; }
   if(Trade_M10) { g_timeframes[index] = PERIOD_M10; g_timeframe_names[index] = "M10"; index++; }
   if(Trade_M15) { g_timeframes[index] = PERIOD_M15; g_timeframe_names[index] = "M15"; index++; }
   if(Trade_M30) { g_timeframes[index] = PERIOD_M30; g_timeframe_names[index] = "M30"; index++; }
   if(Trade_H1)  { g_timeframes[index] = PERIOD_H1;  g_timeframe_names[index] = "H1";  index++; }

   for(int i = 0; i < count; i++)
   {
      g_supertrend_handles[i] = iCustom(_Symbol, g_timeframes[i], "Supertrend",
                                        "SPRTRND", ATRMultiplier, ATRPeriod, 10000, 0,
                                        false, false, false, false, 1);

      if(g_supertrend_handles[i] == INVALID_HANDLE)
         return false;

      g_last_closed_bar_times[i] = 0;
      g_current_trends[i] = -1;
      g_previous_trends[i] = -1;
      g_last_st_prices[i] = 0.0;
      g_previous_st_prices[i] = 0.0;
      g_active_signal_line_prices[i] = 0.0;
      g_signal_entry_prices[i] = 0.0;
      g_signal_anchor_prices[i] = 0.0;
      g_grid_boundary_prices[i] = 0.0;
      g_grid_initialized[i] = false;
   }

   return true;
}

bool IsNewClosedBar(const int tf_index)
{
   datetime closed_bar_time[1];
   if(CopyTime(_Symbol, g_timeframes[tf_index], 1, 1, closed_bar_time) < 1)
      return false;

   if(closed_bar_time[0] != g_last_closed_bar_times[tf_index])
   {
      g_last_closed_bar_times[tf_index] = closed_bar_time[0];
      return true;
   }

   return false;
}

bool UpdateSignalState(const int tf_index)
{
   double direction_buffer[];
   double st_buffer[];
   ArraySetAsSeries(direction_buffer, true);
   ArraySetAsSeries(st_buffer, true);

   if(CopyBuffer(g_supertrend_handles[tf_index], 2, 0, 3, direction_buffer) < 3)
      return false;
   if(CopyBuffer(g_supertrend_handles[tf_index], 0, 0, 2, st_buffer) < 2)
      return false;

   g_current_trends[tf_index] = (int)direction_buffer[1];
   g_last_st_prices[tf_index] = st_buffer[1];
   return true;
}

bool PlaceBaseRetestOrder(const int tf_index, const int trend_direction, const double entry_price)
{
   int magic = TimeframeMagic(tf_index);
   trade.SetExpertMagicNumber(magic);
   trade.SetDeviationInPoints(SlippagePoints);
   double min_distance = GetMinDistancePrice();
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double normalized_entry = NormalizeDouble(entry_price, _Digits);

   string comment = BaseCommentPrefix() + (trend_direction == 0 ? "Buy " : "Sell ") + g_timeframe_names[tf_index];

   bool result = false;
   if(trend_direction == 0)
   {
      if(normalized_entry < ask - min_distance)
         result = trade.BuyLimit(LotSize, normalized_entry, _Symbol, 0, 0, ORDER_TIME_GTC, 0, comment);
      else if(normalized_entry > ask + min_distance)
         result = trade.BuyStop(LotSize, normalized_entry, _Symbol, 0, 0, ORDER_TIME_GTC, 0, comment);
   }
   else if(trend_direction == 1)
   {
      if(normalized_entry > bid + min_distance)
         result = trade.SellLimit(LotSize, normalized_entry, _Symbol, 0, 0, ORDER_TIME_GTC, 0, comment);
      else if(normalized_entry < bid - min_distance)
         result = trade.SellStop(LotSize, normalized_entry, _Symbol, 0, 0, ORDER_TIME_GTC, 0, comment);
   }

   if(!result)
   {
      Print("GoldGrid base retest order failed for ", g_timeframe_names[tf_index],
            " direction=", trend_direction,
            " retcode=", trade.ResultRetcode(),
            " message=", trade.ResultRetcodeDescription());
      return false;
   }

   return true;
}

void PlaceGridPendingOrders(const int tf_index, const int trend_direction, const double boundary_price, const double anchor_price)
{
   if(MaxGridOrders <= 0 || GridGapPoints <= 0 || boundary_price <= 0.0 || anchor_price <= 0.0)
      return;

   if(IsWithinSessionOpenCooldown())
      return;

   int magic = TimeframeMagic(tf_index);
   trade.SetExpertMagicNumber(magic);
   double min_distance = GetMinDistancePrice();
   double gap_price = GetScaledGapPrice(tf_index);
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);

   DeleteGridPendingOrdersForTimeframe(tf_index);
   g_grid_initialized[tf_index] = true;

   for(int level = 1; level <= MaxGridOrders; level++)
   {
      double order_price = 0.0;
      double tp_price = 0.0;

      if(trend_direction == 0)
      {
         order_price = NormalizeDouble(anchor_price - (gap_price * level), digits);
         if(order_price <= boundary_price)
            break;
         if(order_price >= SymbolInfoDouble(_Symbol, SYMBOL_ASK) - min_distance)
            continue;

         tp_price = GetGridTPPrice(tf_index, trend_direction, order_price);
         string comment = GridCommentPrefix() + "Buy " + g_timeframe_names[tf_index] + " #" + IntegerToString(level);
         trade.BuyLimit(LotSize, order_price, _Symbol, 0, tp_price, ORDER_TIME_GTC, 0, comment);
      }
      else if(trend_direction == 1)
      {
         order_price = NormalizeDouble(anchor_price + (gap_price * level), digits);
         if(order_price >= boundary_price)
            break;
         if(order_price <= SymbolInfoDouble(_Symbol, SYMBOL_BID) + min_distance)
            continue;

         tp_price = GetGridTPPrice(tf_index, trend_direction, order_price);
         string comment = GridCommentPrefix() + "Sell " + g_timeframe_names[tf_index] + " #" + IntegerToString(level);
         trade.SellLimit(LotSize, order_price, _Symbol, 0, tp_price, ORDER_TIME_GTC, 0, comment);
      }
   }
}

void UpdateGridPendingOrders(const int tf_index, const int trend_direction, const double boundary_price)
{
   int magic = TimeframeMagic(tf_index);
   double min_distance = GetMinDistancePrice();
   double anchor_price = g_signal_anchor_prices[tf_index];
   double gap_price = GetScaledGapPrice(tf_index);
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);

   if(anchor_price <= 0.0)
      return;

   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0 || !OrderSelect(ticket))
         continue;

      if(OrderGetString(ORDER_SYMBOL) != _Symbol ||
         OrderGetInteger(ORDER_MAGIC) != magic ||
         !OrderCommentStartsWith(GridCommentPrefix()))
      {
         continue;
      }

      int level = ExtractGridLevel(OrderGetString(ORDER_COMMENT));
      if(level < 1)
         continue;

      double new_price = 0.0;
      if(trend_direction == 0)
      {
         new_price = NormalizeDouble(anchor_price - (gap_price * level), digits);
         if(new_price <= boundary_price || new_price >= SymbolInfoDouble(_Symbol, SYMBOL_ASK) - min_distance)
         {
            trade.SetExpertMagicNumber(magic);
            trade.OrderDelete(ticket);
            continue;
         }
      }
      else if(trend_direction == 1)
      {
         new_price = NormalizeDouble(anchor_price + (gap_price * level), digits);
         if(new_price >= boundary_price || new_price <= SymbolInfoDouble(_Symbol, SYMBOL_BID) + min_distance)
         {
            trade.SetExpertMagicNumber(magic);
            trade.OrderDelete(ticket);
            continue;
         }
      }
      else
      {
         trade.SetExpertMagicNumber(magic);
         trade.OrderDelete(ticket);
         continue;
      }

      double new_tp = GetGridTPPrice(tf_index, trend_direction, new_price);
      double old_price = OrderGetDouble(ORDER_PRICE_OPEN);
      double old_tp = OrderGetDouble(ORDER_TP);

      if(MathAbs(old_price - new_price) > (_Point * 0.5) || MathAbs(old_tp - new_tp) > (_Point * 0.5))
      {
         trade.SetExpertMagicNumber(magic);
         trade.OrderModify(ticket,
                           new_price,
                           0,
                           new_tp,
                           (ENUM_ORDER_TYPE_TIME)OrderGetInteger(ORDER_TYPE_TIME),
                           (datetime)OrderGetInteger(ORDER_TIME_EXPIRATION),
                           0.0);
      }
   }
}

void UpdateBasePendingOrder(const int tf_index, const int trend_direction, const double st_price)
{
   int magic = TimeframeMagic(tf_index);

   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0 || !OrderSelect(ticket))
         continue;

      if(OrderGetString(ORDER_SYMBOL) != _Symbol ||
         OrderGetInteger(ORDER_MAGIC) != magic ||
         !OrderCommentStartsWith(BaseCommentPrefix()))
      {
         continue;
      }

      double order_price = OrderGetDouble(ORDER_PRICE_OPEN);
      bool should_delete = false;

      if(trend_direction == 0)
         should_delete = (st_price >= order_price - (_Point * 0.5));
      else if(trend_direction == 1)
         should_delete = (st_price <= order_price + (_Point * 0.5));
      else
         should_delete = true;

      if(should_delete)
      {
         trade.SetExpertMagicNumber(magic);
         trade.OrderDelete(ticket);
         g_signal_entry_prices[tf_index] = 0.0;
         g_signal_anchor_prices[tf_index] = 0.0;
         g_grid_boundary_prices[tf_index] = 0.0;
         SaveTimeframeState(tf_index);
      }
   }
}

void RebuildGridForTimeframe(const int tf_index, const int trend_direction, const double st_price)
{
   g_grid_boundary_prices[tf_index] = st_price;
   UpdateGridPendingOrders(tf_index, trend_direction, g_grid_boundary_prices[tf_index]);
}

void ProcessTimeframe(const int tf_index)
{
   int trend_direction = g_current_trends[tf_index];
   double st_price = g_last_st_prices[tf_index];

   if(g_previous_trends[tf_index] == -1)
   {
      g_active_signal_line_prices[tf_index] = st_price;
      SaveTimeframeState(tf_index);
      g_previous_trends[tf_index] = trend_direction;
      return;
   }

   if(trend_direction != g_previous_trends[tf_index])
   {
      double remembered_previous_signal_line = g_active_signal_line_prices[tf_index];

      CloseAllTradesForTimeframe(tf_index);
      g_signal_anchor_prices[tf_index] = 0.0;
      g_grid_boundary_prices[tf_index] = 0.0;
      g_grid_initialized[tf_index] = false;

      if(CountTimeframePositions(tf_index) > 0 || CountTimeframeOrders(tf_index) > 0)
      {
         Print("GoldGrid deferred reversal for ", g_timeframe_names[tf_index],
               " because previous trades/orders are still active after close request.");
         return;
      }

      if(IsDirectionAllowed(trend_direction))
      {
         double entry_price = remembered_previous_signal_line;
         if(entry_price <= 0.0)
            entry_price = g_previous_st_prices[tf_index];

         if(entry_price > 0.0 && PlaceBaseRetestOrder(tf_index, trend_direction, entry_price))
         {
            g_signal_entry_prices[tf_index] = entry_price;
            g_grid_boundary_prices[tf_index] = st_price;
            SaveTimeframeState(tf_index);
         }
      }
      else
      {
         ClearTimeframeState(tf_index);
         g_signal_anchor_prices[tf_index] = 0.0;
         g_grid_boundary_prices[tf_index] = 0.0;
         g_grid_initialized[tf_index] = false;
      }

      g_active_signal_line_prices[tf_index] = st_price;
      SaveTimeframeState(tf_index);
      g_previous_trends[tf_index] = trend_direction;
      return;
   }

   if(st_price > 0.0)
   {
      g_active_signal_line_prices[tf_index] = st_price;
      SaveTimeframeState(tf_index);
   }

   if(g_signal_entry_prices[tf_index] > 0.0 && g_signal_anchor_prices[tf_index] <= 0.0 && st_price > 0.0)
      UpdateBasePendingOrder(tf_index, trend_direction, st_price);

   if(g_signal_anchor_prices[tf_index] <= 0.0)
   {
      double base_fill_price = 0.0;
      if(GetBasePositionPrice(tf_index, trend_direction, base_fill_price))
         g_signal_anchor_prices[tf_index] = base_fill_price;
   }

   if(!g_grid_initialized[tf_index] &&
      g_signal_anchor_prices[tf_index] > 0.0 &&
      g_grid_boundary_prices[tf_index] > 0.0 &&
      !IsWithinSessionOpenCooldown())
   {
      PlaceGridPendingOrders(tf_index,
                             trend_direction,
                             g_grid_boundary_prices[tf_index],
                             g_signal_anchor_prices[tf_index]);
   }

   if(UpdateGridOnSTMove && st_price > 0.0)
   {
      if(MathAbs(st_price - g_previous_st_prices[tf_index]) > (_Point * 0.5))
         RebuildGridForTimeframe(tf_index, trend_direction, st_price);
   }

   g_previous_st_prices[tf_index] = st_price;
}

int OnInit()
{
   g_is_testing = (MQLInfoInteger(MQL_TESTER) != 0);

   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(SlippagePoints);
   trade.SetTypeFillingBySymbol(_Symbol);

   if(LotSize <= 0.0 || GridGapPoints <= 0 || MaxGridOrders < 0)
      return INIT_PARAMETERS_INCORRECT;

   if(!SetupTimeframes())
      return INIT_FAILED;

   InitializeDailyTarget();

   for(int i = 0; i < ArraySize(g_timeframes); i++)
   {
      LoadTimeframeState(i);

      if(UpdateSignalState(i))
      {
         if(g_active_signal_line_prices[i] <= 0.0)
            g_active_signal_line_prices[i] = g_last_st_prices[i];

         g_previous_trends[i] = g_current_trends[i];
         g_previous_st_prices[i] = g_last_st_prices[i];
         SaveTimeframeState(i);
      }
   }

   if(!g_is_testing)
   {
      EventSetTimer(1);
      UpdateChartStatusLabel();
   }

   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   if(!g_is_testing)
   {
      EventKillTimer();
      ObjectDelete(0, g_status_label_name);
   }

   for(int i = 0; i < ArraySize(g_supertrend_handles); i++)
   {
      if(g_supertrend_handles[i] != INVALID_HANDLE)
         IndicatorRelease(g_supertrend_handles[i]);
   }
}

void OnTick()
{
   RefreshProfitCaches();

   if(!g_is_testing)
      UpdateChartStatusLabel();

   if(CheckDailyTargetLock())
   {
      if(!g_is_testing)
         UpdateChartStatusLabel();
      return;
   }

   if(CheckSessionCloseWindow())
   {
      if(!g_is_testing)
         UpdateChartStatusLabel();
      return;
   }

   for(int i = 0; i < ArraySize(g_timeframes); i++)
   {
      CheckBaseProfitTake(i);
      CheckGridMaxLoss(i);

      if(!IsNewClosedBar(i))
         continue;

      if(!UpdateSignalState(i))
         continue;

      ProcessTimeframe(i);
   }
}

void OnTimer()
{
   if(!g_is_testing)
      UpdateChartStatusLabel();
}
