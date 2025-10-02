//+------------------------------------------------------------------+
//|                                                 SuperTrendEA.mq5 |
//|                                       Copyright 2025, Supertrend |
//|                                                                  |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, Supertrend"
#property link      ""
#property version   "1.00"

//--- Include
#include <Custom\SuperTrendIndicator.mqh>
#include <Custom\OrderManager.mqh>
#include <Custom\CSVBridge.mqh>
#include <Custom\SpreadCalc.mqh>

//--- Input parameters
input double   InpLotSize       = 0.01;         // Lot Size
input int      InpATRPeriod     = 27;           // ATR Period
input double   InpATRMultiplier = 9.0;          // ATR Multiplier
input int      InpMagicNumber   = 939393;       // Magic number
input bool     InpUseCommonFolder = true;       // Save CSV in common folder
input bool     InpUseTakeProfit = true;         // Enable Take Profit per lot
input double   InpTakeProfitDollars = 10.0;    // Take Profit per order in deposit currency

//--- Timeframe settings
input bool     InpTradeM1       = false;        // Trade on M1 (1 minute)
input bool     InpTradeM2       = false;        // Trade on M2 (2 minutes)
input bool     InpTradeM3       = false;        // Trade on M3 (3 minutes)
input bool     InpTradeM5       = true;         // Trade on M5 (5 minutes)
input bool     InpTradeM10      = false;        // Trade on M10 (10 minutes)
input bool     InpTradeM15      = false;        // Trade on M15 (15 minutes)
input bool     InpTradeM30      = false;        // Trade on M30 (30 minutes)
input bool     InpTradeH1       = false;        // Trade on H1 (1 hour)
input ENUM_TIMEFRAMES InpMajorTimeFrame = PERIOD_H1; // Major timeframe for trend direction

