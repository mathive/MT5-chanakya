//+------------------------------------------------------------------+
//|                          SuperTrendRoundNumberGrid_M5.mq5        |
//|      M5-only SuperTrend flip EA with round-number pending grid   |
//+------------------------------------------------------------------+
#property copyright "Chanakya"
#property link      "https://www.mql5.com"
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>

input group "SuperTrend"
input ENUM_TIMEFRAMES SignalTimeframe = PERIOD_M5; // SuperTrend signal timeframe, independent of chart timeframe
input double   ATRMultiplier = 9.0;             // SuperTrend ATR multiplier
input int      ATRPeriod = 27;                  // SuperTrend ATR period
input string   IndicatorPrefix = "SPRTRND";     // SuperTrend object prefix

input group "Grid"
input double   LotSize = 0.01;                  // Pending order lot size
input double   RoundGapPrice = 1.0;             // Gap between round-number levels
input int      MaxOrdersPerSignal = 100;        // Safety cap per signal
input double   TakeProfitPrice = 1.0;           // TP distance in price, shown on chart via order TP
input bool     RepeatOrderForSamePrice = true;  // Allow repeated orders at same TF/trend/price

input group "Execution"
input int      MagicNumber = 551005;            // EA magic number
input int      SlippagePoints = 3;              // Slippage in points

CTrade trade;
int g_supertrend_handle = INVALID_HANDLE;
datetime g_last_signal_bar_time = 0;
int g_last_direction = -1; // 0 = buy/uptrend, 1 = sell/downtrend
double g_last_st_price = 0.0;
string g_used_order_keys[];

double NormalizePrice(const double price)
{
   return NormalizeDouble(price, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS));
}

string OrderRepeatKey(const int direction, const double price)
{
   return EnumToString(SignalTimeframe) + "|" + IntegerToString(direction) + "|" + DoubleToString(NormalizePrice(price), _Digits);
}

bool IsOrderPriceUsed(const int direction, const double price)
{
   if(RepeatOrderForSamePrice)
      return false;

   string key = OrderRepeatKey(direction, price);
   for(int i = 0; i < ArraySize(g_used_order_keys); i++)
   {
      if(g_used_order_keys[i] == key)
         return true;
   }

   return false;
}

void RememberOrderPrice(const int direction, const double price)
{
   if(RepeatOrderForSamePrice)
      return;

   string key = OrderRepeatKey(direction, price);
   for(int i = 0; i < ArraySize(g_used_order_keys); i++)
   {
      if(g_used_order_keys[i] == key)
         return;
   }

   int size = ArraySize(g_used_order_keys);
   ArrayResize(g_used_order_keys, size + 1);
   g_used_order_keys[size] = key;
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

void DeleteOrderByTicket(const ulong ticket)
{
   trade.SetExpertMagicNumber(MagicNumber);
   if(!trade.OrderDelete(ticket))
   {
      Print("Delete order failed ticket=", ticket,
            " retcode=", trade.ResultRetcode(),
            " msg=", trade.ResultRetcodeDescription());
   }
}

void CancelAllOurPendingOrders()
{
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0 || !OrderSelect(ticket))
         continue;

      if(OrderGetString(ORDER_SYMBOL) != _Symbol)
         continue;

      if(OrderGetInteger(ORDER_MAGIC) != MagicNumber)
         continue;

      ENUM_ORDER_TYPE type = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
      if(type != ORDER_TYPE_BUY_LIMIT && type != ORDER_TYPE_SELL_LIMIT)
         continue;

      DeleteOrderByTicket(ticket);
   }
}

void CloseAllOurPositions()
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

      if(!trade.PositionClose(ticket))
      {
         Print("Close position failed ticket=", ticket,
               " retcode=", trade.ResultRetcode(),
               " msg=", trade.ResultRetcodeDescription());
      }
   }
}

