//+------------------------------------------------------------------+
//|                                                       HA-EMA.mq5 |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "1.00"

#include <Trade\Trade.mqh>

// Input parameters
input double   InpLotSize       = 0.01;     // Lot size
input double   InpStopLoss      = 10.0;    // Stop Loss in money (account currency) - set to 0 to use signal changes only
input double   InpTakeProfit    = 30.0;    // Take Profit in money (account currency) - set to 0 to use signal changes only
input int      InpEMAPeriod     = 200;      // EMA period
input int      InpMagicNumber   = 123456;   // Magic number

// Lot size control
input bool     InpUseDoubleLots = true;     // Use double lot size when EMA confirms trend

// Trading filter options
input bool     InpOnlyTradeWithTrend = true; // Only trade in the direction of the EMA trend

// Trading session parameters
input bool     InpUseSessionTime = true;    // Restrict trading to specific hours
input string   InpSessionStart = "15:00";   // Session start time (HH:MM) - Indian time 3:00 PM
input string   InpSessionEnd = "23:59";     // Session end time (HH:MM) - Indian time 11:59 PM
input int      InpTimeZoneOffset = 2;       // India time offset in hours (from chart time)

// Profit target parameters
input bool     InpUseDailyProfitTarget = true;  // Enable daily profit target
input double   InpDailyProfitTarget = 45.0;     // Daily profit target in account currency

// Global variables
int            g_heikenAshiHandle = INVALID_HANDLE;
int            g_emaHandle = INVALID_HANDLE;
CTrade         trade;
bool           g_isHedging = false;
string         g_haIndicatorName = "HA-EMA_Heiken_Ashi";
string         g_emaIndicatorName = "HA-EMA_EMA";

// SL/TP tracking
struct PositionInfo
{
   ulong    ticket;
   double   openPrice;
   double   sl;
   double   tp;
   double   lotSize;
   double   expectedSL;   // Expected SL in account currency
   double   expectedTP;   // Expected TP in account currency
   datetime openTime;
   double   bestDynamicSL; // Stores the best (lowest) SL threshold achieved
};
PositionInfo g_positions[100];  // Store up to 100 positions
int g_positionCount = 0;        // Current number of tracked positions

// Daily profit tracking
datetime       g_lastDayChecked = 0;        // Last day we checked for profit reset
double         g_startBalance = 0;          // Balance at the start of the day
bool           g_dailyTargetReached = false; // Whether we've reached daily target

//+------------------------------------------------------------------+
//| Add Heiken Ashi indicator to the chart                           |
//+------------------------------------------------------------------+
bool AddHeikenAshiToChart()
{
   // Check if indicator with this name already exists
   long chartID = ChartID();
   int window = 0; // Main chart window
   
   // Apply Heiken Ashi indicator to the chart
   int handle = iCustom(_Symbol, PERIOD_CURRENT, "Examples\\Heiken_Ashi");
   if(handle == INVALID_HANDLE)
   {
      Print("Failed to create Heiken Ashi indicator handle: ", GetLastError());
      return false;
   }
      
   if(!ChartIndicatorAdd(chartID, window, handle))
   {
      Print("Failed to add Heiken Ashi to chart, error: ", GetLastError());
      IndicatorRelease(handle);
      return false;
   }
   
   ChartRedraw();
   return true;
}

//+------------------------------------------------------------------+
//| Add EMA indicator to the chart                                   |
//+------------------------------------------------------------------+
bool AddEMAToChart()
{
   // Chart details
   long chartID = ChartID();
   int window = 0; // Main chart window
   
   // Apply EMA indicator to the chart
   int handle = iMA(_Symbol, PERIOD_CURRENT, InpEMAPeriod, 0, MODE_EMA, PRICE_CLOSE);
   if(handle == INVALID_HANDLE)
   {
      Print("Failed to create EMA indicator handle: ", GetLastError());
      return false;
   }
   
   if(!ChartIndicatorAdd(chartID, window, handle))
   {
      Print("Failed to add EMA to chart, error: ", GetLastError());
      IndicatorRelease(handle);
      return false;
   }
   
   ChartRedraw();
   return true;
}

//+------------------------------------------------------------------+
//| Calculate Heiken Ashi color: 0 for blue (bullish), 1 for red (bearish)
//+------------------------------------------------------------------+
int GetHeikenAshiColor(int shift)
{
   double haOpen[1], haClose[1];
   
   if(!CopyBuffer(g_heikenAshiHandle, 0, shift, 1, haOpen) || 
      !CopyBuffer(g_heikenAshiHandle, 3, shift, 1, haClose))
   {
      Print("Failed to copy Heiken Ashi data");
      return -1;
   }
   
   // Return 0 for bullish (blue) candles, 1 for bearish (red)
   return (haOpen[0] < haClose[0]) ? 0 : 1;
}

//+------------------------------------------------------------------+
//| Check if EMA is above or below price
//+------------------------------------------------------------------+
bool IsPriceAboveEMA()
{
   double ema[1];
   double close[1];
   
   if(!CopyBuffer(g_emaHandle, 0, 0, 1, ema) || 
      !CopyClose(_Symbol, PERIOD_CURRENT, 0, 1, close))
   {
      Print("Failed to copy EMA or price data");
      return false;
   }
   
   return close[0] > ema[0];
}

