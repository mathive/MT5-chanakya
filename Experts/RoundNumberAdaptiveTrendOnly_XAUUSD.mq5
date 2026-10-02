//+------------------------------------------------------------------+
//|                      RoundNumberAdaptiveTrendOnly_XAUUSD.mq5      |
//|        Trend-only round-number grid: buy, sell, or no trade      |
//+------------------------------------------------------------------+
#property copyright "Chanakya"
#property link      "https://www.mql5.com"
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>

enum ENUM_TREND_ONLY_MODE
{
   TREND_BUY_ONLY = 0,
   TREND_SELL_ONLY = 1,
   TREND_NO_TRADE = 2
};

input group "Trend Decision"
input ENUM_TIMEFRAMES DecisionTimeframe = PERIOD_M15; // Timeframe used for trend mode
input int      FastEMAPeriod = 34;                    // Fast EMA period
input int      SlowEMAPeriod = 200;                  // Slow EMA period
input int      ADXPeriod = 14;                       // ADX period
input double   ADXTrendThreshold = 30.0;             // Minimum ADX for active trend trading
input int      ATRPeriod = 14;                       // ATR period
input double   MinEMAGapATRMultiplier = 0.22;        // Minimum EMA gap relative to ATR
input bool     UseSpreadNoTrade = true;              // Do not trade when spread too high

input group "Grid Settings"
input double   LotSize = 0.01;                       // Fixed lot size
input double   RoundStepPrice = 1.0;                 // Round-number step
input int      MaxPendingLevels = 10;                // Number of round levels checked
input int      MaxCount = 1;                         // Maximum active count for the allowed side
input double   TargetPriceDistance = 2.5;            // TP distance in price
input int      StopLossPoints = 220;                 // Stop loss in points, 0 = disabled

input group "Execution"
input int      MagicNumber = 455160;                 // EA magic number
input int      SlippagePoints = 3;                   // Allowed slippage
input int      MaxSpreadPoints = 30;                 // Maximum spread allowed
input bool     CloseOppositePositionsOnFlip = true;  // Close opposite open positions on signal flip
input bool     CancelOppositePendingOnFlip = true;   // Cancel opposite pending orders on signal flip

input group "Display"
input bool     ShowStatusLabel = true;               // Show chart status label
input int      StatusLabelFontSize = 14;             // Chart label font size

CTrade trade;

int g_fast_ema_handle = INVALID_HANDLE;
int g_slow_ema_handle = INVALID_HANDLE;
int g_adx_handle = INVALID_HANDLE;
int g_atr_handle = INVALID_HANDLE;
datetime g_last_decision_bar_time = 0;
ENUM_TREND_ONLY_MODE g_current_mode = TREND_NO_TRADE;

string StatusLabelName()
{
   return "TrendOnlyRoundGridStatus_" + IntegerToString(MagicNumber);
}

string ModeToString(const ENUM_TREND_ONLY_MODE mode)
{
   if(mode == TREND_BUY_ONLY)
      return "BUY_ONLY";
   if(mode == TREND_SELL_ONLY)
      return "SELL_ONLY";
   return "NO_TRADE";
}

string OrderCommentPrefix(const ENUM_POSITION_TYPE position_type)
{
   return (position_type == POSITION_TYPE_SELL) ? "TrendSell " : "TrendBuy ";
}

double NormalizePrice(const double price)
{
   return NormalizeDouble(price, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS));
}

double GetSpreadPoints()
{
   if(_Point <= 0.0)
      return 0.0;

   return MathMax(0.0, SymbolInfoDouble(_Symbol, SYMBOL_ASK) - SymbolInfoDouble(_Symbol, SYMBOL_BID)) / _Point;
}

bool IsSpreadOk()
{
   return (MaxSpreadPoints <= 0 || GetSpreadPoints() <= MaxSpreadPoints);
}

double GetStopLossDistancePrice()
{
   if(StopLossPoints <= 0)
      return 0.0;

   return StopLossPoints * _Point;
}

double GetMinOrderDistancePrice()
{
   int stops_level = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   int freeze_level = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL);
   return MathMax(stops_level, freeze_level) * _Point;
}

double GetBuyTopLevel()
{
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   return NormalizePrice(MathFloor(ask / RoundStepPrice) * RoundStepPrice);
}

double GetSellBottomLevel()
{
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   return NormalizePrice(MathCeil(bid / RoundStepPrice) * RoundStepPrice);
}

bool TryGetLevelFromComment(const string comment, double &level_price)
{
   string buy_prefix = OrderCommentPrefix(POSITION_TYPE_BUY);
   if(StringSubstr(comment, 0, StringLen(buy_prefix)) == buy_prefix)
   {
      level_price = StringToDouble(StringSubstr(comment, StringLen(buy_prefix)));
      return (level_price > 0.0);
   }

   string sell_prefix = OrderCommentPrefix(POSITION_TYPE_SELL);
   if(StringSubstr(comment, 0, StringLen(sell_prefix)) == sell_prefix)
   {
      level_price = StringToDouble(StringSubstr(comment, StringLen(sell_prefix)));
      return (level_price > 0.0);
   }

   return false;
}

