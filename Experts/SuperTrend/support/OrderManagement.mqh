//+------------------------------------------------------------------+
//|                                         OrderManagement.mqh      |
//|         Utility functions for order management in MQL5           |
//+------------------------------------------------------------------+

#include <Trade\Trade.mqh>
CTrade m_trade;
//+------------------------------------------------------------------+

// Place a pending BUY STOP order using CTrade object
bool PlaceBuyStop(double lotSize, double price, string comment = "", double stopLoss = 0, double takeProfit = 0)
{
   // stopLoss/takeProfit = 0 means no SL/TP
   datetime expiration = 0;
   bool result = m_trade.BuyLimit(lotSize, price, _Symbol, stopLoss, takeProfit, ORDER_TIME_GTC, expiration, comment);
   if(!result)
   {
      Print("BUY STOP order failed: ", m_trade.ResultRetcode());
      return false;
   }
   return true;
}

// Place a pending SELL STOP order using CTrade object
bool PlaceSellStop(double lotSize, double price, string comment = "", double stopLoss = 0, double takeProfit = 0)
{
   // stopLoss/takeProfit = 0 means no SL/TP
   datetime expiration = 0;
   bool result = m_trade.SellLimit(lotSize, price, _Symbol, stopLoss, takeProfit, ORDER_TIME_GTC, expiration, comment);
   if(!result)
   {
      Print("SELL STOP order failed: ", m_trade.ResultRetcode());
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