//--- Global objects
CSuperTrendIndicator m_indicator;         // SuperTrend indicator object (current timeframe) - kept for compatibility
CSuperTrendIndicator m_major_indicator;   // SuperTrend indicator object (major timeframe)
CSuperTrendIndicator m_indicators[8];     // Array of SuperTrend indicators for all enabled timeframes
ENUM_TIMEFRAMES      m_timeframes[8];     // Array of timeframes corresponding to indicators
bool                 m_timeframe_enabled[8]; // Array of enabled status for each timeframe
int                  m_active_timeframes; // Number of active timeframes
COrderManager        m_order_manager;     // Order manager object
CTrade               m_trade;             // Direct trading object for multiple orders
int                  m_stored_spread;     // Spread stored from CSV
static datetime      m_time_last[8];      // Last bar time for each timeframe
static int           m_major_signal = 0;  // Last major timeframe signal

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   // Setup timeframes and their enabled status
   m_timeframes[0] = PERIOD_M1;  m_timeframe_enabled[0] = InpTradeM1;
   m_timeframes[1] = PERIOD_M2;  m_timeframe_enabled[1] = InpTradeM2;
   m_timeframes[2] = PERIOD_M3;  m_timeframe_enabled[2] = InpTradeM3;
   m_timeframes[3] = PERIOD_M5;  m_timeframe_enabled[3] = InpTradeM5;
   m_timeframes[4] = PERIOD_M10; m_timeframe_enabled[4] = InpTradeM10;
   m_timeframes[5] = PERIOD_M15; m_timeframe_enabled[5] = InpTradeM15;
   m_timeframes[6] = PERIOD_M30; m_timeframe_enabled[6] = InpTradeM30;
   m_timeframes[7] = PERIOD_H1;  m_timeframe_enabled[7] = InpTradeH1;
   
   // Check if any timeframe is enabled for trading
   bool any_timeframe_enabled = false;
   m_active_timeframes = 0;
   
   for(int i = 0; i < 8; i++)
   {
      if(m_timeframe_enabled[i])
      {
         any_timeframe_enabled = true;
         m_active_timeframes++;
         m_time_last[i] = 0; // Initialize time tracking
      }
   }
   
   if(!any_timeframe_enabled)
   {
      Print("ERROR: No timeframes are enabled for trading. Please enable at least one timeframe in inputs.");
      return(INIT_PARAMETERS_INCORRECT);
   }
   
   // Initialize SuperTrend indicators for all enabled timeframes
   string enabled_list = "";
   for(int i = 0; i < 8; i++)
   {
      if(m_timeframe_enabled[i])
      {
         if(!m_indicators[i].Init(Symbol(), m_timeframes[i], InpATRMultiplier, InpATRPeriod))
         {
            Print("Failed to initialize SuperTrend indicator for timeframe: ", EnumToString(m_timeframes[i]));
            return(INIT_FAILED);
         }
         enabled_list += EnumToString(m_timeframes[i]) + " ";
      }
   }
   
   Print("Enabled timeframes for trading: ", enabled_list);
   
   // Initialize the SuperTrend indicator for current timeframe (for compatibility)
   if(!m_indicator.Init(Symbol(), Period(), InpATRMultiplier, InpATRPeriod))
   {
      Print("Failed to initialize SuperTrend indicator for current timeframe");
      return(INIT_FAILED);
   }
   if(!m_indicator.Init(Symbol(), Period(), InpATRMultiplier, InpATRPeriod))
   {
      Print("Failed to initialize SuperTrend indicator for current timeframe");
      return(INIT_FAILED);
   }
   
   // Initialize the SuperTrend indicator for major timeframe
   if(!m_major_indicator.Init(Symbol(), InpMajorTimeFrame, InpATRMultiplier, InpATRPeriod))
   {
      Print("Failed to initialize SuperTrend indicator for major timeframe");
      return(INIT_FAILED);
   }
   
   // Initialize the Order Manager
   if(!m_order_manager.Init(Symbol(), InpMagicNumber, InpLotSize))
   {
      Print("Failed to initialize Order Manager");
      return(INIT_FAILED);
   }
   
   // Initialize the direct trading object
   m_trade.SetExpertMagicNumber(InpMagicNumber);
   m_trade.SetMarginMode();
   m_trade.SetTypeFillingBySymbol(Symbol());
   
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
   
   // Set spread in order manager
   m_order_manager.SetSpread(m_stored_spread);
   
   Print("SuperTrendEA initialized successfully - For BUY signals: pending orders placed ABOVE green SuperTrend line with spread offset. For SELL signals: pending orders placed BELOW red SuperTrend line with spread offset.");
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   // Cancel all pending orders when EA is removed
   m_order_manager.CancelAllPendingOrders();
   
   // SuperTrend indicator will be released in its destructor
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // Global cooldown to prevent order spam - only place orders once per minute
   static datetime last_order_attempt = 0;
   datetime current_time = TimeCurrent();
   
   if(current_time - last_order_attempt < 60) // 60 seconds cooldown
   {
      return; // Exit early if cooldown period hasn't passed
   }
   
   // Check and close positions if profit target is reached
   CheckAndCloseOnProfit();
   
   // Get major timeframe signal and handle direction changes
   int major_signal = GetMajorTimeframeSignal();
   if(major_signal == 0)
   {
      Print("No valid major timeframe signal, waiting...");
      return;
   }
   
   // Update pending orders with SuperTrend values from each timeframe (throttled updates)
   static datetime last_order_update = 0;
   datetime current_server_time = TimeCurrent();
   bool should_update_orders = false;
   
   // Update orders every 5 seconds to avoid excessive processing
   if(current_server_time - last_order_update >= 5)
   {
      should_update_orders = true;
      last_order_update = current_server_time;
   }
   
   // Update ALL pending orders with current SuperTrend values
   if(should_update_orders)
   {
      // Get all pending orders with our magic number
      for(int i = 0; i < OrdersTotal(); i++)
      {
         ulong ticket = OrderGetTicket(i);
         if(ticket > 0 && OrderGetInteger(ORDER_MAGIC) == InpMagicNumber)
         {
            string order_symbol = OrderGetString(ORDER_SYMBOL);
            if(order_symbol == Symbol())
            {
               ENUM_ORDER_TYPE order_type = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
               
               // Find the appropriate timeframe indicator for this order
               // We'll use the first enabled timeframe that matches the major signal
               for(int j = 0; j < 8; j++)
               {
                  if(!m_timeframe_enabled[j])
                     continue;
                     
                  // Update indicator buffers for this timeframe
                  if(!m_indicators[j].UpdateBuffers())
                     continue;
                     
                  int timeframe_signal = m_indicators[j].GetSignal();
                  if(timeframe_signal == major_signal)
                  {
                     double new_price = 0;
                     double trend_line = m_indicators[j].GetCurrentTrendLine(0);
                     
                     if(trend_line == EMPTY_VALUE || trend_line <= 0)
                        continue;
                     
                     if(order_type == ORDER_TYPE_BUY_LIMIT && timeframe_signal == 1)
                     {
                        new_price = trend_line + (m_stored_spread * _Point);
                        Print("Updating BUY LIMIT order #", ticket, " to price: ", new_price, 
                              " (TF: ", EnumToString(m_timeframes[j]), ", TrendLine: ", trend_line, ")");
                     }
                     else if(order_type == ORDER_TYPE_SELL_LIMIT && timeframe_signal == -1)
                     {
                        new_price = trend_line - (m_stored_spread * _Point);
                        Print("Updating SELL LIMIT order #", ticket, " to price: ", new_price, 
                              " (TF: ", EnumToString(m_timeframes[j]), ", TrendLine: ", trend_line, ")");
                     }
                     
                     if(new_price > 0 && MathAbs(new_price - OrderGetDouble(ORDER_PRICE_OPEN)) > _Point * 2)
                     {
                        // Only update if price difference is significant (more than 2 points)
                        MqlTradeRequest request = {};
                        MqlTradeResult result = {};
                        
                        request.action = TRADE_ACTION_MODIFY;
                        request.order = ticket;
                        request.price = new_price;
                        
                        if(OrderSend(request, result))
                        {
                           Print("Order #", ticket, " price updated to: ", new_price);
                        }
                        else
                        {
                           if(result.retcode != 10009) // Ignore "no changes" error
                           {
                              Print("Failed to update order #", ticket, ", Error: ", result.retcode);
                           }
                        }
                     }
                     break; // Use first matching timeframe
                  }
               }
            }
         }
      }
   }
   
   // Static arrays to track signal states for all timeframes
   static int last_signals[8];        // Track last signal for each timeframe
   static int signal_confirmations[8]; // Track confirmations for each timeframe
   static bool signals_ready[8];      // Track if timeframe has confirmed signal ready
   static bool orders_placed[8];      // Track if order already placed for this signal
   static bool arrays_initialized = false;
   
   // Initialize arrays on first run
   if(!arrays_initialized)
   {
      for(int k = 0; k < 8; k++)
      {
         last_signals[k] = 0;
         signal_confirmations[k] = 0;
         signals_ready[k] = false;
         orders_placed[k] = false;
      }
      arrays_initialized = true;
   }
   
   // Process each enabled timeframe for new signals
   for(int i = 0; i < 8; i++)
   {
      if(!m_timeframe_enabled[i])
         continue; // Skip disabled timeframes
         
      // Check if there's a new bar on this timeframe
      datetime time_current = iTime(Symbol(), m_timeframes[i], 0);
      bool isNewBar = false;
      
      if(m_time_last[i] != time_current)
      {
         isNewBar = true;
         m_time_last[i] = time_current;
         Print("New bar detected on ", EnumToString(m_timeframes[i]), " at: ", TimeToString(time_current));
      }
      
      // Only process signals on new bars
      if(!isNewBar)
         continue;
         
      // Update indicator buffers for this timeframe
      if(!m_indicators[i].UpdateBuffers())
         continue;
         
      // Get signal from this timeframe
      int signal = m_indicators[i].GetSignal();
      if(signal == 0)
         continue; // No valid signal
         
      // Only allow trades in the direction of the major timeframe
      if(signal != major_signal)
      {
         Print("Timeframe ", EnumToString(m_timeframes[i]), " signal (", 
               signal == 1 ? "BUY" : "SELL", ") doesn't match major timeframe (", 
               major_signal == 1 ? "BUY" : "SELL", "), skipping...");
         continue;
      }
      
      // Check if signal has changed from the previous bar
      
      if(signal != last_signals[i])
      {
         // Signal just changed and matches major timeframe direction
         Print("SuperTrend signal changed on ", EnumToString(m_timeframes[i]), " to: ", 
               signal == 1 ? "BUY" : "SELL", " (aligned with major timeframe)");
         
         // Reset confirmation counter when signal changes
         signal_confirmations[i] = 1;
         signals_ready[i] = false;
         orders_placed[i] = false; // Reset order placed flag
         
         // Cancel any existing pending orders when signal changes on any timeframe
         CancelAllPendingOrdersWithMagic(InpMagicNumber);
         
         // Reset all order placed flags when canceling orders
         for(int k = 0; k < 8; k++)
            orders_placed[k] = false;
         
         // Update last signal without placing orders yet
         last_signals[i] = signal;
      }
      else if(signal == last_signals[i] && !signals_ready[i] && !orders_placed[i] && signal == major_signal && signal != 0)
      {
         // Signal is the same as previous bar and aligned with major timeframe - confirming
         signal_confirmations[i]++;
         
         // Check if we have enough confirmations (require 3 consecutive bars to reduce false signals)
         if(signal_confirmations[i] >= 3)
         {
            signals_ready[i] = true;
            Print("SuperTrend signal confirmed on ", EnumToString(m_timeframes[i]), " after ", 
                  signal_confirmations[i], " bars - ready for order placement");
         }
         else
         {
            Print("Waiting for signal confirmation on ", EnumToString(m_timeframes[i]), 
                  ". Current count: ", signal_confirmations[i], "/3");
         }
      }
   }
   
   // After processing all timeframes, place orders from ALL confirmed signals
   // Each timeframe can place its own order independently
   for(int i = 0; i < 8; i++)
   {
      if(!m_timeframe_enabled[i] || !signals_ready[i] || orders_placed[i])
         continue;
         
      // Check if we already have a pending order for this timeframe and signal type
      if(HasPendingOrderForTimeframe(m_timeframes[i], last_signals[i]))
      {
         Print("Already have pending order for ", EnumToString(m_timeframes[i]), " - marking as placed");
         signals_ready[i] = false; // Mark as processed
         orders_placed[i] = true;  // Mark order as placed
         continue;
      }
         
      // Place order from this timeframe if signal is confirmed
      int signal = last_signals[i];
      
      Print("Attempting to place order from ", EnumToString(m_timeframes[i]), " confirmed signal");
      
      // Create appropriate order based on confirmed signal
      double trendLine = m_indicators[i].GetCurrentTrendLine(0);
      double currentPrice = SymbolInfoDouble(Symbol(), SYMBOL_BID);
      
      // Validate trend line
      if(trendLine == EMPTY_VALUE || trendLine <= 0 || trendLine > 1000000)
      {
         trendLine = currentPrice;
         Print("WARNING: Invalid trend line value on ", EnumToString(m_timeframes[i]), 
               ". Using current price: ", trendLine);
      }
      
      bool order_placed = false;
      string comment = "ST_" + EnumToString(m_timeframes[i]) + "_" + (signal == 1 ? "BUY" : "SELL");
      
      if(signal == 1)
      {
         // Buy signal
         double buy_price = trendLine + (m_stored_spread * _Point);
         Print("BUY signal confirmed on ", EnumToString(m_timeframes[i]), 
               ". SuperTrend line at: ", trendLine, ", Order price: ", buy_price);
         
         // Create individual buy order for this timeframe
         m_trade.SetExpertMagicNumber(InpMagicNumber);
         if(m_trade.BuyLimit(InpLotSize, buy_price, Symbol(), 0, 0, 0, comment))
         {
            Print("SUCCESS: BUY LIMIT order placed for ", EnumToString(m_timeframes[i]), " at price: ", buy_price);
            order_placed = true;
         }
         else
         {
            Print("FAILED: Could not place BUY order for ", EnumToString(m_timeframes[i]), ", Error: ", GetLastError());
         }
      }
      else if(signal == -1)
      {
         // Sell signal  
         double sell_price = trendLine - (m_stored_spread * _Point);
         Print("SELL signal confirmed on ", EnumToString(m_timeframes[i]), 
               ". SuperTrend line at: ", trendLine, ", Order price: ", sell_price);
               
         // Create individual sell order for this timeframe
         m_trade.SetExpertMagicNumber(InpMagicNumber);
         if(m_trade.SellLimit(InpLotSize, sell_price, Symbol(), 0, 0, 0, comment))
         {
            Print("SUCCESS: SELL LIMIT order placed for ", EnumToString(m_timeframes[i]), " at price: ", sell_price);
            order_placed = true;
         }
         else
         {
            Print("FAILED: Could not place SELL order for ", EnumToString(m_timeframes[i]), ", Error: ", GetLastError());
         }
      }
      
      if(order_placed)
      {
         signals_ready[i] = false;  // Mark this timeframe as processed
         orders_placed[i] = true;   // Mark order as placed to prevent duplicates
         last_order_attempt = current_time; // Set cooldown
         Print("Order placement completed for ", EnumToString(m_timeframes[i]), " - cooldown activated");
      }
   }
}