//+------------------------------------------------------------------+
//| Close all open positions on the current symbol                   |
//+------------------------------------------------------------------+
void CloseAllPositions()
{
   int total = PositionsTotal();
   int closed = 0;
   double totalProfit = 0.0;
   
   Print("Checking ", total, " total positions for closing");
   
   for(int i = total - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket <= 0)
      {
         Print("Error getting position ticket: ", GetLastError());
         continue;
      }
         
      string symbol = PositionGetString(POSITION_SYMBOL);
      if(symbol != _Symbol)
      {
         Print("Skipping position on symbol: ", symbol);
         continue;
      }
      
      long magic = PositionGetInteger(POSITION_MAGIC);
      // Close only positions with our Magic Number
      if(magic != InpMagicNumber)
      {
         Print("Skipping position with different magic number: ", magic);
         continue;
      }
      
      // Get position profit before closing
      double posProfit = PositionGetDouble(POSITION_PROFIT);
      double entryPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double currentPrice = PositionGetDouble(POSITION_PRICE_CURRENT);
      double lots = PositionGetDouble(POSITION_VOLUME);
      
      // Find this position in our tracking array
      int posIndex = -1;
      for(int j = 0; j < g_positionCount; j++)
      {
         if(g_positions[j].ticket == ticket)
         {
            posIndex = j;
            break;
         }
      }
      
      if(posIndex >= 0)
      {
         // Calculate points moved
         double priceDiff = MathAbs(currentPrice - entryPrice);
         double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
         double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
         double pointValue = (tickValue / tickSize) * lots;
         double moneyMoved = priceDiff * pointValue / _Point;
         
         Print("Position #", ticket, " closing with profit: $", DoubleToString(posProfit, 2),
               " (Expected SL: $", DoubleToString(g_positions[posIndex].expectedSL, 2),
               ", Expected TP: $", DoubleToString(g_positions[posIndex].expectedTP, 2),
               ", Money equivalent of price move: $", DoubleToString(moneyMoved, 2), ")");
      }
      else
      {
         Print("Closing position #", ticket, " (Current profit: ", DoubleToString(posProfit, 2), ")");
      }
      
      bool result = trade.PositionClose(ticket);
      
      if(result)
      {
         Print("Position #", ticket, " closed successfully");
         totalProfit += posProfit;
         closed++;
         
         // Remove from tracking array if found
         if(posIndex >= 0)
         {
            for(int j = posIndex; j < g_positionCount - 1; j++)
            {
               g_positions[j] = g_positions[j + 1];
            }
            g_positionCount--;
         }
      }
      else
         Print("Failed to close position #", ticket, ", error: ", trade.ResultRetcode(), " (", trade.ResultRetcodeDescription(), ")");
      
      // Give the system a moment to process the close request
      Sleep(100);
   }
   
   // Log daily PNL after closing positions
   if(closed > 0)
   {
      double currentBalance = AccountInfoDouble(ACCOUNT_BALANCE);
      double dailyProfit = currentBalance - g_startBalance;
      
      Print("Closed ", closed, " positions with total profit: ", DoubleToString(totalProfit, 2));
      Print("Daily PNL status: ", DoubleToString(dailyProfit, 2), " / ", DoubleToString(InpDailyProfitTarget, 2), 
            " (", DoubleToString(dailyProfit / InpDailyProfitTarget * 100, 1), "% of daily target)");
   }
   else
   {
      Print("No positions closed");
   }
}


