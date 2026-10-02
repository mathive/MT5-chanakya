//+------------------------------------------------------------------+
//|                                                         daily.mq5 |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link "https://www.mql5.com"
#property version "1.00"

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
input int magicNumber = 123456;                                       // Magic number for multiple chart usage (MUST be unique per chart)

//--- Global variables
CTrade trade;
CTrade localTrade; // Local trade object for order management
double current_spread = 0.0;
static ENUM_ST_SIGNAL last_signal = ST_SIGNAL_NONE;
static ENUM_ST_SIGNAL lastMajorTFSignal = ST_SIGNAL_NONE; // Track major timeframe signal changes

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
//| Initialize candle tracking for selected timeframes              |
//+------------------------------------------------------------------+
void InitializeCandleTracking()
{
   // Get selected timeframes
   ENUM_TIMEFRAMES selectedTFs[];
   GetSelectedTimeframes(selectedTFs);

   // Check if major timeframe is already in selected timeframes
   bool majorInSelected = false;
   ENUM_TIMEFRAMES majorTF = GetMajorTimeframe();
   for (int i = 0; i < ArraySize(selectedTFs); i++)
   {
      if (selectedTFs[i] == majorTF)
      {
         majorInSelected = true;
         break;
      }
   }

   // Calculate total timeframes to track
   int totalTFs = ArraySize(selectedTFs);
   if (!majorInSelected)
      totalTFs++; // Add major timeframe if not already included

   // Resize arrays
   ArrayResize(lastCandleTimes, totalTFs);
   ArrayResize(trackedTimeframes, totalTFs);
   ArrayResize(lastOrderTickets, totalTFs);
   ArrayResize(lastOrderPrices, totalTFs);
   ArrayResize(lastOrderComments, totalTFs);
   ArrayResize(hasExecutedPosition, totalTFs);

   // Initialize selected timeframes
   for (int i = 0; i < ArraySize(selectedTFs); i++)
   {
      trackedTimeframes[i] = selectedTFs[i];
      lastCandleTimes[i] = iTime(_Symbol, selectedTFs[i], 0);
      lastOrderTickets[i] = 0;
      lastOrderPrices[i] = 0.0;
      lastOrderComments[i] = "SuperTrend " + GetTimeframeName(selectedTFs[i]);
      hasExecutedPosition[i] = false;
   }

   // Add major timeframe if not already included
   if (!majorInSelected)
   {
      int lastIndex = ArraySize(selectedTFs);
      trackedTimeframes[lastIndex] = majorTF;
      lastCandleTimes[lastIndex] = iTime(_Symbol, majorTF, 0);
      lastOrderTickets[lastIndex] = 0;
      lastOrderPrices[lastIndex] = 0.0;
      lastOrderComments[lastIndex] = "SuperTrend " + GetTimeframeName(majorTF);
      hasExecutedPosition[lastIndex] = false;
   }
}

//+------------------------------------------------------------------+
//| Check if candle closed on specific timeframe                    |
//+------------------------------------------------------------------+
bool HasCandleClosed(ENUM_TIMEFRAMES timeframe)
{
   // Find timeframe index in tracked arrays
   int tfIndex = -1;
   for (int i = 0; i < ArraySize(trackedTimeframes); i++)
   {
      if (trackedTimeframes[i] == timeframe)
      {
         tfIndex = i;
         break;
      }
   }

   if (tfIndex == -1)
      return false; // Timeframe not tracked

   datetime currentCandleTime = iTime(_Symbol, timeframe, 0);

   if (currentCandleTime != lastCandleTimes[tfIndex])
   {
      lastCandleTimes[tfIndex] = currentCandleTime;
      return true;
   }

   return false;
}

//+------------------------------------------------------------------+
//| Find timeframe index in tracking arrays                         |
//+------------------------------------------------------------------+
int FindTimeframeIndex(ENUM_TIMEFRAMES timeframe)
{
   for (int i = 0; i < ArraySize(trackedTimeframes); i++)
   {
      if (trackedTimeframes[i] == timeframe)
         return i;
   }
   return -1;
}

//+------------------------------------------------------------------+
//| Check if order still exists                                     |
//+------------------------------------------------------------------+
//| Check if order still exists                                     |
//+------------------------------------------------------------------+
bool OrderExists(ulong ticket)
{
   if (ticket == 0)
      return false;
   return OrderSelect(ticket);
}

//+------------------------------------------------------------------+
//| Check if position exists for timeframe                          |
//+------------------------------------------------------------------+
bool PositionExists(ENUM_TIMEFRAMES timeframe)
{
   // Check if there's an open position with our magic number
   if (PositionsTotal() == 0)
      return false;

   for (int posIdx = PositionsTotal() - 1; posIdx >= 0; posIdx--)
   {
      ulong ticket = PositionGetTicket(posIdx);
      if (ticket > 0 && PositionSelectByTicket(ticket))
      {
         if (PositionGetInteger(POSITION_MAGIC) == magicNumber)
         {
            return true;
         }
      }
   }
   return false;
}

//+------------------------------------------------------------------+
//| Check if position exists for timeframe                          |
//+------------------------------------------------------------------+
bool IsTimeframeInComment(string comment, string tfName)
{
   if(comment == "" || tfName == "")
      return false;

   int len_tf = StringLen(tfName);
   int pos = 0;
   while((pos = StringFind(comment, tfName, pos)) >= 0)
   {
      bool before_ok = (pos == 0) || (StringGetCharacter(comment, pos - 1) == ' ') || (StringGetCharacter(comment, pos - 1) == '_') || (StringGetCharacter(comment, pos - 1) == '-') || (StringGetCharacter(comment, pos - 1) == '[');
      int end_pos = pos + len_tf;
      bool after_ok = (end_pos >= StringLen(comment)) || (StringGetCharacter(comment, end_pos) == ' ') || (StringGetCharacter(comment, end_pos) == '_') || (StringGetCharacter(comment, end_pos) == '-') || (StringGetCharacter(comment, end_pos) == ']');

      if(before_ok && after_ok)
         return true;

      pos += len_tf;
   }
   return false;
}

bool HasOpenPositionForTimeframe(ENUM_TIMEFRAMES timeframe)
{
   string tfName = GetTimeframeName(timeframe);

   // Check all open positions
   for (int i = 0; i < PositionsTotal(); i++)
   {
      ulong ticket = PositionGetTicket(i);
      if (PositionSelectByTicket(ticket))
      {
         string positionComment = PositionGetString(POSITION_COMMENT);
         string positionSymbol = PositionGetString(POSITION_SYMBOL);
         long magic = PositionGetInteger(POSITION_MAGIC);

         // Must belong to this EA instance (matching magicNumber)
         if (positionSymbol == _Symbol)
         {
            bool isOurPosition = (magic == magicNumber) || 
                                 (magic == 0 && StringFind(positionComment, "SuperTrend") >= 0);

            if (isOurPosition && IsTimeframeInComment(positionComment, tfName))
            {
               return true;
            }
         }
      }
   }
   return false;
}

//+------------------------------------------------------------------+
//| Update position tracking for timeframe (CSV-synchronized)      |
//+------------------------------------------------------------------+
void UpdatePositionTracking()
{
   for (int i = 0; i < ArraySize(trackedTimeframes); i++)
   {
      bool hasPosition = HasOpenPositionForTimeframe_Synced(trackedTimeframes[i]);
      bool wasExecuted = hasExecutedPosition[i];

      // If position was executed but now closed, reset tracking
      if (wasExecuted && !hasPosition)
      {
         hasExecutedPosition[i] = false;
         ulong closedTicket = lastOrderTickets[i];
         double closedPrice = lastOrderPrices[i];

         lastOrderTickets[i] = 0;
         lastOrderPrices[i] = 0.0;

         string tfName = GetTimeframeName(trackedTimeframes[i]);
         Print("Position CLOSED for ", tfName, " - Resetting CSV status and checking for auto-reopen");

         // Log position closure and sync to CSV
         LogPositionClosed(trackedTimeframes[i], closedTicket, "Position closed - detected by tracking system", closedPrice);

         // STEP 1: Reset CSV status for this timeframe
         UpdateTimeframeState(tfName, false, 0.0, false, 0, "NONE", 0.0);
         
         // STEP 2: Check if we should auto-reopen position based on MTF alignment
         CheckAndPlaceOrderAfterPositionClose(trackedTimeframes[i]);
      }
      else
      {
         hasExecutedPosition[i] = hasPosition;
      }
   }
}

//+------------------------------------------------------------------+
//| Place or update order for timeframe (CSV-first approach)       |
//+------------------------------------------------------------------+
void PlaceOrUpdateOrder(ENUM_TIMEFRAMES timeframe, ENUM_ST_SIGNAL signal, double newPrice)
{
   int tfIndex = FindTimeframeIndex(timeframe);
   if (tfIndex == -1)
      return;

   string tfName = GetTimeframeName(timeframe);

   // STEP 1: Check CSV state first before any actions
   if (!CanPlaceOrderForTimeframe(timeframe, "PlaceOrUpdateOrder"))
   {
      Print("CSV BLOCK: Order placement blocked for ", tfName, " by CSV validation");
      return;
   }

   // STEP 1.1: Double-check existing orders in MT5 vs CSV
   TimeframeState csvState = GetTimeframeStateFromCSV(tfName);
   if (csvState.isValid && csvState.hasOrder && csvState.orderTicket > 0)
   {
      // CSV says there should be an order - verify it exists in MT5
      if (!OrderSelect(csvState.orderTicket))
      {
         Print("CSV MISMATCH: CSV shows order ", csvState.orderTicket, " for ", tfName, " but order doesn't exist in MT5");
         // Clear CSV state
         UpdateTimeframeState(tfName, false, 0.0, false, 0, "NONE", 0.0);
      }
      else
      {
         // Order exists - check if it matches our tracking
         if (lastOrderTickets[tfIndex] != csvState.orderTicket)
         {
            Print("SYNC UPDATE: Updating tracking for ", tfName, " to match CSV order ", csvState.orderTicket);
            lastOrderTickets[tfIndex] = csvState.orderTicket;
            lastOrderPrices[tfIndex] = csvState.orderPrice;
         }
         
         // Order already exists - just update price if needed
         if (MathAbs(newPrice - csvState.orderPrice) > _Point)
         {
            if (ModifyPendingOrder(csvState.orderTicket, newPrice, 0, 0))
            {
               lastOrderPrices[tfIndex] = newPrice;
               LogOrderUpdated(timeframe, csvState.orderTicket, csvState.orderPrice, newPrice);
               Print("UPDATED: Order ", csvState.orderTicket, " for ", tfName, " price updated to ", newPrice);
            }
         }
         return;
      }
   }

   // STEP 1.5: Check if trading can continue (daily target + max protection)
   if (!CanContinueTrading())
   {
      return;
   }

   // STEP 2: Use synchronized position check
   if (HasOpenPositionForTimeframe_Synced(timeframe))
   {
      hasExecutedPosition[tfIndex] = true;

      // Find and save position to CSV if not already saved
      for (int i = 0; i < PositionsTotal(); i++)
      {
         ulong ticket = PositionGetTicket(i);
         if (PositionSelectByTicket(ticket))
         {
            string positionComment = PositionGetString(POSITION_COMMENT);
            string positionSymbol = PositionGetString(POSITION_SYMBOL);
            string tfNameCheck = GetTimeframeName(timeframe);

            if (positionSymbol == _Symbol && IsTimeframeInComment(positionComment, tfNameCheck))
            {
               ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
               string posTypeStr = (posType == POSITION_TYPE_BUY) ? "BUY" : "SELL";
               double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
               LogPositionOpened(timeframe, ticket, posTypeStr, openPrice);
               break;
            }
         }
      }

      return;
   }

   string comment = "SuperTrend " + GetTimeframeName(timeframe);
   ulong existingTicket = lastOrderTickets[tfIndex];
   double lastPrice = lastOrderPrices[tfIndex];

   // Check if price changed significantly (more than 1 point)
   bool priceChanged = MathAbs(newPrice - lastPrice) > _Point;

   if (existingTicket > 0 && OrderExists(existingTicket))
   {
      if (priceChanged)
      {
         // Update existing order with new price
         if (ModifyPendingOrder(existingTicket, newPrice, 0, 0))
         {
            lastOrderPrices[tfIndex] = newPrice;
            // Log order update and sync to CSV
            LogOrderUpdated(timeframe, existingTicket, lastPrice, newPrice);
         }
         else
         {
            Print("Failed to update order for ", GetTimeframeName(timeframe), ": Ticket=", existingTicket);
         }
      }
   }
   else
   {
      // STEP 3: Double-check CSV before placing new order
      TimeframeState csvState = GetTimeframeStateFromCSV(tfName);
      if (csvState.isValid && (csvState.completed || csvState.hasOrder))
      {
         Print("CSV Double-Check: Blocking new order for ", tfName, " - CSV shows existing state");
         return;
      }

      // Place new order
      ulong newTicket = 0;
      bool success = false;

      if (signal == ST_SIGNAL_BUY)
      {
         success = PlaceBuyStop(lotSize, newPrice, comment, 0, 0);
         if (success)
         {
            // Get the ticket of the last placed order
            newTicket = GetLastOrderTicket();
         }
      }
      else if (signal == ST_SIGNAL_SELL)
      {
         success = PlaceSellStop(lotSize, newPrice, comment, 0, 0);
         if (success)
         {
            // Get the ticket of the last placed order
            newTicket = GetLastOrderTicket();
         }
      }

      if (success && newTicket > 0)
      {
         lastOrderTickets[tfIndex] = newTicket;
         lastOrderPrices[tfIndex] = newPrice;
         string orderTypeStr = (signal == ST_SIGNAL_BUY) ? "BUY_STOP" : "SELL_STOP";
         LogOrderPlaced(timeframe, newTicket, newPrice, orderTypeStr);
      }
   }
}

//+------------------------------------------------------------------+
//| Get the ticket of the last placed order                         |
//+------------------------------------------------------------------+
ulong GetLastOrderTicket()
{
   int total = OrdersTotal();
   if (total > 0)
   {
      return OrderGetTicket(total - 1);
   }
   return 0;
}

