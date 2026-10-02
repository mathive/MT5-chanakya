//+------------------------------------------------------------------+
//|                                HA_EMA_RoundNumberGrid_XAUUSD.mq5 |
//|   Virtual Heiken Ashi + EMA Trend Flip Round-Number Grid EA      |
//|    (Exact Round Number Triggers: 1:1=1, 2:2=2, 3:3=3, 10:10=10)  |
//+------------------------------------------------------------------+
#property copyright "Chanakya"
#property link      "https://www.mql5.com"
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>

input group "EMA Filter & Signal Settings"
input bool            InpUseEMAFilter = true;             // Buy above EMA, sell below EMA
input int             InpEMAPeriod = 200;                 // EMA filter period
input ENUM_TIMEFRAMES InpSignalTimeframe = PERIOD_M5;     // Signal timeframe (independent of chart TF)
input bool            InpBookProfitOnlyOnSignalFlip = false; // Book profit only on signal flip (Disable step TP)
input bool            InpCloseOppositeOnFlip = true;      // Close opposite positions when trend flips
input bool            InpAllowBuy = true;                 // Allow BUY grid
input bool            InpAllowSell = true;                // Allow SELL grid
input bool            InpTradeCurrentFlipOnStartup = true;// Trade immediately on current signal at startup

input group "Grid Mode Presets (1:1 to 10:10)"
input bool Enable_1_1   = true;   // 1:1 (Step: 1.0, Dynamic TP: 1.0) -> on every integer (..., 1, 2, 3, ...)
input bool Enable_2_2   = true;  // 2:2 (Step: 2.0, Dynamic TP: 2.0) -> on multiples of 2 (..., 2, 4, 6, ...)
input bool Enable_3_3   = true;  // 3:3 (Step: 3.0, Dynamic TP: 3.0) -> on multiples of 3 (..., 3, 6, 9, ...)
input bool Enable_4_4   = true;  // 4:4 (Step: 4.0, Dynamic TP: 4.0) -> on multiples of 4 (..., 4, 8, 12, ...)
input bool Enable_5_5   = true;  // 5:5 (Step: 5.0, Dynamic TP: 5.0) -> on multiples of 5 (..., 5, 10, 15, ...)
input bool Enable_6_6   = true;  // 6:6 (Step: 6.0, Dynamic TP: 6.0) -> on multiples of 6 (..., 6, 12, 18, ...)
input bool Enable_7_7   = true;  // 7:7 (Step: 7.0, Dynamic TP: 7.0) -> on multiples of 7 (..., 7, 14, 21, ...)
input bool Enable_8_8   = true;  // 8:8 (Step: 8.0, Dynamic TP: 8.0) -> on multiples of 8 (..., 8, 16, 24, ...)
input bool Enable_9_9   = true;  // 9:9 (Step: 9.0, Dynamic TP: 9.0) -> on multiples of 9 (..., 9, 18, 27, ...)
input bool Enable_10_10 = true;  // 10:10 (Step: 10.0, Dynamic TP: 10.0) -> on 10, 20, 30, 40...

input group "Custom Grid (Used if all presets above are false)"
input double RoundStepPrice = 1.0;           // Custom step price
input double TargetPriceDistance = 1.0;     // Custom dynamic TP distance

input group "Grid Settings"
input double   LotSize = 0.01;                 // Base lot size (1:1=0.01, 2:2=0.02 ... 10:10=0.10)
input int      StopLossPoints = 0;             // 0 = no stop loss, otherwise SL distance in round-step levels
input int      FailedOrderRetrySeconds = 3;    // Cooldown after failed trade execution

input group "Broker Protection & Rate Limiting"
input bool     UseServerSideTP = true;         // Set Take-Profit on broker server at entry (Reduces server load & 0 latency)
input int      MinOrderIntervalMs = 350;       // Minimum delay between order requests in ms (Anti-flood)
input int      CloseRetryCooldownSeconds = 3;  // Cooldown before retrying position close on same ticket

input group "System"
input int      MagicNumber = 881100;           // Base EA magic number
input int      SlippagePoints = 3;             // Allowed slippage
input bool     OnlyXauSymbols = true;          // Warn if chart is not XAU/GOLD
input double   MaxAccountDrawdownPercent = 80.0; // Stop new trades and close positions at this account drawdown
input double   MaxSessionProfitMoney = 0.0;    // 0 = unlimited; otherwise close EA positions, wait for next date
input bool     CloseBeforeMarketClose = false; // Close EA positions before market close
input int      MinutesBeforeMarketClose = 10;  // Minutes before session close to stop/close this EA

input group "Display Dashboard"
input bool     ShowProfitLabel = true;         // Show dashboard on chart
input int      ProfitLabelFontSize = 14;       // Dashboard font size
input bool     HideChartTradeLevels = true;    // Hide broker default trade level lines & arrows on chart

input group "Display Chart Level Settings (Pending & TP per Preset)"
input bool Show_1_1_Pending = false;    // 1:1 Show Pending/Grid Lines (Dotted)
input bool Show_1_1_TP      = false;    // 1:1 Show Dynamic TP Lines (Plain)

input bool Show_2_2_Pending = false;   // 2:2 Show Pending/Grid Lines (Dotted)
input bool Show_2_2_TP      = false;   // 2:2 Show Dynamic TP Lines (Plain)

input bool Show_3_3_Pending = false;   // 3:3 Show Pending/Grid Lines (Dotted)
input bool Show_3_3_TP      = false;   // 3:3 Show Dynamic TP Lines (Plain)

input bool Show_4_4_Pending = false;   // 4:4 Show Pending/Grid Lines (Dotted)
input bool Show_4_4_TP      = false;   // 4:4 Show Dynamic TP Lines (Plain)

input bool Show_5_5_Pending = false;   // 5:5 Show Pending/Grid Lines (Dotted)
input bool Show_5_5_TP      = false;   // 5:5 Show Dynamic TP Lines (Plain)

input bool Show_6_6_Pending = false;   // 6:6 Show Pending/Grid Lines (Dotted)
input bool Show_6_6_TP      = false;   // 6:6 Show Dynamic TP Lines (Plain)

input bool Show_7_7_Pending = false;   // 7:7 Show Pending/Grid Lines (Dotted)
input bool Show_7_7_TP      = false;   // 7:7 Show Dynamic TP Lines (Plain)

input bool Show_8_8_Pending = false;   // 8:8 Show Pending/Grid Lines (Dotted)
input bool Show_8_8_TP      = false;   // 8:8 Show Dynamic TP Lines (Plain)

input bool Show_9_9_Pending = false;   // 9:9 Show Pending/Grid Lines (Dotted)
input bool Show_9_9_TP      = false;   // 9:9 Show Dynamic TP Lines (Plain)

input bool Show_10_10_Pending = false; // 10:10 Show Pending/Grid Lines (Dotted)
input bool Show_10_10_TP      = false; // 10:10 Show Dynamic TP Lines (Plain)

input bool Show_Custom_Pending = false;// Custom Show Pending/Grid Lines (Dotted)
input bool Show_Custom_TP      = false;// Custom Show Dynamic TP Lines (Plain)

input int  ChartDisplayLevelsCount = 5;// Number of nearest grid levels to show

input group "Preset Colors (Dotted = Pending/Grid, Plain = Take-Profit)"
input color Color_1_1    = clrDeepSkyBlue;  // 1:1 Color
input color Color_2_2    = clrGold;         // 2:2 Color
input color Color_3_3    = clrMagenta;      // 3:3 Color
input color Color_4_4    = clrTurquoise;    // 4:4 Color
input color Color_5_5    = clrLimeGreen;    // 5:5 Color
input color Color_6_6    = clrCoral;        // 6:6 Color
input color Color_7_7    = clrMediumPurple; // 7:7 Color
input color Color_8_8    = clrYellowGreen;  // 8:8 Color
input color Color_9_9    = clrHotPink;      // 9:9 Color
input color Color_10_10  = clrAqua;         // 10:10 Color
input color Color_Custom = clrSilver;       // Custom Color

#define MAX_GRID_SCAN_DEPTH 50

CTrade trade;

struct GridStream
{
   int      id;
   double   step;
   double   tp_dist;
   int      magic;
   string   name;
   bool     show_pending;
   bool     show_tp;
   color    preset_color;
   double   lot_size;
   
   double   last_failed_buy_level;
   datetime last_failed_buy_time;
   double   last_failed_sell_level;
   datetime last_failed_sell_time;
};

GridStream g_streams[];

int             g_ema_handle = INVALID_HANDLE;
datetime        g_last_signal_bar_time = 0;
int             g_current_signal = 0; // 1 = Bullish, -1 = Bearish, 0 = None
bool            g_startup_checked = false;

datetime g_session_start_time = 0;
bool     g_session_profit_locked = false;
datetime g_last_session_close_day = 0;

