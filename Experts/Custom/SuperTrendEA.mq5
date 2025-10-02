//+------------------------------------------------------------------+
//|                                                 SuperTrendEA.mq5 |
//|                                       Copyright 2025, Supertrend |
//|                                                                  |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, Supertrend"
#property link      ""
#property version   "1.00"

//--- Include
#include <Trade\Trade.mqh>
#include <Trade\SymbolInfo.mqh>
#include <Custom\SpreadCalc.mqh>
#include <Custom\CSVBridge.mqh>

//--- Input parameters
input double   InpLotSize       = 0.01;         // Lot Size
input int      InpATRPeriod     = 27;           // ATR Period
input double   InpATRMultiplier = 9.0;          // ATR Multiplier
input int      InpMagicNumber   = 939393;       // Magic number
input bool     InpUseCommonFolder = true;       // Save CSV in common folder

//--- Global variables
CTrade         m_trade;         // Trading object
CSymbolInfo    m_symbol;        // Symbol info object
int            m_handle;        // SuperTrend indicator handle
double         m_direction[];   // SuperTrend direction buffer
double         m_upper[];       // SuperTrend upper line buffer
double         m_lower[];       // SuperTrend lower line buffer
int            m_last_signal;   // Last trading signal
int            m_stored_spread; // Spread stored from CSV
bool           m_order_placed;  // Flag to track if pending order is placed
double         m_entry_price;   // Calculated entry price with spread offset
ulong          m_ticket;        // Ticket number of the pending order

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   // Initialize the trading object
   m_trade.SetExpertMagicNumber(InpMagicNumber);
   
   // Initialize symbol object
   if(!m_symbol.Name(Symbol()))
   {
      Print("Failed to initialize symbol object");
      return(INIT_FAILED);
   }
   
   // Create SuperTrend indicator handle
   m_handle = iCustom(Symbol(), Period(), "Supertrend", 
                      "SPRTRND", // Objects Prefix
                      InpATRMultiplier, // ATR Multiplier
                      InpATRPeriod, // ATR Period
                      10000, // ATR Max Bars
                      0, // Indicator shift
                      false, // Enable notifications feature
                      false, // Send alert notification
                      false, // Send push-notification to mobile
                      false, // Send notification via email
                      0); // TriggerCandle = Current (0)
                      
   if(m_handle == INVALID_HANDLE)
   {
      Print("Failed to create SuperTrend indicator handle. Error code:", GetLastError());
      return(INIT_FAILED);
   }
   
   // Initialize signal value
   m_last_signal = 0; // No signal
   
   // Set buffers as series
   ArraySetAsSeries(m_direction, true);
   
   // Get and print initial spread information
   int spread_points = GetSpreadPoints();
   double spread_price = GetSpread();
   Print("EA initialized. Current spread: ", spread_points, " points (", DoubleToString(spread_price, Digits()), ")");
   
   // Create CSV file with ONLY the spread information
   WriteToCSV(Symbol(), spread_points, "INIT", InpUseCommonFolder);
   
   // Load spread from CSV (if it exists)
   m_stored_spread = LoadSpreadFromCSV(Symbol(), InpUseCommonFolder);
   if(m_stored_spread > 0)
   {
      Print("Loaded spread from CSV: ", m_stored_spread, " points");
   }
   else
   {
      // If CSV loading failed, use current spread
      m_stored_spread = spread_points;
      Print("Using current spread: ", m_stored_spread, " points");
   }
   
   // Initialize order state
   m_order_placed = false;
   m_entry_price = 0;
   m_ticket = 0;      // No pending order ticket yet
   
   // Set up buffers for SuperTrend lines
   ArraySetAsSeries(m_upper, true);
   ArraySetAsSeries(m_lower, true);
   
   Print("SuperTrendEA initialized successfully - Will place orders at SuperTrend line with spread offset");
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   // Cancel all pending orders when EA is removed
   CancelAllPendingOrders();
   
   // Release indicator handle
   if(m_handle != INVALID_HANDLE)
      IndicatorRelease(m_handle);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // Update symbol info
   m_symbol.RefreshRates();
   
   // Get new bars
   static datetime time_last = 0;
   datetime time_current = iTime(Symbol(), Period(), 0);
   
   // Get current SuperTrend values to check if we need to update pending orders
   if(!UpdateSuperTrendBuffers())
      return;
      
   // Even if not a new bar, we'll check if SuperTrend lines have moved
   // and update our pending orders if needed
   if(m_order_placed && m_ticket > 0)
   {
      UpdatePendingOrderPrice();
   }
      
   // If not a new bar, we don't need to recalculate the trend signal
   if(time_last == time_current)
      return;
   
   time_last = time_current;
   
   // SuperTrend buffers are already updated in UpdateSuperTrendBuffers()
   // Check if TrendDirection buffer has valid values
   if(m_direction[1] == EMPTY_VALUE)
      return;
      
   // Current trend (0 = uptrend/green, 1 = downtrend/red)
   int trend_current = (int)m_direction[1];
   
   // Convert to signal (1 = buy, -1 = sell)
   int signal = (trend_current == 0) ? 1 : -1;
   
   // Check if signal has changed
   if(signal != m_last_signal)
   {
      // Close all positions first
      CloseAllPositions();
      
      // Cancel any existing pending orders
      CancelAllPendingOrders();
      
      // Reset order tracking
      m_order_placed = false;
      m_ticket = 0;
      
      // Check if we already have open positions
      if(HasOpenPositions())
      {
         Print("Signal changed but already have open positions. Closing existing positions first.");
         CloseAllPositions();
      }
      
      // Calculate the spread adjustment in price
      double spreadAdjustment = m_stored_spread * SymbolInfoDouble(Symbol(), SYMBOL_POINT);
      
      // Calculate entry price based on SuperTrend line plus spread adjustment
      if(signal == 1)
      {
         // Buy signal: entry price is the lower SuperTrend line minus spread
         m_entry_price = m_lower[1] - spreadAdjustment;
         
         // Place a BUY LIMIT order (pending order)
         double stopLoss = 0; // Set to 0 for no stop loss or calculate as needed
         double takeProfit = 0; // Set to 0 for no take profit or calculate as needed
         datetime expiration = 0; // 0 means no expiration
         
         if(m_trade.BuyLimit(InpLotSize, m_entry_price, Symbol(), stopLoss, takeProfit, ORDER_TIME_GTC, expiration, "SuperTrend Buy Limit"))
         {
            m_ticket = m_trade.ResultOrder(); // Store the ticket number
            Print("Placed BUY LIMIT order #", m_ticket, " at price: ", m_entry_price);
            m_order_placed = true;
         }
         else
         {
            Print("Failed to place BUY LIMIT order. Error: ", GetLastError());
         }
      }
      else if(signal == -1)
      {
         // Sell signal: entry price is the upper SuperTrend line plus spread
         m_entry_price = m_upper[1] + spreadAdjustment;
         
         // Place a SELL LIMIT order (pending order)
         double stopLoss = 0; // Set to 0 for no stop loss or calculate as needed
         double takeProfit = 0; // Set to 0 for no take profit or calculate as needed
         datetime expiration = 0; // 0 means no expiration
         
         if(m_trade.SellLimit(InpLotSize, m_entry_price, Symbol(), stopLoss, takeProfit, ORDER_TIME_GTC, expiration, "SuperTrend Sell Limit"))
         {
            m_ticket = m_trade.ResultOrder(); // Store the ticket number
            Print("Placed SELL LIMIT order #", m_ticket, " at price: ", m_entry_price);
            m_order_placed = true;
         }
         else
         {
            Print("Failed to place SELL LIMIT order. Error: ", GetLastError());
         }
      }
      
      // Update last signal
      m_last_signal = signal;
   }
}

