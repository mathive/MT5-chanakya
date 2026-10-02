//+------------------------------------------------------------------+
//|                                         HA-EMA-Flip-Simple.mq5   |
//|                    Simple Heiken Ashi candle flip trading EA      |
//+------------------------------------------------------------------+
#property copyright "Chanakya"
#property link      "https://www.mql5.com"
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>

input group "Trade Settings"
input double          InpLotSize = 0.01;                  // Lot size
input double          InpTakeProfitMoney = 0.0;           // Take profit in account currency, 0 = no TP
input int             InpMagicNumber = 240624;            // Magic number
input int             InpSlippagePoints = 30;             // Slippage in points
input bool            InpAllowBuy = true;                 // Allow buy trades
input bool            InpAllowSell = true;                // Allow sell trades
input bool            InpProtectOtherMagic = true;        // Do not affect other magic positions
input bool            InpTradeCurrentFlipOnStartup = false; // Trade existing flip when EA starts

input group "Signal Settings"
input ENUM_TIMEFRAMES InpSignalTimeframe = PERIOD_M5;     // Fixed signal timeframe
input int             InpEMAPeriod = 200;                 // EMA period
input bool            InpUseEMAFilter = true;             // Buy above EMA, sell below EMA

CTrade trade;

ENUM_TIMEFRAMES g_signal_timeframe = PERIOD_CURRENT;
int             g_ema_handle = INVALID_HANDLE;
datetime        g_last_bar_time = 0;
bool            g_startup_checked = false;
int             g_last_signal = 0;
bool            g_wait_after_tp = false;

string EaComment()
{
   return "HA-EMA Flip Simple";
}

double NormalizePrice(const double price)
{
   return NormalizeDouble(price, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS));
}

double GetTakeProfitPrice(const ENUM_POSITION_TYPE position_type)
{
   if(InpTakeProfitMoney <= 0.0)
      return 0.0;

   double tick_value = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tick_size = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tick_value <= 0.0 || tick_size <= 0.0 || InpLotSize <= 0.0)
   {
      Print("HA-EMA cannot calculate money TP. tick_value=", tick_value,
            " tick_size=", tick_size,
            " lot=", InpLotSize);
      return 0.0;
   }

   double price_distance = (InpTakeProfitMoney * tick_size) / (tick_value * InpLotSize);

   if(position_type == POSITION_TYPE_BUY)
   {
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      if(ask <= 0.0)
         return 0.0;

      return NormalizePrice(ask + price_distance);
   }

   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if(bid <= 0.0)
      return 0.0;

   return NormalizePrice(bid - price_distance);
}

bool IsOurPosition()
{
   return (PositionGetString(POSITION_SYMBOL) == _Symbol &&
           PositionGetInteger(POSITION_MAGIC) == InpMagicNumber);
}

bool HasOurPositionType(const ENUM_POSITION_TYPE position_type)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;

      if(!IsOurPosition())
         continue;

      if((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) == position_type)
         return true;
   }

   return false;
}

bool IsNettingAccount()
{
   ENUM_ACCOUNT_MARGIN_MODE margin_mode = (ENUM_ACCOUNT_MARGIN_MODE)AccountInfoInteger(ACCOUNT_MARGIN_MODE);
   return (margin_mode == ACCOUNT_MARGIN_MODE_RETAIL_NETTING ||
           margin_mode == ACCOUNT_MARGIN_MODE_EXCHANGE);
}

bool HasOtherMagicPositionOnSymbol()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;

      if(PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;

      if(PositionGetInteger(POSITION_MAGIC) != InpMagicNumber)
         return true;
   }

   return false;
}

bool CanOpenWithoutAffectingOtherMagic()
{
   if(!InpProtectOtherMagic)
      return true;

   if(!IsNettingAccount())
      return true;

   if(!HasOtherMagicPositionOnSymbol())
      return true;

   Print("HA-EMA skipped trade: another magic number has a position on ",
         _Symbol,
         ". Netting account would modify that position.");
   return false;
}

void CloseOurPositionsExcept(const ENUM_POSITION_TYPE keep_type)
{
   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(InpSlippagePoints);

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;

      if(!IsOurPosition())
         continue;

      if((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) == keep_type)
         continue;

      if(!trade.PositionClose(ticket))
      {
         Print("HA-EMA close failed ticket=", ticket,
               " retcode=", trade.ResultRetcode(),
               " message=", trade.ResultRetcodeDescription());
      }
   }
}