string ProfitLabelName()
{
   return "HA_EMA_Grid_Profit_Label_" + IntegerToString(MagicNumber);
}

bool IsBuyActive()
{
   return (InpAllowBuy && g_current_signal == 1);
}

bool IsSellActive()
{
   return (InpAllowSell && g_current_signal == -1);
}

string PositionCommentPrefix(const ENUM_POSITION_TYPE position_type, const string stream_name)
{
   return (position_type == POSITION_TYPE_SELL) ? ("HA_RSell_" + stream_name + " ") : ("HA_RBuy_" + stream_name + " ");
}

bool TryGetLevelFromComment(const string comment, const string stream_name, double &level_price)
{
   string buy_prefix = PositionCommentPrefix(POSITION_TYPE_BUY, stream_name);
   if(StringSubstr(comment, 0, StringLen(buy_prefix)) == buy_prefix)
   {
      string price_text = StringSubstr(comment, StringLen(buy_prefix));
      level_price = StringToDouble(price_text);
      return (level_price > 0.0);
   }

   string sell_prefix = PositionCommentPrefix(POSITION_TYPE_SELL, stream_name);
   if(StringSubstr(comment, 0, StringLen(sell_prefix)) == sell_prefix)
   {
      string price_text = StringSubstr(comment, StringLen(sell_prefix));
      level_price = StringToDouble(price_text);
      return (level_price > 0.0);
   }

   return false;
}

double NormalizePrice(const double price)
{
   return NormalizeDouble(price, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS));
}

// Returns the closest round level at or below price that is an exact multiple of step
double GetNearestRoundLevelBelow(const double price, const double step)
{
   if(step <= 0.0)
      return 0.0;
   double step_count = MathFloor((price + 0.0000001) / step);
   return NormalizePrice(step_count * step);
}

// Returns the closest round level at or above price that is an exact multiple of step
double GetNearestRoundLevelAbove(const double price, const double step)
{
   if(step <= 0.0)
      return 0.0;
   double step_count = MathCeil((price - 0.0000001) / step);
   return NormalizePrice(step_count * step);
}

double GetStopLossDistancePrice(const double step)
{
   if(StopLossPoints <= 0)
      return 0.0;

   return StopLossPoints * step;
}

bool IsOurMagic(const long magic)
{
   if(magic == MagicNumber)
      return true;

   if(magic >= MagicNumber + 1 && magic <= MagicNumber + 10)
      return true;

   for(int i = 0; i < ArraySize(g_streams); i++)
   {
      if(magic == g_streams[i].magic)
         return true;
   }
   return false;
}

bool IsOurPositionAtLevel(const GridStream &stream, const double level_price, const ENUM_POSITION_TYPE position_type)
{
   double tolerance = MathMax(_Point * 0.5, stream.step * 0.49);

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;

      if(PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;

      if(PositionGetInteger(POSITION_MAGIC) != stream.magic)
         continue;

      if(PositionGetInteger(POSITION_TYPE) != position_type)
         continue;

      double level = 0.0;
      if(TryGetLevelFromComment(PositionGetString(POSITION_COMMENT), stream.name, level))
      {
         if(MathAbs(level - level_price) <= tolerance)
            return true;
      }
      else
      {
         double open_price = PositionGetDouble(POSITION_PRICE_OPEN);
         double mapped_level = (position_type == POSITION_TYPE_BUY) ?
                               NormalizePrice(MathFloor((open_price + (_Point * 0.5)) / stream.step) * stream.step) :
                               NormalizePrice(MathCeil((open_price - (_Point * 0.5)) / stream.step) * stream.step);
         if(MathAbs(mapped_level - level_price) <= tolerance)
            return true;
      }
   }

   return false;
}

void ClosePositionsForStream(const GridStream &stream, const ENUM_POSITION_TYPE position_type)
{
   trade.SetDeviationInPoints(SlippagePoints);
   trade.SetExpertMagicNumber(stream.magic);

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;

      if(PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;

      if(PositionGetInteger(POSITION_MAGIC) != stream.magic)
         continue;

      if((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) != position_type)
         continue;

      if(!trade.PositionClose(ticket))
      {
         Print("Position close failed [", stream.name, "] ticket=", ticket,
               " retcode=", trade.ResultRetcode(),
               " message=", trade.ResultRetcodeDescription());
      }
   }
}

void DeleteOrderByTicket(const ulong ticket, const int magic)
{
   trade.SetExpertMagicNumber(magic);
   if(!trade.OrderDelete(ticket))
   {
      Print("Delete order failed ticket=", ticket, " magic=", magic,
            " retcode=", trade.ResultRetcode(),
            " message=", trade.ResultRetcodeDescription());
   }
}

void CancelPendingOrdersForStream(const GridStream &stream, const ENUM_POSITION_TYPE position_type)
{
   ENUM_ORDER_TYPE order_type = (position_type == POSITION_TYPE_SELL) ? ORDER_TYPE_SELL_LIMIT : ORDER_TYPE_BUY_LIMIT;

   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0 || !OrderSelect(ticket))
         continue;

      if(OrderGetString(ORDER_SYMBOL) != _Symbol)
         continue;

      if(OrderGetInteger(ORDER_MAGIC) != stream.magic)
         continue;

      if((ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE) != order_type)
         continue;

      DeleteOrderByTicket(ticket, stream.magic);
   }
}

void CloseOurPositionsByType(const ENUM_POSITION_TYPE pos_type)
{
   trade.SetDeviationInPoints(SlippagePoints);

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;

      if(PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;

      long magic = PositionGetInteger(POSITION_MAGIC);
      if(!IsOurMagic(magic))
         continue;

      if((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) != pos_type)
         continue;

      trade.SetExpertMagicNumber((int)magic);
      if(!trade.PositionClose(ticket))
      {
         Print("Signal Flip close failed ticket=", ticket,
               " retcode=", trade.ResultRetcode(),
               " message=", trade.ResultRetcodeDescription());
      }
   }
}