//+------------------------------------------------------------------+
//| Check if current timeframe is enabled for trading                |
//+------------------------------------------------------------------+
bool IsCurrentTimeframeEnabled()
{
   switch(Period())
   {
      case PERIOD_M1:  return InpTradeM1;
      case PERIOD_M2:  return InpTradeM2;
      case PERIOD_M3:  return InpTradeM3;
      case PERIOD_M5:  return InpTradeM5;
      case PERIOD_M10: return InpTradeM10;
      case PERIOD_M15: return InpTradeM15;
      case PERIOD_M30: return InpTradeM30;
      case PERIOD_H1:  return InpTradeH1;
      default: return false;
   }
}

//+------------------------------------------------------------------+
//| Get major timeframe signal and handle direction changes          |
//+------------------------------------------------------------------+
int GetMajorTimeframeSignal()
{
   // Update major timeframe indicator
   if(!m_major_indicator.UpdateBuffers())
      return 0;
      
   int current_major_signal = m_major_indicator.GetSignal();
   
   // Check if major timeframe signal has changed
   if(m_major_signal != 0 && current_major_signal != m_major_signal)
   {
      Print("Major timeframe signal changed from ", 
            m_major_signal == 1 ? "BUY" : "SELL", " to ", 
            current_major_signal == 1 ? "BUY" : "SELL");
      
      // Close all positions and cancel pending orders when major signal changes
      m_order_manager.CloseAllPositions();
      m_order_manager.CancelAllPendingOrders();
      
      Print("All positions closed and pending orders cancelled due to major timeframe signal change");
   }
   
   m_major_signal = current_major_signal;
   return current_major_signal;
}