int CountOpenPositions(const ENUM_POSITION_TYPE position_type)
{
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;
      if(PositionGetInteger(POSITION_MAGIC) != MagicNumber)
         continue;
      if((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) != position_type)
         continue;
      count++;
   }
   return count;
}

int CountPendingOrders(const ENUM_POSITION_TYPE position_type)
{
   ENUM_ORDER_TYPE order_type = (position_type == POSITION_TYPE_SELL) ? ORDER_TYPE_SELL_LIMIT : ORDER_TYPE_BUY_LIMIT;
   int count = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0 || !OrderSelect(ticket))
         continue;
      if(OrderGetString(ORDER_SYMBOL) != _Symbol)
         continue;
      if(OrderGetInteger(ORDER_MAGIC) != MagicNumber)
         continue;
      if((ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE) != order_type)
         continue;
      count++;
   }
   return count;
}

int GetRemainingCapacity(const ENUM_POSITION_TYPE position_type)
{
   int used = CountOpenPositions(position_type) + CountPendingOrders(position_type);
   return MathMax(0, MathMax(1, MaxCount) - used);
}

bool IsOurPositionAtLevel(const double level_price, const ENUM_POSITION_TYPE position_type)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;
      if(PositionGetInteger(POSITION_MAGIC) != MagicNumber)
         continue;
      if((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) != position_type)
         continue;

      double comment_level = 0.0;
      if(TryGetLevelFromComment(PositionGetString(POSITION_COMMENT), comment_level) &&
         MathAbs(comment_level - level_price) <= (_Point * 5.0))
      {
         return true;
      }
   }
   return false;
}

bool IsOurPendingOrderAtLevel(const double level_price, const ENUM_POSITION_TYPE position_type)
{
   ENUM_ORDER_TYPE order_type = (position_type == POSITION_TYPE_SELL) ? ORDER_TYPE_SELL_LIMIT : ORDER_TYPE_BUY_LIMIT;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0 || !OrderSelect(ticket))
         continue;
      if(OrderGetString(ORDER_SYMBOL) != _Symbol)
         continue;
      if(OrderGetInteger(ORDER_MAGIC) != MagicNumber)
         continue;
      if((ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE) != order_type)
         continue;

      double comment_level = 0.0;
      if(TryGetLevelFromComment(OrderGetString(ORDER_COMMENT), comment_level) &&
         MathAbs(comment_level - level_price) <= (_Point * 5.0))
      {
         return true;
      }
   }
   return false;
}

void DeleteOrderByTicket(const ulong ticket)
{
   trade.SetExpertMagicNumber(MagicNumber);
   trade.OrderDelete(ticket);
}

void CancelPendingOrdersByType(const ENUM_POSITION_TYPE position_type)
{
   ENUM_ORDER_TYPE order_type = (position_type == POSITION_TYPE_SELL) ? ORDER_TYPE_SELL_LIMIT : ORDER_TYPE_BUY_LIMIT;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0 || !OrderSelect(ticket))
         continue;
      if(OrderGetString(ORDER_SYMBOL) != _Symbol)
         continue;
      if(OrderGetInteger(ORDER_MAGIC) != MagicNumber)
         continue;
      if((ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE) != order_type)
         continue;
      DeleteOrderByTicket(ticket);
   }
}

void ClosePositionsByType(const ENUM_POSITION_TYPE position_type)
{
   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(SlippagePoints);
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;
      if(PositionGetInteger(POSITION_MAGIC) != MagicNumber)
         continue;
      if((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) != position_type)
         continue;
      trade.PositionClose(ticket);
   }
}

bool PlacePendingAtLevel(const double level_price, const ENUM_POSITION_TYPE position_type)
{
   if(!IsSpreadOk())
      return false;

   double min_distance = GetMinOrderDistancePrice();
   double sl_price = 0.0;
   double tp_price = 0.0;
   double sl_distance = GetStopLossDistancePrice();
   string comment = OrderCommentPrefix(position_type) + DoubleToString(level_price, 2);

   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(SlippagePoints);

   if(position_type == POSITION_TYPE_BUY)
   {
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      if(level_price >= ask - min_distance)
         return false;

      tp_price = NormalizePrice(level_price + TargetPriceDistance);
      if(sl_distance > 0.0)
         sl_price = NormalizePrice(level_price - sl_distance);

      return trade.BuyLimit(LotSize, NormalizePrice(level_price), _Symbol, sl_price, tp_price, ORDER_TIME_GTC, 0, comment);
   }

   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if(level_price <= bid + min_distance)
      return false;

   tp_price = NormalizePrice(level_price - TargetPriceDistance);
   if(sl_distance > 0.0)
      sl_price = NormalizePrice(level_price + sl_distance);

   return trade.SellLimit(LotSize, NormalizePrice(level_price), _Symbol, sl_price, tp_price, ORDER_TIME_GTC, 0, comment);
}