//+------------------------------------------------------------------+
//| Cancel order for specific timeframe                             |
//+------------------------------------------------------------------+
void CancelOrderForTimeframe(ENUM_TIMEFRAMES timeframe)
{
   int tfIndex = FindTimeframeIndex(timeframe);
   if (tfIndex == -1)
      return;

   ulong ticket = lastOrderTickets[tfIndex];
   if (ticket > 0 && OrderExists(ticket))
   {
      if (localTrade.OrderDelete(ticket))
      {
         Print("Order CANCELLED for ", GetTimeframeName(timeframe), ": Ticket=", ticket, " (Signal alignment changed)");

         // Log order cancellation
         LogOrderCancelled(timeframe, ticket, "Signal alignment changed with MTF");

         lastOrderTickets[tfIndex] = 0;
         lastOrderPrices[tfIndex] = 0.0;
      }
      else
      {
         Print("Failed to cancel order for ", GetTimeframeName(timeframe), ": Ticket=", ticket, " Error: ", localTrade.ResultRetcode());
      }
   }
}

//+------------------------------------------------------------------+
//| Handle major timeframe signal change                           |
//+------------------------------------------------------------------+
void HandleMajorTimeframeChange(ENUM_ST_SIGNAL newMajorSignal)
{
   Print("=== MAJOR TIMEFRAME SIGNAL CHANGED ===");

   // Log major timeframe signal change
   string details = "MTF signal changed from " + EnumToString(lastMajorTFSignal) + " to " + EnumToString(newMajorSignal) + " - Portfolio reset initiated";
   Print("MTF Signal Change: ", details);

   // Cancel all pending orders using existing function
   CancelAllPendingOrders();

   // Close all positions using existing function
   CloseAllPositions();

   // Reset our order tracking arrays
   for (int i = 0; i < ArraySize(lastOrderTickets); i++)
   {
      // Log closure of existing orders/positions
      if (lastOrderTickets[i] > 0)
      {
         LogOrderCancelled(trackedTimeframes[i], lastOrderTickets[i], "MTF signal change - portfolio reset");
      }
      if (hasExecutedPosition[i])
      {
         LogPositionClosed(trackedTimeframes[i], 0, "MTF signal change - portfolio reset", 0.0);
      }

      lastOrderTickets[i] = 0;
      lastOrderPrices[i] = 0.0;
      hasExecutedPosition[i] = false;
   }

   // Update the last major timeframe signal
   lastMajorTFSignal = newMajorSignal;

   // Immediately place orders for timeframes aligned with new major signal
   PlaceOrdersAlignedWithMajorTF(newMajorSignal);
}

//+------------------------------------------------------------------+
//| Place orders for all timeframes aligned with major timeframe   |
//+------------------------------------------------------------------+
void PlaceOrdersAlignedWithMajorTF(ENUM_ST_SIGNAL majorSignal)
{

   ENUM_TIMEFRAMES selectedTFs[];
   GetSelectedTimeframes(selectedTFs);

   for (int i = 0; i < ArraySize(selectedTFs); i++)
   {
      ENUM_ST_SIGNAL tfSignal = GetSuperTrendSignalForTimeframe(_Symbol, selectedTFs[i]);

      if (tfSignal == majorSignal && tfSignal != ST_SIGNAL_NONE)
      {
         double stLinePrice = GetSuperTrendLineValue(_Symbol, selectedTFs[i]);
         double currentSpread = GetSpread();
         double price = (majorSignal == ST_SIGNAL_BUY) ? (stLinePrice + currentSpread) : (stLinePrice - currentSpread);

         // Place new order aligned with major timeframe
         PlaceOrUpdateOrder(selectedTFs[i], tfSignal, price);
      }
      else if (tfSignal != ST_SIGNAL_NONE)
      {
         Print("Skipping ", GetTimeframeName(selectedTFs[i]), " - Signal ", EnumToString(tfSignal), " not aligned with MTF ", EnumToString(majorSignal));
      }
   }

   Print("=== MTF ALIGNMENT ORDERS COMPLETED ===");
}

//+------------------------------------------------------------------+
//| Scan existing orders and update internal tracking (SuperTrend-Multi style) |
//+------------------------------------------------------------------+
void ScanExistingOrders()
{
   Print("=== SCANNING EXISTING ORDERS ===");
   
   // Get selected timeframes  
   ENUM_TIMEFRAMES selectedTFs[];
   GetSelectedTimeframes(selectedTFs);
   
   // Clear existing tracking
   for (int i = 0; i < ArraySize(lastOrderTickets); i++)
   {
      lastOrderTickets[i] = 0;
      lastOrderPrices[i] = 0.0;
   }
   
   // First pass: Cancel orders for non-selected timeframes
   int cancelledCount = 0;
   for (int orderIdx = OrdersTotal() - 1; orderIdx >= 0; orderIdx--)
   {
      ulong ticket = OrderGetTicket(orderIdx);
      if (ticket > 0)
      {
         if (OrderGetString(ORDER_SYMBOL) == _Symbol &&
             OrderGetInteger(ORDER_MAGIC) == magicNumber)
         {
            string orderComment = OrderGetString(ORDER_COMMENT);
            bool isSelectedTimeframe = false;
            
            // Check if this order belongs to a selected timeframe
            for (int tfIdx = 0; tfIdx < ArraySize(selectedTFs); tfIdx++)
            {
               string tfName = GetTimeframeName(selectedTFs[tfIdx]);
               string expectedComment = "SuperTrend " + tfName;
               
               if (IsTimeframeInComment(orderComment, tfName))
               {
                  isSelectedTimeframe = true;
                  break;
               }
            }
            
            // Cancel orders for non-selected timeframes
            if (!isSelectedTimeframe)
            {
               if (localTrade.OrderDelete(ticket))
               {
                  cancelledCount++;
                  Print("CLEANUP: Cancelled order for non-selected timeframe - Ticket:", ticket, " Comment:", orderComment);
               }
            }
         }
      }
   }
   
   if (cancelledCount > 0)
   {
      Print("CLEANUP: Cancelled ", cancelledCount, " orders for non-selected timeframes");
   }
   
   // Second pass: Scan remaining orders and update tracking
   for (int orderIdx = 0; orderIdx < OrdersTotal(); orderIdx++)
   {
      ulong ticket = OrderGetTicket(orderIdx);
      if (ticket > 0)
      {
         if (OrderGetString(ORDER_SYMBOL) == _Symbol &&
             OrderGetInteger(ORDER_MAGIC) == magicNumber)
         {
            string orderComment = OrderGetString(ORDER_COMMENT);
            double orderPrice = OrderGetDouble(ORDER_PRICE_OPEN);
            
            // Check which timeframe this order belongs to
            for (int tfIdx = 0; tfIdx < ArraySize(selectedTFs); tfIdx++)
            {
               string tfName = GetTimeframeName(selectedTFs[tfIdx]);
               string expectedComment = "SuperTrend " + tfName;
               
               if (IsTimeframeInComment(orderComment, tfName))
               {
                  // Found order for this timeframe - update tracking
                  int trackingIdx = FindTimeframeIndex(selectedTFs[tfIdx]);
                  if (trackingIdx >= 0)
                  {
                     lastOrderTickets[trackingIdx] = ticket;
                     lastOrderPrices[trackingIdx] = orderPrice;
                     Print("SCAN: Found order for ", tfName, " - Ticket:", ticket, " Price:", orderPrice);
                  }
                  break;
               }
            }
         }
      }
   }
   
   Print("=== ORDER SCANNING COMPLETED ===");
}

//+------------------------------------------------------------------+
//| Get order tracking data for CSV synchronization                |
//+------------------------------------------------------------------+
bool GetOrderTrackingData(ENUM_TIMEFRAMES timeframe, ulong &ticket, double &price, string &orderType)
{
   int tfIndex = FindTimeframeIndex(timeframe);
   if (tfIndex >= 0 && tfIndex < ArraySize(lastOrderTickets))
   {
      ticket = lastOrderTickets[tfIndex];
      price = lastOrderPrices[tfIndex];
      
      if (ticket > 0 && OrderSelect(ticket))
      {
         ENUM_ORDER_TYPE ot = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
         if (ot == ORDER_TYPE_BUY_LIMIT) orderType = "BUY_LIMIT";
         else if (ot == ORDER_TYPE_SELL_LIMIT) orderType = "SELL_LIMIT";
         else if (ot == ORDER_TYPE_BUY_STOP) orderType = "BUY_STOP";
         else if (ot == ORDER_TYPE_SELL_STOP) orderType = "SELL_STOP";
         else orderType = "UNKNOWN";
         return true;
      }
   }
   
   ticket = 0;
   price = 0.0;
   orderType = "NONE";
   return false;
}

//+------------------------------------------------------------------+
//| Synchronize existing MT5 orders with CSV state                 |
//+------------------------------------------------------------------+
void SynchronizeExistingOrdersWithCSV()
{
   if (MQLInfoInteger(MQL_TESTER))
   {
      Print("Sync: Skipped in Strategy Tester mode");
      return;
   }
   
   Print("=== SYNCHRONIZING ORDERS WITH CSV (SuperTrend-Multi Style) ===");
   
   // Step 1: Scan existing orders and update internal tracking (like SuperTrend-Multi)
   ScanExistingOrders();
   
   // Step 2: Use the new CSVTracker synchronization function
   SynchronizeOrdersWithCSV();
   
   Print("=== ORDER SYNCHRONIZATION COMPLETED ===");
}

//+------------------------------------------------------------------+
//| Manual function to clean up orders and sync with CSV           |
//+------------------------------------------------------------------+
void ManualOrderCleanupAndSync()
{
   Print("=== MANUAL ORDER CLEANUP AND SYNC STARTED ===");
   
   // Force CSV cleanup first
   if (EnableCSVTracking && !MQLInfoInteger(MQL_TESTER))
   {
      ManualCleanupCSV();
      SynchronizeExistingOrdersWithCSV();
   }
   
   Print("=== MANUAL ORDER CLEANUP AND SYNC COMPLETED ===");
}

//+------------------------------------------------------------------+
//| Convert string to timeframe enum                               |
//+------------------------------------------------------------------+
ENUM_TIMEFRAMES StringToTimeframe(string tfName)
{
   if (tfName == "M1") return PERIOD_M1;
   if (tfName == "M2") return PERIOD_M2;
   if (tfName == "M3") return PERIOD_M3;
   if (tfName == "M5") return PERIOD_M5;
   if (tfName == "M10") return PERIOD_M10;
   if (tfName == "M15") return PERIOD_M15;
   if (tfName == "M30") return PERIOD_M30;
   if (tfName == "H1") return PERIOD_H1;
   if (tfName == "H4") return PERIOD_H4;
   if (tfName == "D1") return PERIOD_D1;
   return PERIOD_CURRENT;
}

