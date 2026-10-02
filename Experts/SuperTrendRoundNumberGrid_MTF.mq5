//+------------------------------------------------------------------+
//|                          SuperTrendRoundNumberGrid_MTF.mq5       |
//|        Multi-timeframe SuperTrend round-number pending grid      |
//+------------------------------------------------------------------+
#property copyright "Chanakya"
#property link      "https://www.mql5.com"
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>

input group "SuperTrend"
input double   ATRMultiplier = 9.0;             // SuperTrend ATR multiplier
input int      ATRPeriod = 27;                  // SuperTrend ATR period
input string   IndicatorPrefix = "SPRTRND";     // SuperTrend object prefix

input group "Grid"
input double   LotSize = 0.01;                  // Pending order lot size
input double   RoundGapPrice = 1.0;             // Gap between round-number levels
input int      MaxOrdersPerSignal = 100;        // Safety cap per timeframe signal
input double   TakeProfitPrice = 0.0;           // TP distance in price
input bool     RepeatOrderForSamePrice = true;  // Allow repeated orders at same TF/trend/price

input group "Execution"
input int      MagicNumber = 551100;            // Base magic number
input int      SlippagePoints = 3;              // Slippage in points

input group "Timeframes"
input bool     Trade_M1 = true;
input bool     Trade_M2 = true;
input bool     Trade_M3 = true;
input bool     Trade_M5 = true;
input bool     Trade_M15 = true;
input bool     Trade_M30 = true;
input bool     Trade_H1 = true;

input group "Display"
input bool     ShowProfitLabel = true;          // Show EA PNL label on chart
input int      ProfitLabelFontSize = 14;        // Chart profit label font size

CTrade trade;

ENUM_TIMEFRAMES g_timeframes[];
string          g_tf_names[];
int             g_handles[];
datetime        g_last_bar_times[];
int             g_last_directions[];
double          g_last_st_prices[];
int             g_last_open_counts[];
int             g_last_pending_counts[];
string          g_used_order_keys[];

string OrderRepeatKey(const int tf_index, const int direction, const double price)
{
   return TimeframeTag(tf_index) + "|" + IntegerToString(direction) + "|" + DoubleToString(NormalizePrice(price), _Digits);
}

bool IsOrderPriceUsed(const int tf_index, const int direction, const double price)
{
   if(RepeatOrderForSamePrice)
      return false;

   string key = OrderRepeatKey(tf_index, direction, price);
   for(int i = 0; i < ArraySize(g_used_order_keys); i++)
   {
      if(g_used_order_keys[i] == key)
         return true;
   }

   return false;
}

void RememberOrderPrice(const int tf_index, const int direction, const double price)
{
   if(RepeatOrderForSamePrice)
      return;

   string key = OrderRepeatKey(tf_index, direction, price);
   for(int i = 0; i < ArraySize(g_used_order_keys); i++)
   {
      if(g_used_order_keys[i] == key)
         return;
   }

   int size = ArraySize(g_used_order_keys);
   ArrayResize(g_used_order_keys, size + 1);
   g_used_order_keys[size] = key;
}

int CountOpenPositionsForTimeframe(const int tf_index)
{
   int magic = MagicForIndex(tf_index);
   int count = 0;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;

      if(PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;
      if(PositionGetInteger(POSITION_MAGIC) != magic)
         continue;

      count++;
   }

   return count;
}

int CountPendingOrdersForTimeframe(const int tf_index)
{
   int magic = MagicForIndex(tf_index);
   int count = 0;

   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0 || !OrderSelect(ticket))
         continue;

      if(OrderGetString(ORDER_SYMBOL) != _Symbol)
         continue;
      if(OrderGetInteger(ORDER_MAGIC) != magic)
         continue;

      ENUM_ORDER_TYPE type = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
      if(type != ORDER_TYPE_BUY_LIMIT && type != ORDER_TYPE_SELL_LIMIT)
         continue;

      count++;
   }

   return count;
}

