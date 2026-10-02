//+------------------------------------------------------------------+
//|                                         OrderManagement.mqh      |
//|         Utility functions for order management in MQL5           |
//+------------------------------------------------------------------+

#include <Trade\Trade.mqh>
CTrade m_trade;

//+------------------------------------------------------------------+
//| Initialize magic number for order management                   |
//+------------------------------------------------------------------+
void InitOrderManagement(int magic)
{
   m_trade.SetExpertMagicNumber(magic);
   Print("OrderManagement: Magic number set to ", magic);
}

//+------------------------------------------------------------------+

// Place a pending BUY order (auto chooses BuyLimit or BuyStop based on price vs Ask)
bool PlaceBuyStop(double lot_Size, double price, string comment = "", double stopLoss = 0, double takeProfit = 0)
{
   datetime expiration = 0;
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   int stops_level = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   double min_dist = stops_level * point;

   price = NormalizeDouble(price, digits);
   if(stopLoss > 0.0) stopLoss = NormalizeDouble(stopLoss, digits);
   if(takeProfit > 0.0) takeProfit = NormalizeDouble(takeProfit, digits);

   bool result = false;
   if(price < ask - min_dist)
   {
      result = m_trade.BuyLimit(lot_Size, price, _Symbol, stopLoss, takeProfit, ORDER_TIME_GTC, expiration, comment);
   }
   else if(price > ask + min_dist)
   {
      result = m_trade.BuyStop(lot_Size, price, _Symbol, stopLoss, takeProfit, ORDER_TIME_GTC, expiration, comment);
   }
   else
   {
      double adj_price = NormalizeDouble(ask - (min_dist > 0 ? min_dist : point), digits);
      result = m_trade.BuyLimit(lot_Size, adj_price, _Symbol, stopLoss, takeProfit, ORDER_TIME_GTC, expiration, comment);
   }

   if(!result)
   {
      Print("BUY Pending order failed: ", m_trade.ResultRetcode(), " [", m_trade.ResultRetcodeDescription(), "] Price=", price, " Ask=", ask);
      return false;
   }
   return true;
}

// Place a pending SELL order (auto chooses SellLimit or SellStop based on price vs Bid)
bool PlaceSellStop(double lot_Size, double price, string comment = "", double stopLoss = 0, double takeProfit = 0)
{
   datetime expiration = 0;
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   int stops_level = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   double min_dist = stops_level * point;

   price = NormalizeDouble(price, digits);
   if(stopLoss > 0.0) stopLoss = NormalizeDouble(stopLoss, digits);
   if(takeProfit > 0.0) takeProfit = NormalizeDouble(takeProfit, digits);

   bool result = false;
   if(price > bid + min_dist)
   {
      result = m_trade.SellLimit(lot_Size, price, _Symbol, stopLoss, takeProfit, ORDER_TIME_GTC, expiration, comment);
   }
   else if(price < bid - min_dist)
   {
      result = m_trade.SellStop(lot_Size, price, _Symbol, stopLoss, takeProfit, ORDER_TIME_GTC, expiration, comment);
   }
   else
   {
      double adj_price = NormalizeDouble(bid + (min_dist > 0 ? min_dist : point), digits);
      result = m_trade.SellLimit(lot_Size, adj_price, _Symbol, stopLoss, takeProfit, ORDER_TIME_GTC, expiration, comment);
   }

   if(!result)
   {
      Print("SELL Pending order failed: ", m_trade.ResultRetcode(), " [", m_trade.ResultRetcodeDescription(), "] Price=", price, " Bid=", bid);
      return false;
   }
   return true;
}
//+------------------------------------------------------------------+
//| Modify an existing pending order using CTrade::OrderModify      |
//+------------------------------------------------------------------+
bool ModifyPendingOrder(ulong ticket, double newPrice, double stoploss = 0, double takeprofit = 0, ENUM_ORDER_TYPE_TIME type_time = ORDER_TIME_GTC, datetime expiration = 0, double stoplimit = 0.0)
{
   bool result = m_trade.OrderModify(ticket, newPrice, stoploss, takeprofit, type_time, expiration, stoplimit);
   if(!result)
   {
      Print("Order modification failed: ", m_trade.ResultRetcode());
      return false;
   }
   return true;
}
//+------------------------------------------------------------------+
//| Close all open positions for the current symbol                 |
//+------------------------------------------------------------------+
void CloseAllPositions()
{
   for(int i=PositionsTotal()-1; i>=0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionGetString(POSITION_SYMBOL) == _Symbol)
      {
         m_trade.PositionClose(ticket);
      }
   }
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
         m_trade.OrderDelete(ticket);
      }
   }
}