//+------------------------------------------------------------------+
//| Close all positions for this symbol and EA                       |
//+------------------------------------------------------------------+
void CloseAllPositions()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket != 0)
      {
         if(PositionGetString(POSITION_SYMBOL) == Symbol() && 
            PositionGetInteger(POSITION_MAGIC) == InpMagicNumber)
         {
            m_trade.PositionClose(ticket);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Load spread value from CSV file                                  |
//+------------------------------------------------------------------+
int LoadSpreadFromCSV(string symbol, bool useCommonFolder)
{
   // Create filename
   long id = AccountInfoInteger(ACCOUNT_LOGIN);
   string filename = symbol + "_" + IntegerToString(id) + ".csv";
   
   // Set file flags
   int fileFlags = FILE_READ|FILE_CSV|FILE_ANSI;
   if(useCommonFolder) fileFlags |= FILE_COMMON;
   
   // Try to open the file
   int fileHandle = FileOpen(filename, fileFlags);
   if(fileHandle == INVALID_HANDLE)
   {
      Print("Failed to open CSV file to read spread: ", GetLastError());
      return 0;
   }
   
   // Read header line
   if(!FileIsEnding(fileHandle))
   {
      string header1 = FileReadString(fileHandle);
      string header2 = FileReadString(fileHandle);
      
      // Read data line
      if(!FileIsEnding(fileHandle))
      {
         string symbolName = FileReadString(fileHandle);
         string spreadStr = FileReadString(fileHandle);
         
         // Close the file
         FileClose(fileHandle);
         
         // Convert spread to integer
         int spread = (int)StringToInteger(spreadStr);
         return spread;
      }
   }
   
   // Close the file
   FileClose(fileHandle);
   return 0;
}

//+------------------------------------------------------------------+
//| Check if we have any open positions for this EA                  |
//+------------------------------------------------------------------+
bool HasOpenPositions()
{
   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket != 0)
      {
         if(PositionGetString(POSITION_SYMBOL) == Symbol() && 
            PositionGetInteger(POSITION_MAGIC) == InpMagicNumber)
         {
            return true;  // We found a position for this EA
         }
      }
   }
   return false;  // No positions found
}