void SeedUsedOrderPricesFromActiveTrades()
{
   if(RepeatOrderForSamePrice)
      return;

   ArrayResize(g_used_order_keys, 0);

   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0 || !OrderSelect(ticket))
         continue;

      if(OrderGetString(ORDER_SYMBOL) != _Symbol)
         continue;
      if(OrderGetInteger(ORDER_MAGIC) != MagicNumber)
         continue;

      ENUM_ORDER_TYPE type = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
      if(type == ORDER_TYPE_BUY_LIMIT)
         RememberOrderPrice(0, OrderGetDouble(ORDER_PRICE_OPEN));
      else if(type == ORDER_TYPE_SELL_LIMIT)
         RememberOrderPrice(1, OrderGetDouble(ORDER_PRICE_OPEN));
   }

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;

      if(PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;
      if(PositionGetInteger(POSITION_MAGIC) != MagicNumber)
         continue;

      ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      if(type == POSITION_TYPE_BUY)
         RememberOrderPrice(0, PositionGetDouble(POSITION_PRICE_OPEN));
      else if(type == POSITION_TYPE_SELL)
         RememberOrderPrice(1, PositionGetDouble(POSITION_PRICE_OPEN));
   }
}

bool PlaceBuyGridToSupport(const double support_price)
{
   double start_level = GetBuyStartLevel();
   if(start_level < support_price + (_Point * 0.5))
      return false;

   int placed = 0;
   for(double price = start_level; price >= support_price - (_Point * 0.5) && placed < MaxOrdersPerSignal; price -= RoundGapPrice)
   {
      double entry = NormalizePrice(price);
      if(entry < support_price - (_Point * 0.5))
         continue;
      if(IsOrderPriceUsed(0, entry))
         continue;

      double tp_price = 0.0;
      if(TakeProfitPrice > 0.0)
         tp_price = NormalizePrice(entry + TakeProfitPrice);

      if(!trade.BuyLimit(LotSize, entry, _Symbol, 0.0, tp_price, ORDER_TIME_GTC, 0, "ST Buy Grid"))
      {
         Print("BuyLimit failed at ", DoubleToString(entry, _Digits),
               " retcode=", trade.ResultRetcode(),
               " msg=", trade.ResultRetcodeDescription());
      }
      else
      {
         RememberOrderPrice(0, entry);
         placed++;
      }
   }

   return (placed > 0);
}

bool PlaceSellGridToResistance(const double resistance_price)
{
   double start_level = GetSellStartLevel();
   if(start_level > resistance_price - (_Point * 0.5))
      return false;

   int placed = 0;
   for(double price = start_level; price <= resistance_price + (_Point * 0.5) && placed < MaxOrdersPerSignal; price += RoundGapPrice)
   {
      double entry = NormalizePrice(price);
      if(entry > resistance_price + (_Point * 0.5))
         continue;
      if(IsOrderPriceUsed(1, entry))
         continue;

      double tp_price = 0.0;
      if(TakeProfitPrice > 0.0)
         tp_price = NormalizePrice(entry - TakeProfitPrice);

      if(!trade.SellLimit(LotSize, entry, _Symbol, 0.0, tp_price, ORDER_TIME_GTC, 0, "ST Sell Grid"))
      {
         Print("SellLimit failed at ", DoubleToString(entry, _Digits),
               " retcode=", trade.ResultRetcode(),
               " msg=", trade.ResultRetcodeDescription());
      }
      else
      {
         RememberOrderPrice(1, entry);
         placed++;
      }
   }

   return (placed > 0);
}

bool ReadCurrentSignal(int &direction, double &st_price)
{
   if(g_supertrend_handle == INVALID_HANDLE)
      return false;

   datetime times[1];
   if(CopyTime(_Symbol, SignalTimeframe, 0, 1, times) < 1)
      return false;

   if(times[0] == g_last_signal_bar_time)
      return false;

   g_last_signal_bar_time = times[0];

   double direction_buffer[2];
   if(CopyBuffer(g_supertrend_handle, 2, 1, 2, direction_buffer) < 2)
   {
      Print("CopyBuffer direction failed. Error=", GetLastError());
      return false;
   }

   double line_buffer[1];
   if(CopyBuffer(g_supertrend_handle, 0, 1, 1, line_buffer) < 1)
   {
      Print("CopyBuffer line failed. Error=", GetLastError());
      return false;
   }

   direction = (int)direction_buffer[0];
   st_price = NormalizePrice(line_buffer[0]);
   return true;
}