//+------------------------------------------------------------------+
//| Custom function to load spread value from CSV file               |
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
//| Check and close positions on profit target                       |
//+------------------------------------------------------------------+
void CheckAndCloseOnProfit()
{
   // Only check for take profit if the feature is enabled
   if(!InpUseTakeProfit)
      return;
      
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      string sym = PositionGetString(POSITION_SYMBOL);
      long magic = PositionGetInteger(POSITION_MAGIC);
      double profit = PositionGetDouble(POSITION_PROFIT);
      if(sym == Symbol() && magic == InpMagicNumber)
      {
         if(profit >= InpTakeProfitDollars)
         {
            Print("Closing position #", ticket, " for profit $", profit, " (target $", InpTakeProfitDollars, ")");
            m_order_manager.ClosePositionByTicket(ticket);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Check if we already have a pending order for this timeframe     |
//+------------------------------------------------------------------+
bool HasPendingOrderForTimeframe(ENUM_TIMEFRAMES timeframe, int signal_type)
{
   string expected_comment = "ST_" + EnumToString(timeframe) + "_" + (signal_type == 1 ? "BUY" : "SELL");
   
   for(int i = 0; i < OrdersTotal(); i++)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket > 0 && OrderGetInteger(ORDER_MAGIC) == InpMagicNumber)
      {
         string order_symbol = OrderGetString(ORDER_SYMBOL);
         string order_comment = OrderGetString(ORDER_COMMENT);
         
         if(order_symbol == Symbol() && order_comment == expected_comment)
         {
            ENUM_ORDER_TYPE order_type = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
            
            // Check if it's the expected order type
            if((signal_type == 1 && order_type == ORDER_TYPE_BUY_LIMIT) ||
               (signal_type == -1 && order_type == ORDER_TYPE_SELL_LIMIT))
            {
               return true; // Already have this order
            }
         }
      }
   }
   return false; // No existing order found
}

//+------------------------------------------------------------------+
//| Cancel all pending orders with specific magic number             |
//+------------------------------------------------------------------+
void CancelAllPendingOrdersWithMagic(int magic_number)
{
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket > 0 && OrderGetInteger(ORDER_MAGIC) == magic_number)
      {
         string order_symbol = OrderGetString(ORDER_SYMBOL);
         if(order_symbol == Symbol())
         {
            ENUM_ORDER_TYPE order_type = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
            if(order_type == ORDER_TYPE_BUY_LIMIT || order_type == ORDER_TYPE_SELL_LIMIT)
            {
               if(m_trade.OrderDelete(ticket))
               {
                  Print("Cancelled pending order #", ticket);
               }
               else
               {
                  Print("Failed to cancel order #", ticket, ", Error: ", GetLastError());
               }
            }
         }
      }
   }
}
//+------------------------------------------------------------------+