//+------------------------------------------------------------------+
//| Check and place order after position close (auto-reopen)       |
//+------------------------------------------------------------------+
void CheckAndPlaceOrderAfterPositionClose(ENUM_TIMEFRAMES timeframe)
{
   // Skip if trading cannot continue (daily target or protection is active)
   if (!CanContinueTrading())
   {
      Print("AUTO-REOPEN: Skipped for ", GetTimeframeName(timeframe), " - Trading suspended (daily target/protection active)");
      return;
   }

   // Get current signals
   ENUM_ST_SIGNAL currentTFSignal = GetSuperTrendSignalForTimeframe(_Symbol, timeframe);
   ENUM_ST_SIGNAL majorTFSignal = GetSuperTrendSignalForTimeframe(_Symbol, GetMajorTimeframe());

   // Check if both timeframe and major timeframe have valid signals
   if (currentTFSignal == ST_SIGNAL_NONE || majorTFSignal == ST_SIGNAL_NONE)
   {
      Print("AUTO-REOPEN: Skipped for ", GetTimeframeName(timeframe), " - No valid signals (TF:", EnumToString(currentTFSignal), " MTF:", EnumToString(majorTFSignal), ")");
      return;
   }

   // Check if timeframe signal aligns with major timeframe signal
   if (currentTFSignal == majorTFSignal)
   {
      double stLinePrice = GetSuperTrendLineValue(_Symbol, timeframe);
      double currentSpread = GetSpread();
      double price;

      if (currentTFSignal == ST_SIGNAL_BUY)
      {
         price = stLinePrice + currentSpread;
      }
      else // ST_SIGNAL_SELL
      {
         price = stLinePrice - currentSpread;
      }

      Print("AUTO-REOPEN: Placing new order for ", GetTimeframeName(timeframe), 
            " Signal: ", EnumToString(currentTFSignal), 
            " (aligned with MTF: ", EnumToString(majorTFSignal), ")");

      // Place new order using existing function
      PlaceOrUpdateOrder(timeframe, currentTFSignal, price);
   }
   else
   {
      Print("AUTO-REOPEN: Skipped for ", GetTimeframeName(timeframe), 
            " - Signal misalignment (TF:", EnumToString(currentTFSignal), 
            " vs MTF:", EnumToString(majorTFSignal), ")");
   }
}

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   // Create unique instance ID for multi-chart support
   instanceID = StringFormat("%s_%d", _Symbol, magicNumber);
   Print("=== EA INSTANCE ID: ", instanceID, " ===");
   
   // CRITICAL: Check for magic number conflicts
   // Each chart MUST have a unique magic number to avoid conflicts
   for (int i = 0; i < PositionsTotal(); i++)
   {
      if (PositionGetTicket(i) > 0)
      {
         if (PositionGetInteger(POSITION_MAGIC) == magicNumber && 
             PositionGetString(POSITION_SYMBOL) != _Symbol)
         {
            Print("!!! WARNING: Magic number ", magicNumber, " is used by another symbol: ", 
                  PositionGetString(POSITION_SYMBOL));
            Print("!!! This may cause conflicts. Use unique magic numbers for each chart!");
         }
      }
   }
   
   // Validate timeframe selection
   if (!CollectAndValidateTimeframes())
   {
      return (INIT_PARAMETERS_INCORRECT);
   }

   // Initialize trading parameters with magic number
   trade.SetExpertMagicNumber(magicNumber);
   localTrade.SetExpertMagicNumber(magicNumber);
   InitOrderManagement(magicNumber);

   // Get and store the current spread using the included function
   current_spread = GetSpread();

   // Initialize SuperTrend indicator
   if (!InitSuperTrend())
   {
      Print("Failed to initialize SuperTrend indicator");
      return (INIT_FAILED);
   }

   Sleep(1000);

   // Display initialization info
   string initMessage = StringFormat("Expert Advisor initialized successfully!\nInitial spread: %.1f\nSelected timeframes: %d\nMajor timeframe: %s",
                                     current_spread, GetSelectedTimeframesCount(), GetTimeframeName(GetMajorTimeframe()));
   Comment(initMessage);

   // Initialize SuperTrend lines
   InitializeSuperTrendLines();

   // Initialize candle tracking
   InitializeCandleTracking();

   // Initialize CSV tracking system
   if (EnableCSVTracking && !MQLInfoInteger(MQL_TESTER))
   {
      if (!InitializeCSVTracker(magicNumber))
      {
         Print("Warning: CSV tracking system failed to initialize");
      }
      
      // Ensure CSV is clean from any existing duplicates
      ManualCleanupCSV();
      
      // Display the fixed CSV structure
      DisplayCSVStructure();
      
      // FORCE cleanup to remove non-selected timeframes from existing CSV
      Print("=== FORCE CLEANING EXISTING CSV ===");
      ManualCleanupCSV();
      ManualCleanupCSV(); // Double cleanup to be sure
      
      // Load existing state from CSV if available
      LoadEAStateFromCSV();
      
      // Perform initial CSV synchronization
      SynchronizeCSVWithMT5State();
      
      // CRITICAL: Synchronize existing MT5 orders with CSV state
      SynchronizeExistingOrdersWithCSV();
      
      Print("CSV Tracking: Enabled with FIXED STRUCTURE for selected timeframes only");
   }
   else
   {
      if (MQLInfoInteger(MQL_TESTER))
         Print("CSV Tracking: Disabled (Strategy Tester mode)");
      else
         Print("CSV Tracking: Disabled by user setting");
   }

   // Initialize max loss/profit protection variables
   if (EnableMaxLossProtection)
   {
      max_loss_hit = false;
      max_loss_hit_time = 0;
      current_session_loss = 0.0;
      last_major_trend_when_max_loss = -1;
   }

   if (EnableMaxProfitProtection)
   {
      max_profit_hit = false;
      max_profit_hit_time = 0;
   }

   // Initialize daily target protection variables
   if (EnableDailyTarget)
   {
      daily_target_hit = false;
      daily_target_hit_time = 0;
      daily_loss_limit_hit = false;
      daily_loss_hit_time = 0;
      current_trading_date = 0;
      daily_profit_total = 0.0;
      daily_loss_total = 0.0;
      
      // Initialize current trading date
      MqlDateTime dt;
      TimeToStruct(TimeCurrent(), dt);
      dt.hour = 0;
      dt.min = 0;
      dt.sec = 0;
      current_trading_date = StructToTime(dt);
      
      Print("Daily Target Protection: Enabled - Target: $", DoubleToString(DailyTargetProfit, 2), 
            " Max Loss: $", DoubleToString(DailyTargetLoss, 2));
   }

   // Log EA initialization
   string initDetails = "EA initialized with " + IntegerToString(GetSelectedTimeframesCount()) + " timeframes. MTF: " + GetTimeframeName(GetMajorTimeframe()) + ". Spread: " + DoubleToString(current_spread, 1);
   Print("EA Initialization: ", initDetails);

   return (INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Update tracking arrays from CSV data (called by CSVTracker)    |
//+------------------------------------------------------------------+
void UpdateTrackingArraysFromCSV(ENUM_TIMEFRAMES timeframe, ulong orderTicket, double orderPrice, bool hasPosition)
{
   for (int i = 0; i < ArraySize(trackedTimeframes); i++)
   {
      if (trackedTimeframes[i] == timeframe)
      {
         if (orderTicket > 0)
         {
            lastOrderTickets[i] = orderTicket;
            lastOrderPrices[i] = orderPrice;
            Print("CSV Recovery: Updated order tracking for ", GetTimeframeName(timeframe), " Ticket=", orderTicket);
         }
         if (hasPosition)
         {
            hasExecutedPosition[i] = true;
            Print("CSV Recovery: Updated position tracking for ", GetTimeframeName(timeframe));
         }
         break;
      }
   }
}
//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   // Clean up SuperTrend indicator handle
   DeinitSuperTrend();

   // Cleanup SuperTrend lines
   CleanupSuperTrendLines();
}
//+------------------------------------------------------------------+
//| Check if it's a new trading day and reset daily counters        |
//+------------------------------------------------------------------+
void CheckNewTradingDay()
{
   if (!EnableDailyTarget)
      return;
      
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   dt.hour = 0;
   dt.min = 0;
   dt.sec = 0;
   datetime today = StructToTime(dt);
   
   if (today != current_trading_date)
   {
      // New trading day detected
      Print("=== NEW TRADING DAY DETECTED ===");
      Print("Previous day profit: $", DoubleToString(daily_profit_total, 2));
      Print("Previous day loss: $", DoubleToString(daily_loss_total, 2));
      
      // Reset daily counters
      current_trading_date = today;
      daily_profit_total = 0.0;
      daily_loss_total = 0.0;
      daily_target_hit = false;
      daily_target_hit_time = 0;
      daily_loss_limit_hit = false;
      daily_loss_hit_time = 0;
      
      Print("Daily targets reset for new trading day");
   }
}

//+------------------------------------------------------------------+
//| Calculate daily profit/loss from completed trades               |
//+------------------------------------------------------------------+
void CalculateDailyProfitLoss()
{
   if (!EnableDailyTarget)
      return;
      
   daily_profit_total = 0.0;
   daily_loss_total = 0.0;
   
   // Calculate from open positions
   for (int i = 0; i < PositionsTotal(); i++)
   {
      if (PositionGetTicket(i) > 0)
      {
         if (PositionGetInteger(POSITION_MAGIC) == magicNumber &&
             PositionGetString(POSITION_SYMBOL) == _Symbol)
         {
            double profit = PositionGetDouble(POSITION_PROFIT);
            if (profit > 0)
               daily_profit_total += profit;
            else
               daily_loss_total += MathAbs(profit);
         }
      }
   }
   
   // Add closed trades for today (this would require history analysis)
   // For now, we'll work with current open positions only
}

//+------------------------------------------------------------------+
//| Check daily target achievement                                   |
//+------------------------------------------------------------------+
void CheckDailyTarget()
{
   if (!EnableDailyTarget)
      return;
      
   // Check for new trading day first
   CheckNewTradingDay();
   
   // Skip if daily targets already hit
   if (daily_target_hit || daily_loss_limit_hit)
      return;
      
   // Calculate current daily profit/loss
   CalculateDailyProfitLoss();
   
   // Check daily profit target
   if (DailyTargetProfit > 0.0 && daily_profit_total >= DailyTargetProfit)
   {
      // Daily target reached - close all and stop trading
      CloseAllPositions();
      CancelAllPendingOrders();
      
      daily_target_hit = true;
      daily_target_hit_time = TimeCurrent();
      
      Print("=== DAILY TARGET ACHIEVED ===");
      Print("Daily profit target of $", DoubleToString(DailyTargetProfit, 2), " reached!");
      Print("Total daily profit: $", DoubleToString(daily_profit_total, 2));
      Print("All positions closed and orders cancelled. Trading suspended for the day.");
      
      // Reset tracking arrays
      ResetTrackingArrays("Daily target achieved");
      
      // Update CSV status
      UpdateTimeframeState("DAILY_TARGET_STATUS", true, daily_profit_total, false, 0, "DAILY_TARGET_HIT", 0.0);
   }
   
   // Check daily loss limit
   if (DailyTargetLoss > 0.0 && daily_loss_total >= DailyTargetLoss)
   {
      // Daily loss limit reached - close all and stop trading
      CloseAllPositions();
      CancelAllPendingOrders();
      
      daily_loss_limit_hit = true;
      daily_loss_hit_time = TimeCurrent();
      
      Print("=== DAILY LOSS LIMIT HIT ===");
      Print("Daily loss limit of $", DoubleToString(DailyTargetLoss, 2), " reached!");
      Print("Total daily loss: $", DoubleToString(daily_loss_total, 2));
      Print("All positions closed and orders cancelled. Trading suspended for the day.");
      
      // Reset tracking arrays
      ResetTrackingArrays("Daily loss limit hit");
      
      // Update CSV status
      UpdateTimeframeState("DAILY_LOSS_STATUS", true, daily_loss_total, false, 0, "DAILY_LOSS_HIT", 0.0);
   }
}

//+------------------------------------------------------------------+
//| Reset tracking arrays with reason                               |
//+------------------------------------------------------------------+
void ResetTrackingArrays(string reason)
{
   for (int i = 0; i < ArraySize(lastOrderTickets); i++)
   {
      if (lastOrderTickets[i] > 0)
      {
         LogOrderCancelled(trackedTimeframes[i], lastOrderTickets[i], reason);
      }
      if (hasExecutedPosition[i])
      {
         LogPositionClosed(trackedTimeframes[i], 0, reason, 0.0);
      }

      lastOrderTickets[i] = 0;
      lastOrderPrices[i] = 0.0;
      hasExecutedPosition[i] = false;
   }
}

//+------------------------------------------------------------------+
//| Update chart comment with daily progress                        |
//+------------------------------------------------------------------+
void UpdateDailyProgressComment()
{
   if (!EnableDailyTarget)
      return;
      
   string comment = "=== DAILY TRADING PROGRESS ===\n";
   
   // Calculate current daily profit/loss
   CalculateDailyProfitLoss();
   
   comment += "Daily Profit: $" + DoubleToString(daily_profit_total, 2);
   if (DailyTargetProfit > 0.0)
      comment += " / $" + DoubleToString(DailyTargetProfit, 2) + " (" + DoubleToString((daily_profit_total/DailyTargetProfit)*100, 1) + "%)";
   comment += "\n";
   
   comment += "Daily Loss: $" + DoubleToString(daily_loss_total, 2);
   if (DailyTargetLoss > 0.0)
      comment += " / $" + DoubleToString(DailyTargetLoss, 2) + " (" + DoubleToString((daily_loss_total/DailyTargetLoss)*100, 1) + "%)";
   comment += "\n";
   
   if (daily_target_hit)
   {
      comment += "\n*** DAILY TARGET ACHIEVED ***\n";
      comment += "Trading suspended for the day\n";
   }
   else if (daily_loss_limit_hit)
   {
      comment += "\n*** DAILY LOSS LIMIT HIT ***\n";
      comment += "Trading suspended for the day\n";
   }
   else
   {
      comment += "\nTrading Status: ACTIVE\n";
   }
   
   // Add current time
   comment += "Last Update: " + TimeToString(TimeCurrent(), TIME_SECONDS);
   
   Comment(comment);
}

//+------------------------------------------------------------------+
//| Check if trading can continue (includes daily target check)     |
//+------------------------------------------------------------------+
bool CanContinueTrading()
{
   // Check daily targets first
   if (EnableDailyTarget && (daily_target_hit || daily_loss_limit_hit))
   {
      return false;
   }
   
   // Check existing protection systems
   return CanResumeAfterMaxProtection();
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // Periodic CSV synchronization (every 5 minutes) - only if CSV tracking is enabled
   if (EnableCSVTracking && !MQLInfoInteger(MQL_TESTER))
   {
      datetime currentTime = TimeCurrent();
      if (currentTime - lastCSVSyncTime >= 300) // 5 minutes = 300 seconds
      {
         // DISABLED: SynchronizeCSVWithMT5State(); // Can add unwanted timeframes
         // Only clean duplicates periodically
         ManualCleanupCSV();
         lastCSVSyncTime = currentTime;
      }
   }

   // Update position tracking to check for executed orders (CSV-synchronized)
   UpdatePositionTracking();

   // Check daily targets (includes new day detection and profit/loss calculation)
   CheckDailyTarget();

   // Update daily progress display
   UpdateDailyProgressComment();

   // Check max loss and profit protection
   CheckMaxLossProtection();
   CheckMaxProfitProtection();

   // Update SuperTrend lines with optimization (once per minute) - ALWAYS UPDATE VISUALS
   UpdateSuperTrendLinesOptimized();

   // Check if trading can continue (includes daily target and protection checks)
   if (!CanContinueTrading())
   {
      // Even if protection/daily target is active, continue with visual updates and signal detection
      // but skip actual trading activities
      
      // Get selected timeframes for visual updates
      ENUM_TIMEFRAMES selectedTFs[];
      GetSelectedTimeframes(selectedTFs);

      // Continue visual updates on candle close even when protection is active
      for (int i = 0; i < ArraySize(selectedTFs); i++)
      {
         if (HasCandleClosed(selectedTFs[i]))
         {
            // Force visual update when there's a candle close
            ForceUpdateSuperTrendLines();
         }
      }

      // Check major timeframe for visual updates
      if (HasCandleClosed(GetMajorTimeframe()))
      {
         // Force visual update when major timeframe candle closes
         ForceUpdateSuperTrendLines();
      }
      
      return; // Skip trading activities but visuals continue
   }

   // Get selected timeframes once for efficiency
   ENUM_TIMEFRAMES selectedTFs[];
   GetSelectedTimeframes(selectedTFs);

   // Check signals on all selected timeframes (only on candle close)
   for (int i = 0; i < ArraySize(selectedTFs); i++)
   {
      // Only check signals when candle closes on this timeframe
      if (HasCandleClosed(selectedTFs[i]))
      {
         // Log candle close for tracking
         LogCandleClose(selectedTFs[i]);

         // Force immediate update when there's a signal
         ForceUpdateSuperTrendLines();

         ENUM_ST_SIGNAL signal = GetSuperTrendSignalForTimeframe(_Symbol, selectedTFs[i]);
         if (signal != ST_SIGNAL_NONE)
         {
            double stLinePrice = GetSuperTrendLineValue(_Symbol, selectedTFs[i]);

            // Log signal detection
            ENUM_ST_SIGNAL majorTFSignal = GetSuperTrendSignalForTimeframe(_Symbol, GetMajorTimeframe());
            bool isAligned = (majorTFSignal == signal);
            LogSignalDetected(selectedTFs[i], signal, stLinePrice, isAligned);

            // Only place orders when current timeframe signal aligns with Major TimeFrame signal
            if (majorTFSignal == ST_SIGNAL_BUY && signal == ST_SIGNAL_BUY)
            {
               // Get current spread for accurate pricing
               double price = stLinePrice + current_spread;
               PlaceOrUpdateOrder(selectedTFs[i], signal, price);
            }
            else if (majorTFSignal == ST_SIGNAL_SELL && signal == ST_SIGNAL_SELL)
            {
               // Get current spread for accurate pricing
               double price = stLinePrice - current_spread;
               // Place or update order for this timeframe (includes position check)
               PlaceOrUpdateOrder(selectedTFs[i], signal, price);
            }
            else
            {
               string majorTFStr = (majorTFSignal == ST_SIGNAL_BUY) ? "BUY" : (majorTFSignal == ST_SIGNAL_SELL) ? "SELL"
                                                                                                                : "NONE";
               // Cancel existing order for this timeframe if signals don't align
               CancelOrderForTimeframe(selectedTFs[i]);
            }
         }
      }
   }

   // Check major timeframe trend (only on candle close)
   if (HasCandleClosed(GetMajorTimeframe()))
   {
      ENUM_ST_SIGNAL majorTrendSignal = GetSuperTrendSignalForTimeframe(_Symbol, GetMajorTimeframe());
      if (majorTrendSignal != ST_SIGNAL_NONE)
      {
         // Check if major timeframe signal has changed
         if (lastMajorTFSignal != ST_SIGNAL_NONE && lastMajorTFSignal != majorTrendSignal)
         {
            // Major timeframe signal changed - handle the change
            HandleMajorTimeframeChange(majorTrendSignal);
         }
         else if (lastMajorTFSignal == ST_SIGNAL_NONE)
         {
            // First time initializing major timeframe signal
            lastMajorTFSignal = majorTrendSignal;
         }

         double majorStLinePrice = GetSuperTrendLineValue(_Symbol, GetMajorTimeframe());

         // Force immediate update when there's a major signal
         ForceUpdateSuperTrendLines();
      }
      ForceUpdateSuperTrendLines();
   }
}

