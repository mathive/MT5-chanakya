//+------------------------------------------------------------------+
//|                                                         main.mq5 |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link "https://www.mql5.com"
#property version "1.00"

//--- Include custom header files
#include "support\GetSpread.mqh"
#include "support\SuperTrendSignal.mqh"
#include "support\OrderManagement.mqh"
#include "support\TimeFrameSelection.mqh"
#include "support\SuperTrendLines.mqh"
#include "support\CSVTracker.mqh"
#include <Trade\Trade.mqh>

//--- Input parameters for trading
input group "=== TRADING PARAMETERS ===" input double lotSize = 0.01; // Lot size for trading
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

//--- Input parameters for risk management
input group "=== RISK MANAGEMENT ==="
input bool EnableMaxLossProtection = true;   // Enable maximum loss protection
input double MaxOverallLoss = 100.0;         // Maximum overall loss in USD before closing all positions
input bool EnableMaxProfitProtection = true; // Enable maximum profit protection
input double MaxOverallProfit = 360.0;       // Maximum overall profit in USD before closing all positions (0 = unlimited)

input group "=== SYSTEM SETTINGS ==="
input bool EnableCSVTracking = true;         // Enable CSV state tracking (auto-disabled in tester)
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

         // Check if position is for current symbol and contains timeframe name
         if (positionSymbol == _Symbol && StringFind(positionComment, tfName) >= 0)
         {
            return true;
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

   // STEP 1.5: Check if max loss/profit protection is active
   if (!CanResumeAfterMaxProtection())
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

            if (positionSymbol == _Symbol && StringFind(positionComment, tfNameCheck) >= 0)
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
               
               if (StringFind(orderComment, expectedComment) >= 0)
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
               
               if (StringFind(orderComment, expectedComment) >= 0)
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
   // Skip if protection is active
   if (!CanResumeAfterMaxProtection())
   {
      Print("AUTO-REOPEN: Skipped for ", GetTimeframeName(timeframe), " - Protection active");
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

   // Check max loss and profit protection
   CheckMaxLossProtection();
   CheckMaxProfitProtection();

   // Update SuperTrend lines with optimization (once per minute) - ALWAYS UPDATE VISUALS
   UpdateSuperTrendLinesOptimized();

   // Check if trading can resume after protection was triggered
   if (!CanResumeAfterMaxProtection())
   {
      // Even if protection is active, continue with visual updates and signal detection
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
      
      Print("=== MAX LOSS PROTECTION TRIGGERED ===");
      Print("Total Loss: $", DoubleToString(current_session_loss, 2), " reached. All positions closed.");
      Print("Visual updates (ForceUpdateSuperTrendLines) will continue normally.");
      Print("Trading will resume when major trend changes.");

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
