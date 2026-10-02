//+------------------------------------------------------------------+
//|                                               Grid_XAUUSD_EA.mq5 |
//|                                  Copyright 2024, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Gemini Code Assist"
#property link      "https://www.mql5.com"
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>

//--- Enums
enum ENUM_PROFIT_CURRENCY
  {
   PROFIT_CURRENCY_USD, // USD ($)
   PROFIT_CURRENCY_INR  // INR (₹)
  };

//--- Input parameters
input double   InpLotSize        = 0.01;     // Lot Size
input double   InpBuyStep        = 10.0;     // Buy Step (Price change, e.g. 10.0)
input double   InpSellStep       = 15.0;     // Sell Step (Price change, e.g. 15.0)
input ENUM_PROFIT_CURRENCY InpCurrency = PROFIT_CURRENCY_INR; // Profit/Loss Currency
input double   InpTP             = 130.0;    // Take Profit (in selected currency)
input double   InpSL             = 260.0;    // Stop Loss (in selected currency)
input double   InpUSDINR_Rate    = 0.0;      // Manual USDINR Rate (0=Auto)
input int      InpMaxTradesLevel = 2;        // Max trades per level
input int      InpMagic          = 999001;   // Magic Number
input int      InpSlippage       = 3;        // Slippage

//--- Global variables
CTrade         trade;
datetime       ExtLastCandleTime = 0;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(InpSlippage);
   
   // Validate Symbol
   if(StringFind(Symbol(), "XAU") == -1 && StringFind(Symbol(), "GOLD") == -1)
     {
      Print("Warning: This EA is designed for XAUUSD/GOLD. Current symbol: ", Symbol());
     }
   
   // Try to select USDINR for rate retrieval
   SymbolSelect("USDINR", true);
   
   // Print configuration for debugging
   Print("EA Initialized. Currency: ", EnumToString(InpCurrency), 
         " | TP: ", InpTP, " | SL: ", InpSL);

   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
   datetime current_bar_time = (datetime)SeriesInfoInteger(Symbol(), Period(), SERIES_LASTBAR_DATE);

   // 1. Immediate local check to prevent multiple trades in the same candle due to latency
   if(current_bar_time == ExtLastCandleTime) return;

   // Check if we already traded on this candle (Only 1 trade per candle)
   if(IsTradeOnCandle(current_bar_time))
     {
      ExtLastCandleTime = current_bar_time;
      return;
     }

   // Update symbol info
   double ask = SymbolInfoDouble(Symbol(), SYMBOL_ASK);
   double bid = SymbolInfoDouble(Symbol(), SYMBOL_BID);
   
   // Determine Anchor Price (Last Open Trade Price or Current Bid)
   double anchorPrice = GetLastOpenPrice();
   if(anchorPrice == 0) anchorPrice = bid;
   
   // Tolerance for triggering the level (e.g. within 0.50 price units of the level)
   double tolerance = 0.50; 

   // --- BUY LOGIC (On Drops) ---
   // Calculate next Buy Level based on Anchor
   double buyLevel = anchorPrice - InpBuyStep;
   
   // Check if price is at the level
   if(MathAbs(ask - buyLevel) <= tolerance)
     {
      // Check if we can trade this level (Max 2 trades per 30 mins)
      if(CanTradeAtLevel(buyLevel, POSITION_TYPE_BUY, tolerance))
        {
         if(trade.Buy(InpLotSize, Symbol(), ask, 0, 0, "Grid Buy " + DoubleToString(buyLevel, 1)))
           {
            ExtLastCandleTime = current_bar_time; // Mark this candle as traded immediately
            ulong ticket = trade.ResultOrder();
            if(ticket > 0)
              {
               for(int i=0; i<10; i++)
                 {
                  if(PositionSelectByTicket(ticket))
                    {
                     double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
                     double sl_price = 0, tp_price = 0;
                     CalculateSLTP(POSITION_TYPE_BUY, openPrice, sl_price, tp_price);
                     trade.PositionModify(ticket, sl_price, tp_price);
                     break;
                    }
                  Sleep(100);
                 }
              }
           }
        }
     }

   // --- SELL LOGIC (On Rise) ---
   // Calculate next Sell Level based on Anchor
   double sellLevel = anchorPrice + InpSellStep;
   
   if(MathAbs(bid - sellLevel) <= tolerance)
     {
      if(CanTradeAtLevel(sellLevel, POSITION_TYPE_SELL, tolerance))
        {
         if(trade.Sell(InpLotSize, Symbol(), bid, 0, 0, "Grid Sell " + DoubleToString(sellLevel, 1)))
           {
            ExtLastCandleTime = current_bar_time; // Mark this candle as traded immediately
            ulong ticket = trade.ResultOrder();
            if(ticket > 0)
              {
               for(int i=0; i<10; i++)
                 {
                  if(PositionSelectByTicket(ticket))
                    {
                     double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
                     double sl_price = 0, tp_price = 0;
                     CalculateSLTP(POSITION_TYPE_SELL, openPrice, sl_price, tp_price);
                     trade.PositionModify(ticket, sl_price, tp_price);
                     break;
                    }
                  Sleep(100);
                 }
              }
           }
        }
     }
  }