int getMajorTrend()
{
   // Use SuperTrend on the higher timeframe to determine major trend
   ENUM_ST_SIGNAL majorSignal = GetSuperTrendSignalForTimeframe(_Symbol, (int)GetMajorTimeframe());

   // Convert signal to trend value
   switch (majorSignal)
   {
   case ST_SIGNAL_BUY:
      return 1; // Uptrend
   case ST_SIGNAL_SELL:
      return -1; // Downtrend
   default:
      return 0; // No trend
   }
}

//+------------------------------------------------------------------+
//| Check maximum loss protection                                    |
//+------------------------------------------------------------------+
void CheckMaxLossProtection()
{
   if (!EnableMaxLossProtection || max_loss_hit)
      return;

   double total_profit = 0.0;
   int position_count = 0;

   // Calculate total profit/loss across all positions with OUR magic number AND symbol
   for (int i = 0; i < PositionsTotal(); i++)
   {
      if (PositionGetTicket(i) > 0)
      {
         if (PositionGetInteger(POSITION_MAGIC) == magicNumber &&
             PositionGetString(POSITION_SYMBOL) == _Symbol)  // Only THIS symbol
         {
            total_profit += PositionGetDouble(POSITION_PROFIT);
            position_count++;
         }
      }
   }

   // Check if max loss threshold is breached
   if (total_profit <= -MaxOverallLoss && position_count > 0)
   {
      // Close all positions
      CloseAllPositions();

      // Cancel all pending orders
      CancelAllPendingOrders();

      // Mark max loss as hit and record the time
      max_loss_hit = true;
      max_loss_hit_time = TimeCurrent();
      current_session_loss = MathAbs(total_profit);

      // Record major timeframe signal when max loss hit for resume condition
      ENUM_ST_SIGNAL majorSignal = GetSuperTrendSignalForTimeframe(_Symbol, GetMajorTimeframe());
      last_major_trend_when_max_loss = (double)majorSignal;

      // Reset tracking arrays
      for (int i = 0; i < ArraySize(lastOrderTickets); i++)
      {
         if (lastOrderTickets[i] > 0)
         {
            LogOrderCancelled(trackedTimeframes[i], lastOrderTickets[i], "Max loss protection triggered");
         }
         if (hasExecutedPosition[i])
         {
            LogPositionClosed(trackedTimeframes[i], 0, "Max loss protection triggered", 0.0);
         }

         lastOrderTickets[i] = 0;
         lastOrderPrices[i] = 0.0;
         hasExecutedPosition[i] = false;
      }

      // Update CSV to reflect max loss status
      UpdateTimeframeState("MAX_LOSS_STATUS", true, current_session_loss, false, 0, "MAX_LOSS_HIT", 0.0);
   }
}

//+------------------------------------------------------------------+
//| Check maximum profit protection                                  |
//+------------------------------------------------------------------+
void CheckMaxProfitProtection()
{
   if (!EnableMaxProfitProtection || MaxOverallProfit == 0.0 || max_profit_hit)
      return;

   double total_profit = 0.0;
   int position_count = 0;

   // Calculate total profit/loss across all positions with OUR magic number AND symbol
   for (int i = 0; i < PositionsTotal(); i++)
   {
      if (PositionGetTicket(i) > 0)
      {
         if (PositionGetInteger(POSITION_MAGIC) == magicNumber &&
             PositionGetString(POSITION_SYMBOL) == _Symbol)  // Only THIS symbol
         {
            total_profit += PositionGetDouble(POSITION_PROFIT);
            position_count++;
         }
      }
   }

   // Check if max profit threshold is reached
   if (total_profit >= MaxOverallProfit && position_count > 0)
   {
      // Close all positions
      CloseAllPositions();

      // Cancel all pending orders
      CancelAllPendingOrders();

      // Mark max profit as hit and record the time
      max_profit_hit = true;
      max_profit_hit_time = TimeCurrent();
      Print("=== MAX PROFIT PROTECTION TRIGGERED ===");
      Print("Max profit of $", DoubleToString(total_profit, 2), " reached. All positions closed.");
      Print("Visual updates (ForceUpdateSuperTrendLines) will continue normally.");
      Print("Trading will resume when major trend changes.");

      // Record major timeframe signal when max profit hit for resume condition
      ENUM_ST_SIGNAL majorSignal = GetSuperTrendSignalForTimeframe(_Symbol, GetMajorTimeframe());
      last_major_trend_when_max_loss = (double)majorSignal; // Reuse same variable

      // Reset tracking arrays
      for (int i = 0; i < ArraySize(lastOrderTickets); i++)
      {
         if (lastOrderTickets[i] > 0)
         {
            LogOrderCancelled(trackedTimeframes[i], lastOrderTickets[i], "Max profit protection triggered");
         }
         if (hasExecutedPosition[i])
         {
            LogPositionClosed(trackedTimeframes[i], 0, "Max profit protection triggered", 0.0);
         }

         lastOrderTickets[i] = 0;
         lastOrderPrices[i] = 0.0;
         hasExecutedPosition[i] = false;
      }

      // Update CSV to reflect max profit status
      UpdateTimeframeState("MAX_PROFIT_STATUS", true, total_profit, false, 0, "MAX_PROFIT_HIT", 0.0);
   }
}

//+------------------------------------------------------------------+
//| Check if can resume trading after max loss/profit hit           |
//+------------------------------------------------------------------+
bool CanResumeAfterMaxProtection()
{
   if (!max_loss_hit && !max_profit_hit)
      return true;

   // Get current major timeframe signal
   ENUM_ST_SIGNAL currentMajorSignal = GetSuperTrendSignalForTimeframe(_Symbol, GetMajorTimeframe());

   // Check if major trend has changed since protection was triggered
   if ((double)currentMajorSignal != last_major_trend_when_max_loss && currentMajorSignal != ST_SIGNAL_NONE)
   {
      // Reset protection flags
      if (max_loss_hit)
      {
         max_loss_hit = false;
         max_loss_hit_time = 0;
         UpdateTimeframeState("MAX_LOSS_STATUS", false, 0.0, false, 0, "NONE", 0.0);
      }

      if (max_profit_hit)
      {
         max_profit_hit = false;
         max_profit_hit_time = 0;
         UpdateTimeframeState("MAX_PROFIT_STATUS", false, 0.0, false, 0, "NONE", 0.0);
      }

      last_major_trend_when_max_loss = -1;

      return true;
   }

   return false; // Cannot resume yet
}

//+------------------------------------------------------------------+


//+------------------------------------------------------------------+
//|                                                   CSVTracker.mqh |
//|         Simple CSV tracking system for EA state persistence     |
//+------------------------------------------------------------------+

#include <Files\File.mqh>

//--- CSV file settings - make instance-specific using symbol and magic
struct CSVInstance {
    string fileName;
    string filePath;
    int magicNumber;
    string symbol;
};

CSVInstance csvInstance;

//+------------------------------------------------------------------+
//| Generate CSV filename with format: Symbol-ID-MagicNumber       |
//+------------------------------------------------------------------+
string GenerateCSVFilename(int magic)
{
    string filename = StringFormat("%s-%lld-%d.csv", _Symbol, AccountInfoInteger(ACCOUNT_LOGIN), magic);
    return filename;
}

//+------------------------------------------------------------------+
//| Initialize CSV tracking system with simple headers             |
//+------------------------------------------------------------------+
bool InitializeCSVTracker(int magic = 123456)
{
    // Skip CSV tracking in Strategy Tester
    if (MQLInfoInteger(MQL_TESTER))
    {
        Print("CSV Tracker: Disabled in Strategy Tester mode");
        return true;
    }

    // Store instance-specific data
    csvInstance.magicNumber = magic;
    csvInstance.symbol = _Symbol;

    // Generate filename using new format
    csvInstance.fileName = GenerateCSVFilename(magic);

    // Create CSV file path in modular/CSV tracker/ directory
    csvInstance.filePath = "CSV tracker\\" + csvInstance.fileName;

    // Check if file exists, if not create with headers
    int fileHandle = FileOpen(csvInstance.filePath, FILE_READ | FILE_WRITE | FILE_CSV, ",");
    if (fileHandle != INVALID_HANDLE)
    {
        // Check if file is empty (new file)
        if (FileSize(fileHandle) == 0)
        {
            // Write simple headers
            FileWrite(fileHandle, "Timeframe", "Completed", "ProfitTarget", "HasOrder", "OrderTicket", "OrderType", "OrderPrice", "LastUpdate");

            // Write initial status rows for system states
            FileWrite(fileHandle, "MAX_LOSS_STATUS", "FALSE", "0.00", "FALSE", "0", "NONE", "0.0", "1970.01.01 00:00");
            FileWrite(fileHandle, "MAX_PROFIT_STATUS", "FALSE", "0.00", "FALSE", "0", "NONE", "0.0", "1970.01.01 00:00");

            // Write initial rows for ALL SELECTED timeframes
            InitializeSelectedTimeframesInCSV(fileHandle);

            Print("CSV Tracker: Created new state file with fixed selected timeframes");
        }
        FileClose(fileHandle);
        
        // ALWAYS run cleanup on initialization to remove duplicates  
        CleanupCSVDuplicates();
        
        // Ensure all selected timeframes are present (in case of partial file)
        EnsureAllSelectedTimeframesExist();
        
        Print("CSV Tracker: Initialized successfully - File: ", csvInstance.filePath);
        return true;
    }
    else
    {
        Print("CSV Tracker: Failed to initialize - Error: ", GetLastError());
        return false;
    }
}

//+------------------------------------------------------------------+
//| Initialize CSV with all selected timeframes                    |
//+------------------------------------------------------------------+
void InitializeSelectedTimeframesInCSV(int fileHandle)
{
    string defaultTime = "1970.01.01 00:00";
    
    // Get all selected timeframes
    ENUM_TIMEFRAMES selectedTFs[];
    GetSelectedTimeframes(selectedTFs);
    
    // Write entries for all selected timeframes
    for (int i = 0; i < ArraySize(selectedTFs); i++)
    {
        string tfName = GetTimeframeName(selectedTFs[i]);
        FileWrite(fileHandle, tfName, "FALSE", "0.00", "FALSE", "0", "NONE", "0.0", defaultTime);
        Print("CSV Init: Added fixed entry for ", tfName);
    }
    
    // Also ensure major timeframe is included if not already in selected list
    ENUM_TIMEFRAMES majorTF = GetMajorTimeframe();
    string majorTFName = GetTimeframeName(majorTF);
    bool majorInSelected = false;
    
    for (int i = 0; i < ArraySize(selectedTFs); i++)
    {
        if (selectedTFs[i] == majorTF)
        {
            majorInSelected = true;
            break;
        }
    }
    
    if (!majorInSelected)
    {
        FileWrite(fileHandle, majorTFName, "FALSE", "0.00", "FALSE", "0", "NONE", "0.0", defaultTime);
        Print("CSV Init: Added major timeframe ", majorTFName);
    }
}

//+------------------------------------------------------------------+
//| Ensure all selected timeframes exist in CSV                    |
//+------------------------------------------------------------------+
void EnsureAllSelectedTimeframesExist()
{
    // Skip in tester mode
    if (MQLInfoInteger(MQL_TESTER))
        return;
        
    // Get all selected timeframes
    ENUM_TIMEFRAMES selectedTFs[];
    GetSelectedTimeframes(selectedTFs);
    
    // Add major timeframe if not in selected list
    ENUM_TIMEFRAMES majorTF = GetMajorTimeframe();
    bool majorInSelected = false;
    for (int i = 0; i < ArraySize(selectedTFs); i++)
    {
        if (selectedTFs[i] == majorTF)
        {
            majorInSelected = true;
            break;
        }
    }
    
    // Create complete list including major timeframe
    ENUM_TIMEFRAMES allRequiredTFs[];
    int totalRequired = ArraySize(selectedTFs);
    if (!majorInSelected) totalRequired++;
    
    ArrayResize(allRequiredTFs, totalRequired);
    
    // Copy selected timeframes
    for (int i = 0; i < ArraySize(selectedTFs); i++)
    {
        allRequiredTFs[i] = selectedTFs[i];
    }
    
    // Add major timeframe if needed
    if (!majorInSelected)
    {
        allRequiredTFs[ArraySize(selectedTFs)] = majorTF;
    }
    
    // Check and add missing timeframes
    for (int i = 0; i < ArraySize(allRequiredTFs); i++)
    {
        string tfName = GetTimeframeName(allRequiredTFs[i]);
        TimeframeState state = GetTimeframeStateFromCSV(tfName);
        
        if (!state.isValid)
        {
            // Add missing timeframe
            string defaultTime = "1970.01.01 00:00";
            UpdateTimeframeState(tfName, false, 0.0, false, 0, "NONE", 0.0);
            Print("CSV Ensure: Added missing timeframe ", tfName);
        }
    }
}

