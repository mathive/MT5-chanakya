//+-------------------   if(m_take_profit > 0)
   {
      // For buy orders, take profit is above entry price
      // Convert dollar amount to price points based on symbol
      double tick_value = m_symbol.TickValue();
      double tick_size = m_symbol.T   if(m_take_profit > 0)
   {
      // For sell orders, take profit is below entry price
      // Convert dollar amount to price points based on symbol
      double tick_value = m_symbol.TickValue();
      double tick_size = m_symbol.TickSize();
      double profit_points = m_take_profit / tick_value * tick_size;
      takeProfit = m_entry_price - profit_points;
      
      Print("Sell TP Calculation: Dollar amount=", m_take_profit, 
            ", TickValue=", tick_value,
            ", TickSize=", tick_size,
            ", Price distance=", profit_points);
      Print("Setting Sell Take Profit at: ", takeProfit, " (", m_take_profit, " dollars from entry)");
   });
      double profit_points = m_take_profit / tick_value * tick_size;
      takeProfit = m_entry_price + profit_points;
      
      Print("Buy TP Calculation: Dollar amount=", m_take_profit, 
            ", TickValue=", tick_value,
            ", TickSize=", tick_size,
            ", Price distance=", profit_points);
      Print("Setting Buy Take Profit at: ", takeProfit, " (", m_take_profit, " dollars from entry)");
   }---------------------------------------+
//|                                                OrderManager.mqh |
//|                                       Cop   // Calculate SL and TP prices if they are set (in dollar terms)
   double stopLoss = 0;
   double takeProfit = 0;
   
   if(m_stop_loss > 0)
   {
      // For buy orders, stop loss is below entry price
      // Convert dollar amount to price points based on symbol
      double tick_value = m_symbol.TickValue();
      double tick_size = m_symbol.TickSize();
      double stop_points = m_stop_loss / tick_value * tick_size;
      stopLoss = m_entry_price - stop_points;
      
      Print("Buy SL Calculation: Dollar amount=", m_stop_loss, 
            ", TickValue=", tick_value,
            ", TickSize=", tick_size,
            ", Price distance=", stop_points);
      Print("Setting Buy Stop Loss at: ", stopLoss, " (", m_stop_loss, " dollars from entry)");
   }
   
   if(m_take_profit > 0)
   {
      // For buy orders, take profit is above entry price
      // Convert dollar amount to price points based on symbol
      double tp_points = m_take_profit / m_symbol.TickValue() * m_symbol.TickSize();
      takeProfit = m_entry_price + tp_points;
      Print("Setting Buy Take Profit at: ", takeProfit, " (", m_take_profit, " dollars from entry)");
   }
   
   datetime expiration = 0; // 0 means no expiration
   
   if(m_trade.BuyLimit(m_lot_size, m_entry_price, m_symbol.Name(), stopLoss, takeProfit, ORDER_TIME_GTC, expiration, "SuperTrend Buy Limit")) 2025, Supertrend |
//|                                                                  |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, Supertrend"
#property link      ""

//--- Include
#include <Trade\Trade.mqh>
#include <Trade\SymbolInfo.mqh>
#include "SpreadCalc.mqh"

//+------------------------------------------------------------------+
//| OrderManager Class                                               |
//| Handles order creation, modification and tracking                 |
//+------------------------------------------------------------------+
class COrderManager
{
private:
   CTrade            m_trade;            // Trading object
   CSymbolInfo       m_symbol;           // Symbol info object
   int               m_magic_number;     // EA Magic Number
   double            m_lot_size;         // Trading lot size
   ulong             m_ticket;           // Ticket number of the pending order
   bool              m_order_placed;     // Flag to track if pending order is placed
   double            m_entry_price;      // Calculated entry price with spread offset
   int               m_stored_spread;    // Spread value in points
   double            m_take_profit;      // Take profit in points
   double            m_stop_loss;        // Stop loss in points
   
public:
   // Constructor
                     COrderManager();
   // Destructor
                    ~COrderManager();
                    
