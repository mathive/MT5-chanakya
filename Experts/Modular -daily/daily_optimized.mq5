//+------------------------------------------------------------------+
//|                                               daily_optimized.mq5 |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link "https://www.mql5.com"
#property version "1.01"
#property description "Optimized version with improved performance"

//--- Performance optimization settings
input group "=== PERFORMANCE OPTIMIZATION ==="
input int PositionCheckFrequency = 100;    // Check positions every N ticks (default: 100)
input int CSVSyncFrequency = 300;          // CSV sync frequency in seconds (default: 5 minutes)
input int ChartUpdateFrequency = 50;       // Update chart lines every N ticks (default: 50)
input bool EnableAdvancedOptimization = true; // Enable advanced caching and optimization

//--- Include only necessary MQL5 standard library files
#include <Trade\Trade.mqh>

//--- SuperTrend signal enumeration
enum ENUM_ST_SIGNAL
{
   ST_SIGNAL_NONE = 0,    // No signal
   ST_SIGNAL_BUY = 1,     // Buy signal
   ST_SIGNAL_SELL = -1    // Sell signal
};

//--- Input parameters for trading
input group "=== TRADING PARAMETERS ==="
input double lotSize = 0.01; // Lot size for trading
input int magicNumber = 123456; // Magic number for multiple chart usage (MUST be unique per chart)

//--- Global variables
CTrade trade;
CTrade localTrade; // Local trade object for order management
double current_spread = 0.0;
static ENUM_ST_SIGNAL last_signal = ST_SIGNAL_NONE;
static ENUM_ST_SIGNAL lastMajorTFSignal = ST_SIGNAL_NONE; // Track major timeframe signal changes

//--- Performance optimization variables
static int tick_counter = 0;
static int last_position_check_tick = 0;
static int last_chart_update_tick = 0;
static datetime last_csv_sync_time = 0;

//--- Cached data for optimization
struct CachedPositionData
{
   double total_profit;
   int position_count;
   datetime last_update;
   bool is_valid;
};

struct CachedOrderData
{
   int order_count;
   datetime last_update;
   bool is_valid;
};

static CachedPositionData cached_positions;
static CachedOrderData cached_orders;
static datetime cached_positions_expire_time = 0;
static datetime cached_orders_expire_time = 0;

//--- Instance identification for multi-chart support
string instanceID = "";  // Unique identifier for this EA instance

//--- Variables for tracking candle closes
static datetime lastCandleTimes[];
static ENUM_TIMEFRAMES trackedTimeframes[];
static datetime lastCSVSyncTime = 0; // For periodic CSV synchronization

//--- Variables for tracking orders per timeframe
static ulong lastOrderTickets[];   // Order tickets for each timeframe
static double lastOrderPrices[];   // Last order prices for each timeframe
static string lastOrderComments[]; // Order comments to identify timeframes
static bool hasExecutedPosition[]; // Track if position is already open for timeframe

//--- Max Loss Protection variables
static bool max_loss_hit = false;
static datetime max_loss_hit_time = 0;
static double current_session_loss = 0.0;
static bool max_profit_hit = false;
static datetime max_profit_hit_time = 0;
static double last_major_trend_when_max_loss = -1; // Track major trend when max loss hit

//--- Daily Target Protection variables
static bool daily_target_hit = false;
static datetime daily_target_hit_time = 0;
static datetime current_trading_date = 0;
static double daily_profit_total = 0.0;
static double daily_loss_total = 0.0;
static bool daily_loss_limit_hit = false;
static datetime daily_loss_hit_time = 0;

//--- Input parameters for risk management
input group "=== RISK MANAGEMENT ==="
input bool EnableMaxLossProtection = true;   // Enable maximum loss protection
input double MaxOverallLoss = 100.0;         // Maximum overall loss in USD before closing all positions
input bool EnableMaxProfitProtection = true; // Enable maximum profit protection
input double MaxOverallProfit = 360.0;       // Maximum overall profit in USD before closing all positions (0 = unlimited)

input group "=== DAILY TARGET MANAGEMENT ==="
input bool EnableDailyTarget = true;         // Enable daily target protection
input double DailyTargetProfit = 15.0;      // Daily target profit in USD (0 = unlimited)
input double DailyTargetLoss = 50.0;        // Daily maximum loss in USD (0 = unlimited)

input group "=== SYSTEM SETTINGS ==="
input bool EnableCSVTracking = false;        // Enable CSV state tracking (auto-disabled in tester)