void SeedUsedOrderPricesFromActiveTrades()
{
   if(RepeatOrderForSamePrice)
      return;

   ArrayResize(g_used_order_keys, 0);

   for(int tf_index = 0; tf_index < ArraySize(g_timeframes); tf_index++)
   {
      int magic = MagicForIndex(tf_index);

      for(int i = OrdersTotal() - 1; i >= 0; i--)
      {
         ulong ticket = OrderGetTicket(i);
         if(ticket == 0 || !OrderSelect(ticket))
            continue;

         if(OrderGetString(ORDER_SYMBOL) != _Symbol)
            continue;
         if(OrderGetInteger(ORDER_MAGIC) != magic)
            continue;

         ENUM_ORDER_TYPE type = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
         if(type == ORDER_TYPE_BUY_LIMIT)
            RememberOrderPrice(tf_index, 0, OrderGetDouble(ORDER_PRICE_OPEN));
         else if(type == ORDER_TYPE_SELL_LIMIT)
            RememberOrderPrice(tf_index, 1, OrderGetDouble(ORDER_PRICE_OPEN));
      }

      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket == 0 || !PositionSelectByTicket(ticket))
            continue;

         if(PositionGetString(POSITION_SYMBOL) != _Symbol)
            continue;
         if(PositionGetInteger(POSITION_MAGIC) != magic)
            continue;

         ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
         if(type == POSITION_TYPE_BUY)
            RememberOrderPrice(tf_index, 0, PositionGetDouble(POSITION_PRICE_OPEN));
         else if(type == POSITION_TYPE_SELL)
            RememberOrderPrice(tf_index, 1, PositionGetDouble(POSITION_PRICE_OPEN));
      }
   }
}

double NormalizePrice(const double price)
{
   return NormalizeDouble(price, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS));
}

int TimeframeSecondsSafe(const ENUM_TIMEFRAMES tf)
{
   int seconds = PeriodSeconds(tf);
   return (seconds > 0) ? seconds : (int)tf;
}

int MagicForIndex(const int tf_index)
{
   return MagicNumber + TimeframeSecondsSafe(g_timeframes[tf_index]);
}

string TimeframeTag(const int tf_index)
{
   return g_tf_names[tf_index];
}

bool IsOurMagic(const long magic)
{
   for(int i = 0; i < ArraySize(g_timeframes); i++)
   {
      if(magic == MagicForIndex(i))
         return true;
   }
   return false;
}

string ProfitLabelName()
{
   return "ST_MTF_Profit_Label_" + IntegerToString(MagicNumber);
}

datetime GetCurrentSessionStart()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   dt.hour = 0;
   dt.min = 0;
   dt.sec = 0;
   return StructToTime(dt);
}

double GetTodayRealizedProfit()
{
   double realized_profit = 0.0;
   datetime now = TimeCurrent();
   datetime session_start = GetCurrentSessionStart();

   if(!HistorySelect(session_start, now))
      return 0.0;

   for(int i = HistoryDealsTotal() - 1; i >= 0; i--)
   {
      ulong deal_ticket = HistoryDealGetTicket(i);
      if(deal_ticket == 0)
         continue;

      if(HistoryDealGetString(deal_ticket, DEAL_SYMBOL) != _Symbol)
         continue;

      if(!IsOurMagic(HistoryDealGetInteger(deal_ticket, DEAL_MAGIC)))
         continue;

      realized_profit += HistoryDealGetDouble(deal_ticket, DEAL_PROFIT);
      realized_profit += HistoryDealGetDouble(deal_ticket, DEAL_SWAP);
      realized_profit += HistoryDealGetDouble(deal_ticket, DEAL_COMMISSION);
   }

   return realized_profit;
}

double GetHistoryRealizedProfit()
{
   double realized_profit = 0.0;
   datetime now = TimeCurrent();

   if(!HistorySelect(0, now))
      return 0.0;

   for(int i = HistoryDealsTotal() - 1; i >= 0; i--)
   {
      ulong deal_ticket = HistoryDealGetTicket(i);
      if(deal_ticket == 0)
         continue;

      if(HistoryDealGetString(deal_ticket, DEAL_SYMBOL) != _Symbol)
         continue;

      if(!IsOurMagic(HistoryDealGetInteger(deal_ticket, DEAL_MAGIC)))
         continue;

      realized_profit += HistoryDealGetDouble(deal_ticket, DEAL_PROFIT);
      realized_profit += HistoryDealGetDouble(deal_ticket, DEAL_SWAP);
      realized_profit += HistoryDealGetDouble(deal_ticket, DEAL_COMMISSION);
   }

   return realized_profit;
}

double GetFloatingProfit()
{
   double floating_profit = 0.0;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;

      if(PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;

      if(!IsOurMagic(PositionGetInteger(POSITION_MAGIC)))
         continue;

      floating_profit += PositionGetDouble(POSITION_PROFIT);
      floating_profit += PositionGetDouble(POSITION_SWAP);
   }

   return floating_profit;
}