//+------------------------------------------------------------------+
//| Check if timeframe is in selected list (validation)            |
//+------------------------------------------------------------------+
bool IsTimeframeSelected(string timeframeName)
{
    // Allow system status entries
    if (timeframeName == "MAX_LOSS_STATUS" || timeframeName == "MAX_PROFIT_STATUS")
        return true;
        
    // Get all selected timeframes
    ENUM_TIMEFRAMES selectedTFs[];
    GetSelectedTimeframes(selectedTFs);
    
    // Check selected timeframes
    for (int i = 0; i < ArraySize(selectedTFs); i++)
    {
        if (GetTimeframeName(selectedTFs[i]) == timeframeName)
            return true;
    }
    
    // Check major timeframe
    if (GetTimeframeName(GetMajorTimeframe()) == timeframeName)
        return true;
        
    return false;
}

//+------------------------------------------------------------------+
//| Simple position check for CSV synchronization                  |
//+------------------------------------------------------------------+
bool HasPositionForTimeframe_CSV(ENUM_TIMEFRAMES timeframe)
{
    string tfName = GetTimeframeName(timeframe);
    
    for (int i = 0; i < PositionsTotal(); i++)
    {
        if (PositionGetTicket(i) > 0)
        {
            if (PositionGetString(POSITION_SYMBOL) == _Symbol && 
                PositionGetInteger(POSITION_MAGIC) == csvInstance.magicNumber)
            {
                string comment = PositionGetString(POSITION_COMMENT);
                if (IsTimeframeInComment(comment, tfName))
                {
                    return true;
                }
            }
        }
    }
    return false;
}

//+------------------------------------------------------------------+
//| Direct CSV synchronization - rewrite entire file immediately   |
//+------------------------------------------------------------------+
bool SynchronizeCompleteCSVState()
{
    // Skip in tester mode
    if (MQLInfoInteger(MQL_TESTER))
        return true;
    
    Print("CSV Sync: Starting complete CSV state synchronization...");
    
    // Open file for complete rewrite
    int fileHandle = FileOpen(csvInstance.filePath, FILE_WRITE | FILE_TXT);
    if (fileHandle != INVALID_HANDLE)
    {
        // Write header
        FileWriteString(fileHandle, "Timeframe,Completed,ProfitTarget,HasOrder,OrderTicket,OrderType,OrderPrice,LastUpdate\n");
        
        // Write system status entries
        string currentTime = TimeToString(TimeCurrent(), TIME_DATE | TIME_MINUTES);
        FileWriteString(fileHandle, StringFormat("MAX_LOSS_STATUS,FALSE,0.00,FALSE,0,NONE,0.0,%s\n", currentTime));
        FileWriteString(fileHandle, StringFormat("MAX_PROFIT_STATUS,FALSE,0.00,FALSE,0,NONE,0.0,%s\n", currentTime));
        
        // Get all selected timeframes
        ENUM_TIMEFRAMES selectedTFs[];
        GetSelectedTimeframes(selectedTFs);
        
        // Add major timeframe if not in selected list
        ENUM_TIMEFRAMES majorTF = GetMajorTimeframe();
        bool majorInSelected = false;
        for (int i = 0; i < ArraySize(selectedTFs); i++)
        {
            if (selectedTFs[i] == majorTF)
            {
                majorInSelected = true;
                break;
            }
        }
        
        // Create complete list including major timeframe
        ENUM_TIMEFRAMES allRequiredTFs[];
        int totalRequired = ArraySize(selectedTFs);
        if (!majorInSelected) totalRequired++;
        
        ArrayResize(allRequiredTFs, totalRequired);
        
        // Copy selected timeframes
        for (int i = 0; i < ArraySize(selectedTFs); i++)
        {
            allRequiredTFs[i] = selectedTFs[i];
        }
        
        // Add major timeframe if needed
        if (!majorInSelected)
        {
            allRequiredTFs[ArraySize(selectedTFs)] = majorTF;
        }
        
        // Write current state for each required timeframe (using internal tracking)
        for (int i = 0; i < ArraySize(allRequiredTFs); i++)
        {
            string tfName = GetTimeframeName(allRequiredTFs[i]);
            
            // Check if timeframe has active position
            bool hasPosition = HasPositionForTimeframe_CSV(allRequiredTFs[i]);
            
            // Get order tracking data from main EA
            ulong orderTicket = 0;
            double orderPrice = 0.0;
            string orderType = "NONE";
            bool hasOrder = GetOrderTrackingData(allRequiredTFs[i], orderTicket, orderPrice, orderType);
            
            // Write timeframe state
            FileWriteString(fileHandle, StringFormat("%s,%s,0.00,%s,%llu,%s,%.5f,%s\n",
                           tfName,
                           hasPosition ? "TRUE" : "FALSE",
                           hasOrder ? "TRUE" : "FALSE",
                           orderTicket,
                           orderType,
                           orderPrice,
                           currentTime));
                           
            Print("CSV Sync: ", tfName, " -> Position:", hasPosition ? "TRUE" : "FALSE", 
                  " Order:", hasOrder ? "TRUE" : "FALSE", " Ticket:", orderTicket);
        }
        
        FileClose(fileHandle);
        Print("CSV Sync: Complete CSV state synchronization finished successfully");
        return true;
    }
    
    Print("CSV Sync: ERROR - Failed to open file for synchronization");
    return false;
}

//+------------------------------------------------------------------+
//| Fast CSV update for immediate state changes                    |
//+------------------------------------------------------------------+
bool FastUpdateCSVState(string timeframeName, bool completed, double profitTarget, bool hasOrder, ulong orderTicket, string orderType, double orderPrice)
{
    // Skip in tester mode
    if (MQLInfoInteger(MQL_TESTER))
        return true;

    // VALIDATION: Only allow updates for selected timeframes
    if (!IsTimeframeSelected(timeframeName))
    {
        Print("CSV Fast Update BLOCKED: ", timeframeName, " is not in selected timeframes list");
        return false;
    }
    
    // Use complete synchronization for immediate consistency
    bool result = SynchronizeCompleteCSVState();
    
    if (result)
    {
        Print("CSV Fast Update: ", timeframeName, " -> Completed:", completed ? "TRUE" : "FALSE", 
              " HasOrder:", hasOrder ? "TRUE" : "FALSE", " Ticket:", orderTicket);
    }
    
    return result;
}

//+------------------------------------------------------------------+
//| Update timeframe state in CSV (DUPLICATE-SAFE + SELECTED-ONLY) |
//+------------------------------------------------------------------+
bool UpdateTimeframeState(string timeframeName, bool completed, double profitTarget, bool hasOrder, ulong orderTicket, string orderType, double orderPrice)
{
    // Skip in tester mode
    if (MQLInfoInteger(MQL_TESTER))
        return true;

    // VALIDATION: Only allow updates for selected timeframes
    if (!IsTimeframeSelected(timeframeName))
    {
        Print("CSV Update BLOCKED: ", timeframeName, " is not in selected timeframes list");
        return false;
    }

    string lines[];
    string newLines[];
    bool found = false;
    string currentTime = TimeToString(TimeCurrent(), TIME_DATE | TIME_MINUTES);

    // Read all lines from file
    int fileHandle = FileOpen(csvInstance.filePath, FILE_READ | FILE_TXT);
    if (fileHandle != INVALID_HANDLE)
    {
        int lineCount = 0;
        while (!FileIsEnding(fileHandle))
        {
            string line = FileReadString(fileHandle);
            if (line != "")
            {
                ArrayResize(lines, lineCount + 1);
                lines[lineCount] = line;
                lineCount++;
            }
        }
        FileClose(fileHandle);

        // Process lines and REMOVE ALL DUPLICATES
        ArrayResize(newLines, 0);
        int newLineCount = 0;
        
        for (int i = 0; i < lineCount; i++)
        {
            if (i == 0) // Header line
            {
                ArrayResize(newLines, newLineCount + 1);
                newLines[newLineCount] = lines[i];
                newLineCount++;
                continue;
            }

            string parts[];
            int count = StringSplit(lines[i], ',', parts);

            if (count >= 8 && parts[0] == timeframeName)
            {
                if (!found) // Only process the FIRST occurrence
                {
                    // Update this timeframe's data
                    ArrayResize(newLines, newLineCount + 1);
                    newLines[newLineCount] = StringFormat("%s,%s,%.2f,%s,%llu,%s,%.5f,%s",
                                               timeframeName,
                                               completed ? "TRUE" : "FALSE",
                                               profitTarget,
                                               hasOrder ? "TRUE" : "FALSE",
                                               orderTicket,
                                               orderType,
                                               orderPrice,
                                               currentTime);
                    newLineCount++;
                    found = true;
                }
                // Skip any subsequent duplicates for this timeframe
            }
            else
            {
                // Keep lines for other timeframes
                ArrayResize(newLines, newLineCount + 1);
                newLines[newLineCount] = lines[i];
                newLineCount++;
            }
        }

        // If timeframe not found, add new line
        if (!found)
        {
            ArrayResize(newLines, newLineCount + 1);
            newLines[newLineCount] = StringFormat("%s,%s,%.2f,%s,%llu,%s,%.5f,%s",
                                               timeframeName,
                                               completed ? "TRUE" : "FALSE",
                                               profitTarget,
                                               hasOrder ? "TRUE" : "FALSE",
                                               orderTicket,
                                               orderType,
                                               orderPrice,
                                               currentTime);
        }

        // Write all lines back
        fileHandle = FileOpen(csvInstance.filePath, FILE_WRITE | FILE_TXT);
        if (fileHandle != INVALID_HANDLE)
        {
            for (int i = 0; i < ArraySize(newLines); i++)
            {
                if (newLines[i] != "")
                    FileWriteString(fileHandle, newLines[i] + "\n");
            }
            FileClose(fileHandle);
            
            Print("CSV Update: ", timeframeName, " -> Completed:", completed ? "TRUE" : "FALSE", 
                  " HasOrder:", hasOrder ? "TRUE" : "FALSE", " Ticket:", orderTicket);
            
            return true;
        }
    }

    return false;
}

//+------------------------------------------------------------------+
//| Clean up duplicate entries in CSV file                         |
//+------------------------------------------------------------------+
bool CleanupCSVDuplicates()
{
    // Skip in tester mode
    if (MQLInfoInteger(MQL_TESTER))
        return true;
        
    string lines[];
    string cleanLines[];
    string processedTimeframes[];
    
    // Read all lines from file
    int fileHandle = FileOpen(csvInstance.filePath, FILE_READ | FILE_TXT);
    if (fileHandle != INVALID_HANDLE)
    {
        int lineCount = 0;
        while (!FileIsEnding(fileHandle))
        {
            string line = FileReadString(fileHandle);
            if (line != "")
            {
                ArrayResize(lines, lineCount + 1);
                lines[lineCount] = line;
                lineCount++;
            }
        }
        FileClose(fileHandle);

        if (lineCount == 0) return true;

        // Process lines and keep only unique timeframes
        ArrayResize(cleanLines, 0);
        ArrayResize(processedTimeframes, 0);
        int cleanCount = 0;
        int tfCount = 0;
        
        for (int i = 0; i < lineCount; i++)
        {
            if (i == 0) // Header line
            {
                ArrayResize(cleanLines, cleanCount + 1);
                cleanLines[cleanCount] = lines[i];
                cleanCount++;
                continue;
            }

            string parts[];
            int count = StringSplit(lines[i], ',', parts);

            if (count >= 8)
            {
                string timeframeName = parts[0];
                bool alreadyProcessed = false;
                
                // Check if we've already processed this timeframe
                for (int j = 0; j < tfCount; j++)
                {
                    if (processedTimeframes[j] == timeframeName)
                    {
                        alreadyProcessed = true;
                        break;
                    }
                }
                
                // ONLY KEEP SELECTED TIMEFRAMES
                if (!alreadyProcessed && IsTimeframeSelected(timeframeName))
                {
                    // Keep this line (first occurrence of selected timeframe)
                    ArrayResize(cleanLines, cleanCount + 1);
                    cleanLines[cleanCount] = lines[i];
                    cleanCount++;
                    
                    // Mark timeframe as processed
                    ArrayResize(processedTimeframes, tfCount + 1);
                    processedTimeframes[tfCount] = timeframeName;
                    tfCount++;
                }
                else if (!alreadyProcessed && !IsTimeframeSelected(timeframeName))
                {
                    Print("CSV Cleanup: Removed non-selected timeframe ", timeframeName);
                }
                else
                {
                    Print("CSV Cleanup: Removed duplicate entry for ", timeframeName);
                }
            }
        }

        // Write cleaned lines back
        fileHandle = FileOpen(csvInstance.filePath, FILE_WRITE | FILE_TXT);
        if (fileHandle != INVALID_HANDLE)
        {
            for (int i = 0; i < ArraySize(cleanLines); i++)
            {
                if (cleanLines[i] != "")
                    FileWriteString(fileHandle, cleanLines[i] + "\n");
            }
            FileClose(fileHandle);
            
            Print("CSV Cleanup: Processed ", lineCount, " lines -> ", ArraySize(cleanLines), " clean lines");
            return true;
        }
    }

    return false;
}

//+------------------------------------------------------------------+
//| Manually clean current CSV file (can be called anytime)       |
//+------------------------------------------------------------------+
bool ManualCleanupCSV()
{
    if (MQLInfoInteger(MQL_TESTER))
    {
        Print("Manual CSV Cleanup: Skipped in tester mode");
        return true;
    }
    
    Print("=== MANUAL CSV CLEANUP STARTED ===");
    bool result = CleanupCSVDuplicates();
    Print("=== MANUAL CSV CLEANUP COMPLETED ===");
    
    return result;
}

//+------------------------------------------------------------------+
//| Display current CSV structure for verification                 |
//+------------------------------------------------------------------+
void DisplayCSVStructure()
{
    if (MQLInfoInteger(MQL_TESTER))
    {
        Print("CSV Structure Display: Skipped in tester mode");
        return;
    }
    
    Print("=== CURRENT CSV STRUCTURE ===");
    
    // Get selected timeframes
    ENUM_TIMEFRAMES selectedTFs[];
    GetSelectedTimeframes(selectedTFs);
    
    Print("Selected Timeframes for CSV:");
    for (int i = 0; i < ArraySize(selectedTFs); i++)
    {
        Print("  - ", GetTimeframeName(selectedTFs[i]));
    }
    
    // Check major timeframe
    ENUM_TIMEFRAMES majorTF = GetMajorTimeframe();
    string majorTFName = GetTimeframeName(majorTF);
    bool majorInSelected = false;
    for (int i = 0; i < ArraySize(selectedTFs); i++)
    {
        if (selectedTFs[i] == majorTF)
        {
            majorInSelected = true;
            break;
        }
    }
    
    if (!majorInSelected)
    {
        Print("Major Timeframe (additional): ", majorTFName);
    }
    else
    {
        Print("Major Timeframe: ", majorTFName, " (already in selected list)");
    }
    
    Print("System Entries: MAX_LOSS_STATUS, MAX_PROFIT_STATUS");
    Print("=== END CSV STRUCTURE ===");
}