//+------------------------------------------------------------------+
//| Check if we can trade at this level                              |
//+------------------------------------------------------------------+
bool CanTradeAtLevel(double level, ENUM_POSITION_TYPE type, double tolerance)
  {
   int count = 0;
   datetime cutoff_time = TimeCurrent() - (30 * 60); // Default 30 min lookback for history

   // 1. Check Open Positions (Active trades at this level)
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
        {
         if(PositionGetString(POSITION_SYMBOL) == Symbol() && PositionGetInteger(POSITION_MAGIC) == InpMagic)
           {
            if(PositionGetInteger(POSITION_TYPE) == type)
              {
               // Check if position was opened near this level
               // We use the Open Price of the position
               double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
               if(MathAbs(openPrice - level) <= tolerance)
                 {
                  count++;
                 }
              }
           }
        }
     }

   // 2. Check History (Trades in the last 30 mins at this level)
   HistorySelect(cutoff_time, TimeCurrent());
   for(int i = HistoryDealsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = HistoryDealGetTicket(i);
      if(HistoryDealSelect(ticket))
        {
         if(HistoryDealGetString(ticket, DEAL_SYMBOL) == Symbol() && HistoryDealGetInteger(ticket, DEAL_MAGIC) == InpMagic)
           {
            ENUM_DEAL_ENTRY entry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(ticket, DEAL_ENTRY);
            if(entry == DEAL_ENTRY_IN) // Only count entry deals
              {
               ENUM_DEAL_TYPE dealType = (ENUM_DEAL_TYPE)HistoryDealGetInteger(ticket, DEAL_TYPE);
               
               bool match = (type == POSITION_TYPE_BUY && dealType == DEAL_TYPE_BUY) || 
                            (type == POSITION_TYPE_SELL && dealType == DEAL_TYPE_SELL);
               
               if(match)
                 {
                  double price = HistoryDealGetDouble(ticket, DEAL_PRICE);
                  if(MathAbs(price - level) <= tolerance)
                    {
                     count++;
                    }
                 }
              }
           }
        }
     }

   return (count < InpMaxTradesLevel);
  }

//+------------------------------------------------------------------+
//| Calculate SL and TP prices based on USD amount                   |
//+------------------------------------------------------------------+
void CalculateSLTP(ENUM_POSITION_TYPE type, double open_price, double &sl, double &tp)
  {
   // Calculate price distance required for the target USD Profit/Loss
   // Formula: Distance = TargetUSD / (ContractSize * LotSize)
   
   double target_tp_usd = InpTP;
   double target_sl_usd = InpSL;

   // Convert INR to USD if selected
   if(InpCurrency == PROFIT_CURRENCY_INR)
     {
      double usdinr = InpUSDINR_Rate;
      if(usdinr <= 0)
        {
         usdinr = SymbolInfoDouble("USDINR", SYMBOL_BID);
         if(usdinr == 0) usdinr = 87.0; // Fallback if not found
        }
      target_tp_usd = InpTP / usdinr;
      target_sl_usd = InpSL / usdinr;
     }
   
   double contract_size = SymbolInfoDouble(Symbol(), SYMBOL_TRADE_CONTRACT_SIZE);
   if(contract_size == 0) contract_size = 100; // Default Standard Lot for XAUUSD (100 oz)
   
   double distance_tp = target_tp_usd / (contract_size * InpLotSize);
   double distance_sl = target_sl_usd / (contract_size * InpLotSize);
   
   if(type == POSITION_TYPE_BUY)
     {
      tp = open_price + distance_tp;
      sl = open_price - distance_sl;
     }
   else
     {
      tp = open_price - distance_tp;
      sl = open_price + distance_sl;
     }
     
   // Normalize to tick size
   double tick_size = SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_SIZE);
   if(tick_size > 0)
     {
      tp = MathRound(tp / tick_size) * tick_size;
      sl = MathRound(sl / tick_size) * tick_size;
     }
  }

//+------------------------------------------------------------------+
//| Count open positions for this EA                                 |
//+------------------------------------------------------------------+
int CountOpenPositions()
  {
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
        {
         if(PositionGetString(POSITION_SYMBOL) == Symbol() && PositionGetInteger(POSITION_MAGIC) == InpMagic)
            count++;
        }
     }
   return count;
  }

//+------------------------------------------------------------------+
//| Check if a trade occurred on the current candle                  |
//+------------------------------------------------------------------+
bool IsTradeOnCandle(datetime start_time)
  {
   HistorySelect(start_time, TimeCurrent());
   for(int i = HistoryDealsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = HistoryDealGetTicket(i);
      if(HistoryDealSelect(ticket))
        {
         if(HistoryDealGetString(ticket, DEAL_SYMBOL) == Symbol() && HistoryDealGetInteger(ticket, DEAL_MAGIC) == InpMagic)
           {
            ENUM_DEAL_ENTRY entry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(ticket, DEAL_ENTRY);
            if(entry == DEAL_ENTRY_IN) return true;
           }
        }
     }
   return false;
  }

//+------------------------------------------------------------------+
//| Get the Open Price of the last opened position                   |
//+------------------------------------------------------------------+
double GetLastOpenPrice()
  {
   double lastPrice = 0;
   long lastTime = 0;
   
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
        {
         if(PositionGetString(POSITION_SYMBOL) == Symbol() && PositionGetInteger(POSITION_MAGIC) == InpMagic)
           {
            long posTime = PositionGetInteger(POSITION_TIME_MSC);
            if(posTime > lastTime)
              {
               lastTime = posTime;
               lastPrice = PositionGetDouble(POSITION_PRICE_OPEN);
              }
           }
        }
     }
   return lastPrice;
  }