double GetMidPriceForSymbol(const string symbol_name)
{
   MqlTick tick;
   if(SymbolInfoTick(symbol_name, tick))
   {
      if(tick.bid > 0.0 && tick.ask > 0.0)
         return (tick.bid + tick.ask) * 0.5;

      if(tick.last > 0.0)
         return tick.last;
   }

   double bid = SymbolInfoDouble(symbol_name, SYMBOL_BID);
   double ask = SymbolInfoDouble(symbol_name, SYMBOL_ASK);
   if(bid > 0.0 && ask > 0.0)
      return (bid + ask) * 0.5;

   return 0.0;
}

double FindDirectCurrencyRate(const string from_currency, const string to_currency)
{
   if(from_currency == to_currency)
      return 1.0;

   int total_symbols = SymbolsTotal(false);
   for(int i = 0; i < total_symbols; i++)
   {
      string symbol_name = SymbolName(i, false);
      if(symbol_name == "")
         continue;

      string base_currency = SymbolInfoString(symbol_name, SYMBOL_CURRENCY_BASE);
      string quote_currency = SymbolInfoString(symbol_name, SYMBOL_CURRENCY_PROFIT);

      if(base_currency == "" || quote_currency == "")
         continue;

      if((base_currency != from_currency || quote_currency != to_currency) &&
         (base_currency != to_currency || quote_currency != from_currency))
      {
         continue;
      }

      SymbolSelect(symbol_name, true);
      double mid_price = GetMidPriceForSymbol(symbol_name);
      if(mid_price <= 0.0)
         continue;

      if(base_currency == from_currency && quote_currency == to_currency)
         return mid_price;

      if(base_currency == to_currency && quote_currency == from_currency)
         return (mid_price == 0.0) ? 0.0 : (1.0 / mid_price);
   }

   return 0.0;
}

double GetCurrencyConversionRate(const string from_currency, const string to_currency)
{
   if(from_currency == to_currency)
      return 1.0;

   double direct_rate = FindDirectCurrencyRate(from_currency, to_currency);
   if(direct_rate > 0.0)
      return direct_rate;

   static string bridge_currencies[] = {"USD", "EUR", "JPY", "GBP", "AUD"};
   for(int i = 0; i < ArraySize(bridge_currencies); i++)
   {
      string bridge = bridge_currencies[i];
      if(bridge == from_currency || bridge == to_currency)
         continue;

      double first_leg = FindDirectCurrencyRate(from_currency, bridge);
      if(first_leg <= 0.0)
         continue;

      double second_leg = FindDirectCurrencyRate(bridge, to_currency);
      if(second_leg <= 0.0)
         continue;

      return first_leg * second_leg;
   }

   return 0.0;
}

void UpdateProfitLabel()
{
   string label_name = ProfitLabelName();

   if(!ShowProfitLabel)
   {
      ObjectDelete(0, label_name);
      return;
   }

   double realized_profit = GetTodayRealizedProfit();
   double history_profit = GetHistoryRealizedProfit();
   double floating_profit = GetFloatingProfit();
   double total_profit = realized_profit + floating_profit;

   string account_currency = AccountInfoString(ACCOUNT_CURRENCY);
   double inr_rate = GetCurrencyConversionRate(account_currency, "INR");
   bool can_convert_to_inr = (inr_rate > 0.0);

   double total_profit_inr = can_convert_to_inr ? (total_profit * inr_rate) : total_profit;
   double history_profit_inr = can_convert_to_inr ? (history_profit * inr_rate) : history_profit;
   double realized_profit_inr = can_convert_to_inr ? (realized_profit * inr_rate) : realized_profit;
   double floating_profit_inr = can_convert_to_inr ? (floating_profit * inr_rate) : floating_profit;

   string text = "SuperTrend MTF EA Profit: INR " + DoubleToString(total_profit_inr, 2) +
                 "\nCollected: INR " + DoubleToString(realized_profit_inr, 2) +
                 " | Floating: INR " + DoubleToString(floating_profit_inr, 2) +
                 "\nTotal History: INR " + DoubleToString(history_profit_inr, 2);

   if(can_convert_to_inr)
      text += "\nConversion: 1 " + account_currency + " = INR " + DoubleToString(inr_rate, 4);
   else
      text += "\nValues shown in " + account_currency;

   if(ObjectFind(0, label_name) < 0)
   {
      ObjectCreate(0, label_name, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, label_name, OBJPROP_CORNER, CORNER_RIGHT_UPPER);
      ObjectSetInteger(0, label_name, OBJPROP_ANCHOR, ANCHOR_RIGHT_UPPER);
      ObjectSetInteger(0, label_name, OBJPROP_XDISTANCE, 50);
      ObjectSetInteger(0, label_name, OBJPROP_YDISTANCE, 22);
      ObjectSetString(0, label_name, OBJPROP_FONT, "Arial");
   }

   ObjectSetString(0, label_name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, label_name, OBJPROP_FONTSIZE, MathMax(8, ProfitLabelFontSize));
   ObjectSetInteger(0, label_name, OBJPROP_COLOR, total_profit_inr >= 0.0 ? clrBlack : clrTomato);
}