//+------------------------------------------------------------------+
//| Load EA state from simple CSV format                           |
//+------------------------------------------------------------------+
bool LoadEAStateFromCSV()
{
    // Skip in tester mode
    if (MQLInfoInteger(MQL_TESTER))
    {
        Print("CSV Tracker: Skipping state load in tester mode");
        return true;
    }

    int fileHandle = FileOpen(csvInstance.filePath, FILE_READ | FILE_TXT);
    if (fileHandle == INVALID_HANDLE)
    {
        Print("CSV Tracker: No existing state file found - Starting fresh");
        return false;
    }

    // Skip header line
    string header = FileReadString(fileHandle);
    int restoredStates = 0;

    // Read each timeframe state
    while (!FileIsEnding(fileHandle))
    {
        string data = FileReadString(fileHandle);
        if (data == "")
            continue;

        string parts[];
        int count = StringSplit(data, ',', parts);

        if (count >= 8)
        {
            string timeframeName = parts[0];
            bool completed = (parts[1] == "TRUE");
            double profitTarget = StringToDouble(parts[2]);
            bool hasOrder = (parts[3] == "TRUE");
            ulong orderTicket = StringToInteger(parts[4]);
            string orderType = parts[5];
            double orderPrice = StringToDouble(parts[6]);
            string lastUpdate = parts[7];

            // Skip placeholder rows
            if (timeframeName == "MAX_LOSS_STATUS" || timeframeName == "MAX_PROFIT_STATUS")
                continue;

            // Convert timeframe name to ENUM_TIMEFRAMES
            ENUM_TIMEFRAMES tf = GetTimeframeFromName(timeframeName);
            if (tf == PERIOD_CURRENT)
            {
                Print("CSV Tracker: Invalid timeframe: ", timeframeName);
                continue; // Invalid timeframe
            }

            // Find the index in the tracking arrays
            int tfIndex = FindTimeframeIndex(tf);
            if (tfIndex == -1)
            {
                Print("CSV Tracker: Timeframe not tracked: ", timeframeName);
                continue; // Timeframe not tracked by current EA
            }

            // Restore order tracking if there's an active order
            if (hasOrder && orderTicket > 0)
            {
                // Verify order still exists before restoring
                if (OrderExists(orderTicket))
                {
                    lastOrderTickets[tfIndex] = orderTicket;
                    lastOrderPrices[tfIndex] = orderPrice;
                    Print("CSV Tracker: Restored order tracking - TF: ", timeframeName,
                          ", Ticket: ", orderTicket, ", Price: ", orderPrice);
                    restoredStates++;
                }
                else
                {
                    Print("CSV Tracker: Order ", orderTicket, " no longer exists for ", timeframeName);
                    // Clear the state since order doesn't exist
                    lastOrderTickets[tfIndex] = 0;
                    lastOrderPrices[tfIndex] = 0.0;
                }
            }
            else
            {
                // No active order for this timeframe
                lastOrderTickets[tfIndex] = 0;
                lastOrderPrices[tfIndex] = 0.0;
            }

            // Restore position execution status
            if (completed)
            {
                // Check if position is still open for this timeframe
                bool hasPosition = PositionExists(tf);
                hasExecutedPosition[tfIndex] = hasPosition;

                if (hasPosition)
                {
                    Print("CSV Tracker: Restored position status - TF: ", timeframeName, " (Position still open)");
                    restoredStates++;
                }
                else
                {
                    Print("CSV Tracker: Position closed for ", timeframeName, " - resetting status");
                    hasExecutedPosition[tfIndex] = false;
                }
            }
            else
            {
                hasExecutedPosition[tfIndex] = false;
            }
        }
    }

    FileClose(fileHandle);
    Print("=== CSV STATE LOADING COMPLETE - ", restoredStates, " states restored ===");
    return true;
}

//+------------------------------------------------------------------+
//| Immediate CSV update functions matching SuperTrend-Multi style |
//+------------------------------------------------------------------+
bool LogOrderPlaced(ENUM_TIMEFRAMES timeframe, ulong ticket, double price, string orderType)
{
    // Use fast update which triggers complete CSV synchronization
    bool result = FastUpdateCSVState(GetTimeframeName(timeframe), false, 0.0, true, ticket, orderType, price);
    if (result)
    {
        Print("CSV: Order placed for ", GetTimeframeName(timeframe), " - Ticket:", ticket, " Price:", price, " | CSV updated");
    }
    return result;
}

bool LogOrderCancelled(ENUM_TIMEFRAMES timeframe, ulong ticket, string reason)
{
    // Use fast update which triggers complete CSV synchronization  
    bool result = FastUpdateCSVState(GetTimeframeName(timeframe), false, 0.0, false, 0, "NONE", 0.0);
    return result;
}

bool LogOrderUpdated(ENUM_TIMEFRAMES timeframe, ulong ticket, double oldPrice, double newPrice) 
{ 
    // Get current order type for update
    string orderType = "NONE";
    if (OrderSelect(ticket))
    {
        ENUM_ORDER_TYPE ot = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
        if (ot == ORDER_TYPE_BUY_LIMIT) orderType = "BUY_LIMIT";
        else if (ot == ORDER_TYPE_SELL_LIMIT) orderType = "SELL_LIMIT";
        else if (ot == ORDER_TYPE_BUY_STOP) orderType = "BUY_STOP";
        else if (ot == ORDER_TYPE_SELL_STOP) orderType = "SELL_STOP";
    }
    
    // Use fast update which triggers complete CSV synchronization
    bool result = FastUpdateCSVState(GetTimeframeName(timeframe), false, 0.0, true, ticket, orderType, newPrice);
    if (result)
    {
        Print("CSV: Order updated for ", GetTimeframeName(timeframe), " - Ticket:", ticket, " NewPrice:", newPrice, " | CSV updated");
    }
    return result;
}

bool LogPositionOpened(ENUM_TIMEFRAMES timeframe, ulong ticket, string positionType, double openPrice)
{
    // Position opened - mark as completed in CSV
    bool result = FastUpdateCSVState(GetTimeframeName(timeframe), true, 0.0, false, 0, "NONE", 0.0);
    if (result)
    {
        Print("CSV: Position opened for ", GetTimeframeName(timeframe), " - Ticket:", ticket, " Type:", positionType, " | CSV updated");
    }
    return result;
}

bool LogPositionClosed(ENUM_TIMEFRAMES timeframe, ulong ticket, string reason, double closePrice)
{
    // Position closed - reset timeframe in CSV
    bool result = FastUpdateCSVState(GetTimeframeName(timeframe), false, 0.0, false, 0, "NONE", 0.0);
    if (result)
    {
        Print("CSV: Position closed for ", GetTimeframeName(timeframe), " - Ticket:", ticket, " Reason:", reason, " | CSV updated");
    }
    return result;
}

//+------------------------------------------------------------------+
//| Helper functions for CSV state restoration                     |
//+------------------------------------------------------------------+

// Convert timeframe name string to ENUM_TIMEFRAMES
ENUM_TIMEFRAMES GetTimeframeFromName(string tfName)
{
    if (tfName == "M1")
        return PERIOD_M1;
    if (tfName == "M5")
        return PERIOD_M5;
    if (tfName == "M15")
        return PERIOD_M15;
    if (tfName == "M30")
        return PERIOD_M30;
    if (tfName == "H1")
        return PERIOD_H1;
    if (tfName == "H4")
        return PERIOD_H4;
    if (tfName == "D1")
        return PERIOD_D1;
    if (tfName == "W1")
        return PERIOD_W1;
    if (tfName == "MN1")
        return PERIOD_MN1;

    return PERIOD_CURRENT; // Invalid timeframe
}

//+------------------------------------------------------------------+
//| External variable references from main.mq5                      |
//+------------------------------------------------------------------+
extern ulong lastOrderTickets[];
extern double lastOrderPrices[];
extern bool hasExecutedPosition[];
extern ENUM_TIMEFRAMES trackedTimeframes[];

//+------------------------------------------------------------------+
//| CSV State Verification and Synchronization Functions           |
//+------------------------------------------------------------------+

// Get timeframe state from CSV
struct TimeframeState
{
    bool completed;
    double profitTarget;
    bool hasOrder;
    ulong orderTicket;
    string orderType;
    double orderPrice;
    string lastUpdate;
    bool isValid;
};

//+------------------------------------------------------------------+
//| Get timeframe state from CSV file                              |
//+------------------------------------------------------------------+
TimeframeState GetTimeframeStateFromCSV(string timeframeName)
{
    TimeframeState state;
    state.isValid = false;

    if (MQLInfoInteger(MQL_TESTER))
        return state;

    int fileHandle = FileOpen(csvInstance.filePath, FILE_READ | FILE_TXT);
    if (fileHandle == INVALID_HANDLE)
        return state;

    string header = FileReadString(fileHandle); // Skip header

    while (!FileIsEnding(fileHandle))
    {
        string line = FileReadString(fileHandle);
        if (line == "")
            continue;

        string parts[];
        int count = StringSplit(line, ',', parts);

        if (count >= 8 && parts[0] == timeframeName)
        {
            state.completed = (parts[1] == "TRUE");
            state.profitTarget = StringToDouble(parts[2]);
            state.hasOrder = (parts[3] == "TRUE");
            state.orderTicket = (ulong)StringToInteger(parts[4]);
            state.orderType = parts[5];
            state.orderPrice = StringToDouble(parts[6]);
            state.lastUpdate = parts[7];
            state.isValid = true;
            break;
        }
    }

    FileClose(fileHandle);
    return state;
}

//+------------------------------------------------------------------+
//| Check if EA can place order based on CSV state                 |
//+------------------------------------------------------------------+
bool CanPlaceOrderForTimeframe(ENUM_TIMEFRAMES timeframe, string reason = "")
{
    string tfName = GetTimeframeName(timeframe);
    TimeframeState csvState = GetTimeframeStateFromCSV(tfName);

    // If CSV state not found, allow order placement
    if (!csvState.isValid)
    {
        return true;
    }

    // Check if position is already completed (open)
    if (csvState.completed)
    {
        // Verify position still exists
        bool actuallyHasPosition = HasOpenPositionForTimeframe(timeframe);
        if (actuallyHasPosition)
        {
            return false;
        }
        else
        {
            Print("CSV Check: CSV shows completed but no position found for ", tfName, " - allowing order (will sync CSV)");
            // Update CSV to reflect reality
            UpdateTimeframeState(tfName, false, 0.0, false, 0, "NONE", 0.0);
            return true;
        }
    }

    // Check if order already exists
    if (csvState.hasOrder && csvState.orderTicket > 0)
    {
        // Verify order still exists
        if (OrderExists(csvState.orderTicket))
        {
            Print("CSV Check: Active order exists for ", tfName, " (Ticket: ", csvState.orderTicket, ") - allowing update");
            return true; // Allow updates to existing orders
        }
        else
        {
            Print("CSV Check: CSV shows order but order doesn't exist for ", tfName, " - allowing new order (will sync CSV)");
            // Update CSV to reflect reality
            UpdateTimeframeState(tfName, false, 0.0, false, 0, "NONE", 0.0);
            return true;
        }
    }

    Print("CSV Check: No conflicts found for ", tfName, " - allowing order placement");
    return true;
}

//+------------------------------------------------------------------+
//| IMMEDIATE CSV SYNCHRONIZATION - Match SuperTrend-Multi Logic   |
//+------------------------------------------------------------------+
void SynchronizeOrdersWithCSV()
{
    if (MQLInfoInteger(MQL_TESTER))
        return;
        
    Print("=== CSV SYNC: Starting order synchronization (SuperTrend-Multi style) ===");
    
    int existingOrders = 0;
    
    // Count existing orders for our symbol and magic
    for (int i = 0; i < OrdersTotal(); i++)
    {
        if (OrderSelect(i))
        {
            if (OrderGetString(ORDER_SYMBOL) == _Symbol && 
                OrderGetInteger(ORDER_MAGIC) == csvInstance.magicNumber)
            {
                existingOrders++;
            }
        }
    }
    
    if (existingOrders > 0)
    {
        Print("CSV Sync: Found ", existingOrders, " existing orders - updating CSV to match broker state");
        SynchronizeCompleteCSVState();
    }
    else
    {
        Print("CSV Sync: No existing orders found - CSV will be updated as new orders are placed");
        // Still sync to clean up any stale CSV data
        SynchronizeCompleteCSVState();
    }
    
    Print("=== CSV SYNC: Order synchronization completed ===");
}

//+------------------------------------------------------------------+
//| Enhanced CSV state sync compatible with SuperTrend-Multi       |
//+------------------------------------------------------------------+
void SynchronizeCSVWithMT5State()
{
    if (MQLInfoInteger(MQL_TESTER))
        return;

    Print("=== CSV SYNC: FULL SYNCHRONIZATION (SuperTrend-Multi Compatible) ===");
    
    // Use the immediate synchronization approach
    SynchronizeOrdersWithCSV();
    
    // Additional cleanup
    CleanupCSVDuplicates();
    
    Print("=== CSV SYNC COMPLETE ===");
}

//+------------------------------------------------------------------+
//| Enhanced HasOpenPositionForTimeframe with immediate CSV sync   |
//+------------------------------------------------------------------+
bool HasOpenPositionForTimeframe_Synced(ENUM_TIMEFRAMES timeframe)
{
    // First check actual MT5 state
    bool actualHasPosition = HasOpenPositionForTimeframe(timeframe);

    // Get CSV state
    string tfName = GetTimeframeName(timeframe);
    TimeframeState csvState = GetTimeframeStateFromCSV(tfName);

    // If states don't match, immediately sync the entire CSV
    if (csvState.isValid && csvState.completed != actualHasPosition)
    {
        Print("CSV State Mismatch for ", tfName, " - CSV:", csvState.completed ? "TRUE" : "FALSE", 
              " MT5:", actualHasPosition ? "TRUE" : "FALSE", " - Syncing immediately");
        
        // Use fast update which triggers complete synchronization
        FastUpdateCSVState(tfName, actualHasPosition, 0.0, csvState.hasOrder, csvState.orderTicket, csvState.orderType, csvState.orderPrice);
    }

    return actualHasPosition;
}