//+------------------------------------------------------------------+
//| Performance Optimization Functions                              |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| Get cached position data with expiration                        |
//+------------------------------------------------------------------+
CachedPositionData GetCachedPositionData()
{
   datetime current_time = TimeCurrent();
   
   // Check if cache is still valid (update every 10 seconds or when forced)
   if (cached_positions.is_valid && 
       current_time - cached_positions.last_update < 10 && 
       current_time < cached_positions_expire_time)
   {
      return cached_positions;
   }
   
   // Update cache
   cached_positions.total_profit = 0.0;
   cached_positions.position_count = 0;
   cached_positions.last_update = current_time;
   cached_positions_expire_time = current_time + 10; // Cache for 10 seconds
   
   int total_positions = PositionsTotal(); // Call once and store
   for (int i = 0; i < total_positions; i++)
   {
      if (PositionGetTicket(i) > 0)
      {
         if (PositionGetInteger(POSITION_MAGIC) == magicNumber &&
             PositionGetString(POSITION_SYMBOL) == _Symbol)
         {
            cached_positions.total_profit += PositionGetDouble(POSITION_PROFIT);
            cached_positions.position_count++;
         }
      }
   }
   
   cached_positions.is_valid = true;
   return cached_positions;
}

//+------------------------------------------------------------------+
//| Get cached order data with expiration                           |
//+------------------------------------------------------------------+
CachedOrderData GetCachedOrderData()
{
   datetime current_time = TimeCurrent();
   
   // Check if cache is still valid (update every 30 seconds)
   if (cached_orders.is_valid && 
       current_time - cached_orders.last_update < 30 && 
       current_time < cached_orders_expire_time)
   {
      return cached_orders;
   }
   
   // Update cache
   cached_orders.order_count = 0;
   cached_orders.last_update = current_time;
   cached_orders_expire_time = current_time + 30; // Cache for 30 seconds
   
   int total_orders = OrdersTotal(); // Call once and store
   for (int i = 0; i < total_orders; i++)
   {
      if (OrderGetTicket(i) > 0)
      {
         if (OrderGetString(ORDER_SYMBOL) == _Symbol &&
             OrderGetInteger(ORDER_MAGIC) == magicNumber)
         {
            cached_orders.order_count++;
         }
      }
   }
   
   cached_orders.is_valid = true;
   return cached_orders;
}

//+------------------------------------------------------------------+
//| Force refresh of cached data                                    |
//+------------------------------------------------------------------+
void RefreshCachedData()
{
   cached_positions.is_valid = false;
   cached_orders.is_valid = false;
   cached_positions_expire_time = 0;
   cached_orders_expire_time = 0;
}