void CloseAllOurPositions()
{
   trade.SetDeviationInPoints(SlippagePoints);

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;

      if(PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;

      long magic = PositionGetInteger(POSITION_MAGIC);
      if(!IsOurMagic(magic))
         continue;

      trade.SetExpertMagicNumber((int)magic);
      if(!trade.PositionClose(ticket))
      {
         Print("Position close failed ticket=", ticket,
               " retcode=", trade.ResultRetcode(),
               " message=", trade.ResultRetcodeDescription());
      }
   }
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

void ResetSessionLockIfNeeded()
{
   datetime current_session_start = GetCurrentSessionStart();

   if(g_session_start_time == current_session_start)
      return;

   g_session_start_time = current_session_start;
   g_session_profit_locked = false;
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

string GetSignalSummary()
{
   if(g_current_signal == 1)
      return "BULLISH (BUY GRID ACTIVE)";
   else if(g_current_signal == -1)
      return "BEARISH (SELL GRID ACTIVE)";
   return "NEUTRAL (WAITING SIGNAL)";
}

struct StreamProfitData
{
   double realized_today;
   double floating;
};

void CalculateProfits(double &total_realized_today, double &total_history_realized, double &total_floating, StreamProfitData &stream_data[])
{
   datetime now = TimeCurrent();
   datetime today_start = GetCurrentSessionStart();

   total_realized_today = 0.0;
   total_history_realized = 0.0;
   total_floating = 0.0;

   int num_streams = ArraySize(g_streams);
   ArrayResize(stream_data, num_streams);
   for(int s = 0; s < num_streams; s++)
   {
      stream_data[s].realized_today = 0.0;
      stream_data[s].floating = 0.0;
   }

   // 1. Calculate Floating Profit from Open Positions
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;

      if(PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;

      long pos_magic = PositionGetInteger(POSITION_MAGIC);
      double pos_pnl = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);

      if(IsOurMagic(pos_magic))
      {
         total_floating += pos_pnl;

         for(int s = 0; s < num_streams; s++)
         {
            if(pos_magic == g_streams[s].magic)
            {
               stream_data[s].floating += pos_pnl;
               break;
            }
         }
      }
   }

   // 2. Select full history ONCE (never select by position inside loop to prevent cache corruption)
   if(!HistorySelect(0, now))
      return;

   int total_deals = HistoryDealsTotal();
   if(total_deals <= 0)
      return;

   // Pass 1: Build pos_id -> magic mapping from all DEAL_ENTRY_IN deals
   struct PosMagicMap
   {
      long pos_id;
      long magic;
   };
   PosMagicMap pos_map[];
   ArrayResize(pos_map, 0);

   for(int i = 0; i < total_deals; i++)
   {
      ulong d_ticket = HistoryDealGetTicket(i);
      if(d_ticket == 0) continue;

      if(HistoryDealGetString(d_ticket, DEAL_SYMBOL) != _Symbol)
         continue;

      ENUM_DEAL_ENTRY entry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(d_ticket, DEAL_ENTRY);
      if(entry == DEAL_ENTRY_IN)
      {
         long m = HistoryDealGetInteger(d_ticket, DEAL_MAGIC);
         if(IsOurMagic(m))
         {
            long p_id = HistoryDealGetInteger(d_ticket, DEAL_POSITION_ID);
            int sz = ArraySize(pos_map);
            ArrayResize(pos_map, sz + 1);
            pos_map[sz].pos_id = p_id;
            pos_map[sz].magic = m;
         }
      }
   }

   // Pass 2: Process all exit deals (DEAL_ENTRY_OUT / INOUT / OUT_BY)
   for(int i = 0; i < total_deals; i++)
   {
      ulong d_ticket = HistoryDealGetTicket(i);
      if(d_ticket == 0) continue;

      if(HistoryDealGetString(d_ticket, DEAL_SYMBOL) != _Symbol)
         continue;

      ENUM_DEAL_ENTRY entry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(d_ticket, DEAL_ENTRY);
      if(entry != DEAL_ENTRY_OUT && entry != DEAL_ENTRY_INOUT && entry != DEAL_ENTRY_OUT_BY)
         continue;

      long deal_magic = HistoryDealGetInteger(d_ticket, DEAL_MAGIC);
      long pos_id = HistoryDealGetInteger(d_ticket, DEAL_POSITION_ID);

      // If closed manually (deal_magic == 0), lookup from our pos_map
      if(deal_magic == 0 && pos_id > 0)
      {
         for(int m = ArraySize(pos_map) - 1; m >= 0; m--)
         {
            if(pos_map[m].pos_id == pos_id)
            {
               deal_magic = pos_map[m].magic;
               break;
            }
         }
      }

      if(!IsOurMagic(deal_magic))
         continue;

      double deal_pnl = HistoryDealGetDouble(d_ticket, DEAL_PROFIT) +
                        HistoryDealGetDouble(d_ticket, DEAL_SWAP) +
                        HistoryDealGetDouble(d_ticket, DEAL_COMMISSION);

      datetime deal_time = (datetime)HistoryDealGetInteger(d_ticket, DEAL_TIME);

      // Add to Total History Realized
      total_history_realized += deal_pnl;

      // Add to Today's Realized if within today's session
      if(deal_time >= today_start)
      {
         total_realized_today += deal_pnl;

         for(int s = 0; s < num_streams; s++)
         {
            if(deal_magic == g_streams[s].magic)
            {
               stream_data[s].realized_today += deal_pnl;
               break;
            }
         }
      }
   }
}

double GetTodayRealizedProfit()
{
   double realized_today = 0.0, history_realized = 0.0, floating = 0.0;
   StreamProfitData s_data[];
   CalculateProfits(realized_today, history_realized, floating, s_data);
   return realized_today;
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
      floating_profit += PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
   }
   return floating_profit;
}

struct OpenPositionsStats
{
   int    buy_count;
   int    sell_count;
   double buy_lots;
   double sell_lots;
   double buy_mean_price;
   double sell_mean_price;
};

void GetOpenPositionsStats(OpenPositionsStats &stats)
{
   stats.buy_count = 0;
   stats.sell_count = 0;
   stats.buy_lots = 0.0;
   stats.sell_lots = 0.0;
   stats.buy_mean_price = 0.0;
   stats.sell_mean_price = 0.0;

   double buy_weight_sum = 0.0;
   double sell_weight_sum = 0.0;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;

      if(PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;

      if(!IsOurMagic(PositionGetInteger(POSITION_MAGIC)))
         continue;

      ENUM_POSITION_TYPE p_type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      double vol = PositionGetDouble(POSITION_VOLUME);
      double open_price = PositionGetDouble(POSITION_PRICE_OPEN);

      if(p_type == POSITION_TYPE_BUY)
      {
         stats.buy_count++;
         stats.buy_lots += vol;
         buy_weight_sum += (open_price * vol);
      }
      else if(p_type == POSITION_TYPE_SELL)
      {
         stats.sell_count++;
         stats.sell_lots += vol;
         sell_weight_sum += (open_price * vol);
      }
   }

   if(stats.buy_lots > 0.0)
      stats.buy_mean_price = buy_weight_sum / stats.buy_lots;

   if(stats.sell_lots > 0.0)
      stats.sell_mean_price = sell_weight_sum / stats.sell_lots;
}

bool GetAccountCurrencyToInrRate(double &rate)
{
   rate = 0.0;
   string acc_curr = AccountInfoString(ACCOUNT_CURRENCY);
   StringToUpper(acc_curr);
   StringTrimLeft(acc_curr);
   StringTrimRight(acc_curr);

   if(acc_curr == "INR")
   {
      rate = 1.0;
      return true;
   }

   // Cent accounts detection (1 USC = 0.01 USD)
   double cent_multiplier = 1.0;
   string base_curr = acc_curr;

   if(acc_curr == "USC" || acc_curr == "USCENT" || acc_curr == "USDC" || acc_curr == "CENT" || acc_curr == "USD_CENT")
   {
      base_curr = "USD";
      cent_multiplier = 0.01;
   }
   else if(acc_curr == "EUC" || acc_curr == "EURC" || acc_curr == "EUX" || acc_curr == "EUR_CENT")
   {
      base_curr = "EUR";
      cent_multiplier = 0.01;
   }
   else if(acc_curr == "GBC" || acc_curr == "GBPC" || acc_curr == "GBX" || acc_curr == "GBP_CENT")
   {
      base_curr = "GBP";
      cent_multiplier = 0.01;
   }

   // Direct check on common USDINR symbol variants
   if(base_curr == "USD")
   {
      string candidates[] = {
         "USDINR", "USDINR.sc", "USDINR.ecn", "USDINR_i", "USDINR.", "USD/INR", 
         "USDINR_", "USDINR-", "USDINR#", "USDINR.r", "USDINR.pro", "USDINR_m"
      };
      for(int i = 0; i < ArraySize(candidates); i++)
      {
         double bid = SymbolInfoDouble(candidates[i], SYMBOL_BID);
         if(bid > 0.0)
         {
            rate = bid * cent_multiplier;
            return true;
         }
      }
   }

   // Search Market Watch & all symbols for base_curr + INR
   int total = SymbolsTotal(false);
   for(int i = 0; i < total; i++)
   {
      string s = SymbolName(i, false);
      string b = SymbolInfoString(s, SYMBOL_CURRENCY_BASE);
      string p = SymbolInfoString(s, SYMBOL_CURRENCY_PROFIT);

      if((b == base_curr && p == "INR") || (StringFind(s, base_curr) >= 0 && StringFind(s, "INR") >= 0))
      {
         double bid = SymbolInfoDouble(s, SYMBOL_BID);
         if(bid > 0.0)
         {
            rate = bid * cent_multiplier;
            return true;
         }
      }
   }

   // Fallback: Check if broker has INR quotes against EUR, GBP, etc.
   double usd_to_inr = 0.0;
   for(int i = 0; i < total; i++)
   {
      string s = SymbolName(i, false);
      if(StringFind(s, "USD") >= 0 && StringFind(s, "INR") >= 0)
      {
         double bid = SymbolInfoDouble(s, SYMBOL_BID);
         if(bid > 0.0)
         {
            usd_to_inr = bid;
            break;
         }
      }
   }

   if(usd_to_inr > 0.0)
   {
      if(base_curr == "USD")
      {
         rate = usd_to_inr * cent_multiplier;
         return true;
      }
      else
      {
         double base_to_usd = 0.0;
         string pair1 = base_curr + "USD";
         double b1 = SymbolInfoDouble(pair1, SYMBOL_BID);
         if(b1 > 0.0) base_to_usd = b1;
         else
         {
            string pair2 = "USD" + base_curr;
            double b2 = SymbolInfoDouble(pair2, SYMBOL_BID);
            if(b2 > 0.0) base_to_usd = 1.0 / b2;
         }

         if(base_to_usd > 0.0)
         {
            rate = (base_to_usd * usd_to_inr) * cent_multiplier;
            return true;
         }
      }
   }

   return false;
}

const string g_dashPrefix = "HA_DASH_";
int          g_dash_prev_lines = 0;

void CreateOrUpdateDashLabel(string name, string text, int x, int y, color clr, int fontSize = 9, bool isBold = false)
{
   if(ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_BACK, false);
   }

   ObjectSetString(0, name, OBJPROP_FONT, isBold ? "Consolas Bold" : "Consolas");
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, fontSize);
}

void DeleteDashLabels()
{
   ObjectsDeleteAll(0, g_dashPrefix);
}