double GetBuyStartLevel()
{
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double level = MathFloor(ask / RoundGapPrice) * RoundGapPrice;
   if(level >= ask - (_Point * 0.5))
      level -= RoundGapPrice;
   return NormalizePrice(level);
}

double GetSellStartLevel()
{
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double level = MathCeil(bid / RoundGapPrice) * RoundGapPrice;
   return NormalizePrice(level);
}

double GetBuyGridStartForTimeframe(const int tf_index)
{
   double start_level = GetBuyStartLevel();
   for(int j = 0; j < tf_index; j++)
   {
      if(g_last_directions[j] == 0)
      {
         double prev_support = g_last_st_prices[j];
         double level = MathFloor(prev_support / RoundGapPrice) * RoundGapPrice;
         if(level >= prev_support - (_Point * 0.5))
            level -= RoundGapPrice;
            
         if(level < start_level)
            start_level = level;
      }
   }
   
   return NormalizePrice(start_level);
}

double GetSellGridStartForTimeframe(const int tf_index)
{
   double start_level = GetSellStartLevel();
   
   for(int j = 0; j < tf_index; j++)
   {
      if(g_last_directions[j] == 1)
      {
         double prev_resistance = g_last_st_prices[j];
         double level = MathCeil(prev_resistance / RoundGapPrice) * RoundGapPrice;
         if(level <= prev_resistance + (_Point * 0.5))
            level += RoundGapPrice;
            
         if(level > start_level)
            start_level = level;
      }
   }
   
   return NormalizePrice(start_level);
}

string PendingComment(const int tf_index, const bool is_buy)
{
   return TimeframeTag(tf_index) + (is_buy ? "_BUY_GRID" : "_SELL_GRID");
}

void DeleteOrderByTicket(const ulong ticket, const int tf_index)
{
   trade.SetExpertMagicNumber(MagicForIndex(tf_index));
   if(!trade.OrderDelete(ticket))
   {
      Print("Delete order failed tf=", TimeframeTag(tf_index),
            " ticket=", ticket,
            " retcode=", trade.ResultRetcode(),
            " msg=", trade.ResultRetcodeDescription());
   }
}

void CancelPendingOrdersForTimeframe(const int tf_index)
{
   int magic = MagicForIndex(tf_index);
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0 || !OrderSelect(ticket))
         continue;

      if(OrderGetString(ORDER_SYMBOL) != _Symbol)
         continue;
      if(OrderGetInteger(ORDER_MAGIC) != magic)
         continue;

      ENUM_ORDER_TYPE type = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
      if(type != ORDER_TYPE_BUY_LIMIT && type != ORDER_TYPE_SELL_LIMIT)
         continue;

      DeleteOrderByTicket(ticket, tf_index);
   }
}

void ClosePositionsForTimeframe(const int tf_index)
{
   int magic = MagicForIndex(tf_index);
   trade.SetExpertMagicNumber(magic);
   trade.SetDeviationInPoints(SlippagePoints);

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;

      if(PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;
      if(PositionGetInteger(POSITION_MAGIC) != magic)
         continue;

      if(!trade.PositionClose(ticket))
      {
         Print("Close position failed tf=", TimeframeTag(tf_index),
               " ticket=", ticket,
               " retcode=", trade.ResultRetcode(),
               " msg=", trade.ResultRetcodeDescription());
      }
   }
}

bool PlaceBuyGridToSupport(const int tf_index, const double support_price)
{
   double start_level = GetBuyGridStartForTimeframe(tf_index);
   if(start_level < support_price + (_Point * 0.5))
      return false;

   int magic = MagicForIndex(tf_index);
   int placed = 0;
   trade.SetExpertMagicNumber(magic);
   trade.SetDeviationInPoints(SlippagePoints);

   for(double price = start_level; price >= support_price - (_Point * 0.5) && placed < MaxOrdersPerSignal; price -= RoundGapPrice)
   {
      double entry = NormalizePrice(price);
      if(entry < support_price - (_Point * 0.5))
         continue;
      if(IsOrderPriceUsed(tf_index, 0, entry))
         continue;

      double tp_price = 0.0;
      if(TakeProfitPrice > 0.0)
         tp_price = NormalizePrice(entry + TakeProfitPrice);

      if(!trade.BuyLimit(LotSize, entry, _Symbol, 0.0, tp_price, ORDER_TIME_GTC, 0, PendingComment(tf_index, true)))
      {
         Print("BuyLimit failed tf=", TimeframeTag(tf_index),
               " entry=", DoubleToString(entry, _Digits),
               " retcode=", trade.ResultRetcode(),
               " msg=", trade.ResultRetcodeDescription());
      }
      else
      {
         RememberOrderPrice(tf_index, 0, entry);
         placed++;
      }
   }

   return (placed > 0);
}