void MaintainAllowedSideGrid(const ENUM_POSITION_TYPE position_type)
{
   int capacity = GetRemainingCapacity(position_type);
   if(capacity <= 0)
      return;

   if(position_type == POSITION_TYPE_BUY)
   {
      double top_level = GetBuyTopLevel();
      for(int i = 0; i < MaxPendingLevels && capacity > 0; i++)
      {
         double level = NormalizePrice(top_level - (RoundStepPrice * i));
         if(IsOurPositionAtLevel(level, position_type) || IsOurPendingOrderAtLevel(level, position_type))
            continue;
         if(PlacePendingAtLevel(level, position_type))
            capacity--;
      }
      return;
   }

   double bottom_level = GetSellBottomLevel();
   for(int i = 0; i < MaxPendingLevels && capacity > 0; i++)
   {
      double level = NormalizePrice(bottom_level + (RoundStepPrice * i));
      if(IsOurPositionAtLevel(level, position_type) || IsOurPendingOrderAtLevel(level, position_type))
         continue;
      if(PlacePendingAtLevel(level, position_type))
         capacity--;
   }
}

bool ReadIndicatorValue(const int handle, const int buffer_index, double &value)
{
   double values[];
   if(CopyBuffer(handle, buffer_index, 1, 1, values) <= 0)
      return false;
   value = values[0];
   return true;
}

ENUM_TREND_ONLY_MODE DetermineTrendMode()
{
   if(UseSpreadNoTrade && !IsSpreadOk())
      return TREND_NO_TRADE;

   double fast_ema = 0.0;
   double slow_ema = 0.0;
   double adx_main = 0.0;
   double atr_value = 0.0;

   if(!ReadIndicatorValue(g_fast_ema_handle, 0, fast_ema) ||
      !ReadIndicatorValue(g_slow_ema_handle, 0, slow_ema) ||
      !ReadIndicatorValue(g_adx_handle, 0, adx_main) ||
      !ReadIndicatorValue(g_atr_handle, 0, atr_value))
   {
      return TREND_NO_TRADE;
   }

   double ema_gap = MathAbs(fast_ema - slow_ema);
   if(adx_main < ADXTrendThreshold)
      return TREND_NO_TRADE;

   if(ema_gap < (atr_value * MinEMAGapATRMultiplier))
      return TREND_NO_TRADE;

   if(fast_ema > slow_ema)
      return TREND_BUY_ONLY;

   if(fast_ema < slow_ema)
      return TREND_SELL_ONLY;

   return TREND_NO_TRADE;
}

bool IsNewDecisionBar()
{
   datetime bar_time = iTime(_Symbol, DecisionTimeframe, 0);
   if(bar_time == 0)
      return false;
   if(bar_time == g_last_decision_bar_time)
      return false;
   g_last_decision_bar_time = bar_time;
   return true;
}

void ApplyModeChange(const ENUM_TREND_ONLY_MODE new_mode)
{
   if(new_mode == g_current_mode)
      return;

   if(new_mode == TREND_BUY_ONLY)
   {
      if(CancelOppositePendingOnFlip)
         CancelPendingOrdersByType(POSITION_TYPE_SELL);
      if(CloseOppositePositionsOnFlip)
         ClosePositionsByType(POSITION_TYPE_SELL);
   }
   else if(new_mode == TREND_SELL_ONLY)
   {
      if(CancelOppositePendingOnFlip)
         CancelPendingOrdersByType(POSITION_TYPE_BUY);
      if(CloseOppositePositionsOnFlip)
         ClosePositionsByType(POSITION_TYPE_BUY);
   }
   else
   {
      CancelPendingOrdersByType(POSITION_TYPE_BUY);
      CancelPendingOrdersByType(POSITION_TYPE_SELL);
   }

   g_current_mode = new_mode;
}

void UpdateMode()
{
   if(g_current_mode == TREND_NO_TRADE || IsNewDecisionBar())
      ApplyModeChange(DetermineTrendMode());
}