// Additional logging functions for compatibility
bool LogSignalDetected(ENUM_TIMEFRAMES timeframe, ENUM_ST_SIGNAL signal, double linePrice, bool aligned) { return true; }
bool LogCandleClose(ENUM_TIMEFRAMES timeframe) { return true; }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//|                                                    GetSpread.mqh |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

//+------------------------------------------------------------------+
//| Function to get current spread                                   |
//+------------------------------------------------------------------+
double GetSpread()
  {
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double spread = ask - bid;
   
   // Convert to points if needed
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double spread_points = spread / point;
   
//    Print("Current spread: ", spread, " (", spread_points, " points)");
   return spread;
  }

//+------------------------------------------------------------------+
//| Function to get spread in points                                 |
//+------------------------------------------------------------------+
double GetSpreadPoints()
  {
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double spread = ask - bid;
   
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double spread_points = spread / point;
   
   return spread_points;
  }

//+------------------------------------------------------------------+
//| Function to get spread without printing                         |
//+------------------------------------------------------------------+
double GetSpreadSilent()
  {
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   return (ask - bid);
  }

//+------------------------------------------------------------------+
//|                                         OrderManagement.mqh      |
//+------------------------------------------------------------------+

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

// Place a pending BUY STOP order using CTrade object
bool PlaceBuyStop(double lot_Size, double price, string comment = "", double stopLoss = 0, double takeProfit = 0)
{
   // stopLoss/takeProfit = 0 means no SL/TP
   datetime expiration = 0;
   bool result = m_trade.BuyLimit(lot_Size, price, _Symbol, stopLoss, takeProfit, ORDER_TIME_GTC, expiration, comment);
   if(!result)
   {
      Print("BUY STOP order failed: ", m_trade.ResultRetcode());
      return false;
   }
   return true;
}