//+------------------------------------------------------------------+
//| Check for trade signals
//+------------------------------------------------------------------+
void CheckForSignals()
{
   // Get current and previous Heiken Ashi candle colors
   int currentColor = GetHeikenAshiColor(1); // Last closed candle
   int prevColor = GetHeikenAshiColor(2);    // Previous candle
   
   if(currentColor == -1 || prevColor == -1)
   {
      Print("Error: Could not get Heiken Ashi colors");
      return;
   }
      
   // Check if color change occurred
   if(currentColor == prevColor)
      return;  // No color change, no action
   
   Print("Color change detected: ", prevColor == 0 ? "Blue" : "Red", " -> ", currentColor == 0 ? "Blue" : "Red");
   
   // Get current price and other symbol info
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double spread = ask - bid;
   bool isPriceAboveEMA = IsPriceAboveEMA();
   
   // Check for excessive spread
   if(spread > 20 * _Point) {
      Print("WARNING: Large spread detected: ", DoubleToString(spread/_Point, 1), " points. Trading may be risky.");
   }
   
   // Log the EMA position relative to price
   Print("Price is ", isPriceAboveEMA ? "ABOVE" : "BELOW", " EMA");
   
   // Close any existing positions first (flip positions)
   Print("Closing any existing positions before opening new ones");
   CloseAllPositions();
   
   // Add small delay to ensure orders are processed
   Sleep(100);
   
   // Determine lot size based on conditions
   double lotSize = InpLotSize;
   
   // Blue → Red transition (Sell signal)
   if(prevColor == 0 && currentColor == 1)
   {
      // Check if we should only trade with the trend
      if(InpOnlyTradeWithTrend && isPriceAboveEMA)
      {
         Print("Blue → Red but price ABOVE EMA: Skipping sell signal (trading with trend only)");
         return;
      }
      
      // If EMA is below price (EMA below 200), use double lot size (if enabled)
      if(!isPriceAboveEMA && InpUseDoubleLots)
      {
         lotSize *= 2.0;
         Print("Blue → Red & EMA below price: Using DOUBLE lot size ", lotSize);
      }
      else
      {
         Print("Blue → Red & EMA ", isPriceAboveEMA ? "above" : "below", " price: Using NORMAL lot size ", lotSize, 
               (!isPriceAboveEMA && !InpUseDoubleLots) ? " (Double lots disabled)" : "");
      }
      
      // No longer calculating chart SL/TP, we'll use PNL tracking
      // But we'll keep the money-to-points calculation logic for logging purposes
      double pointsSL = 0, pointsTP = 0;
      
      if(InpStopLoss > 0)
      {
         double moneyPerPoint = tickValue / tickSize;
         pointsSL = (moneyPerPoint > 0 && lotSize > 0) ? InpStopLoss / (moneyPerPoint * lotSize) : 0;
         
         // Log the equivalent point distance for reference
         Print("Sell order SL in points: ", DoubleToString(pointsSL, 1), 
               " (equivalent to $", DoubleToString(InpStopLoss, 2), " for lot size ", DoubleToString(lotSize, 2), ")");
      }
      
      if(InpTakeProfit > 0)
      {
         double moneyPerPoint = tickValue / tickSize;
         pointsTP = (moneyPerPoint > 0 && lotSize > 0) ? InpTakeProfit / (moneyPerPoint * lotSize) : 0;
         
         // Log the equivalent point distance for reference
         Print("Sell order TP in points: ", DoubleToString(pointsTP, 1), 
               " (equivalent to $", DoubleToString(InpTakeProfit, 2), " for lot size ", DoubleToString(lotSize, 2), ")");
      }
      
      if(InpStopLoss <= 0 && InpTakeProfit <= 0)
         Print("Sell signal - No SL/TP set. Position will be closed on next signal change or by PNL tracking.");
      else
         Print("Sell signal - Expected SL: $", DoubleToString(InpStopLoss, 2), 
               ", Expected TP: $", DoubleToString(InpTakeProfit, 2), 
               " (PNL will be tracked automatically)");
      
      // Place order without chart SL/TP, we'll manage via PNL tracking
      bool result = trade.Sell(lotSize, _Symbol, bid, 0, 0, "HA-EMA Sell");
      if(result)
      {
         Print("Sell order placed successfully, ticket #", trade.ResultOrder());
         
         // Track this position for SL/TP monitoring
         if(g_positionCount < ArraySize(g_positions))
         {
            g_positions[g_positionCount].ticket = trade.ResultOrder();
            g_positions[g_positionCount].openPrice = bid;
            g_positions[g_positionCount].sl = 0;  // Not using chart SL/TP
            g_positions[g_positionCount].tp = 0;  // Not using chart SL/TP
            g_positions[g_positionCount].lotSize = lotSize;
            g_positions[g_positionCount].expectedSL = InpStopLoss;
            g_positions[g_positionCount].expectedTP = InpTakeProfit;
            g_positions[g_positionCount].openTime = TimeCurrent();
            // Initialize best SL to original SL, or 0 if SL is disabled
            g_positions[g_positionCount].bestDynamicSL = InpStopLoss;
            g_positionCount++;
            
            Print("Position tracking added: Ticket #", trade.ResultOrder(), 
                  ", Expected SL: $", DoubleToString(InpStopLoss, 2),
                  ", Expected TP: $", DoubleToString(InpTakeProfit, 2),
                  " (PNL will be tracked in OnTick)");
         }
      }
      else
         Print("Failed to place Sell order, error: ", trade.ResultRetcode(), " (", trade.ResultRetcodeDescription(), ")");
   }
   
   // Red → Blue transition (Buy signal)
   else if(prevColor == 1 && currentColor == 0)
   {
      // Check if we should only trade with the trend
      if(InpOnlyTradeWithTrend && !isPriceAboveEMA)
      {
         Print("Red → Blue but price BELOW EMA: Skipping buy signal (trading with trend only)");
         return;
      }
      
      // If EMA is above price (EMA above 200), use double lot size (if enabled)
      if(isPriceAboveEMA && InpUseDoubleLots)
      {
         lotSize *= 2.0;
         Print("Red → Blue & EMA above price: Using DOUBLE lot size ", lotSize);
      }
      else
      {
         Print("Red → Blue & EMA ", isPriceAboveEMA ? "above" : "below", " price: Using NORMAL lot size ", lotSize,
               (isPriceAboveEMA && !InpUseDoubleLots) ? " (Double lots disabled)" : "");
      }
      
      // No longer calculating chart SL/TP, we'll use PNL tracking
      // But we'll keep the money-to-points calculation logic for logging purposes
      double pointsSL = 0, pointsTP = 0;
      
      if(InpStopLoss > 0)
      {
         double moneyPerPoint = tickValue / tickSize;
         pointsSL = (moneyPerPoint > 0 && lotSize > 0) ? InpStopLoss / (moneyPerPoint * lotSize) : 0;
         
         // Log the equivalent point distance for reference
         Print("Buy order SL in points: ", DoubleToString(pointsSL, 1), 
               " (equivalent to $", DoubleToString(InpStopLoss, 2), " for lot size ", DoubleToString(lotSize, 2), ")");
      }
      
      if(InpTakeProfit > 0)
      {
         double moneyPerPoint = tickValue / tickSize;
         pointsTP = (moneyPerPoint > 0 && lotSize > 0) ? InpTakeProfit / (moneyPerPoint * lotSize) : 0;
         
         // Log the equivalent point distance for reference
         Print("Buy order TP in points: ", DoubleToString(pointsTP, 1), 
               " (equivalent to $", DoubleToString(InpTakeProfit, 2), " for lot size ", DoubleToString(lotSize, 2), ")");
      }
      
      if(InpStopLoss <= 0 && InpTakeProfit <= 0)
         Print("Buy signal - No SL/TP set. Position will be closed on next signal change or by PNL tracking.");
      else
         Print("Buy signal - Expected SL: $", DoubleToString(InpStopLoss, 2), 
               ", Expected TP: $", DoubleToString(InpTakeProfit, 2), 
               " (PNL will be tracked automatically)");
      
      // Place order without chart SL/TP, we'll manage via PNL tracking
      bool result = trade.Buy(lotSize, _Symbol, ask, 0, 0, "HA-EMA Buy");
      if(result)
      {
         Print("Buy order placed successfully, ticket #", trade.ResultOrder());
         
         // Track this position for SL/TP monitoring
         if(g_positionCount < ArraySize(g_positions))
         {
            g_positions[g_positionCount].ticket = trade.ResultOrder();
            g_positions[g_positionCount].openPrice = ask;
            g_positions[g_positionCount].sl = 0;  // Not using chart SL/TP
            g_positions[g_positionCount].tp = 0;  // Not using chart SL/TP
            g_positions[g_positionCount].lotSize = lotSize;
            g_positions[g_positionCount].expectedSL = InpStopLoss;
            g_positions[g_positionCount].expectedTP = InpTakeProfit;
            g_positions[g_positionCount].openTime = TimeCurrent();
            // Initialize best SL to original SL, or 0 if SL is disabled
            g_positions[g_positionCount].bestDynamicSL = InpStopLoss;
            g_positionCount++;
            
            Print("Position tracking added: Ticket #", trade.ResultOrder(), 
                  ", Expected SL: $", DoubleToString(InpStopLoss, 2),
                  ", Expected TP: $", DoubleToString(InpTakeProfit, 2),
                  " (PNL will be tracked in OnTick)");
         }
      }
      else
         Print("Failed to place Buy order, error: ", trade.ResultRetcode(), " (", trade.ResultRetcodeDescription(), ")");
   }
}

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   // Initialize trade operations
   g_isHedging = ((ENUM_ACCOUNT_MARGIN_MODE)AccountInfoInteger(ACCOUNT_MARGIN_MODE) == ACCOUNT_MARGIN_MODE_RETAIL_HEDGING);
   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetMarginMode();
   trade.SetTypeFillingBySymbol(_Symbol);
   
   // Initialize daily profit tracking
   g_startBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   g_lastDayChecked = 0; // Force check and reset on first tick
   g_dailyTargetReached = false;
   
   // Print important symbol information
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double contractSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_CONTRACT_SIZE);
   
   Print("Symbol Information for ", _Symbol, ":");
   Print("  Point Size: ", DoubleToString(point, _Digits));
   Print("  Tick Size: ", DoubleToString(tickSize, _Digits));
   Print("  Tick Value: ", DoubleToString(tickValue, 6), " ", AccountInfoString(ACCOUNT_CURRENCY));
   Print("  Contract Size: ", DoubleToString(contractSize, 2));
   Print("  Money-based SL/TP: EA will monitor PNL instead of using chart SL/TP");
   
   if(InpUseDailyProfitTarget)
   {
      Print("Daily profit target enabled: $", DoubleToString(InpDailyProfitTarget, 2), 
            " starting from $", DoubleToString(g_startBalance, 2));
   }
   
   Print("Lot size control: ", InpUseDoubleLots ? "Using DOUBLE lot size when EMA confirms trend" : "Using FIXED lot size regardless of EMA position");
   
   // Check if we're starting on a weekend
   if(IsWeekend())
   {
      Print("WARNING: EA started on a weekend. Trading will be disabled until Monday.");
   }
   
   // Validate session time inputs
   if(InpUseSessionTime)
   {
      int startSecs = TimeStringToSeconds(InpSessionStart);
      int endSecs = TimeStringToSeconds(InpSessionEnd);
      
      if(startSecs == -1 || endSecs == -1)
      {
         Print("ERROR: Invalid session time format. Please use HH:MM format (e.g. 15:00).");
         return INIT_PARAMETERS_INCORRECT;
      }
      
      // Get and display server and India time
      datetime serverTime = TimeCurrent();
      datetime indiaTime = GetAdjustedTime();
      MqlDateTime serverDT, indiaDT;
      TimeToStruct(serverTime, serverDT);
      TimeToStruct(indiaTime, indiaDT);
      
      string serverTimeStr = StringFormat("%04d.%02d.%02d %02d:%02d:%02d", 
                                        serverDT.year, serverDT.mon, serverDT.day, 
                                        serverDT.hour, serverDT.min, serverDT.sec);
                                        
      string indiaTimeStr = StringFormat("%04d.%02d.%02d %02d:%02d:%02d", 
                                      indiaDT.year, indiaDT.mon, indiaDT.day, 
                                      indiaDT.hour, indiaDT.min, indiaDT.sec);
      
      Print("Current Server Time: ", serverTimeStr);
      Print("Current India Time:  ", indiaTimeStr, " (Offset: ", InpTimeZoneOffset, " hours)");
      Print("Trading Session: ", InpSessionStart, " to ", InpSessionEnd, " (Indian trading hours)");
      
      // Check if we're starting outside of session hours
      if(!IsWithinSession())
      {
         Print("WARNING: EA started outside of trading hours. Trading will be disabled until session start.");
      }
   }
   else
   {
      Print("Trading Session: No time restrictions");
   }
   
   // Print important information about SL/TP behavior
   if(InpStopLoss <= 0 && InpTakeProfit <= 0)
      Print("WARNING: Both StopLoss and TakeProfit are set to 0. Positions will ONLY close when a signal change occurs.");
   else if(InpStopLoss <= 0)
      Print("WARNING: StopLoss is set to 0. Positions will close on TakeProfit or signal change.");
   else if(InpTakeProfit <= 0) 
      Print("WARNING: TakeProfit is set to 0. Positions will close on StopLoss or signal change.");
   
   // Initialize Heiken Ashi indicator
   g_heikenAshiHandle = iCustom(_Symbol, PERIOD_CURRENT, "Examples\\Heiken_Ashi");
   if(g_heikenAshiHandle == INVALID_HANDLE)
   {
      Print("Failed to create Heiken Ashi indicator");
      return INIT_FAILED;
   }
   
   // Initialize EMA indicator
   g_emaHandle = iMA(_Symbol, PERIOD_CURRENT, InpEMAPeriod, 0, MODE_EMA, PRICE_CLOSE);
   if(g_emaHandle == INVALID_HANDLE)
   {
      Print("Failed to create EMA indicator");
      return INIT_FAILED;
   }
   
   // Apply Heiken Ashi indicator to the chart
   if(!AddHeikenAshiToChart())
   {
      Print("Warning: Could not apply Heiken Ashi indicator to chart automatically");
   }
   
   // Apply EMA indicator to the chart
   if(!AddEMAToChart())
   {
      Print("Warning: Could not apply EMA indicator to chart automatically");
   }
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   // Release indicator handles used by EA
   if(g_heikenAshiHandle != INVALID_HANDLE)
      IndicatorRelease(g_heikenAshiHandle);
      
   if(g_emaHandle != INVALID_HANDLE)
      IndicatorRelease(g_emaHandle);
      
   // Remove indicators from chart if this was due to removal of the EA or program close
   if(reason == REASON_REMOVE || reason == REASON_CLOSE || reason == REASON_PROGRAM)
   {
      // Get chart ID
      long chartID = ChartID();
      
      // Get indicators list
      int total = ChartIndicatorsTotal(chartID, 0);
      
      for(int i = total - 1; i >= 0; i--)
      {
         // Get indicator name
         string indName = ChartIndicatorName(chartID, 0, i);
         
         // If it's a Heiken Ashi or EMA indicator added by this EA, remove it
         if(StringFind(indName, "Heiken_Ashi") >= 0 || 
            StringFind(indName, "Moving Average") >= 0)
         {
            ChartIndicatorDelete(chartID, 0, indName);
            Print("Removed indicator: ", indName);
         }
      }
      
      ChartRedraw();
   }
}