bool GetHeikenAshiColors(int &last_closed_color, int &previous_color)
{
   int bars_needed = MathMax(InpEMAPeriod + 10, 100);
   MqlRates rates[];
   ArraySetAsSeries(rates, true);

   int copied = CopyRates(_Symbol, g_signal_timeframe, 0, bars_needed, rates);
   if(copied < 4)
   {
      Print("HA-EMA not enough bars for ", _Symbol, " timeframe=", EnumToString(g_signal_timeframe));
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
      CopyClose(_Symbol, g_signal_timeframe, 1, 1, close) != 1)
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

void FlipToBuy()
{
   if(!InpAllowBuy)
      return;

   CloseOurPositionsExcept(POSITION_TYPE_BUY);

   if(HasOurPositionType(POSITION_TYPE_BUY))
      return;

   if(!CanOpenWithoutAffectingOtherMagic())
      return;

   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(InpSlippagePoints);

   double tp_price = GetTakeProfitPrice(POSITION_TYPE_BUY);
   if(!trade.Buy(InpLotSize, _Symbol, 0.0, 0.0, tp_price, EaComment() + " Buy"))
   {
      Print("HA-EMA buy failed retcode=", trade.ResultRetcode(),
            " message=", trade.ResultRetcodeDescription());
   }
}

void FlipToSell()
{
   if(!InpAllowSell)
      return;

   CloseOurPositionsExcept(POSITION_TYPE_SELL);

   if(HasOurPositionType(POSITION_TYPE_SELL))
      return;

   if(!CanOpenWithoutAffectingOtherMagic())
      return;

   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(InpSlippagePoints);

   double tp_price = GetTakeProfitPrice(POSITION_TYPE_SELL);
   if(!trade.Sell(InpLotSize, _Symbol, 0.0, 0.0, tp_price, EaComment() + " Sell"))
   {
      Print("HA-EMA sell failed retcode=", trade.ResultRetcode(),
            " message=", trade.ResultRetcodeDescription());
   }
}

int GetCurrentSignal()
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

void ExecuteSignal(const int signal)
{
   if(signal > 0)
   {
      Print("HA-EMA bullish signal on ", EnumToString(g_signal_timeframe), ". Closing sells and opening buy.");
      FlipToBuy();
   }
   else if(signal < 0)
   {
      Print("HA-EMA bearish signal on ", EnumToString(g_signal_timeframe), ". Closing buys and opening sell.");
      FlipToSell();
   }
}

void ProcessSignalChange(const bool allow_startup_trade)
{
   int current_signal = GetCurrentSignal();
   if(current_signal == 0)
      return;

   if(g_last_signal == 0)
   {
      g_last_signal = current_signal;
      if(allow_startup_trade)
         ExecuteSignal(current_signal);
      return;
   }

   if(current_signal == g_last_signal)
      return;

   if(g_wait_after_tp)
      Print("HA-EMA signal changed after TP. Trading is enabled again.");

   g_wait_after_tp = false;
   g_last_signal = current_signal;
   ExecuteSignal(current_signal);
}

void MarkWaitAfterTakeProfit()
{
   int current_signal = GetCurrentSignal();
   if(current_signal != 0)
      g_last_signal = current_signal;

   g_wait_after_tp = true;
   Print("HA-EMA TP completed. Waiting for next signal change before opening another trade.");
}

void CheckForNewSignalBar()
{
   datetime current_bar_time = iTime(_Symbol, g_signal_timeframe, 0);
   if(current_bar_time <= 0)
      return;

   if(g_last_bar_time == 0)
   {
      g_last_bar_time = current_bar_time;

      if(!g_startup_checked)
      {
         g_startup_checked = true;
         if(InpTradeCurrentFlipOnStartup)
            ProcessSignalChange(true);
         else
            ProcessSignalChange(false);
      }

      return;
   }

   if(current_bar_time == g_last_bar_time)
      return;

   g_last_bar_time = current_bar_time;
   ProcessSignalChange(true);
}

int OnInit()
{
   if(InpLotSize <= 0.0 || InpEMAPeriod <= 0 || InpTakeProfitMoney < 0.0)
      return INIT_PARAMETERS_INCORRECT;

   g_signal_timeframe = InpSignalTimeframe;

   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(InpSlippagePoints);
   trade.SetTypeFillingBySymbol(_Symbol);

   g_ema_handle = iMA(_Symbol, g_signal_timeframe, InpEMAPeriod, 0, MODE_EMA, PRICE_CLOSE);
   if(g_ema_handle == INVALID_HANDLE)
   {
      Print("HA-EMA failed to create EMA handle. Error=", GetLastError());
      return INIT_FAILED;
   }

   EventSetTimer(1);
   Print("HA-EMA Flip Simple initialized for ", _Symbol,
         " signal timeframe=", EnumToString(g_signal_timeframe),
         ". Chart timeframe changes will not change the signal timeframe.");

   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   EventKillTimer();

   if(g_ema_handle != INVALID_HANDLE)
   {
      IndicatorRelease(g_ema_handle);
      g_ema_handle = INVALID_HANDLE;
   }
}

void OnTick()
{
   CheckForNewSignalBar();
}

void OnTimer()
{
   CheckForNewSignalBar();
}

void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
{
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD || trans.deal == 0)
      return;

   if(!HistoryDealSelect(trans.deal))
      return;

   if(HistoryDealGetString(trans.deal, DEAL_SYMBOL) != _Symbol)
      return;

   if(HistoryDealGetInteger(trans.deal, DEAL_MAGIC) != InpMagicNumber)
      return;

   ENUM_DEAL_ENTRY deal_entry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(trans.deal, DEAL_ENTRY);
   if(deal_entry != DEAL_ENTRY_OUT && deal_entry != DEAL_ENTRY_OUT_BY)
      return;

   ENUM_DEAL_REASON deal_reason = (ENUM_DEAL_REASON)HistoryDealGetInteger(trans.deal, DEAL_REASON);
   if(deal_reason == DEAL_REASON_TP)
      MarkWaitAfterTakeProfit();
}

//+------------------------------------------------------------------+