//+------------------------------------------------------------------+
//| Cancel all pending orders for this EA                            |
//+------------------------------------------------------------------+
void CancelAllPendingOrders()
{
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket != 0)
      {
         // Check if the order is for this symbol and has our magic number
         if(OrderGetString(ORDER_SYMBOL) == Symbol() &&
            OrderGetInteger(ORDER_MAGIC) == InpMagicNumber)
         {
            // Delete the pending order
            m_trade.OrderDelete(ticket);
            Print("Pending order #", ticket, " canceled");
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Update SuperTrend buffers with the latest values                 |
//+------------------------------------------------------------------+
bool UpdateSuperTrendBuffers()
{
   // Copy SuperTrend direction values (buffer 2)
   if(CopyBuffer(m_handle, 2, 0, 3, m_direction) <= 0)
   {
      Print("Failed to copy SuperTrend direction buffer. Error:", GetLastError());
      return false;
   }
   
   // Copy SuperTrend upper and lower lines (buffers 0 and 1)
   if(CopyBuffer(m_handle, 0, 0, 3, m_upper) <= 0 || 
      CopyBuffer(m_handle, 1, 0, 3, m_lower) <= 0)
   {
      Print("Failed to copy SuperTrend line buffers. Error:", GetLastError());
      return false;
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| Update pending order price if SuperTrend line has moved          |
//+------------------------------------------------------------------+
void UpdatePendingOrderPrice()
{
   // Check if order still exists
   if(!OrderSelect(m_ticket))
   {
      // Order may have been executed or canceled
      m_order_placed = false;
      m_ticket = 0;
      return;
   }
   
   // Calculate the spread adjustment in price
   double spreadAdjustment = m_stored_spread * SymbolInfoDouble(Symbol(), SYMBOL_POINT);
   double newPrice = 0;
   
   // Calculate new price based on current signal
   if(m_last_signal == 1) // Buy signal
   {
      newPrice = m_lower[1] - spreadAdjustment;
      
      // Only modify if price has changed significantly (avoid too frequent updates)
      double currentPrice = OrderGetDouble(ORDER_PRICE_OPEN);
      if(MathAbs(newPrice - currentPrice) > SymbolInfoDouble(Symbol(), SYMBOL_POINT))
      {
         if(m_trade.OrderModify(
            m_ticket,                         // Ticket
            newPrice,                         // New price
            OrderGetDouble(ORDER_SL),         // Keep existing Stop Loss
            OrderGetDouble(ORDER_TP),         // Keep existing Take Profit
            (ENUM_ORDER_TYPE_TIME)OrderGetInteger(ORDER_TYPE_TIME), // Keep existing type time (with proper cast)
            OrderGetInteger(ORDER_TIME_EXPIRATION), // Keep existing expiration
            OrderGetDouble(ORDER_PRICE_STOPLIMIT) // Keep existing Stop Limit price
         ))
         {
            m_entry_price = newPrice;
            Print("Updated BUY LIMIT order #", m_ticket, " to new price: ", newPrice);
         }
         else
         {
            Print("Failed to modify BUY LIMIT order #", m_ticket, ". Error: ", GetLastError());
         }
      }
   }
   else if(m_last_signal == -1) // Sell signal
   {
      newPrice = m_upper[1] + spreadAdjustment;
      
      // Only modify if price has changed significantly (avoid too frequent updates)
      double currentPrice = OrderGetDouble(ORDER_PRICE_OPEN);
      if(MathAbs(newPrice - currentPrice) > SymbolInfoDouble(Symbol(), SYMBOL_POINT))
      {
         if(m_trade.OrderModify(
            m_ticket,                         // Ticket
            newPrice,                         // New price
            OrderGetDouble(ORDER_SL),         // Keep existing Stop Loss
            OrderGetDouble(ORDER_TP),         // Keep existing Take Profit
            (ENUM_ORDER_TYPE_TIME)OrderGetInteger(ORDER_TYPE_TIME), // Keep existing type time (with proper cast)
            OrderGetInteger(ORDER_TIME_EXPIRATION), // Keep existing expiration
            OrderGetDouble(ORDER_PRICE_STOPLIMIT) // Keep existing Stop Limit price
         ))
         {
            m_entry_price = newPrice;
            Print("Updated SELL LIMIT order #", m_ticket, " to new price: ", newPrice);
         }
         else
         {
            Print("Failed to modify SELL LIMIT order #", m_ticket, ". Error: ", GetLastError());
         }
      }
   }
}