//+------------------------------------------------------------------+
//| Check if today is a weekend (Saturday or Sunday)                 |
//+------------------------------------------------------------------+
bool IsWeekend()
{
   MqlDateTime dt;
   TimeCurrent(dt);
   
   // 0 = Sunday, 6 = Saturday
   return (dt.day_of_week == 0 || dt.day_of_week == 6);
}

//+------------------------------------------------------------------+
//| Check if we just entered the weekend                             |
//+------------------------------------------------------------------+
bool JustEnteredWeekend()
{
   static datetime lastCheckTime = 0;
   static bool lastIsWeekend = false;
   
   datetime currentTime = TimeCurrent();
   bool currentIsWeekend = IsWeekend();
   
   // If this is our first check, just store the current values
   if(lastCheckTime == 0)
   {
      lastCheckTime = currentTime;
      lastIsWeekend = currentIsWeekend;
      return false;
   }
   
   // If we're now in the weekend and we weren't before
   bool result = (currentIsWeekend && !lastIsWeekend);
   
   // Update the last check values
   lastCheckTime = currentTime;
   lastIsWeekend = currentIsWeekend;
   
   return result;
}

//+------------------------------------------------------------------+
//| Convert string time (HH:MM) to seconds from midnight             |
//+------------------------------------------------------------------+
int TimeStringToSeconds(string timeStr)
{
   string parts[];
   if(StringSplit(timeStr, ':', parts) != 2)
      return -1;
      
   int hours = (int)StringToInteger(parts[0]);
   int minutes = (int)StringToInteger(parts[1]);
   
   if(hours < 0 || hours > 23 || minutes < 0 || minutes > 59)
      return -1;
      
   return hours * 3600 + minutes * 60;
}