void UpdateProfitLabel()
{
   if(!ShowProfitLabel)
   {
      DeleteDashLabels();
      return;
   }

   double realized_profit = 0.0;
   double history_profit = 0.0;
   double floating_profit = 0.0;
   StreamProfitData stream_data[];
   CalculateProfits(realized_profit, history_profit, floating_profit, stream_data);

   double total_profit = realized_profit + floating_profit;
   string account_currency = AccountInfoString(ACCOUNT_CURRENCY);
   if(account_currency == "")
      account_currency = "USD";

   double inr_rate = 1.0;
   bool can_convert_to_inr = GetAccountCurrencyToInrRate(inr_rate);

   double realized_profit_inr = can_convert_to_inr ? (realized_profit * inr_rate) : realized_profit;
   double floating_profit_inr = can_convert_to_inr ? (floating_profit * inr_rate) : floating_profit;
   double total_profit_inr = can_convert_to_inr ? (total_profit * inr_rate) : total_profit;
   double history_profit_inr = can_convert_to_inr ? (history_profit * inr_rate) : history_profit;

   string target_text = "Unlimited";
   string remaining_text = "Unlimited";

   if(MaxSessionProfitMoney > 0.0)
   {
      double target_inr = can_convert_to_inr ? (MaxSessionProfitMoney * inr_rate) : MaxSessionProfitMoney;
      double remaining_inr = can_convert_to_inr ? (MathMax(0.0, MaxSessionProfitMoney - total_profit) * inr_rate)
                                                : MathMax(0.0, MaxSessionProfitMoney - total_profit);
      target_text = "INR " + DoubleToString(target_inr, 2);
      remaining_text = "INR " + DoubleToString(remaining_inr, 2);
   }

   OpenPositionsStats stats;
   GetOpenPositionsStats(stats);

   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   string mean_str = "";
   if(stats.buy_count > 0 && stats.sell_count > 0)
      mean_str = "Buy:" + DoubleToString(stats.buy_mean_price, digits) + " | Sell:" + DoubleToString(stats.sell_mean_price, digits);
   else if(stats.buy_count > 0)
      mean_str = DoubleToString(stats.buy_mean_price, digits);
   else if(stats.sell_count > 0)
      mean_str = DoubleToString(stats.sell_mean_price, digits);
   else
      mean_str = "None (No Open Trades)";

   string orders_str = "";
   string lots_str = "";
   if(stats.buy_count > 0 && stats.sell_count > 0)
   {
      orders_str = "Buy: " + IntegerToString(stats.buy_count) + " | Sell: " + IntegerToString(stats.sell_count);
      lots_str = "Buy: " + DoubleToString(stats.buy_lots, 2) + " | Sell: " + DoubleToString(stats.sell_lots, 2);
   }
   else if(stats.sell_count > 0)
   {
      orders_str = IntegerToString(stats.sell_count) + " (Sell)";
      lots_str = DoubleToString(stats.sell_lots, 2) + " (Sell)";
   }
   else
   {
      orders_str = IntegerToString(stats.buy_count);
      lots_str = DoubleToString(stats.buy_lots, 2);
   }

   // --- RENDER BLACK BOX DASHBOARD ---
   int start_x = 15;
   int start_y = 35;
   int row_h = 18;
   int panel_w = 340;
   
   int total_rows = 13 + (InpBookProfitOnlyOnSignalFlip ? 0 : ArraySize(g_streams)) + (can_convert_to_inr ? 1 : 0) + (g_session_profit_locked ? 1 : 0);

   // 1. Render Background Black Box FIRST with Z-order 0
   string bgName = g_dashPrefix + "BG";
   if(ObjectFind(0, bgName) < 0)
   {
      ObjectCreate(0, bgName, OBJ_RECTANGLE_LABEL, 0, 0, 0);
      ObjectSetInteger(0, bgName, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, bgName, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, bgName, OBJPROP_BACK, false);
      ObjectSetInteger(0, bgName, OBJPROP_ZORDER, 0);
   }
   ObjectSetInteger(0, bgName, OBJPROP_XDISTANCE, start_x - 8);
   ObjectSetInteger(0, bgName, OBJPROP_YDISTANCE, start_y - 8);
   ObjectSetInteger(0, bgName, OBJPROP_XSIZE, panel_w);
   ObjectSetInteger(0, bgName, OBJPROP_YSIZE, (total_rows * row_h) + 16);
   ObjectSetInteger(0, bgName, OBJPROP_BGCOLOR, C'20,24,32');
   ObjectSetInteger(0, bgName, OBJPROP_BORDER_COLOR, C'50,60,80');
   ObjectSetInteger(0, bgName, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, bgName, OBJPROP_BACK, false);
   ObjectSetInteger(0, bgName, OBJPROP_ZORDER, 0);

   // 2. Render Foreground Text Labels with Z-order 10
   int line_idx = 0;

   // 0. Title
   CreateOrUpdateDashLabel(g_dashPrefix + "L_" + IntegerToString(line_idx), "=== HA-EMA GRID DASHBOARD ===", start_x, start_y + (line_idx * row_h), clrGold, 10, true);
   line_idx++;

   // 1. Orders
   CreateOrUpdateDashLabel(g_dashPrefix + "L_" + IntegerToString(line_idx), StringFormat("Total Orders     : %s", orders_str), start_x, start_y + (line_idx * row_h), clrWhite, 9, true);
   line_idx++;

   // 2. Lots
   CreateOrUpdateDashLabel(g_dashPrefix + "L_" + IntegerToString(line_idx), StringFormat("Total Lots       : %s", lots_str), start_x, start_y + (line_idx * row_h), clrAqua, 9, true);
   line_idx++;

   // 3. Mean Point
   CreateOrUpdateDashLabel(g_dashPrefix + "L_" + IntegerToString(line_idx), StringFormat("Mean Point (BE)  : %s", mean_str), start_x, start_y + (line_idx * row_h), clrYellow, 9, true);
   line_idx++;

   // 4. Current Float
   color floatClr = (floating_profit >= 0.0) ? clrLimeGreen : clrCrimson;
   string floatStr = StringFormat("Current Float PNL: INR %.2f (%.2f %s)", floating_profit_inr, floating_profit, account_currency);
   CreateOrUpdateDashLabel(g_dashPrefix + "L_" + IntegerToString(line_idx), floatStr, start_x, start_y + (line_idx * row_h), floatClr, 9, true);
   line_idx++;

   // 5. Total Collected
   color collClr = (realized_profit >= 0.0) ? clrLimeGreen : clrCrimson;
   string collStr = StringFormat("Total Collected  : INR %.2f (%.2f %s)", realized_profit_inr, realized_profit, account_currency);
   CreateOrUpdateDashLabel(g_dashPrefix + "L_" + IntegerToString(line_idx), collStr, start_x, start_y + (line_idx * row_h), collClr, 9, false);
   line_idx++;

   // 6. Net Combined Profit
   color netClr = (total_profit >= 0.0) ? clrLimeGreen : clrCrimson;
   string netStr = StringFormat("Net Combined PNL : INR %.2f", total_profit_inr);
   CreateOrUpdateDashLabel(g_dashPrefix + "L_" + IntegerToString(line_idx), netStr, start_x, start_y + (line_idx * row_h), netClr, 9, true);
   line_idx++;

   // 7. Total History
   string histStr = StringFormat("Total History    : INR %.2f", history_profit_inr);
   CreateOrUpdateDashLabel(g_dashPrefix + "L_" + IntegerToString(line_idx), histStr, start_x, start_y + (line_idx * row_h), clrSilver, 9, false);
   line_idx++;

   // 8. HA-EMA Trend
   string trendSummary = GetSignalSummary();
   color trendClr = (g_current_signal == 1) ? clrLimeGreen : ((g_current_signal == -1) ? clrCrimson : clrSilver);
   string trendStr = StringFormat("HA-EMA Trend (%-3s): %s", EnumToString(InpSignalTimeframe), trendSummary);
   CreateOrUpdateDashLabel(g_dashPrefix + "L_" + IntegerToString(line_idx), trendStr, start_x, start_y + (line_idx * row_h), trendClr, 9, true);
   line_idx++;

   // 9. TP Mode
   if(InpBookProfitOnlyOnSignalFlip)
      CreateOrUpdateDashLabel(g_dashPrefix + "L_" + IntegerToString(line_idx), "TP Mode          : BOOK ALL ON SIGNAL FLIP", start_x, start_y + (line_idx * row_h), clrOrange, 8, true);
   else
      CreateOrUpdateDashLabel(g_dashPrefix + "L_" + IntegerToString(line_idx), "TP Mode          : STEP-BY-STEP TP", start_x, start_y + (line_idx * row_h), clrDodgerBlue, 8, true);
   line_idx++;

   // Separator
   CreateOrUpdateDashLabel(g_dashPrefix + "L_" + IntegerToString(line_idx), "---------------------------------------------", start_x, start_y + (line_idx * row_h), C'70,80,100', 8, false);
   line_idx++;

   // Active Grids Breakdown (if not in flip-only mode)
   if(!InpBookProfitOnlyOnSignalFlip)
   {
      for(int i = 0; i < ArraySize(g_streams); i++)
      {
         double stream_realized = (i < ArraySize(stream_data)) ? stream_data[i].realized_today : 0.0;
         double stream_floating = (i < ArraySize(stream_data)) ? stream_data[i].floating : 0.0;
         double stream_total = stream_realized + stream_floating;
         double stream_total_inr = can_convert_to_inr ? (stream_total * inr_rate) : stream_total;
         double stream_realized_inr = can_convert_to_inr ? (stream_realized * inr_rate) : stream_realized;
         double stream_floating_inr = can_convert_to_inr ? (stream_floating * inr_rate) : stream_floating;

         string streamStr = StringFormat("  %-6s: INR %.2f (Coll: %.2f, Flt: %.2f)",
                                         g_streams[i].name, stream_total_inr, stream_realized_inr, stream_floating_inr);
         CreateOrUpdateDashLabel(g_dashPrefix + "L_" + IntegerToString(line_idx), streamStr, start_x, start_y + (line_idx * row_h), clrLightSkyBlue, 8, false);
         line_idx++;
      }

      // Separator
      CreateOrUpdateDashLabel(g_dashPrefix + "L_" + IntegerToString(line_idx), "---------------------------------------------", start_x, start_y + (line_idx * row_h), C'70,80,100', 8, false);
      line_idx++;
   }

   // Target / Remaining
   string targetStr = StringFormat("Target: %s | Rem: %s", target_text, remaining_text);
   CreateOrUpdateDashLabel(g_dashPrefix + "L_" + IntegerToString(line_idx), targetStr, start_x, start_y + (line_idx * row_h), clrKhaki, 9, false);
   line_idx++;

   if(can_convert_to_inr)
   {
      string convStr = StringFormat("Conversion: 1 %s = INR %.4f", account_currency, inr_rate);
      CreateOrUpdateDashLabel(g_dashPrefix + "L_" + IntegerToString(line_idx), convStr, start_x, start_y + (line_idx * row_h), clrDarkGray, 8, false);
      line_idx++;
   }

   if(g_session_profit_locked)
   {
      CreateOrUpdateDashLabel(g_dashPrefix + "L_" + IntegerToString(line_idx), "STATUS: PROFIT TARGET LOCKED", start_x, start_y + (line_idx * row_h), clrTomato, 9, true);
      line_idx++;
   }

   // Adjust actual height of background box
   ObjectSetInteger(0, bgName, OBJPROP_YSIZE, (line_idx * row_h) + 16);

   // Clean up any extra rows
   for(int k = line_idx; k < g_dash_prev_lines; k++)
   {
      ObjectDelete(0, g_dashPrefix + "L_" + IntegerToString(k));
   }
   g_dash_prev_lines = line_idx;

   ChartRedraw(0);
}