bool PlaceSellGridToResistance(const int tf_index, const double resistance_price)
{
   double start_level = GetSellGridStartForTimeframe(tf_index);
   if(start_level > resistance_price - (_Point * 0.5))
      return false;

   int magic = MagicForIndex(tf_index);
   int placed = 0;
   trade.SetExpertMagicNumber(magic);
   trade.SetDeviationInPoints(SlippagePoints);

   for(double price = start_level; price <= resistance_price + (_Point * 0.5) && placed < MaxOrdersPerSignal; price += RoundGapPrice)
   {
      double entry = NormalizePrice(price);
      if(entry > resistance_price + (_Point * 0.5))
         continue;
      if(IsOrderPriceUsed(tf_index, 1, entry))
         continue;

      double tp_price = 0.0;
      if(TakeProfitPrice > 0.0)
         tp_price = NormalizePrice(entry - TakeProfitPrice);

      if(!trade.SellLimit(LotSize, entry, _Symbol, 0.0, tp_price, ORDER_TIME_GTC, 0, PendingComment(tf_index, false)))
      {
         Print("SellLimit failed tf=", TimeframeTag(tf_index),
               " entry=", DoubleToString(entry, _Digits),
               " retcode=", trade.ResultRetcode(),
               " msg=", trade.ResultRetcodeDescription());
      }
      else
      {
         RememberOrderPrice(tf_index, 1, entry);
         placed++;
      }
   }

   return (placed > 0);
}

bool AddMissingBuyOrders(const int tf_index, const double support_price)
{
   double existing_prices[];
   int existing_count = 0;
   const int magic = MagicForIndex(tf_index);

   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0 || !OrderSelect(ticket))
         continue;

      if(OrderGetInteger(ORDER_MAGIC) == magic && OrderGetString(ORDER_SYMBOL) == _Symbol &&
         (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE) == ORDER_TYPE_BUY_LIMIT)
      {
         ArrayResize(existing_prices, existing_count + 1);
         existing_prices[existing_count] = OrderGetDouble(ORDER_PRICE_OPEN);
         existing_count++;
      }
   }
   
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;

      if(PositionGetInteger(POSITION_MAGIC) == magic && PositionGetString(POSITION_SYMBOL) == _Symbol &&
         (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
      {
         ArrayResize(existing_prices, existing_count + 1);
         existing_prices[existing_count] = PositionGetDouble(POSITION_PRICE_OPEN);
         existing_count++;
      }
   }

   double start_level = GetBuyGridStartForTimeframe(tf_index);
   if(start_level < support_price + (_Point * 0.5))
      return false;

   int placed = 0;
   trade.SetExpertMagicNumber(magic);
   trade.SetDeviationInPoints(SlippagePoints);

   for(double price = start_level; price >= support_price - (_Point * 0.5) && (placed + existing_count) < MaxOrdersPerSignal; price -= RoundGapPrice)
   {
      double entry = NormalizePrice(price);
      if(entry < support_price - (_Point * 0.5))
         continue;

      bool exists = false;
      for(int j = 0; j < existing_count; j++)
      {
         if(MathAbs(existing_prices[j] - entry) < RoundGapPrice * 0.5)
         {
            exists = true;
            break;
         }
      }

      if(!exists)
      {
         if(IsOrderPriceUsed(tf_index, 0, entry))
            continue;

         double tp_price = 0.0;
         if(TakeProfitPrice > 0.0)
            tp_price = NormalizePrice(entry + TakeProfitPrice);

         if(!trade.BuyLimit(LotSize, entry, _Symbol, 0.0, tp_price, ORDER_TIME_GTC, 0, PendingComment(tf_index, true)))
         {
            Print("BuyLimit (add missing) failed tf=", TimeframeTag(tf_index), " entry=", DoubleToString(entry, _Digits), " retcode=", trade.ResultRetcode(), " msg=", trade.ResultRetcodeDescription());
         }
         else
         {
            RememberOrderPrice(tf_index, 0, entry);
            placed++;
         }
      }
   }
   return (placed > 0);
}