//+------------------------------------------------------------------+
//| Optimized position checking (reduced frequency)                 |
//+------------------------------------------------------------------+
bool ShouldCheckPositions()
{
   tick_counter++;
   
   // Check positions only every N ticks or when forced
   if (tick_counter - last_position_check_tick >= PositionCheckFrequency)
   {
      last_position_check_tick = tick_counter;
      return true;
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| Optimized chart update (reduced frequency)                      |
//+------------------------------------------------------------------+
bool ShouldUpdateChart()
{
   // Update chart only every N ticks
   if (tick_counter - last_chart_update_tick >= ChartUpdateFrequency)
   {
      last_chart_update_tick = tick_counter;
      return true;
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| Include all the original MQH files                              |
//+------------------------------------------------------------------+

// Note: Include all the original .mqh files here
// TimeFrameSelection.mqh, SuperTrendSignal.mqh, etc.
// For brevity, I'm showing the optimization structure

//+------------------------------------------------------------------+
//| Optimized OnTick function                                       |
//+------------------------------------------------------------------+
void OnTick()
{
   // Early exit if markets are closed (weekend optimization)
   if (IsMarketClosed())
   {
      return;
   }
   
   // Optimized CSV synchronization (less frequent)
   if (EnableCSVTracking && !MQLInfoInteger(MQL_TESTER))
   {
      datetime currentTime = TimeCurrent();
      if (currentTime - last_csv_sync_time >= CSVSyncFrequency)
      {
         ManualCleanupCSV();
         last_csv_sync_time = currentTime;
      }
   }

   // Update position tracking only when necessary
   if (ShouldCheckPositions())
   {
      UpdatePositionTrackingOptimized();
   }

   // Check daily targets (less frequent)
   if (ShouldCheckPositions())
   {
      CheckDailyTarget();
   }

   // Update daily progress display (less frequent)
   if (ShouldUpdateChart())
   {
      UpdateDailyProgressComment();
   }

   // Check max loss and profit protection (optimized with caching)
   if (ShouldCheckPositions())
   {
      CheckMaxLossProtectionOptimized();
      CheckMaxProfitProtectionOptimized();
   }

   // Update SuperTrend lines (less frequent)
   if (ShouldUpdateChart())
   {
      UpdateSuperTrendLinesOptimized();
   }

   // Check if trading can continue
   if (!CanContinueTrading())
   {
      // Reduced visual updates when protection is active
      if (ShouldUpdateChart())
      {
         ENUM_TIMEFRAMES selectedTFs[];
         GetSelectedTimeframes(selectedTFs);

         for (int i = 0; i < ArraySize(selectedTFs); i++)
         {
            if (HasCandleClosed(selectedTFs[i]))
            {
               ForceUpdateSuperTrendLines();
               break; // Only update once, not for each timeframe
            }
         }
      }
      return;
   }

   // Main trading logic (only on candle close)
   ENUM_TIMEFRAMES selectedTFs[];
   GetSelectedTimeframes(selectedTFs);

   bool signal_detected = false;
   
   for (int i = 0; i < ArraySize(selectedTFs); i++)
   {
      if (HasCandleClosed(selectedTFs[i]))
      {
         signal_detected = true;
         
         // Log candle close for tracking
         LogCandleClose(selectedTFs[i]);

         ENUM_ST_SIGNAL signal = GetSuperTrendSignalForTimeframe(_Symbol, selectedTFs[i]);
         if (signal != ST_SIGNAL_NONE)
         {
            double stLinePrice = GetSuperTrendLineValue(_Symbol, selectedTFs[i]);

            // Log signal detection
            ENUM_ST_SIGNAL majorTFSignal = GetSuperTrendSignalForTimeframe(_Symbol, GetMajorTimeframe());
            bool isAligned = (majorTFSignal == signal);
            LogSignalDetected(selectedTFs[i], signal, stLinePrice, isAligned);

            // Only place orders when aligned with Major TimeFrame
            if (majorTFSignal == signal)
            {
               double price = (signal == ST_SIGNAL_BUY) ? 
                             stLinePrice + current_spread : 
                             stLinePrice - current_spread;
               PlaceOrUpdateOrder(selectedTFs[i], signal, price);
            }
            else
            {
               CancelOrderForTimeframe(selectedTFs[i]);
            }
         }
      }
   }

   // Force chart update only when signals are detected
   if (signal_detected)
   {
      ForceUpdateSuperTrendLines();
   }

   // Check major timeframe (only on candle close)
   if (HasCandleClosed(GetMajorTimeframe()))
   {
      ENUM_ST_SIGNAL majorTrendSignal = GetSuperTrendSignalForTimeframe(_Symbol, GetMajorTimeframe());
      if (majorTrendSignal != ST_SIGNAL_NONE)
      {
         if (lastMajorTFSignal != ST_SIGNAL_NONE && lastMajorTFSignal != majorTrendSignal)
         {
            HandleMajorTimeframeChange(majorTrendSignal);
         }
         else if (lastMajorTFSignal == ST_SIGNAL_NONE)
         {
            lastMajorTFSignal = majorTrendSignal;
         }

         ForceUpdateSuperTrendLines();
      }
   }
}

//+------------------------------------------------------------------+
//| Optimized position tracking                                     |
//+------------------------------------------------------------------+
void UpdatePositionTrackingOptimized()
{
   // Use cached data when possible
   CachedPositionData pos_data = GetCachedPositionData();
   
   // Only scan positions if we have any
   if (pos_data.position_count == 0)
   {
      return;
   }

   // Efficient position scanning
   for (int i = 0; i < ArraySize(trackedTimeframes); i++)
   {
      if (hasExecutedPosition[i])
      {
         continue; // Skip already tracked positions
      }

      // Check if position exists for this timeframe
      bool found_position = false;
      
      for (int j = 0; j < pos_data.position_count && j < PositionsTotal(); j++)
      {
         if (PositionGetTicket(j) > 0)
         {
            string positionComment = PositionGetString(POSITION_COMMENT);
            string positionSymbol = PositionGetString(POSITION_SYMBOL);
            string tfName = GetTimeframeName(trackedTimeframes[i]);

            if (positionSymbol == _Symbol && StringFind(positionComment, tfName) >= 0)
            {
               hasExecutedPosition[i] = true;
               lastOrderTickets[i] = 0;
               lastOrderPrices[i] = 0.0;
               
               // Log position opening
               ulong ticket = PositionGetTicket(j);
               ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
               string posTypeStr = (posType == POSITION_TYPE_BUY) ? "BUY" : "SELL";
               double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
               LogPositionOpened(trackedTimeframes[i], ticket, posTypeStr, openPrice);
               
               found_position = true;
               break;
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Optimized max loss protection with caching                      |
//+------------------------------------------------------------------+
void CheckMaxLossProtectionOptimized()
{
   if (!EnableMaxLossProtection || max_loss_hit)
      return;

   // Use cached position data
   CachedPositionData pos_data = GetCachedPositionData();

   // Check if max loss threshold is breached
   if (pos_data.total_profit <= -MaxOverallLoss && pos_data.position_count > 0)
   {
      // Refresh cache to ensure accuracy before taking action
      RefreshCachedData();
      pos_data = GetCachedPositionData();
      
      // Double-check with fresh data
      if (pos_data.total_profit <= -MaxOverallLoss && pos_data.position_count > 0)
      {
         // Close all positions
         CloseAllPositions();
         CancelAllPendingOrders();

         // Mark max loss as hit
         max_loss_hit = true;
         max_loss_hit_time = TimeCurrent();
         current_session_loss = MathAbs(pos_data.total_profit);

         // Record major timeframe signal
         ENUM_ST_SIGNAL majorSignal = GetSuperTrendSignalForTimeframe(_Symbol, GetMajorTimeframe());
         last_major_trend_when_max_loss = (double)majorSignal;

         // Reset tracking arrays
         ResetTrackingArrays("Max loss protection triggered");

         // Update CSV status
         UpdateTimeframeState("MAX_LOSS_STATUS", true, current_session_loss, false, 0, "MAX_LOSS_HIT", 0.0);
         
         Print("=== MAX LOSS PROTECTION TRIGGERED ===");
         Print("Loss: $", DoubleToString(current_session_loss, 2));
      }
   }
}

//+------------------------------------------------------------------+
//| Optimized max profit protection with caching                    |
//+------------------------------------------------------------------+
void CheckMaxProfitProtectionOptimized()
{
   if (!EnableMaxProfitProtection || MaxOverallProfit == 0.0 || max_profit_hit)
      return;

   // Use cached position data
   CachedPositionData pos_data = GetCachedPositionData();

   // Check if max profit threshold is reached
   if (pos_data.total_profit >= MaxOverallProfit && pos_data.position_count > 0)
   {
      // Refresh cache to ensure accuracy
      RefreshCachedData();
      pos_data = GetCachedPositionData();
      
      // Double-check with fresh data
      if (pos_data.total_profit >= MaxOverallProfit && pos_data.position_count > 0)
      {
         // Close all positions
         CloseAllPositions();
         CancelAllPendingOrders();

         // Mark max profit as hit
         max_profit_hit = true;
         max_profit_hit_time = TimeCurrent();

         // Record major timeframe signal
         ENUM_ST_SIGNAL majorSignal = GetSuperTrendSignalForTimeframe(_Symbol, GetMajorTimeframe());
         last_major_trend_when_max_loss = (double)majorSignal;

         // Reset tracking arrays
         ResetTrackingArrays("Max profit protection triggered");

         // Update CSV status
         UpdateTimeframeState("MAX_PROFIT_STATUS", true, pos_data.total_profit, false, 0, "MAX_PROFIT_HIT", 0.0);
         
         Print("=== MAX PROFIT PROTECTION TRIGGERED ===");
         Print("Profit: $", DoubleToString(pos_data.total_profit, 2));
      }
   }
}

//+------------------------------------------------------------------+
//| Check if market is closed (weekend optimization)                |
//+------------------------------------------------------------------+
bool IsMarketClosed()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   
   // Skip processing on weekends
   if (dt.day_of_week == 0 || dt.day_of_week == 6) // Sunday or Saturday
   {
      return true;
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| Optimized initialization                                         |
//+------------------------------------------------------------------+
int OnInit()
{
   // Initialize performance optimization variables
   tick_counter = 0;
   last_position_check_tick = 0;
   last_chart_update_tick = 0;
   last_csv_sync_time = 0;
   
   // Initialize cached data
   cached_positions.is_valid = false;
   cached_orders.is_valid = false;
   cached_positions_expire_time = 0;
   cached_orders_expire_time = 0;
   
   // Create unique instance ID for multi-chart support
   instanceID = StringFormat("%s_%d", _Symbol, magicNumber);
   Print("=== EA INSTANCE ID: ", instanceID, " ===");
   
   if (EnableAdvancedOptimization)
   {
      Print("=== ADVANCED OPTIMIZATION ENABLED ===");
      Print("Position check frequency: every ", PositionCheckFrequency, " ticks");
      Print("Chart update frequency: every ", ChartUpdateFrequency, " ticks");
      Print("CSV sync frequency: every ", CSVSyncFrequency, " seconds");
   }
   
   // Continue with original initialization...
   // [Include all original OnInit() code here]
   
   return (INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Include all original functions here                             |
//+------------------------------------------------------------------+

// Note: For a complete implementation, include all the original functions:
// - TimeFrame selection functions
// - SuperTrend signal functions  
// - Order management functions
// - CSV tracking functions
// - All other utility functions

// The key optimization is in the OnTick() function and caching mechanisms