void UpdateOpenPositionProtection()
{
   trade.SetExpertMagicNumber(MagicNumber);
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;
      if(PositionGetInteger(POSITION_MAGIC) != MagicNumber)
         continue;

      ENUM_POSITION_TYPE position_type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      double base_price = PositionGetDouble(POSITION_PRICE_OPEN);
      double level = 0.0;
      if(TryGetLevelFromComment(PositionGetString(POSITION_COMMENT), level))
         base_price = level;

      double sl_distance = GetStopLossDistancePrice();
      double new_sl = 0.0;
      if(sl_distance > 0.0)
      {
         new_sl = (position_type == POSITION_TYPE_SELL)
                  ? NormalizePrice(base_price + sl_distance)
                  : NormalizePrice(base_price - sl_distance);
      }

      double new_tp = (position_type == POSITION_TYPE_SELL)
                      ? NormalizePrice(base_price - TargetPriceDistance)
                      : NormalizePrice(base_price + TargetPriceDistance);

      double current_sl = PositionGetDouble(POSITION_SL);
      double current_tp = PositionGetDouble(POSITION_TP);
      if(MathAbs(current_sl - new_sl) <= (_Point * 0.5) && MathAbs(current_tp - new_tp) <= (_Point * 0.5))
         continue;

      trade.PositionModify(ticket, new_sl, new_tp);
   }
}

void UpdateStatusLabel()
{
   string label_name = StatusLabelName();
   if(!ShowStatusLabel)
   {
      ObjectDelete(0, label_name);
      return;
   }

   if(ObjectFind(0, label_name) < 0)
   {
      ObjectCreate(0, label_name, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, label_name, OBJPROP_CORNER, CORNER_RIGHT_UPPER);
      ObjectSetInteger(0, label_name, OBJPROP_ANCHOR, ANCHOR_RIGHT_UPPER);
      ObjectSetInteger(0, label_name, OBJPROP_XDISTANCE, 20);
      ObjectSetInteger(0, label_name, OBJPROP_YDISTANCE, 20);
      ObjectSetString(0, label_name, OBJPROP_FONT, "Arial");
   }

   string text = "TrendOnly Adaptive Grid" +
                 "\nMode: " + ModeToString(g_current_mode) +
                 "\nSpread: " + DoubleToString(GetSpreadPoints(), 1) + " pts" +
                 "\nBuy Open/Pending: " + IntegerToString(CountOpenPositions(POSITION_TYPE_BUY)) + "/" + IntegerToString(CountPendingOrders(POSITION_TYPE_BUY)) +
                 "\nSell Open/Pending: " + IntegerToString(CountOpenPositions(POSITION_TYPE_SELL)) + "/" + IntegerToString(CountPendingOrders(POSITION_TYPE_SELL));

   ObjectSetString(0, label_name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, label_name, OBJPROP_FONTSIZE, MathMax(8, StatusLabelFontSize));
   ObjectSetInteger(0, label_name, OBJPROP_COLOR, clrLime);
   ObjectSetInteger(0, label_name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, label_name, OBJPROP_HIDDEN, true);
}

void OnTick()
{
   UpdateMode();
   UpdateOpenPositionProtection();

   if(g_current_mode == TREND_BUY_ONLY)
      MaintainAllowedSideGrid(POSITION_TYPE_BUY);
   else if(g_current_mode == TREND_SELL_ONLY)
      MaintainAllowedSideGrid(POSITION_TYPE_SELL);

   UpdateStatusLabel();
}

int OnInit()
{
   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(SlippagePoints);
   trade.SetTypeFillingBySymbol(_Symbol);

   if(LotSize <= 0.0 || RoundStepPrice <= 0.0 || TargetPriceDistance <= 0.0 || MaxPendingLevels <= 0 || MaxCount <= 0)
      return INIT_PARAMETERS_INCORRECT;

   g_fast_ema_handle = iMA(_Symbol, DecisionTimeframe, FastEMAPeriod, 0, MODE_EMA, PRICE_CLOSE);
   g_slow_ema_handle = iMA(_Symbol, DecisionTimeframe, SlowEMAPeriod, 0, MODE_EMA, PRICE_CLOSE);
   g_adx_handle = iADX(_Symbol, DecisionTimeframe, ADXPeriod);
   g_atr_handle = iATR(_Symbol, DecisionTimeframe, ATRPeriod);

   if(g_fast_ema_handle == INVALID_HANDLE || g_slow_ema_handle == INVALID_HANDLE ||
      g_adx_handle == INVALID_HANDLE || g_atr_handle == INVALID_HANDLE)
   {
      return INIT_FAILED;
   }

   g_current_mode = DetermineTrendMode();
   UpdateStatusLabel();
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   if(g_fast_ema_handle != INVALID_HANDLE)
      IndicatorRelease(g_fast_ema_handle);
   if(g_slow_ema_handle != INVALID_HANDLE)
      IndicatorRelease(g_slow_ema_handle);
   if(g_adx_handle != INVALID_HANDLE)
      IndicatorRelease(g_adx_handle);
   if(g_atr_handle != INVALID_HANDLE)
      IndicatorRelease(g_atr_handle);

   ObjectDelete(0, StatusLabelName());
}

//+------------------------------------------------------------------+