//--- BROKER FLOOD PROTECTION & MARGIN GUARD ---
ulong    g_last_trade_request_ms = 0;
datetime g_low_margin_cooldown_until = 0;

struct InFlightClose
{
   ulong    ticket;
   ulong    attempt_ms;
};
InFlightClose g_inflight_closes[];

bool IsTradeThrottled(const int min_interval_ms = 350)
{
   ulong now_ms = GetTickCount64();
   if(now_ms - g_last_trade_request_ms < (ulong)min_interval_ms)
      return true; // Throttled, wait for next tick
   return false;
}

void RegisterTradeRequest()
{
   g_last_trade_request_ms = GetTickCount64();
}

bool HasEnoughMargin(const ENUM_ORDER_TYPE order_type, const double lot)
{
   if(TimeCurrent() < g_low_margin_cooldown_until)
      return false;

   double margin_required = 0.0;
   double price = (order_type == ORDER_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   
   if(!OrderCalcMargin(order_type, _Symbol, lot, price, margin_required))
   {
      margin_required = lot * price / 100.0; // Fallback estimate
   }

   double free_margin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   
   // Require at least margin + 20% safety buffer
   if(free_margin < margin_required * 1.20)
   {
      g_low_margin_cooldown_until = TimeCurrent() + 10; // 10-second cooldown on low margin
      Print("INSUFFICIENT MARGIN: Free=", DoubleToString(free_margin, 2), " Required=", DoubleToString(margin_required, 2), ". Pausing order requests for 10s.");
      return false;
   }

   return true;
}

bool CanAttemptClose(const ulong ticket, const int cooldown_ms = 2500)
{
   ulong now_ms = GetTickCount64();

   // Clean old entries
   int total = ArraySize(g_inflight_closes);
   for(int i = total - 1; i >= 0; i--)
   {
      if(now_ms - g_inflight_closes[i].attempt_ms > 10000) // Older than 10s
      {
         for(int j = i; j < total - 1; j++)
            g_inflight_closes[j] = g_inflight_closes[j + 1];
         ArrayResize(g_inflight_closes, total - 1);
         total--;
      }
   }

   // Check if this ticket was recently attempted
   for(int i = 0; i < ArraySize(g_inflight_closes); i++)
   {
      if(g_inflight_closes[i].ticket == ticket)
      {
         if(now_ms - g_inflight_closes[i].attempt_ms < (ulong)cooldown_ms)
            return false; // Still in cooldown/processing
         else
         {
            g_inflight_closes[i].attempt_ms = now_ms;
            return true;
         }
      }
   }

   // New close attempt
   int sz = ArraySize(g_inflight_closes);
   ArrayResize(g_inflight_closes, sz + 1);
   g_inflight_closes[sz].ticket = ticket;
   g_inflight_closes[sz].attempt_ms = now_ms;
   return true;
}

bool OpenVirtualBuyAtLevel(GridStream &stream, const double level_price)
{
   double trade_lot = (stream.lot_size > 0.0) ? stream.lot_size : GetNormalizedLot(LotSize * (stream.id > 0 ? (double)stream.id : 1.0));
   if(trade_lot <= 0.0) trade_lot = 0.01;

   if(stream.last_failed_buy_level == level_price && (TimeCurrent() - stream.last_failed_buy_time < FailedOrderRetrySeconds))
      return false;

   double sl_price = 0.0;
   double stop_loss_distance = GetStopLossDistancePrice(stream.step);
   if(stop_loss_distance > 0.0)
      sl_price = NormalizePrice(level_price - stop_loss_distance);

   double tp_price = 0.0;
   if(!InpBookProfitOnlyOnSignalFlip && UseServerSideTP && stream.tp_dist > 0.0)
   {
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      tp_price = NormalizePrice(ask + stream.tp_dist);
   }

   string comment = PositionCommentPrefix(POSITION_TYPE_BUY, stream.name) + DoubleToString(level_price, 2);

   trade.SetExpertMagicNumber(stream.magic);
   trade.SetDeviationInPoints(SlippagePoints);

   bool result = trade.Buy(trade_lot, _Symbol, 0.0, sl_price, tp_price, comment);

   if(!result)
   {
      stream.last_failed_buy_level = level_price;
      stream.last_failed_buy_time = TimeCurrent();
      Print("Virtual BUY failed [", stream.name, "] level=", DoubleToString(level_price, 2),
            " retcode=", trade.ResultRetcode(),
            " message=", trade.ResultRetcodeDescription());
   }
   else
   {
      stream.last_failed_buy_level = 0.0;
      stream.last_failed_buy_time = 0;
      Print("Virtual BUY opened [", stream.name, "] at exact level=", DoubleToString(level_price, 2),
            " ticket=", trade.ResultOrder());
   }

   return result;
}

bool OpenVirtualSellAtLevel(GridStream &stream, const double level_price)
{
   double trade_lot = (stream.lot_size > 0.0) ? stream.lot_size : GetNormalizedLot(LotSize * (stream.id > 0 ? (double)stream.id : 1.0));
   if(trade_lot <= 0.0) trade_lot = 0.01;

   if(stream.last_failed_sell_level == level_price && (TimeCurrent() - stream.last_failed_sell_time < FailedOrderRetrySeconds))
      return false;

   double sl_price = 0.0;
   double stop_loss_distance = GetStopLossDistancePrice(stream.step);
   if(stop_loss_distance > 0.0)
      sl_price = NormalizePrice(level_price + stop_loss_distance);

   double tp_price = 0.0;
   if(!InpBookProfitOnlyOnSignalFlip && UseServerSideTP && stream.tp_dist > 0.0)
   {
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      tp_price = NormalizePrice(bid - stream.tp_dist);
   }

   string comment = PositionCommentPrefix(POSITION_TYPE_SELL, stream.name) + DoubleToString(level_price, 2);

   trade.SetExpertMagicNumber(stream.magic);
   trade.SetDeviationInPoints(SlippagePoints);

   bool result = trade.Sell(trade_lot, _Symbol, 0.0, sl_price, tp_price, comment);

   if(!result)
   {
      stream.last_failed_sell_level = level_price;
      stream.last_failed_sell_time = TimeCurrent();
      Print("Virtual SELL failed [", stream.name, "] level=", DoubleToString(level_price, 2),
            " retcode=", trade.ResultRetcode(),
            " message=", trade.ResultRetcodeDescription());
   }
   else
   {
      stream.last_failed_sell_level = 0.0;
      stream.last_failed_sell_time = 0;
      Print("Virtual SELL opened [", stream.name, "] at exact level=", DoubleToString(level_price, 2),
            " ticket=", trade.ResultOrder());
   }

   return result;
}





void CheckVirtualGridTriggersForStream(GridStream &stream)
{
   if(stream.step <= 0.0 || stream.tp_dist <= 0.0 || LotSize <= 0.0)
      return;

   // Tight tolerance window: order must only trigger when price is ACTUALLY AT the round number
   double level_tolerance = MathMax(_Point * 15, 0.25);

   if(IsBuyActive())
   {
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      if(ask <= 0.0) return;

      double nearest_round = NormalizePrice(MathRound(ask / stream.step) * stream.step);

      // Price must be touching this exact round level
      if(MathAbs(ask - nearest_round) <= level_tolerance)
      {
         if(!IsOurPositionAtLevel(stream, nearest_round, POSITION_TYPE_BUY))
         {
            OpenVirtualBuyAtLevel(stream, nearest_round);
         }
      }
   }
   else if(IsSellActive())
   {
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      if(bid <= 0.0) return;

      double nearest_round = NormalizePrice(MathRound(bid / stream.step) * stream.step);

      // Price must be touching this exact round level
      if(MathAbs(bid - nearest_round) <= level_tolerance)
      {
         if(!IsOurPositionAtLevel(stream, nearest_round, POSITION_TYPE_SELL))
         {
            OpenVirtualSellAtLevel(stream, nearest_round);
         }
      }
   }
}

void CheckDynamicTakeProfitForStream(GridStream &stream)
{
   if(InpBookProfitOnlyOnSignalFlip)
      return;

   if(stream.tp_dist <= 0.0)
      return;

   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   if(bid <= 0.0 || ask <= 0.0)
      return;

   trade.SetExpertMagicNumber(stream.magic);
   trade.SetDeviationInPoints(SlippagePoints);

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;

      if(PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;

      if(PositionGetInteger(POSITION_MAGIC) != stream.magic)
         continue;

      ENUM_POSITION_TYPE position_type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      if(position_type != POSITION_TYPE_BUY && position_type != POSITION_TYPE_SELL)
         continue;

      double open_price = PositionGetDouble(POSITION_PRICE_OPEN);
      double current_tp = PositionGetDouble(POSITION_TP);

      if(position_type == POSITION_TYPE_BUY)
      {
         double target_price = NormalizePrice(open_price + stream.tp_dist);

         // Auto-sync missing TP to broker server
         if(UseServerSideTP && current_tp == 0.0)
         {
            trade.PositionModify(ticket, PositionGetDouble(POSITION_SL), target_price);
         }

         if(bid >= target_price - (_Point * 0.5))
         {
            if(!CanAttemptClose(ticket, CloseRetryCooldownSeconds * 1000) || IsTradeThrottled(MinOrderIntervalMs))
               continue;

            RegisterTradeRequest();
            if(trade.PositionClose(ticket))
            {
               Print("Dynamic TP closed [", stream.name, "] ticket=", ticket,
                     " open=", DoubleToString(open_price, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS)),
                     " bid=", DoubleToString(bid, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS)),
                     " target=", DoubleToString(target_price, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS)));
            }
            else
            {
               Print("Dynamic TP close failed [", stream.name, "] ticket=", ticket,
                     " retcode=", trade.ResultRetcode(),
                     " message=", trade.ResultRetcodeDescription());
            }
         }
      }
      else if(position_type == POSITION_TYPE_SELL)
      {
         double target_price = NormalizePrice(open_price - stream.tp_dist);

         // Auto-sync missing TP to broker server
         if(UseServerSideTP && current_tp == 0.0)
         {
            trade.PositionModify(ticket, PositionGetDouble(POSITION_SL), target_price);
         }

         if(ask <= target_price + (_Point * 0.5))
         {
            if(!CanAttemptClose(ticket, CloseRetryCooldownSeconds * 1000) || IsTradeThrottled(MinOrderIntervalMs))
               continue;

            RegisterTradeRequest();
            if(trade.PositionClose(ticket))
            {
               Print("Dynamic TP closed [", stream.name, "] ticket=", ticket,
                     " open=", DoubleToString(open_price, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS)),
                     " ask=", DoubleToString(ask, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS)),
                     " target=", DoubleToString(target_price, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS)));
            }
            else
            {
               Print("Dynamic TP close failed [", stream.name, "] ticket=", ticket,
                     " retcode=", trade.ResultRetcode(),
                     " message=", trade.ResultRetcodeDescription());
            }
         }
      }
   }
}