bool AddMissingSellOrders(const int tf_index, const double resistance_price)
{
   double existing_prices[];
   int existing_count = 0;
   const int magic = MagicForIndex(tf_index);

   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0 || !OrderSelect(ticket))
         continue;

      if(OrderGetInteger(ORDER_MAGIC) == magic && OrderGetString(ORDER_SYMBOL) == _Symbol &&
         (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE) == ORDER_TYPE_SELL_LIMIT)
      {
         ArrayResize(existing_prices, existing_count + 1);
         existing_prices[existing_count] = OrderGetDouble(ORDER_PRICE_OPEN);
         existing_count++;
      }
   }

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;

      if(PositionGetInteger(POSITION_MAGIC) == magic && PositionGetString(POSITION_SYMBOL) == _Symbol &&
         (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL)
      {
         ArrayResize(existing_prices, existing_count + 1);
         existing_prices[existing_count] = PositionGetDouble(POSITION_PRICE_OPEN);
         existing_count++;
      }
   }

   double start_level = GetSellGridStartForTimeframe(tf_index);
   if(start_level > resistance_price - (_Point * 0.5))
      return false;

   int placed = 0;
   trade.SetExpertMagicNumber(magic);
   trade.SetDeviationInPoints(SlippagePoints);

   for(double price = start_level; price <= resistance_price + (_Point * 0.5) && (placed + existing_count) < MaxOrdersPerSignal; price += RoundGapPrice)
   {
      double entry = NormalizePrice(price);
      if(entry > resistance_price + (_Point * 0.5))
         continue;

      bool exists = false;
      for(int j = 0; j < existing_count; j++)
      {
         if(MathAbs(existing_prices[j] - entry) < RoundGapPrice * 0.5)
         {
            exists = true;
            break;
         }
      }

      if(!exists)
      {
         if(IsOrderPriceUsed(tf_index, 1, entry))
            continue;

         double tp_price = 0.0;
         if(TakeProfitPrice > 0.0)
            tp_price = NormalizePrice(entry - TakeProfitPrice);

         if(!trade.SellLimit(LotSize, entry, _Symbol, 0.0, tp_price, ORDER_TIME_GTC, 0, PendingComment(tf_index, false)))
         {
            Print("SellLimit (add missing) failed tf=", TimeframeTag(tf_index), " entry=", DoubleToString(entry, _Digits), " retcode=", trade.ResultRetcode(), " msg=", trade.ResultRetcodeDescription());
         }
         else
         {
            RememberOrderPrice(tf_index, 1, entry);
            placed++;
         }
      }
   }
   return (placed > 0);
}

bool ReadSignalSnapshot(const int tf_index, int &direction, double &st_price)
{
   if(g_handles[tf_index] == INVALID_HANDLE)
      return false;

   double direction_buffer[1];
   if(CopyBuffer(g_handles[tf_index], 2, 1, 1, direction_buffer) < 1)
      return false;

   double line_buffer[1];
   if(CopyBuffer(g_handles[tf_index], 0, 1, 1, line_buffer) < 1)
      return false;

   direction = (int)direction_buffer[0];
   st_price = NormalizePrice(line_buffer[0]);
   return true;
}

bool ReadNewBarSignal(const int tf_index, int &direction, double &st_price)
{
   datetime times[1];
   if(CopyTime(_Symbol, g_timeframes[tf_index], 0, 1, times) < 1)
      return false;

   if(times[0] == g_last_bar_times[tf_index])
      return false;

   g_last_bar_times[tf_index] = times[0];
   return ReadSignalSnapshot(tf_index, direction, st_price);
}

void ApplySignalGrid(const int tf_index, const int direction, const double st_price)
{
   ClosePositionsForTimeframe(tf_index);
   CancelPendingOrdersForTimeframe(tf_index);

   if(direction == 0)
   {
      if(!PlaceBuyGridToSupport(tf_index, st_price))
      {
         Print("Buy grid not placed tf=", TimeframeTag(tf_index),
               " start=", DoubleToString(GetBuyGridStartForTimeframe(tf_index), _Digits),
               " support=", DoubleToString(st_price, _Digits));
      }
   }
   else if(direction == 1)
   {
      if(!PlaceSellGridToResistance(tf_index, st_price))
      {
         Print("Sell grid not placed tf=", TimeframeTag(tf_index),
               " start=", DoubleToString(GetSellGridStartForTimeframe(tf_index), _Digits),
               " resistance=", DoubleToString(st_price, _Digits));
      }
   }
}