   // Initialize the OrderManager
   bool              Init(const string symbol, const int magicNumber, const double lotSize, 
                         const double takeProfit = 0.0, const double stopLoss = 0.0);
   
   // Set spread adjustment value
   void              SetSpread(const int spread) { m_stored_spread = spread; }
   
   // Create Buy Limit order at SuperTrend lower line
   bool              CreateBuyLimitOrder(const double lowerLine);
   
   // Create Sell Limit order at SuperTrend upper line
   bool              CreateSellLimitOrder(const double upperLine);
   
   // Update Buy Limit order price when SuperTrend moves
   bool              UpdateBuyLimitOrder(const double lowerLine);
   
   // Update Sell Limit order price when SuperTrend moves
   bool              UpdateSellLimitOrder(const double upperLine);
   
   // Update Pending Order Price based on signal type
   bool              UpdatePendingOrderPrice(const int signal, const double upperLine, const double lowerLine);
   
   // Close all positions
   void              CloseAllPositions();
   
   // Cancel all pending orders
   void              CancelAllPendingOrders();
   
   // Check if order still exists
   bool              OrderExists();
   
   // Check if we have open positions
   bool              HasOpenPositions();
   
   // Getters
   bool              IsOrderPlaced() const { return m_order_placed; }
   ulong             GetTicket() const { return m_ticket; }
   double            GetEntryPrice() const { return m_entry_price; }
};

//+------------------------------------------------------------------+
//| Constructor                                                       |
//+------------------------------------------------------------------+
COrderManager::COrderManager()
{
   m_ticket = 0;
   m_order_placed = false;
   m_entry_price = 0;
   m_stored_spread = 0;
   m_take_profit = 0.0;
   m_stop_loss = 0.0;
}

//+------------------------------------------------------------------+
//| Destructor                                                        |
//+------------------------------------------------------------------+
COrderManager::~COrderManager()
{
   // Nothing to clean up
}