bool CheckSessionCloseWindow()
{
   if(!CloseBeforeMarketClose)
      return false;

   datetime now = TimeCurrent();
   MqlDateTime dt;
   TimeToStruct(now, dt);

   MqlDateTime day_dt = dt;
   day_dt.hour = 0;
   day_dt.min = 0;
   day_dt.sec = 0;
   datetime current_day = StructToTime(day_dt);

   datetime session_close_time = 0;
   int day_of_week = dt.day_of_week;

   datetime session_from, session_to;
   if(SymbolInfoSessionTrade(_Symbol, (ENUM_DAY_OF_WEEK)day_of_week, 0, session_from, session_to))
   {
      MqlDateTime close_dt;
      TimeToStruct(session_to, close_dt);
      close_dt.year = dt.year;
      close_dt.mon = dt.mon;
      close_dt.day = dt.day;
      session_close_time = StructToTime(close_dt);
   }

   if(session_close_time <= 0)
      return false;

   int buffer_seconds = MathMax(1, MinutesBeforeMarketClose) * 60;
   datetime cutoff_time = session_close_time - buffer_seconds;

   if(now >= cutoff_time && now < session_close_time)
   {
      if(g_last_session_close_day != current_day)
      {
         Print("HA-EMA Virtual Grid market close approaching. Closing all positions.");
         CloseAllOurPositions();
         g_last_session_close_day = current_day;
      }
      return true;
   }

   return false;
}

bool IsSessionProfitBlocked()
{
   ResetSessionLockIfNeeded();

   if(g_session_profit_locked)
      return true;

   if(MaxSessionProfitMoney <= 0.0)
      return false;

   double today_profit = GetTodayRealizedProfit() + GetFloatingProfit();

   if(today_profit >= MaxSessionProfitMoney)
   {
      g_session_profit_locked = true;
      Print("HA-EMA Virtual Grid target profit reached: ", DoubleToString(today_profit, 2),
            " >= ", DoubleToString(MaxSessionProfitMoney, 2), ". Closing positions.");
      CloseAllOurPositions();
      return true;
   }

   return false;
}

bool IsAccountDrawdownBlocked()
{
   if(MaxAccountDrawdownPercent <= 0.0)
      return false;

   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   if(balance <= 0.0)
      return false;

   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double drawdown_percent = ((balance - equity) / balance) * 100.0;

   if(drawdown_percent >= MaxAccountDrawdownPercent)
   {
      Print("HA-EMA Virtual Grid account drawdown threshold breached: ", DoubleToString(drawdown_percent, 2),
            "% >= ", DoubleToString(MaxAccountDrawdownPercent, 2), "%. Stopping new trades.");
      return true;
   }

   return false;
}

string ChartObjPrefix()
{
   return "RGridObj_" + IntegerToString(MagicNumber) + "_";
}

void DeleteAllChartObjects()
{
   string prefix = ChartObjPrefix();
   int total = ObjectsTotal(0, 0, -1);
   for(int i = total - 1; i >= 0; i--)
   {
      string name = ObjectName(0, i, 0, -1);
      if(StringSubstr(name, 0, StringLen(prefix)) == prefix)
      {
         ObjectDelete(0, name);
      }
   }
}

void DrawOrUpdateHLine(const string name, const double price, const color clr, const ENUM_LINE_STYLE style, const int width, const string tooltip)
{
   if(ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_HLINE, 0, 0, price);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   }

   ObjectSetDouble(0, name, OBJPROP_PRICE, price);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_STYLE, style);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, width);
   ObjectSetString(0, name, OBJPROP_TOOLTIP, tooltip);
}