void ApplySignalGrid(const int direction, const double st_price)
{
   CloseAllOurPositions();
   CancelAllOurPendingOrders();

   if(direction == 0)
   {
      if(!PlaceBuyGridToSupport(st_price))
         Print("Buy grid not placed. Start/support invalid. Start=", DoubleToString(GetBuyStartLevel(), _Digits),
               " support=", DoubleToString(st_price, _Digits));
   }
   else if(direction == 1)
   {
      if(!PlaceSellGridToResistance(st_price))
         Print("Sell grid not placed. Start/resistance invalid. Start=", DoubleToString(GetSellStartLevel(), _Digits),
               " resistance=", DoubleToString(st_price, _Digits));
   }
}

void RefreshPendingGridOnly(const int direction, const double st_price)
{
   CancelAllOurPendingOrders();

   if(direction == 0)
   {
      if(!PlaceBuyGridToSupport(st_price))
         Print("Buy grid refresh not placed. Start/support invalid. Start=", DoubleToString(GetBuyStartLevel(), _Digits),
               " support=", DoubleToString(st_price, _Digits));
   }
   else if(direction == 1)
   {
      if(!PlaceSellGridToResistance(st_price))
         Print("Sell grid refresh not placed. Start/resistance invalid. Start=", DoubleToString(GetSellStartLevel(), _Digits),
               " resistance=", DoubleToString(st_price, _Digits));
   }
}

bool LoadCurrentSignalSnapshot(int &direction, double &st_price)
{
   if(g_supertrend_handle == INVALID_HANDLE)
      return false;

   double direction_buffer[1];
   if(CopyBuffer(g_supertrend_handle, 2, 1, 1, direction_buffer) < 1)
   {
      Print("CopyBuffer snapshot direction failed. Error=", GetLastError());
      return false;
   }

   double line_buffer[1];
   if(CopyBuffer(g_supertrend_handle, 0, 1, 1, line_buffer) < 1)
   {
      Print("CopyBuffer snapshot line failed. Error=", GetLastError());
      return false;
   }

   direction = (int)direction_buffer[0];
   st_price = NormalizePrice(line_buffer[0]);
   return true;
}

int OnInit()
{
   if(LotSize <= 0.0 || RoundGapPrice <= 0.0 || MaxOrdersPerSignal <= 0 || TakeProfitPrice < 0.0)
      return INIT_PARAMETERS_INCORRECT;

   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(SlippagePoints);
   trade.SetTypeFillingBySymbol(_Symbol);

   g_supertrend_handle = iCustom(_Symbol, SignalTimeframe, "\\Indicators\\Supertrend",
                                 IndicatorPrefix, ATRMultiplier, ATRPeriod);
   if(g_supertrend_handle == INVALID_HANDLE)
   {
      Print("Failed to create SuperTrend handle. Error=", GetLastError());
      return INIT_FAILED;
   }

   int current_direction = -1;
   double current_st_price = 0.0;
   if(LoadCurrentSignalSnapshot(current_direction, current_st_price))
   {
      SeedUsedOrderPricesFromActiveTrades();
      g_last_direction = current_direction;
      g_last_st_price = current_st_price;
      ApplySignalGrid(current_direction, current_st_price);
   }

   return INIT_SUCCEEDED;
}

void OnTick()
{
   int direction = -1;
   double st_price = 0.0;
   if(!ReadCurrentSignal(direction, st_price))
      return;

   if(g_last_direction == -1)
   {
      g_last_direction = direction;
      g_last_st_price = st_price;
      ApplySignalGrid(direction, st_price);
      return;
   }

   if(direction != g_last_direction)
   {
      g_last_direction = direction;
      g_last_st_price = st_price;
      ApplySignalGrid(direction, st_price);
   }
   else if(MathAbs(st_price - g_last_st_price) > (_Point * 0.5))
   {
      g_last_st_price = st_price;
      RefreshPendingGridOnly(direction, st_price);
   }
}

void OnDeinit(const int reason)
{
   if(g_supertrend_handle != INVALID_HANDLE)
      IndicatorRelease(g_supertrend_handle);
}

//+------------------------------------------------------------------+