//+------------------------------------------------------------------+
//| Get current time adjusted for Indian timezone                    |
//+------------------------------------------------------------------+
datetime GetAdjustedTime()
{
   datetime serverTime = TimeCurrent();
   
   // Add the timezone offset (in seconds)
   return serverTime + InpTimeZoneOffset * 3600;
}

//+------------------------------------------------------------------+
//| Convert datetime to time string in HH:MM format                  |
//+------------------------------------------------------------------+
string TimeToHHMM(datetime dt)
{
   MqlDateTime mdt;
   TimeToStruct(dt, mdt);
   
   string hh = (mdt.hour < 10) ? "0" + IntegerToString(mdt.hour) : IntegerToString(mdt.hour);
   string mm = (mdt.min < 10) ? "0" + IntegerToString(mdt.min) : IntegerToString(mdt.min);
   
   return hh + ":" + mm;
}

//+------------------------------------------------------------------+
//| Check if current time is within trading session                  |
//+------------------------------------------------------------------+
bool IsWithinSession()
{
   if(!InpUseSessionTime)
      return true;  // Session restriction disabled
      
   // Convert session times to seconds
   int sessionStartSecs = TimeStringToSeconds(InpSessionStart);
   int sessionEndSecs = TimeStringToSeconds(InpSessionEnd);
   
   if(sessionStartSecs == -1 || sessionEndSecs == -1)
   {
      Print("ERROR: Invalid session time format. Use HH:MM format.");
      return false;
   }
   
   // Get current time adjusted for India timezone
   MqlDateTime now;
   TimeToStruct(GetAdjustedTime(), now);
   int currentTimeSecs = now.hour * 3600 + now.min * 60 + now.sec;
   
   // Check if current time is within session
   bool isInSession;
   
   // Handle both normal and overnight sessions
   if(sessionStartSecs <= sessionEndSecs)
   {
      // Normal session (e.g., 9:00 to 17:00)
      isInSession = (currentTimeSecs >= sessionStartSecs && currentTimeSecs <= sessionEndSecs);
   }
   else
   {
      // Overnight session (e.g., 22:00 to 08:00)
      isInSession = (currentTimeSecs >= sessionStartSecs || currentTimeSecs <= sessionEndSecs);
   }
   
   return isInSession;
}

