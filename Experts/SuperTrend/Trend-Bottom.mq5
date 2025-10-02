//+------------------------------------------------------------------+
//|                                                 Trend-Bottom.mq5 |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "1.00"

//--- Include custom header file
#include "support\GetSpread.mqh"
#include "support\SuperTrendSignal.mqh"
#include "support\OrderManagement.mqh"
#include <Trade\Trade.mqh>

//--- Global variables
double current_spread = 0.0;
static datetime last_candle_time = 0;
static ENUM_ST_SIGNAL last_signal = ST_SIGNAL_NONE;
static double last_stLinePrice = 0;
input bool takePositionsAtStart = false;
input double takeProfitForPosition = 30.0;  // Take profit in account currency
input double stopLossForPosition = 10.0;    // Stop loss in account currency
input bool trackMajorTrend = false;
input ENUM_TIMEFRAMES tradeWithMajorTrend = PERIOD_H1;
input double lotSize = 0.01;
input bool checkOverAllPositionsForProfit = false;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   // Get and store the current spread using the included function
   current_spread = GetSpread();
   // Initialize SuperTrend indicator
   if (!InitSuperTrend())
   {
      Print("Failed to initialize SuperTrend indicator");
      return(INIT_FAILED);
   }
   Sleep(1000);
   getMajorTrend();
   Comment("Expert Advisor initialized. Initial spread: ", current_spread);
   return(INIT_SUCCEEDED);
}
//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   // Clean up SuperTrend indicator handle
   DeinitSuperTrend();
}
//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   checkProfit();
   datetime current_candle_time = iTime(_Symbol, 0, 0);
   double stLinePrice = 0;
   if (current_candle_time != last_candle_time)
   {
      ENUM_ST_SIGNAL current_signal = GetSuperTrendSignal();
      double st_line[1];      
      double spread = GetSpread() * 2.5;
      int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
      datetime expiration = 0; // Good till cancel
      double stopLoss = 0;
      double takeProfit = 0;
      if (CopyBuffer(SuperTrend_Handle, 0, 1, 1, st_line) == 1)
      {
         stLinePrice = st_line[0];
      }
      int majorTrend = trackMajorTrend ? getMajorTrend() : current_signal;
      if (current_signal != ST_SIGNAL_NONE && current_signal != last_signal)
      {
         // Close all positions on any signal change
         // CloseAllPositions();
         if(current_signal == ST_SIGNAL_BUY && (!trackMajorTrend || majorTrend == 1))
         {
            if(takePositionsAtStart){
               m_trade.Buy(lotSize, _Symbol, stLinePrice, stopLoss, takeProfit, "SuperTrend Buy");
            }
            // else{
               double price = stLinePrice + spread;
               price = NormalizeDouble(price, digits);
               PlaceBuyStop(lotSize, price, "SuperTrend Buy Stop");
            // }
         }
         else if(current_signal == ST_SIGNAL_SELL && (!trackMajorTrend || majorTrend == -1))
         {
            if(takePositionsAtStart){
               m_trade.Sell(lotSize, _Symbol, stLinePrice, stopLoss, takeProfit, "SuperTrend Sell");
            }
            // else{
               double price = stLinePrice - spread;
               price = NormalizeDouble(price, digits);
               PlaceSellStop(lotSize, price, "SuperTrend Sell Stop");
            // }
         }
         last_signal = current_signal;
      }
      else
      {
         double buyPrice = NormalizeDouble(stLinePrice + spread, digits);
         double sellPrice = NormalizeDouble(stLinePrice - spread, digits);
         if (stLinePrice != last_stLinePrice)
         {
            updateOrder(buyPrice, sellPrice);
         }
      }
      last_stLinePrice = stLinePrice;
      last_candle_time = current_candle_time;
   }
}

void updateOrder(double buyPrice, double sellPrice) {
   for(int i=0; i<OrdersTotal(); i++)
   {
      ulong ticket = OrderGetTicket(i);
      if(OrderGetString(ORDER_SYMBOL) == _Symbol && OrderGetInteger(ORDER_TYPE) == ORDER_TYPE_BUY_LIMIT)
      {
         double oldPrice = OrderGetDouble(ORDER_PRICE_OPEN);
         if(MathAbs(oldPrice - buyPrice) > SymbolInfoDouble(_Symbol, SYMBOL_POINT) * 0.5)
            ModifyPendingOrder(ticket, buyPrice, 0, 0, ORDER_TIME_GTC, 0, 0.0);
      }
      if(OrderGetString(ORDER_SYMBOL) == _Symbol && OrderGetInteger(ORDER_TYPE) == ORDER_TYPE_SELL_LIMIT)
      {
         double oldPrice = OrderGetDouble(ORDER_PRICE_OPEN);
         if(MathAbs(oldPrice - sellPrice) > SymbolInfoDouble(_Symbol, SYMBOL_POINT) * 0.5)
            ModifyPendingOrder(ticket, sellPrice, 0, 0, ORDER_TIME_GTC, 0, 0.0);
      }
   }
}

void checkProfit() {
   // Skip if both TP and SL are disabled (set to 0)
   if(takeProfitForPosition == 0 && stopLossForPosition == 0)
      return;
      
   // Convert stopLoss to negative if it's positive
   double stopLoss = stopLossForPosition > 0 ? -stopLossForPosition : stopLossForPosition;
   
   if(checkOverAllPositionsForProfit) {
      // Calculate total profit across all positions
      double totalProfit = 0;
      for(int i=PositionsTotal()-1; i>=0; i--)
      {
         ulong ticket = PositionGetTicket(i);
         if(PositionGetString(POSITION_SYMBOL) == _Symbol)
         {
            totalProfit += PositionGetDouble(POSITION_PROFIT);
         }
      }
      
      // Check take profit and stop loss on total profit
      bool tpHit = (takeProfitForPosition != 0 && totalProfit >= takeProfitForPosition);
      bool slHit = (stopLossForPosition != 0 && totalProfit <= stopLoss);
      
      // Close all positions if either condition is met
      if(tpHit || slHit) {
         CloseAllPositions();
      }
      if(tpHit) {
         CancelAllPendingOrders();
      }
   }
   else {
      // Check each position's profit/loss individually
      for(int i=PositionsTotal()-1; i>=0; i--)
      {
         ulong ticket = PositionGetTicket(i);
         if(PositionGetString(POSITION_SYMBOL) == _Symbol)
         {
            double posProfit = PositionGetDouble(POSITION_PROFIT);
            
            // Check take profit if enabled
            bool tpHit = (takeProfitForPosition != 0 && posProfit >= takeProfitForPosition);
            // Check stop loss if enabled
            bool slHit = (stopLossForPosition != 0 && posProfit <= stopLoss);
            
            if(tpHit || slHit)
            {
               m_trade.PositionClose(ticket);
            }
         }
      }
   }
}

int getMajorTrend() {
   // Use SuperTrend on the higher timeframe (tradeWithMajorTrend) to determine major trend
   ENUM_ST_SIGNAL majorSignal = GetSuperTrendSignalForTimeframe(_Symbol, (int)tradeWithMajorTrend);
   
   // Convert signal to trend value
   switch(majorSignal) {
      case ST_SIGNAL_BUY:  return 1;   // Uptrend
      case ST_SIGNAL_SELL: return -1;  // Downtrend
      default:             return 0;   // No trend
   }
}
//+------------------------------------------------------------------+