//+------------------------------------------------------------------+
//| Initialize the OrderManager                                       |
//+------------------------------------------------------------------+
bool COrderManager::Init(const string symbol, const int magicNumber, const double lotSize, 
                        const double takeProfit = 0.0, const double stopLoss = 0.0)
{
   // Initialize magic number
   m_magic_number = magicNumber;
   
   // Initialize lot size
   m_lot_size = lotSize;
   
   // Initialize take profit and stop loss
   m_take_profit = takeProfit;
   m_stop_loss = stopLoss;
   
   // Initialize the trading object
   m_trade.SetExpertMagicNumber(magicNumber);
   
   // Initialize symbol object
   if(!m_symbol.Name(symbol))
   {
      Print("Failed to initialize symbol object");
      return false;
   }
   
   // Log symbol properties for debugging
   m_symbol.RefreshRates();
   double tick_value = m_symbol.TickValue();
   double tick_size = m_symbol.TickSize();
   double point = m_symbol.Point();
   
   Print("OrderManager Init - Symbol: ", symbol,
         ", TickValue: ", DoubleToString(tick_value, 8),
         ", TickSize: ", DoubleToString(tick_size, 8),
         ", Point: ", DoubleToString(point, 8));
   
   if(takeProfit > 0 || stopLoss > 0)
   {
      Print("Using dollar-based risk: TP=", takeProfit, " USD, SL=", stopLoss, " USD");
      
      // Show example calculation
      if(takeProfit > 0)
      {
         double tp_points = takeProfit / tick_value * tick_size;
         Print("Example calculation: ", takeProfit, " USD = ", 
               DoubleToString(tp_points, 5), " price distance");
      }
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| Create Buy Limit order at SuperTrend lower line                   |
//+------------------------------------------------------------------+
bool COrderManager::CreateBuyLimitOrder(const double lowerLine)
{
   // Reset order tracking
   m_order_placed = false;
   m_ticket = 0;
   
   // Validate the input price
   if(lowerLine <= 0 || lowerLine == EMPTY_VALUE)
   {
      Print("ERROR: Invalid SuperTrend lower line value: ", lowerLine);
      return false;
   }
   
   // Refresh symbol info to ensure accurate calculations
   m_symbol.RefreshRates();
   
   // Calculate the spread adjustment in price
   double spreadAdjustment = m_stored_spread * SymbolInfoDouble(m_symbol.Name(), SYMBOL_POINT);
   
   // Buy signal: entry price is ABOVE the lower (green) SuperTrend line + spread (offset)
   // Adding spreadAdjustment*2 to place the order ABOVE the line
   m_entry_price = lowerLine + spreadAdjustment * 2; // Double the offset to ensure it's above the line
   
   // Place a BUY LIMIT order (pending order)
   datetime expiration = 0; // 0 means no expiration
   
   if(m_trade.BuyLimit(m_lot_size, m_entry_price, m_symbol.Name(), stopLoss, takeProfit, ORDER_TIME_GTC, expiration, "SuperTrend Buy Limit"))
   {
      m_ticket = m_trade.ResultOrder(); // Store the ticket number
      Print("Placed BUY LIMIT order #", m_ticket, " at price: ", m_entry_price);
      m_order_placed = true;
      return true;
   }
   else
   {
      Print("Failed to place BUY LIMIT order. Error: ", GetLastError());
      return false;
   }
}

//+------------------------------------------------------------------+
//| Create Sell Limit order at SuperTrend upper line                  |
//+------------------------------------------------------------------+
bool COrderManager::CreateSellLimitOrder(const double upperLine)
{
   // Reset order tracking
   m_order_placed = false;
   m_ticket = 0;
   
   // Validate the input price
   if(upperLine <= 0 || upperLine == EMPTY_VALUE)
   {
      Print("ERROR: Invalid SuperTrend upper line value: ", upperLine);
      return false;
   }
   
   // Refresh symbol info to ensure accurate calculations
   m_symbol.RefreshRates();
   
   // Calculate the spread adjustment in price
   double spreadAdjustment = m_stored_spread * SymbolInfoDouble(m_symbol.Name(), SYMBOL_POINT);
   
   // Sell signal: entry price is BELOW the upper (red) SuperTrend line - spread (offset)
   // We're subtracting spreadAdjustment to place the order BELOW the line
   m_entry_price = upperLine - spreadAdjustment * 2; // Double the offset to ensure it's below the line
   
   // Calculate SL and TP prices if they are set (in dollar terms)
   double stopLoss = 0;
   double takeProfit = 0;
   
   if(m_stop_loss > 0)
   {
      // For sell orders, stop loss is above entry price
      // Convert dollar amount to price points based on symbol
      double tick_value = m_symbol.TickValue();
      double tick_size = m_symbol.TickSize();
      double stop_points = m_stop_loss / tick_value * tick_size;
      stopLoss = m_entry_price + stop_points;
      
      Print("Sell SL Calculation: Dollar amount=", m_stop_loss, 
            ", TickValue=", tick_value,
            ", TickSize=", tick_size,
            ", Price distance=", stop_points);
      Print("Setting Sell Stop Loss at: ", stopLoss, " (", m_stop_loss, " dollars from entry)");
   }
   
   if(m_take_profit > 0)
   {
      // For sell orders, take profit is below entry price
      // Convert dollar amount to price points based on symbol
      double tp_points = m_take_profit / m_symbol.TickValue() * m_symbol.TickSize();
      takeProfit = m_entry_price - tp_points;
      Print("Setting Sell Take Profit at: ", takeProfit, " (", m_take_profit, " dollars from entry)");
   }
   
   datetime expiration = 0; // 0 means no expiration
   
   if(m_trade.SellLimit(m_lot_size, m_entry_price, m_symbol.Name(), stopLoss, takeProfit, ORDER_TIME_GTC, expiration, "SuperTrend Sell Limit"))
   {
      m_ticket = m_trade.ResultOrder(); // Store the ticket number
      Print("Placed SELL LIMIT order #", m_ticket, " at price: ", m_entry_price);
      m_order_placed = true;
      return true;
   }
   else
   {
      Print("Failed to place SELL LIMIT order. Error: ", GetLastError());
      return false;
   }
}

//+------------------------------------------------------------------+
//| Update Pending Order Price based on signal type                   |
//+------------------------------------------------------------------+
bool COrderManager::UpdatePendingOrderPrice(const int signal, const double upperLine, const double lowerLine)
{
   static datetime last_check_time = 0;
   datetime current_time = iTime(m_symbol.Name(), Period(), 0);
   
   // Limit checks to once per bar unless testing
   if(current_time == last_check_time && !MQLInfoInteger(MQL_TESTER))
      return true;
      
   last_check_time = current_time;
   
   // Check if order still exists
   if(!OrderExists())
   {
      return false;
   }
   
   // Validate line values before updating
   if(signal == 1 && (lowerLine <= 0 || lowerLine == EMPTY_VALUE))
   {
      Print("WARNING: Cannot update buy limit order - Invalid lower line value: ", lowerLine);
      return false;
   }
   else if(signal == -1 && (upperLine <= 0 || upperLine == EMPTY_VALUE))
   {
      Print("WARNING: Cannot update sell limit order - Invalid upper line value: ", upperLine);
      return false;
   }
   
   // Update based on signal type
   if(signal == 1) // Buy signal
   {
      return UpdateBuyLimitOrder(lowerLine);
   }
   else if(signal == -1) // Sell signal
   {
      return UpdateSellLimitOrder(upperLine);
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| Update Buy Limit order price when SuperTrend moves                |
//+------------------------------------------------------------------+
bool COrderManager::UpdateBuyLimitOrder(const double lowerLine)
{
   // Store timeframe for updates
   static datetime last_update_time = 0;
   datetime current_time = iTime(m_symbol.Name(), Period(), 0);
   
   // Skip if we've already updated in this timeframe bar and not enough price change
   if(current_time == last_update_time && !MQLInfoInteger(MQL_TESTER)) // In live trading, respect timeframe
      return true; // No need to update yet
      
   // Refresh symbol info to ensure accurate calculations
   m_symbol.RefreshRates();
   
   // Calculate the spread adjustment in price
   double spreadAdjustment = m_stored_spread * SymbolInfoDouble(m_symbol.Name(), SYMBOL_POINT);
   // Buy signal: Update price to be ABOVE the lower (green) SuperTrend line + spread
   // Double the offset to ensure it's above the line
   double newPrice = lowerLine + spreadAdjustment * 2;
   
   // Debug logging
   Print("UpdateBuyLimitOrder - Line: ", lowerLine, 
         ", SpreadAdjustment: ", spreadAdjustment,
         ", New Price: ", newPrice);
   
   // Only modify if price has changed significantly (avoid too frequent updates)
   double currentPrice = OrderGetDouble(ORDER_PRICE_OPEN);
   
   // Update if: 1) New bar formed OR 2) Significant price change
   bool significantChange = MathAbs(newPrice - currentPrice) > 
                            SymbolInfoDouble(m_symbol.Name(), SYMBOL_POINT) * 3; // More threshold for change
   
   if(significantChange || current_time != last_update_time)
   {
      // Recalculate SL and TP for the new price
      double newSL = OrderGetDouble(ORDER_SL);
      double newTP = OrderGetDouble(ORDER_TP);
      
      // Only recalculate if we're using our own SL/TP (not zero)
      if(m_stop_loss > 0)
      {
         // Convert dollar amount to price points based on symbol
         double tick_value = m_symbol.TickValue();
         double tick_size = m_symbol.TickSize();
         double stop_points = m_stop_loss / tick_value * tick_size;
         newSL = newPrice - stop_points;  // Below entry price for buy
         
         Print("Update Buy SL: Dollar amount=", m_stop_loss, 
               ", TickValue=", tick_value,
               ", TickSize=", tick_size,
               ", Price distance=", stop_points,
               ", New SL=", newSL);
      }
      
      if(m_take_profit > 0)
      {
         // Convert dollar amount to price points based on symbol
         double tick_value = m_symbol.TickValue();
         double tick_size = m_symbol.TickSize();
         double tp_points = m_take_profit / tick_value * tick_size;
         newTP = newPrice + tp_points; // Above entry price for buy
         
         Print("Update Buy TP: Dollar amount=", m_take_profit, 
               ", TickValue=", tick_value,
               ", TickSize=", tick_size,
               ", Price distance=", tp_points,
               ", New TP=", newTP);
      }
      
      if(m_trade.OrderModify(
         m_ticket,                         // Ticket
         newPrice,                         // New price
         newSL,                            // Updated Stop Loss
         newTP,                            // Updated Take Profit
         (ENUM_ORDER_TYPE_TIME)OrderGetInteger(ORDER_TYPE_TIME), // Keep existing type time (with proper cast)
         OrderGetInteger(ORDER_TIME_EXPIRATION), // Keep existing expiration
         OrderGetDouble(ORDER_PRICE_STOPLIMIT) // Keep existing Stop Limit price
      ))
      {
         m_entry_price = newPrice;
         Print("Updated BUY LIMIT order #", m_ticket, " to new price: ", newPrice, 
               ", SL: ", newSL, ", TP: ", newTP);
         last_update_time = current_time; // Store the update time
         return true;
      }
      else
      {
         Print("Failed to modify BUY LIMIT order #", m_ticket, ". Error: ", GetLastError());
         return false;
      }
   }
   
   return true; // No update needed
}

//+------------------------------------------------------------------+
//| Update Sell Limit order price when SuperTrend moves               |
//+------------------------------------------------------------------+
bool COrderManager::UpdateSellLimitOrder(const double upperLine)
{
   // Store timeframe for updates
   static datetime last_update_time = 0;
   datetime current_time = iTime(m_symbol.Name(), Period(), 0);
   
   // Skip if we've already updated in this timeframe bar and not enough price change
   if(current_time == last_update_time && !MQLInfoInteger(MQL_TESTER)) // In live trading, respect timeframe
      return true; // No need to update yet
      
   // Refresh symbol info to ensure accurate calculations
   m_symbol.RefreshRates();
      
   // Calculate the spread adjustment in price
   double spreadAdjustment = m_stored_spread * SymbolInfoDouble(m_symbol.Name(), SYMBOL_POINT);
   // Sell signal: Update price to be BELOW the upper (red) SuperTrend line - spread
   // Double the offset to ensure it's below the line
   double newPrice = upperLine - spreadAdjustment * 2;
   
   // Debug logging
   Print("UpdateSellLimitOrder - Line: ", upperLine, 
         ", SpreadAdjustment: ", spreadAdjustment,
         ", New Price: ", newPrice);
   
   // Only modify if price has changed significantly (avoid too frequent updates)
   double currentPrice = OrderGetDouble(ORDER_PRICE_OPEN);
   
   // Update if: 1) New bar formed OR 2) Significant price change
   bool significantChange = MathAbs(newPrice - currentPrice) > 
                            SymbolInfoDouble(m_symbol.Name(), SYMBOL_POINT) * 3; // More threshold for change
   
   if(significantChange || current_time != last_update_time)
   {
      // Recalculate SL and TP for the new price
      double newSL = OrderGetDouble(ORDER_SL);
      double newTP = OrderGetDouble(ORDER_TP);
      
      // Only recalculate if we're using our own SL/TP (not zero)
      if(m_stop_loss > 0)
      {
         // Convert dollar amount to price points based on symbol
         double tick_value = m_symbol.TickValue();
         double tick_size = m_symbol.TickSize();
         double stop_points = m_stop_loss / tick_value * tick_size;
         newSL = newPrice + stop_points;  // Above entry price for sell
         
         Print("Update Sell SL: Dollar amount=", m_stop_loss, 
               ", TickValue=", tick_value,
               ", TickSize=", tick_size,
               ", Price distance=", stop_points,
               ", New SL=", newSL);
      }
      
      if(m_take_profit > 0)
      {
         // Convert dollar amount to price points based on symbol
         double tick_value = m_symbol.TickValue();
         double tick_size = m_symbol.TickSize();
         double tp_points = m_take_profit / tick_value * tick_size;
         newTP = newPrice - tp_points; // Below entry price for sell
         
         Print("Update Sell TP: Dollar amount=", m_take_profit, 
               ", TickValue=", tick_value,
               ", TickSize=", tick_size,
               ", Price distance=", tp_points,
               ", New TP=", newTP);
      }
      
      if(m_trade.OrderModify(
         m_ticket,                         // Ticket
         newPrice,                         // New price
         newSL,                            // Updated Stop Loss
         newTP,                            // Updated Take Profit
         (ENUM_ORDER_TYPE_TIME)OrderGetInteger(ORDER_TYPE_TIME), // Keep existing type time (with proper cast)
         OrderGetInteger(ORDER_TIME_EXPIRATION), // Keep existing expiration
         OrderGetDouble(ORDER_PRICE_STOPLIMIT) // Keep existing Stop Limit price
      ))
      {
         m_entry_price = newPrice;
         Print("Updated SELL LIMIT order #", m_ticket, " to new price: ", newPrice, 
               ", SL: ", newSL, ", TP: ", newTP);
         last_update_time = current_time; // Store the update time
         return true;
      }
      else
      {
         Print("Failed to modify SELL LIMIT order #", m_ticket, ". Error: ", GetLastError());
         return false;
      }
   }
   
   return true; // No update needed
}

//+------------------------------------------------------------------+
//| Check if order still exists                                      |
//+------------------------------------------------------------------+
bool COrderManager::OrderExists()
{
   if(!OrderSelect(m_ticket))
   {
      // Order may have been executed or canceled
      m_order_placed = false;
      m_ticket = 0;
      return false;
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| Close all positions for this symbol and EA                        |
//+------------------------------------------------------------------+
void COrderManager::CloseAllPositions()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket != 0)
      {
         if(PositionGetString(POSITION_SYMBOL) == m_symbol.Name() && 
            PositionGetInteger(POSITION_MAGIC) == m_magic_number)
         {
            m_trade.PositionClose(ticket);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Cancel all pending orders for this EA                            |
//+------------------------------------------------------------------+
void COrderManager::CancelAllPendingOrders()
{
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket != 0)
      {
         // Check if the order is for this symbol and has our magic number
         if(OrderGetString(ORDER_SYMBOL) == m_symbol.Name() &&
            OrderGetInteger(ORDER_MAGIC) == m_magic_number)
         {
            // Delete the pending order
            m_trade.OrderDelete(ticket);
            Print("Pending order #", ticket, " canceled");
         }
      }
   }
   
   // Reset order tracking
   m_order_placed = false;
   m_ticket = 0;
}

//+------------------------------------------------------------------+
//| Check if we have any open positions for this EA                   |
//+------------------------------------------------------------------+
bool COrderManager::HasOpenPositions()
{
   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket != 0)
      {
         if(PositionGetString(POSITION_SYMBOL) == m_symbol.Name() && 
            PositionGetInteger(POSITION_MAGIC) == m_magic_number)
         {
            return true;  // We found a position for this EA
         }
      }
   }
   return false;  // No positions found
}