//+------------------------------------------------------------------+
//| Check if we just exited the trading session                      |
//+------------------------------------------------------------------+
bool JustExitedSession()
{
   static datetime lastCheckTime = 0;
   static bool lastInSession = false;
   
   datetime currentTime = TimeCurrent();
   bool currentInSession = IsWithinSession();
   
   // If this is our first check, just store the current values
   if(lastCheckTime == 0)
   {
      lastCheckTime = currentTime;
      lastInSession = currentInSession;
      return false;
   }
   
   // If we were in session before but now we're not
   bool result = (lastInSession && !currentInSession);
   
   // Update the last check values
   lastCheckTime = currentTime;
   lastInSession = currentInSession;
   
   return result;
}

//+------------------------------------------------------------------+
//| Reset daily profit tracking at the start of a new day            |
//+------------------------------------------------------------------+
void CheckAndResetDailyProfit()
{
   // Get the current day
   MqlDateTime dt;
   TimeCurrent(dt);
   
   // Create a datetime for the current day at 00:00:00
   MqlDateTime startOfDay;
   startOfDay.year = dt.year;
   startOfDay.mon = dt.mon;
   startOfDay.day = dt.day;
   startOfDay.hour = 0;
   startOfDay.min = 0;
   startOfDay.sec = 0;
   
   datetime todayStart = StructToTime(startOfDay);
   
   // If this is a new day, reset the profit tracking
   if(g_lastDayChecked < todayStart)
   {
      // If we have previous day data, report final results
      if(g_lastDayChecked > 0)
      {
         double previousBalance = AccountInfoDouble(ACCOUNT_BALANCE);
         double prevDayProfit = previousBalance - g_startBalance;
         Print("DAILY SUMMARY: Previous day's final P&L: ", DoubleToString(prevDayProfit, 2), 
               " (Target was: ", DoubleToString(InpDailyProfitTarget, 2), ")");
      }
      
      g_startBalance = AccountInfoDouble(ACCOUNT_BALANCE);
      g_dailyTargetReached = false;
      g_lastDayChecked = todayStart;
      
      Print("New day detected. Resetting daily profit tracking. Starting balance: ", DoubleToString(g_startBalance, 2));
   }
}