void RefreshPendingGridOnly(const int tf_index, const int direction, const double st_price)
{
   if(direction == 0)
      AddMissingBuyOrders(tf_index, st_price);
   else if(direction == 1)
      AddMissingSellOrders(tf_index, st_price);
}

void UpdateOrdersAndPositionsTP(const int tf_index, const int direction)
{
   int magic = MagicForIndex(tf_index);

   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0 || !OrderSelect(ticket))
         continue;

      if(OrderGetString(ORDER_SYMBOL) == _Symbol && OrderGetInteger(ORDER_MAGIC) == magic)
      {
         double entry = OrderGetDouble(ORDER_PRICE_OPEN);
         double current_tp = OrderGetDouble(ORDER_TP);
         double current_sl = OrderGetDouble(ORDER_SL);
         
         double new_tp = 0.0;
         if(TakeProfitPrice > 0.0)
            new_tp = NormalizePrice(entry + (direction == 0 ? TakeProfitPrice : -TakeProfitPrice));
            
         if(MathAbs(current_tp - new_tp) > _Point * 0.5)
            trade.OrderModify(ticket, entry, current_sl, new_tp, (ENUM_ORDER_TYPE_TIME)OrderGetInteger(ORDER_TYPE_TIME), (datetime)OrderGetInteger(ORDER_TIME_EXPIRATION));
      }
   }

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;

      if(PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_MAGIC) == magic)
      {
         double entry = PositionGetDouble(POSITION_PRICE_OPEN);
         double current_tp = PositionGetDouble(POSITION_TP);
         double current_sl = PositionGetDouble(POSITION_SL);
         
         double new_tp = 0.0;
         if(TakeProfitPrice > 0.0)
            new_tp = NormalizePrice(entry + (direction == 0 ? TakeProfitPrice : -TakeProfitPrice));
            
         if(MathAbs(current_tp - new_tp) > _Point * 0.5)
            trade.PositionModify(ticket, current_sl, new_tp);
      }
   }
}

void AddTimeframe(const ENUM_TIMEFRAMES tf, const string name)
{
   int size = ArraySize(g_timeframes);
   ArrayResize(g_timeframes, size + 1);
   ArrayResize(g_tf_names, size + 1);
   ArrayResize(g_handles, size + 1);
   ArrayResize(g_last_bar_times, size + 1);
   ArrayResize(g_last_directions, size + 1);
   ArrayResize(g_last_st_prices, size + 1);
   ArrayResize(g_last_open_counts, size + 1);
   ArrayResize(g_last_pending_counts, size + 1);

   g_timeframes[size] = tf;
   g_tf_names[size] = name;
   g_handles[size] = INVALID_HANDLE;
   g_last_bar_times[size] = 0;
   g_last_directions[size] = -1;
   g_last_st_prices[size] = 0.0;
   g_last_open_counts[size] = 0;
   g_last_pending_counts[size] = 0;
}

void SetupTimeframes()
{
   ArrayResize(g_timeframes, 0);
   ArrayResize(g_tf_names, 0);
   ArrayResize(g_handles, 0);
   ArrayResize(g_last_bar_times, 0);
   ArrayResize(g_last_directions, 0);
   ArrayResize(g_last_st_prices, 0);
   ArrayResize(g_last_open_counts, 0);
   ArrayResize(g_last_pending_counts, 0);

   if(Trade_M1)  AddTimeframe(PERIOD_M1,  "M1");
   if(Trade_M2)  AddTimeframe(PERIOD_M2,  "M2");
   if(Trade_M3)  AddTimeframe(PERIOD_M3,  "M3");
   if(Trade_M5)  AddTimeframe(PERIOD_M5,  "M5");
   if(Trade_M15) AddTimeframe(PERIOD_M15, "M15");
   if(Trade_M30) AddTimeframe(PERIOD_M30, "M30");
   if(Trade_H1)  AddTimeframe(PERIOD_H1,  "H1");
}