void UpdateChartVisualsForStream(const GridStream &stream, string &active_obj_names[])
{
   string prefix = ChartObjPrefix();

   // 1. Draw/Update Pending/Grid Levels (Dotted line with pair's unique color)
   if(stream.show_pending && stream.step > 0.0)
   {
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

      if(IsBuyActive())
      {
         double nearest_round = NormalizePrice(MathRound(ask / stream.step) * stream.step);
         int count = MathMax(1, ChartDisplayLevelsCount);

         for(int i = 0; i < count; i++)
         {
            double level = NormalizePrice(nearest_round - (stream.step * i));
            if(!IsOurPositionAtLevel(stream, level, POSITION_TYPE_BUY))
            {
               string obj_name = prefix + "Pnd_" + stream.name + "_B_" + DoubleToString(level, 2);
               DrawOrUpdateHLine(obj_name, level, stream.preset_color, STYLE_DOT, 1, stream.name + " Pending Buy Grid @ " + DoubleToString(level, 2));
               
               int sz = ArraySize(active_obj_names);
               ArrayResize(active_obj_names, sz + 1);
               active_obj_names[sz] = obj_name;
            }
         }
      }

      if(IsSellActive())
      {
         double nearest_round = NormalizePrice(MathRound(bid / stream.step) * stream.step);
         int count = MathMax(1, ChartDisplayLevelsCount);

         for(int i = 0; i < count; i++)
         {
            double level = NormalizePrice(nearest_round + (stream.step * i));
            if(!IsOurPositionAtLevel(stream, level, POSITION_TYPE_SELL))
            {
               string obj_name = prefix + "Pnd_" + stream.name + "_S_" + DoubleToString(level, 2);
               DrawOrUpdateHLine(obj_name, level, stream.preset_color, STYLE_DOT, 1, stream.name + " Pending Sell Grid @ " + DoubleToString(level, 2));
               
               int sz = ArraySize(active_obj_names);
               ArrayResize(active_obj_names, sz + 1);
               active_obj_names[sz] = obj_name;
            }
         }
      }
   }

   // 2. Draw/Update TP Levels for Open Positions (Plain / Solid line with pair's unique color)
   if(!InpBookProfitOnlyOnSignalFlip && stream.show_tp && stream.tp_dist > 0.0)
   {
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket == 0 || !PositionSelectByTicket(ticket))
            continue;

         if(PositionGetString(POSITION_SYMBOL) != _Symbol || PositionGetInteger(POSITION_MAGIC) != stream.magic)
            continue;

         ENUM_POSITION_TYPE pos_type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
         double open_p = PositionGetDouble(POSITION_PRICE_OPEN);
         double tp_p = (pos_type == POSITION_TYPE_BUY) ? NormalizePrice(open_p + stream.tp_dist) : NormalizePrice(open_p - stream.tp_dist);

         string obj_name = prefix + "TP_" + stream.name + "_" + IntegerToString(ticket);
         DrawOrUpdateHLine(obj_name, tp_p, stream.preset_color, STYLE_SOLID, 2, stream.name + " Plain TP @ " + DoubleToString(tp_p, 2) + " (Pos #" + IntegerToString(ticket) + ")");

         int sz = ArraySize(active_obj_names);
         ArrayResize(active_obj_names, sz + 1);
         active_obj_names[sz] = obj_name;
      }
   }
}

void UpdateAllChartVisuals()
{
   string active_objs[];
   ArrayResize(active_objs, 0);

   for(int i = 0; i < ArraySize(g_streams); i++)
   {
      UpdateChartVisualsForStream(g_streams[i], active_objs);
   }

   // Delete inactive objects
   string prefix = ChartObjPrefix();
   int total = ObjectsTotal(0, 0, -1);
   for(int i = total - 1; i >= 0; i--)
   {
      string name = ObjectName(0, i, 0, -1);
      if(StringSubstr(name, 0, StringLen(prefix)) == prefix)
      {
         bool found = false;
         for(int j = 0; j < ArraySize(active_objs); j++)
         {
            if(active_objs[j] == name)
            {
               found = true;
               break;
            }
         }
         if(!found)
         {
            ObjectDelete(0, name);
         }
      }
   }
}

void SyncPositionTakeProfits()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;

      if(PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;

      long magic = PositionGetInteger(POSITION_MAGIC);
      if(!IsOurMagic(magic))
         continue;

      double current_tp = PositionGetDouble(POSITION_TP);
      double sl = PositionGetDouble(POSITION_SL);

      // If InpBookProfitOnlyOnSignalFlip is true, strip any TP from broker server!
      if(InpBookProfitOnlyOnSignalFlip)
      {
         if(current_tp > 0.0)
         {
            trade.SetExpertMagicNumber((int)magic);
            trade.PositionModify(ticket, sl, 0.0);
         }
      }
      else if(UseServerSideTP)
      {
         // If regular step TP mode and TP is missing (0.0), calculate and attach it
         if(current_tp == 0.0)
         {
            for(int s = 0; s < ArraySize(g_streams); s++)
            {
               if(g_streams[s].magic == magic && g_streams[s].tp_dist > 0.0)
               {
                  ENUM_POSITION_TYPE p_type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
                  double open_p = PositionGetDouble(POSITION_PRICE_OPEN);
                  double target_p = (p_type == POSITION_TYPE_BUY) ?
                                    NormalizePrice(open_p + g_streams[s].tp_dist) :
                                    NormalizePrice(open_p - g_streams[s].tp_dist);
                  trade.SetExpertMagicNumber((int)magic);
                  trade.PositionModify(ticket, sl, target_p);
                  break;
               }
            }
         }
      }
   }
}

void MaintainAllGrids()
{
   SyncPositionTakeProfits();

   for(int i = 0; i < ArraySize(g_streams); i++)
      CheckDynamicTakeProfitForStream(g_streams[i]);

   UpdateProfitLabel();

   if(CheckSessionCloseWindow())
      return;

   if(IsSessionProfitBlocked())
      return;

   if(IsAccountDrawdownBlocked())
      return;

   for(int i = 0; i < ArraySize(g_streams); i++)
      CheckVirtualGridTriggersForStream(g_streams[i]);

   UpdateAllChartVisuals();
}

bool GetHeikenAshiColors(int &last_closed_color, int &previous_color)
{
   int bars_needed = MathMax(InpEMAPeriod + 10, 100);
   MqlRates rates[];
   ArraySetAsSeries(rates, true);

   int copied = CopyRates(_Symbol, InpSignalTimeframe, 0, bars_needed, rates);
   if(copied < 4)
   {
      Print("HA-EMA not enough bars for ", _Symbol, " timeframe=", EnumToString(InpSignalTimeframe));
      return false;
   }

   double ha_open[];
   double ha_close[];
   ArrayResize(ha_open, copied);
   ArrayResize(ha_close, copied);

   for(int i = copied - 1; i >= 0; i--)
   {
      ha_close[i] = (rates[i].open + rates[i].high + rates[i].low + rates[i].close) / 4.0;

      if(i == copied - 1)
         ha_open[i] = (rates[i].open + rates[i].close) / 2.0;
      else
         ha_open[i] = (ha_open[i + 1] + ha_close[i + 1]) / 2.0;
   }

   if(ha_close[1] > ha_open[1])
      last_closed_color = 1;
   else if(ha_close[1] < ha_open[1])
      last_closed_color = -1;
   else
      last_closed_color = 0;

   if(ha_close[2] > ha_open[2])
      previous_color = 1;
   else if(ha_close[2] < ha_open[2])
      previous_color = -1;
   else
      previous_color = 0;

   return true;
}

bool IsEmaConfirmed(const int signal)
{
   if(!InpUseEMAFilter)
      return true;

   double ema[];
   double close[];
   ArraySetAsSeries(ema, true);
   ArraySetAsSeries(close, true);

   if(CopyBuffer(g_ema_handle, 0, 1, 1, ema) != 1 ||
      CopyClose(_Symbol, InpSignalTimeframe, 1, 1, close) != 1)
   {
      Print("HA-EMA failed to copy EMA/close data");
      return false;
   }

   if(signal > 0)
      return (close[0] > ema[0]);

   if(signal < 0)
      return (close[0] < ema[0]);

   return false;
}

int CalculateCurrentSignal()
{
   int current_color = 0;
   int previous_color = 0;
   if(!GetHeikenAshiColors(current_color, previous_color))
      return 0;

   if(current_color == 0)
      return 0;

   if(!IsEmaConfirmed(current_color))
      return 0;

   return current_color;
}