// Place a pending SELL STOP order using CTrade object
bool PlaceSellStop(double lot_Size, double price, string comment = "", double stopLoss = 0, double takeProfit = 0)
{
   // stopLoss/takeProfit = 0 means no SL/TP
   datetime expiration = 0;
   bool result = m_trade.SellLimit(lot_Size, price, _Symbol, stopLoss, takeProfit, ORDER_TIME_GTC, expiration, comment);
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


//+------------------------------------------------------------------+
//|                                              SuperTrendLines.mqh |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

//--- Drawing parameters
input group "=== DRAWING PARAMETERS ==="
input bool DrawSuperTrendLines = true;   // Draw SuperTrend horizontal lines
input bool ShowTimeframeLabels = true;   // Show timeframe labels on lines
input int LineWidth = 2;                 // Line width
input ENUM_LINE_STYLE LineStyle = STYLE_SOLID; // Line style
input int TextFontSize = 18;              // Font size for labels
input string TextFont = "Arial";         // Font for labels

//--- Color array for different timeframes
color TimeframeColors[] = {
   clrBlue,      // For first timeframe
   clrRed,       // For second timeframe  
   clrGreen,     // For third timeframe
   clrViolet,    // For fourth timeframe
   clrPurple,    // For fifth timeframe
   clrChocolate,    // For sixth timeframe
   clrCyan,      // For seventh timeframe
   clrMagenta    // For eighth timeframe
};

//--- Global variables for line management
static datetime last_update_time = 0;

//+------------------------------------------------------------------+
//| Create or update horizontal line for SuperTrend                 |
//+------------------------------------------------------------------+
void CreateOrUpdateSuperTrendLine(string lineName, double price, color lineColor, int width = 2, ENUM_LINE_STYLE style = STYLE_SOLID)
{
   if(!DrawSuperTrendLines) return;
   
   // Delete existing line if it exists
   if(ObjectFind(0, lineName) >= 0)
   {
      ObjectDelete(0, lineName);
   }
   
   // Delete existing text label if it exists
   string textName = lineName + "_Text";
   if(ObjectFind(0, textName) >= 0)
   {
      ObjectDelete(0, textName);
   }
   
   // Create new horizontal line
   if(ObjectCreate(0, lineName, OBJ_HLINE, 0, 0, price))
   {
      ObjectSetInteger(0, lineName, OBJPROP_COLOR, lineColor);
      ObjectSetInteger(0, lineName, OBJPROP_WIDTH, width);
      ObjectSetInteger(0, lineName, OBJPROP_STYLE, style);
      ObjectSetInteger(0, lineName, OBJPROP_BACK, false);
      ObjectSetInteger(0, lineName, OBJPROP_SELECTABLE, true);
      ObjectSetInteger(0, lineName, OBJPROP_HIDDEN, false);
      ObjectSetString(0, lineName, OBJPROP_TOOLTIP, lineName + ": " + DoubleToString(price, _Digits));
   }
   
   // Create text label for the line (only if enabled)
   if(ShowTimeframeLabels)
   {
      string timeframeName = "";
      if(StringFind(lineName, "_Major_") >= 0)
      {
         // Extract timeframe name from major line
         int pos = StringFind(lineName, "_Major_") + 7;
         timeframeName = StringSubstr(lineName, pos) + "MTF";
      }
      else
      {
         // Extract timeframe name from regular line
         int pos = StringFind(lineName, "ST_Line_") + 8;
         timeframeName = StringSubstr(lineName, pos);
      }
      
      datetime currentTime = TimeCurrent();
      if(ObjectCreate(0, textName, OBJ_TEXT, 0, currentTime, price))
      {
         ObjectSetString(0, textName, OBJPROP_TEXT, timeframeName + ":" + DoubleToString(price, _Digits));
         ObjectSetInteger(0, textName, OBJPROP_COLOR, lineColor);
         ObjectSetInteger(0, textName, OBJPROP_FONTSIZE, TextFontSize);
         ObjectSetString(0, textName, OBJPROP_FONT, TextFont);
         ObjectSetInteger(0, textName, OBJPROP_ANCHOR, ANCHOR_LEFT);
         ObjectSetInteger(0, textName, OBJPROP_BACK, false);
         ObjectSetInteger(0, textName, OBJPROP_SELECTABLE, false);
         ObjectSetInteger(0, textName, OBJPROP_HIDDEN, false);
      }
   }
}

//+------------------------------------------------------------------+
//| Remove all SuperTrend lines                                     |
//+------------------------------------------------------------------+
void RemoveAllSuperTrendLines()
{
   // Remove all objects that start with "ST_Line_"
   int totalObjects = ObjectsTotal(0);
   for(int i = totalObjects - 1; i >= 0; i--)
   {
      string objName = ObjectName(0, i);
      if(StringFind(objName, "ST_Line_") == 0)
      {
         ObjectDelete(0, objName);
      }
   }
}

//+------------------------------------------------------------------+
//| Remove all SuperTrend lines (legacy function for compatibility) |
//+------------------------------------------------------------------+
void RemoveAllSuperTrendLinesLegacy()
{
   // Get selected timeframes
   ENUM_TIMEFRAMES selectedTFs[];
   GetSelectedTimeframes(selectedTFs);
   
   // Remove lines and text labels for selected timeframes
   for(int i = 0; i < ArraySize(selectedTFs); i++)
   {
      string lineName = "ST_Line_" + GetTimeframeName(selectedTFs[i]);
      string textName = lineName + "_Text";
      
      if(ObjectFind(0, lineName) >= 0)
      {
         ObjectDelete(0, lineName);
      }
      if(ObjectFind(0, textName) >= 0)
      {
         ObjectDelete(0, textName);
      }
   }
   
   // Remove major timeframe line and text
   string majorLineName = "ST_Line_Major_" + GetTimeframeName(GetMajorTimeframe());
   string majorTextName = majorLineName + "_Text";
   
   if(ObjectFind(0, majorLineName) >= 0)
   {
      ObjectDelete(0, majorLineName);
   }
   if(ObjectFind(0, majorTextName) >= 0)
   {
      ObjectDelete(0, majorTextName);
   }
}

//+------------------------------------------------------------------+
//| Update all SuperTrend lines                                     |
//+------------------------------------------------------------------+
void UpdateSuperTrendLines()
{
   if(!DrawSuperTrendLines) return;
   
   // Get selected timeframes
   ENUM_TIMEFRAMES selectedTFs[];
   GetSelectedTimeframes(selectedTFs);
   
   // Draw lines for each selected timeframe
   for(int i = 0; i < ArraySize(selectedTFs); i++)
   {
      double stLinePrice = GetSuperTrendLineValue(_Symbol, selectedTFs[i]);
      if(stLinePrice > 0)
      {
         string lineName = "ST_Line_" + GetTimeframeName(selectedTFs[i]);
         color lineColor = TimeframeColors[i % ArraySize(TimeframeColors)];
         
         // Check if this is the major timeframe and set to black
         if(selectedTFs[i] == GetMajorTimeframe())
         {
            lineColor = clrBlack;
            lineName = "ST_Line_Major_" + GetTimeframeName(selectedTFs[i]);
         }
         
         CreateOrUpdateSuperTrendLine(lineName, stLinePrice, lineColor, LineWidth, LineStyle);
      }
   }
   
   // Draw major timeframe line if it's not in selected timeframes
   bool majorInSelected = false;
   for(int i = 0; i < ArraySize(selectedTFs); i++)
   {
      if(selectedTFs[i] == GetMajorTimeframe())
      {
         majorInSelected = true;
         break;
      }
   }
   
   if(!majorInSelected)
   {
      double majorStLinePrice = GetSuperTrendLineValue(_Symbol, GetMajorTimeframe());
      if(majorStLinePrice > 0)
      {
         string majorLineName = "ST_Line_Major_" + GetTimeframeName(GetMajorTimeframe());
         CreateOrUpdateSuperTrendLine(majorLineName, majorStLinePrice, clrBlack, LineWidth + 1, LineStyle);
      }
   }
}

//+------------------------------------------------------------------+
//| Update lines with performance optimization                      |
//+------------------------------------------------------------------+
void UpdateSuperTrendLinesOptimized()
{
   // Update SuperTrend lines only once per minute to improve performance
   datetime current_time = TimeGMT();
   if(current_time - last_update_time >= 60 || last_update_time == 0)
   {
      UpdateSuperTrendLines();
      last_update_time = current_time;
   }
}

//+------------------------------------------------------------------+
//| Force immediate update of SuperTrend lines                     |
//+------------------------------------------------------------------+
void ForceUpdateSuperTrendLines()
{
   UpdateSuperTrendLines();
   last_update_time = TimeGMT();
}

//+------------------------------------------------------------------+
//| Initialize SuperTrend lines (call in OnInit)                   |
//+------------------------------------------------------------------+
void InitializeSuperTrendLines()
{
   // Draw initial SuperTrend lines
   UpdateSuperTrendLines();
   last_update_time = TimeGMT();
}

//+------------------------------------------------------------------+
//| Cleanup SuperTrend lines (call in OnDeinit)                    |
//+------------------------------------------------------------------+
void CleanupSuperTrendLines()
{
   // Remove all SuperTrend lines
   RemoveAllSuperTrendLines();
}

//+------------------------------------------------------------------+
//|                                              SuperTrendSignal.mqh |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

//--- SuperTrend parameters (matching the indicator)
string IndicatorName = "SPRTRND"; // Objects Prefix
double ATRMultiplier = 9.0;       // ATR Multiplier
int ATRPeriod = 27;                // ATR Period
int ATRMaxBars = 10000;            // ATR Max Bars
int IndicatorShift = 0;            // Indicator shift
bool EnableNotify = false;         // Enable notifications
bool SendAlert = false;            // Send alert
bool SendApp = false;              // Send push notification
bool SendEmail = false;            // Send email
int TriggerCandle = 1;             // Trigger Candle (0=Current, 1=Previous)

//--- SuperTrend indicator handle
int SuperTrend_Handle = INVALID_HANDLE;

//+------------------------------------------------------------------+
//| Initialize SuperTrend indicator handle                          |
//+------------------------------------------------------------------+
bool InitSuperTrend()
{
   SuperTrend_Handle = iCustom(_Symbol, 0, "Supertrend", 
                               IndicatorName, ATRMultiplier, ATRPeriod, ATRMaxBars, IndicatorShift, 
                               EnableNotify, SendAlert, SendApp, SendEmail, TriggerCandle);
   
   if (SuperTrend_Handle == INVALID_HANDLE)
   {
      Print("Failed to create SuperTrend indicator handle. Error: ", GetLastError());
      return false;
   }
   
   Print("SuperTrend indicator initialized successfully");
   return true;
}

//+------------------------------------------------------------------+
//| Function to get SuperTrend signal                               |
//+------------------------------------------------------------------+
ENUM_ST_SIGNAL GetSuperTrendSignal()
{
   if (SuperTrend_Handle == INVALID_HANDLE)
   {
      Print("SuperTrend handle is invalid, attempting to initialize...");
      if (!InitSuperTrend()) return ST_SIGNAL_NONE;
   }
   
   double st_direction[5];  // Get more values for better analysis
   
   // Copy TrendDirection buffer data (buffer 2)
   if (CopyBuffer(SuperTrend_Handle, 2, 0, 5, st_direction) < 5)
   {
      return ST_SIGNAL_NONE;
   }
   
   // Check if we have valid data (not EMPTY_VALUE)
   bool hasValidData = false;
   for(int i = 1; i < 5; i++)  // Start from index 1, skip current candle [0]
   {
      if(st_direction[i] != EMPTY_VALUE)
      {
         hasValidData = true;
         break;
      }
   }
   
   if(!hasValidData)
   {
      Print("SuperTrend indicator data not ready yet");
      return ST_SIGNAL_NONE;
   }
   
   ENUM_ST_SIGNAL signal = ST_SIGNAL_NONE;
   
   // Check for SELL signal (trend changes from 1 to 0)
   if (st_direction[1] == 0 && st_direction[2] == 1)
   {
      signal = ST_SIGNAL_SELL;
   }
   // Check for BUY signal (trend changes from 0 to 1)
   else if (st_direction[1] == 1 && st_direction[2] == 0)
   {
      signal = ST_SIGNAL_BUY;
   }
   
   return signal;
}

//+------------------------------------------------------------------+
//| Function to get SuperTrend signal without printing              |
//+------------------------------------------------------------------+
ENUM_ST_SIGNAL GetSuperTrendSignalSilent()
{
   if (SuperTrend_Handle == INVALID_HANDLE)
   {
      if (!InitSuperTrend()) return ST_SIGNAL_NONE;
   }
   
   double st_direction[3];
   
   if (CopyBuffer(SuperTrend_Handle, 2, 0, 3, st_direction) < 3)
   {
      return ST_SIGNAL_NONE;
   }
   
   if (st_direction[1] == 0 && st_direction[2] == 1)
      return ST_SIGNAL_SELL;
   else if (st_direction[1] == 1 && st_direction[2] == 0)
      return ST_SIGNAL_BUY;
   
   return ST_SIGNAL_NONE;
}

//+------------------------------------------------------------------+
//| Function to get current SuperTrend trend direction              |
//+------------------------------------------------------------------+
string GetSuperTrendDirection()
{
   if (SuperTrend_Handle == INVALID_HANDLE)
   {
      if (!InitSuperTrend()) return "ERROR";
   }
   
   double st_direction[1];
   
   if (CopyBuffer(SuperTrend_Handle, 2, 0, 1, st_direction) < 1)
   {
      return "ERROR";
   }
   
   if (st_direction[0] == 0)
      return "UPTREND";
   else if (st_direction[0] == 1)
      return "DOWNTREND";
   else
      return "NEUTRAL";
}

//+------------------------------------------------------------------+
//| Cleanup SuperTrend indicator handle                             |
//+------------------------------------------------------------------+
void DeinitSuperTrend()
{
   if (SuperTrend_Handle != INVALID_HANDLE)
   {
      IndicatorRelease(SuperTrend_Handle);
      SuperTrend_Handle = INVALID_HANDLE;
      Print("SuperTrend indicator handle released");
   }
}

//+------------------------------------------------------------------+
//| Get SuperTrend indicator handle for any symbol and timeframe    |
//+------------------------------------------------------------------+
int GetSuperTrendHandle(string symbol, int timeframe)
{
   int handle = iCustom(symbol, (ENUM_TIMEFRAMES)timeframe, "Supertrend",
                        IndicatorName, ATRMultiplier, ATRPeriod, ATRMaxBars, IndicatorShift,
                        EnableNotify, SendAlert, SendApp, SendEmail, TriggerCandle);
   if(handle == INVALID_HANDLE)
   {
      Print("Failed to create SuperTrend indicator handle for ", symbol, " ", EnumToString((ENUM_TIMEFRAMES)timeframe), ". Error: ", GetLastError());
   }
   return handle;
}

//+------------------------------------------------------------------+
//| Get SuperTrend signal (BUY/SELL/NONE) for any symbol/timeframe  |
//+------------------------------------------------------------------+
ENUM_ST_SIGNAL GetSuperTrendSignalForTimeframe(string symbol, int timeframe)
{
   int handle = GetSuperTrendHandle(symbol, timeframe);
   if(handle == INVALID_HANDLE)
      return ST_SIGNAL_NONE;
   double st_direction[3];
   if(CopyBuffer(handle, 2, 0, 3, st_direction) < 3)
   {
      IndicatorRelease(handle);
      return ST_SIGNAL_NONE;
   }
   // Get current values
   double currentValue = st_direction[1];
   ENUM_ST_SIGNAL signal = ST_SIGNAL_NONE;
   if(currentValue == 0)
      signal = ST_SIGNAL_BUY;
   else if(currentValue == 1)
      signal = ST_SIGNAL_SELL;
   IndicatorRelease(handle);
   return signal;
}

//+------------------------------------------------------------------+
//| Get SuperTrend line value for any symbol/timeframe              |
//+------------------------------------------------------------------+
double GetSuperTrendLineValue(string symbol, int timeframe, int shift = 0)
{
   int handle = GetSuperTrendHandle(symbol, timeframe);
   if(handle == INVALID_HANDLE)
      return 0.0;
      
   double st_line[1];
   // Buffer 0 is usually the SuperTrend line value
   if(CopyBuffer(handle, 0, shift, 1, st_line) < 1)
   {
      IndicatorRelease(handle);
      return 0.0;
   }
   
   double lineValue = st_line[0];
   IndicatorRelease(handle);
   return lineValue;
}

//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//|                                           TimeFrameSelection.mqh |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

//--- Input parameters for timeframe selection
input group "=== TIMEFRAME SELECTION ==="
input bool UseTF_M1 = true;        // Use M1 timeframe
input bool UseTF_M2 = true;        // Use M2 timeframe
input bool UseTF_M3 = true;        // Use M3 timeframe
input bool UseTF_M5 = true;         // Use M5 timeframe
input bool UseTF_M10 = true;       // Use M10 timeframe
input bool UseTF_M15 = true;        // Use M15 timeframe
input bool UseTF_M30 = false;       // Use M30 timeframe
input bool UseTF_H1 = false;        // Use H1 timeframe
input bool UseTF_H2 = false;        // Use H2 timeframe
input bool UseTF_H3 = false;        // Use H3 timeframe
input bool UseTF_H4 = false;        // Use H4 timeframe
input bool UseTF_H6 = false;        // Use H6 timeframe
input bool UseTF_H8 = false;        // Use H8 timeframe
input bool UseTF_H12 = false;       // Use H12 timeframe
input bool UseTF_D1 = false;        // Use Daily timeframe
input bool UseTF_W1 = false;        // Use Weekly timeframe
input bool UseTF_MN1 = false;       // Use Monthly timeframe

input group "=== MAJOR TIMEFRAME ==="
input ENUM_TIMEFRAMES MajorTimeframe = PERIOD_M30;  // Major timeframe (must be higher than selected timeframes)

//--- Global variables for timeframe management
ENUM_TIMEFRAMES selectedTimeframes[];
int totalSelectedTimeframes = 0;

//+------------------------------------------------------------------+
//| Get timeframe value for comparison (lower value = shorter timeframe) |
//+------------------------------------------------------------------+
int GetTimeframeValue(ENUM_TIMEFRAMES tf)
{
   switch(tf)
   {
      case PERIOD_M1:   return 1;
      case PERIOD_M2:   return 2;
      case PERIOD_M3:   return 3;
      case PERIOD_M5:   return 5;
      case PERIOD_M10:  return 10;
      case PERIOD_M15:  return 15;
      case PERIOD_M30:  return 30;
      case PERIOD_H1:   return 60;
      case PERIOD_H2:   return 120;
      case PERIOD_H3:   return 180;
      case PERIOD_H4:   return 240;
      case PERIOD_H6:   return 360;
      case PERIOD_H8:   return 480;
      case PERIOD_H12:  return 720;
      case PERIOD_D1:   return 1440;
      case PERIOD_W1:   return 10080;
      case PERIOD_MN1:  return 43200;
      default:          return 0;
   }
}

//+------------------------------------------------------------------+
//| Get timeframe name string                                        |
//+------------------------------------------------------------------+
string GetTimeframeName(ENUM_TIMEFRAMES tf)
{
   switch(tf)
   {
      case PERIOD_M1:   return "M1";
      case PERIOD_M2:   return "M2";
      case PERIOD_M3:   return "M3";
      case PERIOD_M5:   return "M5";
      case PERIOD_M10:  return "M10";
      case PERIOD_M15:  return "M15";
      case PERIOD_M30:  return "M30";
      case PERIOD_H1:   return "H1";
      case PERIOD_H2:   return "H2";
      case PERIOD_H3:   return "H3";
      case PERIOD_H4:   return "H4";
      case PERIOD_H6:   return "H6";
      case PERIOD_H8:   return "H8";
      case PERIOD_H12:  return "H12";
      case PERIOD_D1:   return "D1";
      case PERIOD_W1:   return "W1";
      case PERIOD_MN1:  return "MN1";
      default:          return "Unknown";
   }
}

//+------------------------------------------------------------------+
//| Collect selected timeframes and validate against major timeframe |
//+------------------------------------------------------------------+
bool CollectAndValidateTimeframes()
{
   // Clear previous selections
   ArrayFree(selectedTimeframes);
   totalSelectedTimeframes = 0;
   
   // Collect all selected timeframes
   if(UseTF_M1)   { ArrayResize(selectedTimeframes, ++totalSelectedTimeframes); selectedTimeframes[totalSelectedTimeframes-1] = PERIOD_M1; }
   if(UseTF_M2)   { ArrayResize(selectedTimeframes, ++totalSelectedTimeframes); selectedTimeframes[totalSelectedTimeframes-1] = PERIOD_M2; }
   if(UseTF_M3)   { ArrayResize(selectedTimeframes, ++totalSelectedTimeframes); selectedTimeframes[totalSelectedTimeframes-1] = PERIOD_M3; }
   if(UseTF_M5)   { ArrayResize(selectedTimeframes, ++totalSelectedTimeframes); selectedTimeframes[totalSelectedTimeframes-1] = PERIOD_M5; }
   if(UseTF_M10)  { ArrayResize(selectedTimeframes, ++totalSelectedTimeframes); selectedTimeframes[totalSelectedTimeframes-1] = PERIOD_M10; }
   if(UseTF_M15)  { ArrayResize(selectedTimeframes, ++totalSelectedTimeframes); selectedTimeframes[totalSelectedTimeframes-1] = PERIOD_M15; }
   if(UseTF_M30)  { ArrayResize(selectedTimeframes, ++totalSelectedTimeframes); selectedTimeframes[totalSelectedTimeframes-1] = PERIOD_M30; }
   if(UseTF_H1)   { ArrayResize(selectedTimeframes, ++totalSelectedTimeframes); selectedTimeframes[totalSelectedTimeframes-1] = PERIOD_H1; }
   if(UseTF_H2)   { ArrayResize(selectedTimeframes, ++totalSelectedTimeframes); selectedTimeframes[totalSelectedTimeframes-1] = PERIOD_H2; }
   if(UseTF_H3)   { ArrayResize(selectedTimeframes, ++totalSelectedTimeframes); selectedTimeframes[totalSelectedTimeframes-1] = PERIOD_H3; }
   if(UseTF_H4)   { ArrayResize(selectedTimeframes, ++totalSelectedTimeframes); selectedTimeframes[totalSelectedTimeframes-1] = PERIOD_H4; }
   if(UseTF_H6)   { ArrayResize(selectedTimeframes, ++totalSelectedTimeframes); selectedTimeframes[totalSelectedTimeframes-1] = PERIOD_H6; }
   if(UseTF_H8)   { ArrayResize(selectedTimeframes, ++totalSelectedTimeframes); selectedTimeframes[totalSelectedTimeframes-1] = PERIOD_H8; }
   if(UseTF_H12)  { ArrayResize(selectedTimeframes, ++totalSelectedTimeframes); selectedTimeframes[totalSelectedTimeframes-1] = PERIOD_H12; }
   if(UseTF_D1)   { ArrayResize(selectedTimeframes, ++totalSelectedTimeframes); selectedTimeframes[totalSelectedTimeframes-1] = PERIOD_D1; }
   if(UseTF_W1)   { ArrayResize(selectedTimeframes, ++totalSelectedTimeframes); selectedTimeframes[totalSelectedTimeframes-1] = PERIOD_W1; }
   if(UseTF_MN1)  { ArrayResize(selectedTimeframes, ++totalSelectedTimeframes); selectedTimeframes[totalSelectedTimeframes-1] = PERIOD_MN1; }
   
   // Check if at least one timeframe is selected
   if(totalSelectedTimeframes == 0)
   {
      Print("ERROR: No timeframes selected for trading. Please select at least one timeframe.");
      Alert("ERROR: No timeframes selected for trading. Please select at least one timeframe.");
      return false;
   }
   
   // Validate that major timeframe is greater than all selected timeframes
   int majorTfValue = GetTimeframeValue(MajorTimeframe);
   string invalidTimeframes = "";
   bool hasInvalidTimeframes = false;
   
   for(int i = 0; i < totalSelectedTimeframes; i++)
   {
      int selectedTfValue = GetTimeframeValue(selectedTimeframes[i]);
      if(majorTfValue <= selectedTfValue)
      {
         if(hasInvalidTimeframes) invalidTimeframes += ", ";
         invalidTimeframes += GetTimeframeName(selectedTimeframes[i]);
         hasInvalidTimeframes = true;
      }
   }
   
   if(hasInvalidTimeframes)
   {
      string errorMsg = StringFormat("ERROR: Major timeframe (%s) must be greater than all selected trading timeframes. Invalid timeframes: %s", 
                                   GetTimeframeName(MajorTimeframe), invalidTimeframes);
      Print(errorMsg);
      Alert(errorMsg);
      return false;
   }
   
   // Print successful validation
   string selectedTfList = "";
   for(int i = 0; i < totalSelectedTimeframes; i++)
   {
      if(i > 0) selectedTfList += ", ";
      selectedTfList += GetTimeframeName(selectedTimeframes[i]);
   }
   
   Print("Timeframe validation successful!");
   Print("Selected trading timeframes: ", selectedTfList);
   Print("Major timeframe: ", GetTimeframeName(MajorTimeframe));
   
   return true;
}

//+------------------------------------------------------------------+
//| Get array of selected timeframes                                |
//+------------------------------------------------------------------+
void GetSelectedTimeframes(ENUM_TIMEFRAMES &timeframes[])
{
   ArrayResize(timeframes, totalSelectedTimeframes);
   for(int i = 0; i < totalSelectedTimeframes; i++)
   {
      timeframes[i] = selectedTimeframes[i];
   }
}

//+------------------------------------------------------------------+
//| Get total count of selected timeframes                          |
//+------------------------------------------------------------------+
int GetSelectedTimeframesCount()
{
   return totalSelectedTimeframes;
}

//+------------------------------------------------------------------+
//| Get major timeframe                                             |
//+------------------------------------------------------------------+
ENUM_TIMEFRAMES GetMajorTimeframe()
{
   return MajorTimeframe;
}

//+------------------------------------------------------------------+
//| Check if a specific timeframe is selected                       |
//+------------------------------------------------------------------+
bool IsTimeframeSelected(ENUM_TIMEFRAMES tf)
{
   for(int i = 0; i < totalSelectedTimeframes; i++)
   {
      if(selectedTimeframes[i] == tf)
         return true;
   }
   return false;
}