//+------------------------------------------------------------------+
//| Check if daily profit target has been reached                    |
//+------------------------------------------------------------------+
bool CheckDailyProfitTarget()
{
   if(!InpUseDailyProfitTarget || g_dailyTargetReached)
      return g_dailyTargetReached;
      
   double currentBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   double dailyProfit = currentBalance - g_startBalance;
   
   // Log progress towards daily target every 25%
   static double lastReportedPercentage = 0.0;
   if(InpDailyProfitTarget > 0)
   {
      double currentPercentage = MathFloor(dailyProfit / InpDailyProfitTarget * 100 / 25) * 25;
      
      if(currentPercentage > lastReportedPercentage && currentPercentage < 100)
      {
         Print("Daily profit progress: ", DoubleToString(dailyProfit, 2), " / ", DoubleToString(InpDailyProfitTarget, 2),
               " (", DoubleToString(dailyProfit / InpDailyProfitTarget * 100, 1), "% of daily target)");
         lastReportedPercentage = currentPercentage;
      }
   }
   
   if(dailyProfit >= InpDailyProfitTarget)
   {
      g_dailyTargetReached = true;
      Print("Daily profit target reached! Current profit: $", DoubleToString(dailyProfit, 2), 
            ", Target: $", DoubleToString(InpDailyProfitTarget, 2));
      Print("Trading will be paused for the rest of the day.");
      
      // Close all open positions
      CloseAllPositions();
   }
   
   return g_dailyTargetReached;
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//| Check if any positions were closed (not by this EA)              |
//+------------------------------------------------------------------+
void CheckSLTPTriggers()
{
   if(g_positionCount <= 0) return;
   
   for(int i = g_positionCount - 1; i >= 0; i--)
   {
      // Check if position still exists
      bool found = false;
      for(int j = 0; j < PositionsTotal(); j++)
      {
         if(PositionGetTicket(j) == g_positions[i].ticket)
         {
            found = true;
            break;
         }
      }
      
      // Position no longer exists, it was closed either manually or by another EA
      if(!found)
      {
         // Calculate time open
         datetime closeTime = TimeCurrent();
         int timeOpenSeconds = (int)(closeTime - g_positions[i].openTime);
         
         // Look up history to find the actual closing price and P/L
         HistorySelect(g_positions[i].openTime, closeTime + 60); // Add a small buffer
         
         bool historyFound = false;
         for(int j = 0; j < HistoryDealsTotal(); j++)
         {
            ulong dealTicket = HistoryDealGetTicket(j);
            if(dealTicket > 0 && HistoryDealGetInteger(dealTicket, DEAL_POSITION_ID) == g_positions[i].ticket)
            {
               if(HistoryDealGetInteger(dealTicket, DEAL_ENTRY) == DEAL_ENTRY_OUT)
               {
                  double profit = HistoryDealGetDouble(dealTicket, DEAL_PROFIT);
                  double closePrice = HistoryDealGetDouble(dealTicket, DEAL_PRICE);
                  
                  // Calculate equivalent money move
                  double priceDiff = MathAbs(closePrice - g_positions[i].openPrice);
                  double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
                  double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
                  double moneyValue = (priceDiff / _Point) * (tickValue / tickSize) * g_positions[i].lotSize;
                  
                  Print("Position #", g_positions[i].ticket, " was externally closed",
                        ", Profit: $", DoubleToString(profit, 2),
                        ", Expected SL: $", DoubleToString(g_positions[i].expectedSL, 2),
                        ", Expected TP: $", DoubleToString(g_positions[i].expectedTP, 2),
                        ", Actual move in money: $", DoubleToString(moneyValue, 2),
                        ", Time open: ", timeOpenSeconds, " seconds");
                        
                  historyFound = true;
                  break;
               }
            }
         }
         
         if(!historyFound)
         {
            Print("Position #", g_positions[i].ticket, " was closed but details not found in history");
         }
         
         // Remove this position from tracking array
         for(int j = i; j < g_positionCount - 1; j++)
         {
            g_positions[j] = g_positions[j + 1];
         }
         g_positionCount--;
      }
   }
}

// Function to check positions against their SL/TP in dollar terms
void CheckPositionsPNL()
{
   if(g_positionCount <= 0) return;
   
   for(int i = g_positionCount - 1; i >= 0; i--)
   {
      // Select position by ticket
      if(!PositionSelectByTicket(g_positions[i].ticket))
      {
         // Position may have been closed already
         continue;
      }
      
      // Get position details
      double currentPrice = PositionGetDouble(POSITION_PRICE_CURRENT);
      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double lots = PositionGetDouble(POSITION_VOLUME);
      ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      double profit = PositionGetDouble(POSITION_PROFIT);
      
      // Calculate dynamic SL threshold - tighten as profit increases
      double profitThreshold = 10.0;  // When profit exceeds $10, start improving SL
      double dynamicSLThreshold;
      
      // Only apply dynamic SL if the original SL is greater than 0
      if(g_positions[i].expectedSL > 0)
      {
         // If profit is positive and exceeds the threshold, calculate a potentially tighter SL
         if(profit > profitThreshold)
         {
            // Calculate how much to reduce SL (1:1 ratio with profit increase)
            double slReduction = MathMin(profit - profitThreshold, g_positions[i].expectedSL);
            double currentDynamicSL = g_positions[i].expectedSL - slReduction;
            
            // Never let SL go below 1.0
            if(currentDynamicSL < 1.0) currentDynamicSL = 1.0;
            
            // Only update if this SL is tighter (lower) than the previous best
            if(currentDynamicSL < g_positions[i].bestDynamicSL)
            {
               // Update the position's best dynamic SL
               g_positions[i].bestDynamicSL = currentDynamicSL;
               Print("Tightening SL for position #", g_positions[i].ticket, 
                     " from $", DoubleToString(g_positions[i].bestDynamicSL, 2), 
                     " to $", DoubleToString(currentDynamicSL, 2), 
                     " (profit: $", DoubleToString(profit, 2), ")");
            }
         }
      }
      else
      {
         // If SL is 0, set bestDynamicSL to 0 as well (no SL)
         g_positions[i].bestDynamicSL = 0;
      }
      
      // Always use the best (lowest) SL we've achieved for this position
      dynamicSLThreshold = g_positions[i].bestDynamicSL;
      
      // For debug - log PNL status every 100 ticks for each position
      static int tickCounter = 0;
      if(tickCounter++ % 100 == 0)
      {
         string slInfo = g_positions[i].expectedSL > 0 ? 
            (", Original SL threshold: $" + DoubleToString(-g_positions[i].expectedSL, 2) +
             ", Current Dynamic SL threshold: $" + DoubleToString(-dynamicSLThreshold, 2)) : 
            ", No SL configured";
            
         string tpInfo = g_positions[i].expectedTP > 0 ? 
            (", TP threshold: $" + DoubleToString(g_positions[i].expectedTP, 2)) : 
            ", No TP configured";
            
         string slProtection = (profit > 10.0 && g_positions[i].expectedSL > 0) ? ", SL Protection Active" : "";
            
         Print("Position #", g_positions[i].ticket, " current PNL: $", DoubleToString(profit, 2),
               slInfo, tpInfo, slProtection);
      }
      
      // Check if SL or TP is reached in dollar terms
      bool closePosition = false;
      string reason = "";
      
      // For buy position: profit is positive when price goes up
      if(posType == POSITION_TYPE_BUY)
      {
         // Check for dynamic stop loss (negative profit exceeding adjusted SL), but only if SL is enabled
         if(dynamicSLThreshold > 0 && profit < 0 && MathAbs(profit) >= dynamicSLThreshold)
         {
            closePosition = true;
            reason = "Manual Stop Loss" + (dynamicSLThreshold < g_positions[i].expectedSL ? " (Dynamic)" : "");
         }
         // Check for take profit (positive profit exceeding TP), but only if TP is enabled
         else if(g_positions[i].expectedTP > 0 && profit > 0 && profit >= g_positions[i].expectedTP)
         {
            closePosition = true;
            reason = "Manual Take Profit";
         }
      }
      // For sell position: profit is positive when price goes down
      else
      {
         // Check for dynamic stop loss (negative profit exceeding adjusted SL), but only if SL is enabled
         if(dynamicSLThreshold > 0 && profit < 0 && MathAbs(profit) >= dynamicSLThreshold)
         {
            closePosition = true;
            reason = "Manual Stop Loss" + (dynamicSLThreshold < g_positions[i].expectedSL ? " (Dynamic)" : "");
         }
         // Check for take profit (positive profit exceeding TP), but only if TP is enabled
         else if(g_positions[i].expectedTP > 0 && profit > 0 && profit >= g_positions[i].expectedTP)
         {
            closePosition = true;
            reason = "Manual Take Profit";
         }
      }
      
      // Close position if conditions met
      if(closePosition)
      {
         Print("Closing position #", g_positions[i].ticket, " by ", reason, 
               ". Current profit: $", DoubleToString(profit, 2),
               ", Original SL: $", DoubleToString(g_positions[i].expectedSL, 2), 
               ", Dynamic SL: $", DoubleToString(dynamicSLThreshold, 2),
               ", Expected TP: $", DoubleToString(g_positions[i].expectedTP, 2));
         
         bool result = trade.PositionClose(g_positions[i].ticket);
         
         if(result)
         {
            Print("Successfully closed position #", g_positions[i].ticket);
            
            // Remove from tracking array
            for(int j = i; j < g_positionCount - 1; j++)
            {
               g_positions[j] = g_positions[j + 1];
            }
            g_positionCount--;
         }
         else
         {
            Print("Failed to close position #", g_positions[i].ticket, 
                  ", error: ", trade.ResultRetcode(), " (", trade.ResultRetcodeDescription(), ")");
         }
      }
   }
}

void OnTick()
{
   // Check if any positions were closed by SL/TP
   CheckSLTPTriggers();
   
   // Check if any positions should be closed based on their PNL
   CheckPositionsPNL();
   
   // Check and reset daily profit tracking if needed
   CheckAndResetDailyProfit();
   
   // Check if we just entered the weekend
   if(JustEnteredWeekend())
   {
      Print("Weekend detected! Closing all positions and stopping trading until Monday.");
      CloseAllPositions();
      return; // Skip further processing
   }
   
   // Skip trading on weekends
   if(IsWeekend())
   {
      // Uncomment the next line if you want to see this message periodically
      // if(TimeToString(TimeCurrent(), TIME_MINUTES) == "00:00")
      //    Print("Weekend - no trading until Monday.");
      return;
   }
   
   // Check if daily profit target reached
   if(InpUseDailyProfitTarget && CheckDailyProfitTarget())
   {
      // Print profit status every hour
      static datetime lastProfitCheck = 0;
      datetime currentTime = TimeCurrent();
      
      if(currentTime - lastProfitCheck > 3600)  // 3600 seconds = 1 hour
      {
         lastProfitCheck = currentTime;
         double currentBalance = AccountInfoDouble(ACCOUNT_BALANCE);
         double dailyProfit = currentBalance - g_startBalance;
         Print("Daily profit target reached. Current profit: $", DoubleToString(dailyProfit, 2), 
               ", no more trading today.");
      }
      return; // Skip further processing
   }
   
   // Check if we just exited the trading session
   if(JustExitedSession())
   {
      Print("Trading session ended! Closing all positions until next session.");
      CloseAllPositions();
      return; // Skip further processing
   }
   
   // Skip trading outside of trading hours
   if(InpUseSessionTime && !IsWithinSession())
   {
      // Print time status every hour to help debug timezone issues
      static datetime lastTimeCheck = 0;
      datetime currentTime = TimeCurrent();
      
      // Print message every hour
      if(currentTime - lastTimeCheck > 3600)  // 3600 seconds = 1 hour
      {
         lastTimeCheck = currentTime;
         datetime adjustedTime = GetAdjustedTime();
         
         MqlDateTime serverDT, indiaDT;
         TimeToStruct(currentTime, serverDT);
         TimeToStruct(adjustedTime, indiaDT);
         
         string currentTimeStr = TimeToHHMM(currentTime);
         string adjustedTimeStr = TimeToHHMM(adjustedTime);
         
         Print("Outside trading hours. Server time: ", currentTimeStr, 
               ", India time: ", adjustedTimeStr, 
               ", Session: ", InpSessionStart, " - ", InpSessionEnd);
      }
      return;
   }
   
   // Check for new bar
   static datetime lastBarTime = 0;
   datetime currentBarTime = iTime(_Symbol, PERIOD_CURRENT, 0);
   
   // Only check for signals on a new bar
   if(currentBarTime != lastBarTime)
   {
      lastBarTime = currentBarTime;
      CheckForSignals();
   }
}
//+------------------------------------------------------------------+