int OnInit()
{
   if(LotSize <= 0.0 || RoundGapPrice <= 0.0 || MaxOrdersPerSignal <= 0 || TakeProfitPrice < 0.0)
      return INIT_PARAMETERS_INCORRECT;

   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(SlippagePoints);
   trade.SetTypeFillingBySymbol(_Symbol);

   SetupTimeframes();
   if(ArraySize(g_timeframes) == 0)
      return INIT_PARAMETERS_INCORRECT;

   for(int i = 0; i < ArraySize(g_timeframes); i++)
   {
      g_handles[i] = iCustom(_Symbol, g_timeframes[i], "\\Indicators\\Supertrend",
                             IndicatorPrefix, ATRMultiplier, ATRPeriod);
      if(g_handles[i] == INVALID_HANDLE)
      {
         Print("Failed to create SuperTrend handle for ", TimeframeTag(i), ". Error=", GetLastError());
         return INIT_FAILED;
      }

      int direction = -1;
      double st_price = 0.0;
      if(ReadSignalSnapshot(i, direction, st_price))
      {
         g_last_directions[i] = direction;
         g_last_st_prices[i] = st_price;
      }

      g_last_open_counts[i] = CountOpenPositionsForTimeframe(i);
      g_last_pending_counts[i] = CountPendingOrdersForTimeframe(i);
   }

   SeedUsedOrderPricesFromActiveTrades();

   for(int i = 0; i < ArraySize(g_timeframes); i++)
   {
      if(g_last_directions[i] != -1)
      {
         UpdateOrdersAndPositionsTP(i, g_last_directions[i]);
         RefreshPendingGridOnly(i, g_last_directions[i], g_last_st_prices[i]);
      }
   }

   EventSetTimer(1);
   UpdateProfitLabel();
   return INIT_SUCCEEDED;
}

void OnTick()
{
   UpdateProfitLabel();

   bool signal_changed[];
   bool line_changed[];
   bool count_changed[];
   ArrayResize(signal_changed, ArraySize(g_timeframes));
   ArrayResize(line_changed, ArraySize(g_timeframes));
   ArrayResize(count_changed, ArraySize(g_timeframes));

   for(int i = 0; i < ArraySize(g_timeframes); i++)
   {
      signal_changed[i] = false;
      line_changed[i] = false;
      count_changed[i] = false;

      int direction = -1;
      double st_price = 0.0;
      if(!ReadNewBarSignal(i, direction, st_price))
      {
         int open_count = CountOpenPositionsForTimeframe(i);
         int pending_count = CountPendingOrdersForTimeframe(i);
         if(open_count != g_last_open_counts[i] || pending_count != g_last_pending_counts[i])
         {
            g_last_open_counts[i] = open_count;
            g_last_pending_counts[i] = pending_count;
            count_changed[i] = true;
         }
         continue;
      }

      if(g_last_directions[i] == -1)
      {
         g_last_directions[i] = direction;
         g_last_st_prices[i] = st_price;
         signal_changed[i] = true;
      }
      else if(direction != g_last_directions[i])
      {
         g_last_directions[i] = direction;
         g_last_st_prices[i] = st_price;
         signal_changed[i] = true;
      }
      else if(MathAbs(st_price - g_last_st_prices[i]) > (_Point * 0.5))
      {
         g_last_st_prices[i] = st_price;
         line_changed[i] = true;
      }

      g_last_open_counts[i] = CountOpenPositionsForTimeframe(i);
      g_last_pending_counts[i] = CountPendingOrdersForTimeframe(i);
   }

   for(int i = 0; i < ArraySize(g_timeframes); i++)
   {
      if(signal_changed[i])
      {
         ApplySignalGrid(i, g_last_directions[i], g_last_st_prices[i]);
      }
      else
      {
         bool needs_refresh = false;
         
         if(line_changed[i] || (count_changed[i] && g_last_directions[i] != -1))
         {
            needs_refresh = true;
         }
         else if(g_last_directions[i] != -1)
         {
            for(int j = 0; j < i; j++)
            {
               if(signal_changed[j]) 
               {
                  needs_refresh = true;
                  break;
               }
               if(line_changed[j] && g_last_directions[j] == g_last_directions[i])
               {
                  needs_refresh = true;
                  break;
               }
            }
         }
         
         if(needs_refresh)
         {
            RefreshPendingGridOnly(i, g_last_directions[i], g_last_st_prices[i]);
         }
      }
   }
}

void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
{
   if(trans.symbol != _Symbol)
      return;

   if(trans.type == TRADE_TRANSACTION_DEAL_ADD)
      UpdateProfitLabel();
}

void OnTimer()
{
   UpdateProfitLabel();
}

void OnDeinit(const int reason)
{
   EventKillTimer();
   ObjectDelete(0, ProfitLabelName());

   for(int i = 0; i < ArraySize(g_handles); i++)
   {
      if(g_handles[i] != INVALID_HANDLE)
         IndicatorRelease(g_handles[i]);
   }
}

//+------------------------------------------------------------------+