void HandleSignalFlip(const int new_signal)
{
   if(new_signal == g_current_signal)
      return;

   int old_signal = g_current_signal;
   g_current_signal = new_signal;

   Print("HA-EMA candle trend flipped from ", old_signal, " to ", new_signal,
         " on ", EnumToString(InpSignalTimeframe), ". Flipping active grid orders!");

   if(new_signal == 1) // Flipped to Bullish (BUY candle)
   {
      if(InpCloseOppositeOnFlip || InpBookProfitOnlyOnSignalFlip)
      {
         // Close all SELL positions belonging to our EA
         CloseOurPositionsByType(POSITION_TYPE_SELL);
         for(int i = 0; i < ArraySize(g_streams); i++)
         {
            g_streams[i].last_failed_buy_level = 0.0;
            g_streams[i].last_failed_buy_time = 0;
         }
      }
   }
   else if(new_signal == -1) // Flipped to Bearish (SELL candle)
   {
      if(InpCloseOppositeOnFlip || InpBookProfitOnlyOnSignalFlip)
      {
         // Close all BUY positions belonging to our EA
         CloseOurPositionsByType(POSITION_TYPE_BUY);
         for(int i = 0; i < ArraySize(g_streams); i++)
         {
            g_streams[i].last_failed_sell_level = 0.0;
            g_streams[i].last_failed_sell_time = 0;
         }
      }
   }

   MaintainAllGrids();
}

void CheckForNewSignalBar()
{
   datetime current_bar_time = iTime(_Symbol, InpSignalTimeframe, 0);
   if(current_bar_time <= 0)
      return;

   // If startup signal not resolved yet, keep calculating every tick until valid signal is established
   if(g_current_signal == 0)
   {
      int sig = CalculateCurrentSignal();
      if(sig != 0)
      {
         g_last_signal_bar_time = current_bar_time;
         HandleSignalFlip(sig);
         Print("HA-EMA startup signal resolved: ", (sig == 1 ? "BULLISH (BUY)" : "BEARISH (SELL)"), " on ", EnumToString(InpSignalTimeframe));
      }
      return;
   }

   // On new bar open, check if signal flipped
   if(current_bar_time != g_last_signal_bar_time)
   {
      g_last_signal_bar_time = current_bar_time;
      int sig = CalculateCurrentSignal();
      if(sig != 0 && sig != g_current_signal)
      {
         HandleSignalFlip(sig);
      }
   }
}

double GetNormalizedLot(const double raw_lot)
{
   double min_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double max_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double step_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

   if(min_lot <= 0.0) min_lot = 0.01;
   if(max_lot <= 0.0) max_lot = 100.0;
   if(step_lot <= 0.0) step_lot = 0.01;

   double lots = MathRound(raw_lot / step_lot) * step_lot;
   if(lots < min_lot) lots = min_lot;
   if(lots > max_lot) lots = max_lot;

   int digits = 2;
   if(step_lot == 0.1) digits = 1;
   else if(step_lot == 1.0) digits = 0;
   else if(step_lot == 0.001) digits = 3;

   return NormalizeDouble(lots, digits);
}

void AddGridStream(const int id, const double step, const double tp_dist, const string name, const bool show_pending, const bool show_tp, const color preset_color)
{
   int size = ArraySize(g_streams);
   ArrayResize(g_streams, size + 1);

   g_streams[size].id = id;
   g_streams[size].step = step;
   g_streams[size].tp_dist = tp_dist;
   g_streams[size].magic = (id == 0) ? MagicNumber : (MagicNumber + id);
   g_streams[size].name = name;
   g_streams[size].show_pending = show_pending;
   g_streams[size].show_tp = show_tp;
   g_streams[size].preset_color = preset_color;
   double stream_multiplier = (id > 0) ? (double)id : 1.0;
   g_streams[size].lot_size = GetNormalizedLot(LotSize * stream_multiplier);
   g_streams[size].last_failed_buy_level = 0.0;
   g_streams[size].last_failed_buy_time = 0;
   g_streams[size].last_failed_sell_level = 0.0;
   g_streams[size].last_failed_sell_time = 0;
}

void SetupGridStreams()
{
   ArrayResize(g_streams, 0);

   if(InpBookProfitOnlyOnSignalFlip)
   {
      // Flip mode: Clean single trade per 1 step (e.g. 4001, 4002, 4003...) without multiple preset stacking
      AddGridStream(1, 1.0, 1.0, "1:1", Show_1_1_Pending, false, Color_1_1);
      return;
   }

   bool any_preset = (Enable_1_1 || Enable_2_2 || Enable_3_3 || Enable_4_4 || Enable_5_5 ||
                      Enable_6_6 || Enable_7_7 || Enable_8_8 || Enable_9_9 || Enable_10_10);

   if(any_preset)
   {
      if(Enable_1_1)   AddGridStream(1, 1.0, 1.0, "1:1", Show_1_1_Pending, Show_1_1_TP, Color_1_1);
      if(Enable_2_2)   AddGridStream(2, 2.0, 2.0, "2:2", Show_2_2_Pending, Show_2_2_TP, Color_2_2);
      if(Enable_3_3)   AddGridStream(3, 3.0, 3.0, "3:3", Show_3_3_Pending, Show_3_3_TP, Color_3_3);
      if(Enable_4_4)   AddGridStream(4, 4.0, 4.0, "4:4", Show_4_4_Pending, Show_4_4_TP, Color_4_4);
      if(Enable_5_5)   AddGridStream(5, 5.0, 5.0, "5:5", Show_5_5_Pending, Show_5_5_TP, Color_5_5);
      if(Enable_6_6)   AddGridStream(6, 6.0, 6.0, "6:6", Show_6_6_Pending, Show_6_6_TP, Color_6_6);
      if(Enable_7_7)   AddGridStream(7, 7.0, 7.0, "7:7", Show_7_7_Pending, Show_7_7_TP, Color_7_7);
      if(Enable_8_8)   AddGridStream(8, 8.0, 8.0, "8:8", Show_8_8_Pending, Show_8_8_TP, Color_8_8);
      if(Enable_9_9)   AddGridStream(9, 9.0, 9.0, "9:9", Show_9_9_Pending, Show_9_9_TP, Color_9_9);
      if(Enable_10_10) AddGridStream(10, 10.0, 10.0, "10:10", Show_10_10_Pending, Show_10_10_TP, Color_10_10);
   }
   else
   {
      AddGridStream(0, RoundStepPrice, TargetPriceDistance, "Custom", Show_Custom_Pending, Show_Custom_TP, Color_Custom);
   }
}

int OnInit()
{
   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(SlippagePoints);
   trade.SetTypeFillingBySymbol(_Symbol);

   if(HideChartTradeLevels)
   {
      ChartSetInteger(0, CHART_SHOW_TRADE_LEVELS, false);
      ChartSetInteger(0, CHART_SHOW_TRADE_HISTORY, false);
   }

   if(OnlyXauSymbols && StringFind(_Symbol, "XAU") < 0 && StringFind(_Symbol, "GOLD") < 0)
      Print("HA-EMA Virtual Grid warning: this EA is intended for XAU/GOLD symbols. Current symbol=", _Symbol);

   if(LotSize <= 0.0 || InpEMAPeriod <= 0)
   {
      Print("HA-EMA Virtual Grid invalid parameters: LotSize and InpEMAPeriod must be greater than zero.");
      return INIT_PARAMETERS_INCORRECT;
   }

   g_ema_handle = iMA(_Symbol, InpSignalTimeframe, InpEMAPeriod, 0, MODE_EMA, PRICE_CLOSE);
   if(g_ema_handle == INVALID_HANDLE)
   {
      Print("HA-EMA Virtual Grid failed to create EMA handle. Error=", GetLastError());
      return INIT_FAILED;
   }

   SetupGridStreams();

   EventSetTimer(1);
   CheckForNewSignalBar();
   MaintainAllGrids();

   Print("HA-EMA Virtual Grid initialized for ", _Symbol,
         " (Exact Round Numbers Grid). Signal timeframe=", EnumToString(InpSignalTimeframe));

   return INIT_SUCCEEDED;
}

void OnTick()
{
   CheckForNewSignalBar();
   MaintainAllGrids();
}

void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
{
   if(trans.symbol != _Symbol)
      return;

   if(trans.type == TRADE_TRANSACTION_DEAL_ADD)
   {
      MaintainAllGrids();
   }
}

void OnTimer()
{
   CheckForNewSignalBar();
   MaintainAllGrids();
}

void OnDeinit(const int reason)
{
   EventKillTimer();
   DeleteDashLabels();
   ObjectDelete(0, ProfitLabelName());
   DeleteAllChartObjects();

   if(HideChartTradeLevels)
   {
      ChartSetInteger(0, CHART_SHOW_TRADE_LEVELS, true);
   }

   if(g_ema_handle != INVALID_HANDLE)
   {
      IndicatorRelease(g_ema_handle);
      g_ema_handle = INVALID_HANDLE;
   }
}
//+------------------------------------------------------------------+
