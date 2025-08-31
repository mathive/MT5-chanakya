//+------------------------------------------------------------------+
//|                                                      HA-EMA.mq5 |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "1.00"

#include <Trade\Trade.mqh>
#include <Arrays\ArrayString.mqh>

// We'll include the display file after all globals are defined

// Input parameters - general
input double   InpLotSize       = 0.02;     // Lot size
input double   InpStopLoss      = 20.0;    // Stop Loss in money (account currency) - set to 0 to use signal changes only
input double   InpTakeProfit    = 60.0;    // Take Profit in money (account currency) - set to 0 to use signal changes only
input int      InpEMAPeriod     = 200;      // EMA period
input int      InpMagicNumber   = 123456;   // Base magic number

// Lot size control
input bool     InpUseDoubleLots = false;     // Use double lot size when EMA confirms trend

// Trading filter options
input bool     InpOnlyTradeWithTrend = true; // Only trade in the direction of the EMA trend

// Trading session parameters
input bool     InpUseSessionTime = false;    // Restrict trading to specific hours
input string   InpSessionStart = "15:00";   // Session start time (HH:MM) - Indian time 3:00 PM
input string   InpSessionEnd = "23:59";     // Session end time (HH:MM) - Indian time 11:59 PM
input int      InpTimeZoneOffset = 0;       // India time offset in hours (from chart time)
input bool     InpDisableWeekendTrading = false; // Disable trading on weekends (Saturday/Sunday)

// Profit target parameters
input bool     InpUseDailyProfitTarget = false;  // Enable daily profit target
input double   InpDailyProfitTarget = 60.0;     // Daily profit target (includes unrealized profit)
input bool     InpUseMonthlyProfitTarget = true; // Enable monthly profit target
input double   InpMonthlyProfitTarget = 300.0;   // Monthly profit target in account currency
input bool     InpUseMaxDrawdown = true;        // Enable maximum drawdown protection
input double   InpMaxDrawdown = 100.0;          // Maximum drawdown from monthly peak (in account currency)

// Display settings
input bool     InpShowInfoPanel = true;        // Show information panel on chart
input int      InpUpdateInterval = 5;          // Update interval in seconds (minimum 1)

// EA will only trade the current chart symbol

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

// Class to handle symbol-specific operations
class CSymbolTrader
{
private:
   string   m_symbol;
   int      m_magicNumber;
   int      m_heikenAshiHandle;
   int      m_emaHandle;
   CTrade   m_trade;
   PositionInfo m_positions[100];  // Store up to 100 positions
   int      m_positionCount;       // Current number of tracked positions
   string   m_haIndicatorName;
   string   m_emaIndicatorName;

public:
   // Constructor
   CSymbolTrader(string symbol, int baseMagicNumber, int index)
   {
      m_symbol = symbol;
      // Create unique magic number for each symbol by adding index
      m_magicNumber = baseMagicNumber + index;
      m_heikenAshiHandle = INVALID_HANDLE;
      m_emaHandle = INVALID_HANDLE;
      m_positionCount = 0;
      m_haIndicatorName = "HA-EMA_Heiken_Ashi_" + m_symbol;
      m_emaIndicatorName = "HA-EMA_EMA_" + m_symbol;
      
      // Initialize trade object
      m_trade.SetExpertMagicNumber(m_magicNumber);
      m_trade.SetMarginMode();
      m_trade.SetTypeFillingBySymbol(m_symbol);
   }
   
   // Destructor
   ~CSymbolTrader()
   {
      ReleaseIndicators();
   }
   
   // Initialize indicators
   bool Initialize()
   {
      // Initialize Heiken Ashi indicator
      m_heikenAshiHandle = iCustom(m_symbol, PERIOD_CURRENT, "Examples\\Heiken_Ashi");
      if(m_heikenAshiHandle == INVALID_HANDLE)
      {
         Print("Failed to create Heiken Ashi indicator for symbol ", m_symbol);
         return false;
      }
      
      // Initialize EMA indicator
      m_emaHandle = iMA(m_symbol, PERIOD_CURRENT, InpEMAPeriod, 0, MODE_EMA, PRICE_CLOSE);
      if(m_emaHandle == INVALID_HANDLE)
      {
         Print("Failed to create EMA indicator for symbol ", m_symbol);
         return false;
      }
      
      // Print symbol info
      double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
      double tickSize = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_SIZE);
      double tickValue = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_VALUE);
      double contractSize = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_CONTRACT_SIZE);
      
      Print("Symbol Information for ", m_symbol, ":");
      Print("  Point Size: ", DoubleToString(point, (int)SymbolInfoInteger(m_symbol, SYMBOL_DIGITS)));
      Print("  Tick Size: ", DoubleToString(tickSize, (int)SymbolInfoInteger(m_symbol, SYMBOL_DIGITS)));
      Print("  Tick Value: ", DoubleToString(tickValue, 6), " ", AccountInfoString(ACCOUNT_CURRENCY));
      Print("  Contract Size: ", DoubleToString(contractSize, 2));
      Print("  Magic Number: ", m_magicNumber);
      
      return true;
   }
   
   // Release indicator handles
   void ReleaseIndicators()
   {
      if(m_heikenAshiHandle != INVALID_HANDLE)
      {
         IndicatorRelease(m_heikenAshiHandle);
         m_heikenAshiHandle = INVALID_HANDLE;
      }
      
      if(m_emaHandle != INVALID_HANDLE)
      {
         IndicatorRelease(m_emaHandle);
         m_emaHandle = INVALID_HANDLE;
      }
   }
   
   // Calculate Heiken Ashi color: 0 for blue (bullish), 1 for red (bearish)
   int GetHeikenAshiColor(int shift)
   {
      double haOpen[1], haClose[1];
      
      if(!CopyBuffer(m_heikenAshiHandle, 0, shift, 1, haOpen) || 
         !CopyBuffer(m_heikenAshiHandle, 3, shift, 1, haClose))
      {
         Print("Failed to copy Heiken Ashi data for ", m_symbol);
         return -1;
      }
      
      // Return 0 for bullish (blue) candles, 1 for bearish (red)
      return (haOpen[0] < haClose[0]) ? 0 : 1;
   }
   
   // Check if price is above EMA
   bool IsPriceAboveEMA()
   {
      double ema[1];
      double close[1];
      
      if(!CopyBuffer(m_emaHandle, 0, 0, 1, ema) || 
         !CopyClose(m_symbol, PERIOD_CURRENT, 0, 1, close))
      {
         Print("Failed to copy EMA or price data for ", m_symbol);
         return false;
      }
      
      return close[0] > ema[0];
   }
   
   // Close all open positions for this symbol
   void CloseAllPositions()
   {
      int total = PositionsTotal();
      int closed = 0;
      double totalProfit = 0.0;
      
      for(int i = total - 1; i >= 0; i--)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket <= 0)
         {
            Print("[", m_symbol, "] Error getting position ticket: ", GetLastError());
            continue;
         }
            
         string symbol = PositionGetString(POSITION_SYMBOL);
         if(symbol != m_symbol)
         {
            // Not our symbol
            continue;
         }
         
         long magic = PositionGetInteger(POSITION_MAGIC);
         // Close only positions with our Magic Number
         if(magic != m_magicNumber)
         {
            // Not our magic number
            continue;
         }
         
         // Get position profit before closing
         double posProfit = PositionGetDouble(POSITION_PROFIT);
         
         // Find this position in our tracking array
         int posIndex = -1;
         for(int j = 0; j < m_positionCount; j++)
         {
            if(m_positions[j].ticket == ticket)
            {
               posIndex = j;
               break;
            }
         }
         
         bool result = m_trade.PositionClose(ticket);
         
         if(result)
         {
            string message = "[" + m_symbol + "] POSITION CLOSED: Ticket #" + IntegerToString(ticket) + 
                           ", Profit: $" + DoubleToString(posProfit, 2);
            Print(message);
            
            totalProfit += posProfit;
            closed++;
            
            // Update consecutive losses tracking
            UpdateConsecutiveLossesCounter(posProfit);
            
            // Remove from tracking array if found
            if(posIndex >= 0)
            {
               for(int j = posIndex; j < m_positionCount - 1; j++)
               {
                  m_positions[j] = m_positions[j + 1];
               }
               m_positionCount--;
            }
         }
         else
            Print("[", m_symbol, "] Failed to close position #", ticket, ", error: ", m_trade.ResultRetcode(), " (", m_trade.ResultRetcodeDescription(), ")");
         
         // Give the system a moment to process the close request
         Sleep(100);
      }
      
      if(closed > 0)
      {
         string message = "[" + m_symbol + "] CLOSED " + IntegerToString(closed) + 
                        " POSITIONS WITH TOTAL PROFIT: $" + DoubleToString(totalProfit, 2);
         Print(message);
         if(MathAbs(totalProfit) > 5.0) // Only alert if profit/loss is significant
         {
            Alert(message);
         }
      }
   }
   
   // Check for trade signals
   void CheckForSignals()
   {
      // Get current and previous Heiken Ashi candle colors
      int currentColor = GetHeikenAshiColor(1); // Last closed candle
      int prevColor = GetHeikenAshiColor(2);    // Previous candle
      
      if(currentColor == -1 || prevColor == -1)
      {
         Print("[", m_symbol, "] Error: Could not get Heiken Ashi colors");
         return;
      }
         
      // Check if color change occurred
      if(currentColor == prevColor)
         return;  // No color change, no action
      
      // Check trend strength using ADX
      bool trendIsStrong = IsTrendStrong();
      if(!trendIsStrong)
      {
         Print("[", m_symbol, "] Signal detected but trend is weak - SKIPPING this trade");
         return; // Don't trade in weak trends at all
      }
      
      // Check for price action confirmation
      bool priceActionConfirmed = CheckPriceActionConfirmation(prevColor == 0 ? POSITION_TYPE_SELL : POSITION_TYPE_BUY);
      if(!priceActionConfirmed)
      {
         Print("[", m_symbol, "] Signal lacks price action confirmation - SKIPPING this trade");
         return; // Skip trades without price action confirmation
      }
      
      // Add RSI confirmation filter
      int rsiHandle = iRSI(m_symbol, PERIOD_CURRENT, 14, PRICE_CLOSE);
      if(rsiHandle == INVALID_HANDLE)
      {
         Print("[", m_symbol, "] Error: Could not create RSI indicator");
         // Continue without RSI filter
      }
      else
      {
         double rsiValues[1];
         if(CopyBuffer(rsiHandle, 0, 0, 1, rsiValues))
         {
            // If we have a sell signal (blue→red) but RSI is oversold (<35), skip the trade
            if(prevColor == 0 && currentColor == 1 && rsiValues[0] < 35)
            {
               Print("[", m_symbol, "] Blue → Red but RSI is oversold (", DoubleToString(rsiValues[0], 1), 
                     ") - SKIPPING this signal");
               IndicatorRelease(rsiHandle);
               return; // Skip this trade completely
            }
            // If we have a buy signal (red→blue) but RSI is overbought (>65), skip the trade
            else if(prevColor == 1 && currentColor == 0 && rsiValues[0] > 65)
            {
               Print("[", m_symbol, "] Red → Blue but RSI is overbought (", DoubleToString(rsiValues[0], 1), 
                     ") - SKIPPING this signal");
               IndicatorRelease(rsiHandle);
               return; // Skip this trade completely
            }
            
            // Add RSI confirmation requirement for buy signals in trending markets
            if(prevColor == 1 && currentColor == 0 && InpOnlyTradeWithTrend)
            {
               // For buy signals, we want RSI to be recovering from oversold
               if(rsiValues[0] < 40 || rsiValues[0] > 70)
               {
                  // Skip unless RSI is in a good zone for buying
                  Print("[", m_symbol, "] Red → Blue but RSI at ", DoubleToString(rsiValues[0], 1), 
                        " is not in optimal buying zone (40-70) - SKIPPING");
                  IndicatorRelease(rsiHandle);
                  return;
               }
            }
            
            // Add RSI confirmation requirement for sell signals in trending markets
            if(prevColor == 0 && currentColor == 1 && InpOnlyTradeWithTrend)
            {
               // For sell signals, we want RSI to be falling from overbought
               if(rsiValues[0] < 30 || rsiValues[0] > 60)
               {
                  // Skip unless RSI is in a good zone for selling
                  Print("[", m_symbol, "] Blue → Red but RSI at ", DoubleToString(rsiValues[0], 1), 
                        " is not in optimal selling zone (30-60) - SKIPPING");
                  IndicatorRelease(rsiHandle);
                  return;
               }
            }
         }
         IndicatorRelease(rsiHandle);
      }
      
      // Get current price and other symbol info
      double ask = SymbolInfoDouble(m_symbol, SYMBOL_ASK);
      double bid = SymbolInfoDouble(m_symbol, SYMBOL_BID);
      double tickSize = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_SIZE);
      double tickValue = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_VALUE);
      double spread = ask - bid;
      bool isPriceAboveEMA = IsPriceAboveEMA();
      double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
      
      // Check for excessive spread
      if(spread > 20 * point) {
         Print("[", m_symbol, "] WARNING: Large spread detected: ", DoubleToString(spread/point, 1), " points. Trading may be risky.");
      }
      
      // Close any existing positions first (flip positions)
      CloseAllPositions();
      
      // Add small delay to ensure orders are processed
      Sleep(100);
      
      // Base lot size adjusted by volatility and risk management
      double baseLotSize = NormalizeLotSize(InpLotSize);
      
      // Apply dynamic lot sizing based on volatility and consecutive losses
      double lotSize = CalculateDynamicLotSize(baseLotSize);
      
      // Blue → Red transition (Sell signal)
      if(prevColor == 0 && currentColor == 1)
      {
         // Check if we should only trade with the trend
         if(InpOnlyTradeWithTrend && isPriceAboveEMA)
         {
            Print("[", m_symbol, "] Blue → Red but price ABOVE EMA: Skipping sell signal (trading with trend only)");
            return;
         }
         
         // If EMA is below price, use double lot size (if enabled)
         if(!isPriceAboveEMA && InpUseDoubleLots)
         {
            double doubleLotSize = NormalizeLotSize(baseLotSize * 2.0);
            lotSize = CalculateDynamicLotSize(doubleLotSize);
            Print("[", m_symbol, "] Blue → Red & EMA below price: Using DOUBLE lot size ", lotSize);
         }
         else
         {
            Print("[", m_symbol, "] Blue → Red & EMA ", isPriceAboveEMA ? "above" : "below", " price: Using NORMAL lot size ", lotSize, 
                  (!isPriceAboveEMA && !InpUseDoubleLots) ? " (Double lots disabled)" : "");
         }
         
         double pointsSL = 0, pointsTP = 0;
         
         if(InpStopLoss > 0)
         {
            double moneyPerPoint = tickValue / tickSize;
            pointsSL = (moneyPerPoint > 0 && lotSize > 0) ? InpStopLoss / (moneyPerPoint * lotSize) : 0;
            
            // Log the equivalent point distance for reference
            Print("[", m_symbol, "] Sell order SL in points: ", DoubleToString(pointsSL, 1), 
                  " (equivalent to $", DoubleToString(InpStopLoss, 2), " for lot size ", DoubleToString(lotSize, 2), ")");
         }
         
         if(InpTakeProfit > 0)
         {
            double moneyPerPoint = tickValue / tickSize;
            pointsTP = (moneyPerPoint > 0 && lotSize > 0) ? InpTakeProfit / (moneyPerPoint * lotSize) : 0;
            
            // Log the equivalent point distance for reference
            Print("[", m_symbol, "] Sell order TP in points: ", DoubleToString(pointsTP, 1), 
                  " (equivalent to $", DoubleToString(InpTakeProfit, 2), " for lot size ", DoubleToString(lotSize, 2), ")");
         }
         
         if(InpStopLoss <= 0 && InpTakeProfit <= 0)
            Print("[", m_symbol, "] Sell signal - No SL/TP set. Position will be closed on next signal change or by PNL tracking.");
         else
            Print("[", m_symbol, "] Sell signal - Expected SL: $", DoubleToString(InpStopLoss, 2), 
                  ", Expected TP: $", DoubleToString(InpTakeProfit, 2), 
                  " (PNL will be tracked automatically)");
         
         // Place order without chart SL/TP, we'll manage via PNL tracking
         bool result = m_trade.Sell(lotSize, m_symbol, bid, 0, 0, "HA-EMA Sell");
         if(result)
         {
            string message = "[" + m_symbol + "] SELL ORDER OPENED: Ticket #" + IntegerToString(m_trade.ResultOrder()) + 
                           ", Lot Size: " + DoubleToString(lotSize, 2) + 
                           ", SL: $" + DoubleToString(InpStopLoss, 2) + 
                           ", TP: $" + DoubleToString(InpTakeProfit, 2);
            
            Print(message);
            Alert(message);
            
            // Track this position for SL/TP monitoring
            if(m_positionCount < ArraySize(m_positions))
            {
               m_positions[m_positionCount].ticket = m_trade.ResultOrder();
               m_positions[m_positionCount].openPrice = bid;
               m_positions[m_positionCount].sl = 0;  // Not using chart SL/TP
               m_positions[m_positionCount].tp = 0;  // Not using chart SL/TP
               m_positions[m_positionCount].lotSize = lotSize;
               m_positions[m_positionCount].expectedSL = InpStopLoss;
               m_positions[m_positionCount].expectedTP = InpTakeProfit;
               m_positions[m_positionCount].openTime = TimeCurrent();
               // Initialize best SL to original SL, or 0 if SL is disabled
               m_positions[m_positionCount].bestDynamicSL = InpStopLoss;
               m_positionCount++;
            }
         }
         else
            Print("[", m_symbol, "] Failed to place Sell order, error: ", m_trade.ResultRetcode(), " (", m_trade.ResultRetcodeDescription(), ")");
      }
      
      // Red → Blue transition (Buy signal)
      else if(prevColor == 1 && currentColor == 0)
      {
         // Check if we should only trade with the trend
         if(InpOnlyTradeWithTrend && !isPriceAboveEMA)
         {
            Print("[", m_symbol, "] Red → Blue but price BELOW EMA: Skipping buy signal (trading with trend only)");
            return;
         }
         
         // If EMA is above price, use double lot size (if enabled)
         if(isPriceAboveEMA && InpUseDoubleLots)
         {
            double doubleLotSize = NormalizeLotSize(baseLotSize * 2.0);
            lotSize = CalculateDynamicLotSize(doubleLotSize);
            Print("[", m_symbol, "] Red → Blue & EMA above price: Using DOUBLE lot size ", lotSize);
         }
         else
         {
            Print("[", m_symbol, "] Red → Blue & EMA ", isPriceAboveEMA ? "above" : "below", " price: Using NORMAL lot size ", lotSize,
                  (isPriceAboveEMA && !InpUseDoubleLots) ? " (Double lots disabled)" : "");
         }
         
         double pointsSL = 0, pointsTP = 0;
         
         if(InpStopLoss > 0)
         {
            double moneyPerPoint = tickValue / tickSize;
            pointsSL = (moneyPerPoint > 0 && lotSize > 0) ? InpStopLoss / (moneyPerPoint * lotSize) : 0;
            
            // Log the equivalent point distance for reference
            Print("[", m_symbol, "] Buy order SL in points: ", DoubleToString(pointsSL, 1), 
                  " (equivalent to $", DoubleToString(InpStopLoss, 2), " for lot size ", DoubleToString(lotSize, 2), ")");
         }
         
         if(InpTakeProfit > 0)
         {
            double moneyPerPoint = tickValue / tickSize;
            pointsTP = (moneyPerPoint > 0 && lotSize > 0) ? InpTakeProfit / (moneyPerPoint * lotSize) : 0;
            
            // Log the equivalent point distance for reference
            Print("[", m_symbol, "] Buy order TP in points: ", DoubleToString(pointsTP, 1), 
                  " (equivalent to $", DoubleToString(InpTakeProfit, 2), " for lot size ", DoubleToString(lotSize, 2), ")");
         }
         
         if(InpStopLoss <= 0 && InpTakeProfit <= 0)
            Print("[", m_symbol, "] Buy signal - No SL/TP set. Position will be closed on next signal change or by PNL tracking.");
         else
            Print("[", m_symbol, "] Buy signal - Expected SL: $", DoubleToString(InpStopLoss, 2), 
                  ", Expected TP: $", DoubleToString(InpTakeProfit, 2), 
                  " (PNL will be tracked automatically)");
         
         // Place order without chart SL/TP, we'll manage via PNL tracking
         bool result = m_trade.Buy(lotSize, m_symbol, ask, 0, 0, "HA-EMA Buy");
         if(result)
         {
            string message = "[" + m_symbol + "] BUY ORDER OPENED: Ticket #" + IntegerToString(m_trade.ResultOrder()) + 
                           ", Lot Size: " + DoubleToString(lotSize, 2) + 
                           ", SL: $" + DoubleToString(InpStopLoss, 2) + 
                           ", TP: $" + DoubleToString(InpTakeProfit, 2);
                           
            Print(message);
            Alert(message);
            
            // Track this position for SL/TP monitoring
            if(m_positionCount < ArraySize(m_positions))
            {
               m_positions[m_positionCount].ticket = m_trade.ResultOrder();
               m_positions[m_positionCount].openPrice = ask;
               m_positions[m_positionCount].sl = 0;  // Not using chart SL/TP
               m_positions[m_positionCount].tp = 0;  // Not using chart SL/TP
               m_positions[m_positionCount].lotSize = lotSize;
               m_positions[m_positionCount].expectedSL = InpStopLoss;
               m_positions[m_positionCount].expectedTP = InpTakeProfit;
               m_positions[m_positionCount].openTime = TimeCurrent();
               // Initialize best SL to original SL, or 0 if SL is disabled
               m_positions[m_positionCount].bestDynamicSL = InpStopLoss;
               m_positionCount++;
            }
         }
         else
            Print("[", m_symbol, "] Failed to place Buy order, error: ", m_trade.ResultRetcode(), " (", m_trade.ResultRetcodeDescription(), ")");
      }
   }
   
   // Check if any positions were closed (not by this EA)
   void CheckSLTPTriggers()
   {
      if(m_positionCount <= 0) return;
      
      for(int i = m_positionCount - 1; i >= 0; i--)
      {
         // Check if position still exists
         bool found = false;
         for(int j = 0; j < PositionsTotal(); j++)
         {
            if(PositionGetTicket(j) == m_positions[i].ticket)
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
            int timeOpenSeconds = (int)(closeTime - m_positions[i].openTime);
            
            // Look up history to find the actual closing price and P/L
            HistorySelect(m_positions[i].openTime, closeTime + 60); // Add a small buffer
            
            bool historyFound = false;
            for(int j = 0; j < HistoryDealsTotal(); j++)
            {
               ulong dealTicket = HistoryDealGetTicket(j);
               if(dealTicket > 0 && HistoryDealGetInteger(dealTicket, DEAL_POSITION_ID) == m_positions[i].ticket)
               {
                  if(HistoryDealGetInteger(dealTicket, DEAL_ENTRY) == DEAL_ENTRY_OUT)
                  {
                     double profit = HistoryDealGetDouble(dealTicket, DEAL_PROFIT);
                     double closePrice = HistoryDealGetDouble(dealTicket, DEAL_PRICE);
                     
                     // Calculate equivalent money move
                     double priceDiff = MathAbs(closePrice - m_positions[i].openPrice);
                     double tickSize = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_SIZE);
                     double tickValue = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_VALUE);
                     double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
                     double moneyValue = (priceDiff / point) * (tickValue / tickSize) * m_positions[i].lotSize;
                     
                     Print("[", m_symbol, "] Position #", m_positions[i].ticket, " was externally closed",
                           ", Profit: $", DoubleToString(profit, 2),
                           ", Expected SL: $", DoubleToString(m_positions[i].expectedSL, 2),
                           ", Expected TP: $", DoubleToString(m_positions[i].expectedTP, 2),
                           ", Actual move in money: $", DoubleToString(moneyValue, 2),
                           ", Time open: ", timeOpenSeconds, " seconds");
                           
                     historyFound = true;
                     break;
                  }
               }
            }
            
            if(!historyFound)
            {
               Print("[", m_symbol, "] Position #", m_positions[i].ticket, " was closed but details not found in history");
            }
            
            // Remove this position from tracking array
            for(int j = i; j < m_positionCount - 1; j++)
            {
               m_positions[j] = m_positions[j + 1];
            }
            m_positionCount--;
         }
      }
   }
   
   // Function to check positions against their SL/TP in dollar terms
   void CheckPositionsPNL()
   {
      if(m_positionCount <= 0) return;
      
      for(int i = m_positionCount - 1; i >= 0; i--)
      {
         // Select position by ticket
         if(!PositionSelectByTicket(m_positions[i].ticket))
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
         
         // Get position time information for trailing stop
         datetime currentTime = TimeCurrent();
         int timeOpenMinutes = (int)(currentTime - m_positions[i].openTime) / 60;
         
         // Enhanced trailing stop logic with progressive profit protection
         double takeProfit = m_positions[i].expectedTP;
         
         // Step 1: Early protection (after 15 minutes, if 20% of TP reached)
         if(profit >= takeProfit * 0.2 && timeOpenMinutes >= 15)
         {
            // Lock in at least 10% of current profit
            double trailingStopLevel = MathMax(InpStopLoss * 0.8, profit * 0.1);
            
            if(trailingStopLevel < m_positions[i].bestDynamicSL)
            {
               double oldSL = m_positions[i].bestDynamicSL;
               m_positions[i].bestDynamicSL = trailingStopLevel;
               Print("[", m_symbol, "] Early trailing stop for position #", m_positions[i].ticket, 
                     ", from $", DoubleToString(oldSL, 2), " to $", DoubleToString(trailingStopLevel, 2), 
                     " (profit: $", DoubleToString(profit, 2), ", 20% of TP reached)");
            }
         }
         
         // Step 2: Medium protection (after 30 minutes, if 40% of TP reached)
         if(profit >= takeProfit * 0.4 && timeOpenMinutes >= 30)
         {
            // Lock in at least 30% of current profit
            double trailingStopLevel = MathMax(profit * 0.3, 0);
            
            if(trailingStopLevel < m_positions[i].bestDynamicSL)
            {
               double oldSL = m_positions[i].bestDynamicSL;
               m_positions[i].bestDynamicSL = trailingStopLevel;
               Print("[", m_symbol, "] Medium trailing stop for position #", m_positions[i].ticket, 
                     ", from $", DoubleToString(oldSL, 2), " to $", DoubleToString(trailingStopLevel, 2), 
                     " (profit: $", DoubleToString(profit, 2), ", 40% of TP reached)");
            }
         }
         
         // Step 3: Strong protection (after 60 minutes, if 60% of TP reached)
         if(profit >= takeProfit * 0.6 && timeOpenMinutes >= 60)
         {
            // Lock in at least 50% of current profit
            double trailingStopLevel = MathMax(profit * 0.5, 2.0);
            
            if(trailingStopLevel < m_positions[i].bestDynamicSL)
            {
               double oldSL = m_positions[i].bestDynamicSL;
               m_positions[i].bestDynamicSL = trailingStopLevel;
               Print("[", m_symbol, "] Strong trailing stop for position #", m_positions[i].ticket, 
                     ", from $", DoubleToString(oldSL, 2), " to $", DoubleToString(trailingStopLevel, 2), 
                     " (profit: $", DoubleToString(profit, 2), ", 60% of TP reached)");
            }
         }
         
         // Step 4: Full protection (after 90 minutes, if 80% of TP reached)
         if(profit >= takeProfit * 0.8 && timeOpenMinutes >= 90)
         {
            // Lock in at least 75% of current profit
            double trailingStopLevel = MathMax(profit * 0.75, 5.0);
            
            if(trailingStopLevel < m_positions[i].bestDynamicSL)
            {
               double oldSL = m_positions[i].bestDynamicSL;
               m_positions[i].bestDynamicSL = trailingStopLevel;
               Print("[", m_symbol, "] Full trailing stop for position #", m_positions[i].ticket, 
                     ", from $", DoubleToString(oldSL, 2), " to $", DoubleToString(trailingStopLevel, 2), 
                     " (profit: $", DoubleToString(profit, 2), ", 80% of TP reached)");
            }
         }
         
         // Special case: Position open over 4 hours - start moving to breakeven regardless of profit
         if(timeOpenMinutes >= 240 && profit > 0)
         {
            // Move stop to breakeven +$1
            double trailingStopLevel = -1.0; // $1 profit guaranteed
            
            if(trailingStopLevel < m_positions[i].bestDynamicSL)
            {
               double oldSL = m_positions[i].bestDynamicSL;
               m_positions[i].bestDynamicSL = trailingStopLevel;
               Print("[", m_symbol, "] Time-based trailing stop for position #", m_positions[i].ticket, 
                     ", from $", DoubleToString(oldSL, 2), " to breakeven+$1", 
                     " (position open for ", timeOpenMinutes, " minutes)");
            }
         }
         
         // Calculate dynamic SL threshold - tighten as profit increases
         double profitThreshold = 10.0;  // When profit exceeds $10, start improving SL
         double dynamicSLThreshold;
         
         // Only apply dynamic SL if the original SL is greater than 0
         if(m_positions[i].expectedSL > 0)
         {
            // If profit is positive and exceeds the threshold, calculate a potentially tighter SL
            if(profit > profitThreshold)
            {
               // Calculate how much to reduce SL (1:1 ratio with profit increase)
               double slReduction = MathMin(profit - profitThreshold, m_positions[i].expectedSL);
               double currentDynamicSL = m_positions[i].expectedSL - slReduction;
               
               // Never let SL go below 1.0
               if(currentDynamicSL < 1.0) currentDynamicSL = 1.0;
               
               // Only update if this SL is tighter (lower) than the previous best
               if(currentDynamicSL < m_positions[i].bestDynamicSL)
               {
                  // Update the position's best dynamic SL
                  m_positions[i].bestDynamicSL = currentDynamicSL;
                  Print("[", m_symbol, "] Tightening SL for position #", m_positions[i].ticket, 
                        " from $", DoubleToString(m_positions[i].bestDynamicSL, 2), 
                        " to $", DoubleToString(currentDynamicSL, 2), 
                        " (profit: $", DoubleToString(profit, 2), ")");
               }
            }
         }
         else
         {
            // If SL is 0, set bestDynamicSL to 0 as well (no SL)
            m_positions[i].bestDynamicSL = 0;
         }
         
         // Always use the best (lowest) SL we've achieved for this position
         dynamicSLThreshold = m_positions[i].bestDynamicSL;
         
         // We don't need to log status on every tick
         static int tickCounter = 0;
         // Only log once every 1000 ticks to reduce log spam
         // This can be completely removed if you want no position status logs
         /* 
         if(tickCounter++ % 1000 == 0)
         {
            Print("[", m_symbol, "] Position #", m_positions[i].ticket, " current PNL: $", DoubleToString(profit, 2));
         }
         */
         
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
               reason = "Manual Stop Loss" + (dynamicSLThreshold < m_positions[i].expectedSL ? " (Dynamic)" : "");
            }
            // Check for take profit (positive profit exceeding TP), but only if TP is enabled
            else if(m_positions[i].expectedTP > 0 && profit > 0 && profit >= m_positions[i].expectedTP)
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
               reason = "Manual Stop Loss" + (dynamicSLThreshold < m_positions[i].expectedSL ? " (Dynamic)" : "");
            }
            // Check for take profit (positive profit exceeding TP), but only if TP is enabled
            else if(m_positions[i].expectedTP > 0 && profit > 0 && profit >= m_positions[i].expectedTP)
            {
               closePosition = true;
               reason = "Manual Take Profit";
            }
         }
         
         // Close position if conditions met
         if(closePosition)
         {
            bool result = m_trade.PositionClose(m_positions[i].ticket);
            
            if(result)
            {
               string message = "[" + m_symbol + "] POSITION CLOSED: Ticket #" + IntegerToString(m_positions[i].ticket) + 
                              ", By " + reason + 
                              ", Profit: $" + DoubleToString(profit, 2);
               
               Print(message);
               Alert(message);
               
               // Update consecutive losses tracking
               UpdateConsecutiveLossesCounter(profit);
               
               // Remove from tracking array
               for(int j = i; j < m_positionCount - 1; j++)
               {
                  m_positions[j] = m_positions[j + 1];
               }
               m_positionCount--;
            }
            else
            {
               Print("[", m_symbol, "] Failed to close position #", m_positions[i].ticket, 
                     ", error: ", m_trade.ResultRetcode(), " (", m_trade.ResultRetcodeDescription(), ")");
            }
         }
      }
   }
   
   //+------------------------------------------------------------------+
   //| Update the consecutive losses counter                            |
   //+------------------------------------------------------------------+
   void UpdateConsecutiveLossesCounter(double profit)
   {
      if(profit < 0)
      {
         g_consecutiveLosses++;
         
         // After several consecutive losses, reduce position size temporarily
         if(g_consecutiveLosses >= 3)
         {
            Print("[", m_symbol, "] WARNING: ", g_consecutiveLosses, " consecutive losses detected! Consider reducing risk.");
         }
      }
      else
      {
         // Reset counter on profitable trade
         g_consecutiveLosses = 0;
      }
   }
   
   //+------------------------------------------------------------------+
   //| Calculate dynamic lot size based on market volatility            |
   //+------------------------------------------------------------------+
   double CalculateDynamicLotSize(double baseLotSize)
   {
      double calculatedLotSize = baseLotSize;
      
      // Calculate ATR for volatility measurement
      int atrHandle = iATR(m_symbol, PERIOD_CURRENT, 14);
      if(atrHandle == INVALID_HANDLE)
         return NormalizeLotSize(baseLotSize);
      
      double atrValues[1];
      if(!CopyBuffer(atrHandle, 0, 0, 1, atrValues))
      {
         IndicatorRelease(atrHandle);
         return NormalizeLotSize(baseLotSize);
      }
      IndicatorRelease(atrHandle);
      
      // Get 20-day average ATR for comparison
      int atr20Handle = iATR(m_symbol, PERIOD_CURRENT, 20);
      double atr20Values[20];
      
      if(atr20Handle != INVALID_HANDLE && CopyBuffer(atr20Handle, 0, 0, 20, atr20Values))
      {
         double avgAtr = 0;
         for(int i = 0; i < 20; i++)
            avgAtr += atr20Values[i];
         avgAtr /= 20;
         
         IndicatorRelease(atr20Handle);
         
         // Adjust lot size based on current volatility compared to average
         if(atrValues[0] > avgAtr * 1.5)
         {
            calculatedLotSize = baseLotSize * 0.75; // Reduce size in high volatility
            Print("[", m_symbol, "] High volatility detected. Reducing lot size from ", 
                  DoubleToString(baseLotSize, 2), " to ", DoubleToString(calculatedLotSize, 2));
         }
         else if(atrValues[0] < avgAtr * 0.75)
         {
            calculatedLotSize = baseLotSize * 1.25; // Increase size in low volatility
            Print("[", m_symbol, "] Low volatility detected. Increasing lot size from ", 
                  DoubleToString(baseLotSize, 2), " to ", DoubleToString(calculatedLotSize, 2));
         }
      }
      
      // If consecutive losses > 2, reduce position size
      if(g_consecutiveLosses > 2)
      {
         calculatedLotSize = baseLotSize * (1.0 - (0.1 * MathMin(g_consecutiveLosses - 2, 5)));
         Print("[", m_symbol, "] Reducing lot size due to ", g_consecutiveLosses, " consecutive losses: ", 
               DoubleToString(baseLotSize, 2), " to ", DoubleToString(calculatedLotSize, 2));
      }
      
      // Normalize the lot size to the allowed increments
      return NormalizeLotSize(calculatedLotSize);
   }
   
   //+------------------------------------------------------------------+
   //| Normalize lot size to valid increment (0.01 for BTCUSD)          |
   //+------------------------------------------------------------------+
   double NormalizeLotSize(double lotSize)
   {
      // Get the minimum lot size and step for the symbol
      double minLot = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_MIN);
      double maxLot = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_MAX);
      double stepLot = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_STEP);
      
      // If we can't get the lot information, default to 0.01 step
      if(stepLot <= 0)
         stepLot = 0.01;
         
      // Round to the nearest allowed lot size increment
      double normalizedLot = MathRound(lotSize / stepLot) * stepLot;
      
      // Ensure the lot size is not below the minimum or above the maximum
      normalizedLot = MathMax(minLot, MathMin(maxLot, normalizedLot));
      
      // Ensure minimum of 0.01 for safety
      normalizedLot = MathMax(0.01, normalizedLot);
      
      // Debug log if there was a significant adjustment
      if(MathAbs(normalizedLot - lotSize) > 0.001)
      {
         Print("[", m_symbol, "] Lot size normalized from ", DoubleToString(lotSize, 3), 
               " to ", DoubleToString(normalizedLot, 2), 
               " (min:", DoubleToString(minLot, 2), 
               ", max:", DoubleToString(maxLot, 2), 
               ", step:", DoubleToString(stepLot, 2), ")");
      }
      
      return normalizedLot;
   }
   
   //+------------------------------------------------------------------+
   //| Check if current trend is strong enough for reliable signals     |
   //+------------------------------------------------------------------+
   bool IsTrendStrong()
   {
      // Use ADX to measure trend strength
      int adxHandle = iADX(m_symbol, PERIOD_CURRENT, 14);
      if(adxHandle == INVALID_HANDLE)
         return true; // Default to true if we can't calculate
      
      double adxMain[1], plusDI[1], minusDI[1];
      if(!CopyBuffer(adxHandle, 0, 0, 1, adxMain) ||
         !CopyBuffer(adxHandle, 1, 0, 1, plusDI) ||
         !CopyBuffer(adxHandle, 2, 0, 1, minusDI))
      {
         IndicatorRelease(adxHandle);
         return true;
      }
      IndicatorRelease(adxHandle);
      
      // Check both ADX value and DI separation for trend strength
      bool adxStrong = (adxMain[0] > 22);  // Slightly higher threshold for ADX
      bool diSeparation = (MathAbs(plusDI[0] - minusDI[0]) > 8.0); // DI lines need decent separation
      
      bool strongTrend = adxStrong && diSeparation;
      
      // Get the true trend direction from DI lines
      bool uptrend = (plusDI[0] > minusDI[0]);
      bool downtrend = (minusDI[0] > plusDI[0]);
      
      if(!strongTrend)
      {
         Print("[", m_symbol, "] Weak trend detected (ADX: ", DoubleToString(adxMain[0], 1), 
               ", +DI: ", DoubleToString(plusDI[0], 1),
               ", -DI: ", DoubleToString(minusDI[0], 1),
               "). Trade signals may be less reliable.");
               
         return false; // Don't trade in weak trends
      }
      else
      {
         Print("[", m_symbol, "] Strong ", uptrend ? "UPTREND" : "DOWNTREND", 
               " detected (ADX: ", DoubleToString(adxMain[0], 1), 
               ", +DI: ", DoubleToString(plusDI[0], 1),
               ", -DI: ", DoubleToString(minusDI[0], 1), ")");
      }
         
      return strongTrend;
   }
   
   // Process tick for this symbol
   void OnTick(datetime currentBarTime)
   {
      // Check if any positions were closed by SL/TP
      CheckSLTPTriggers();
      
      // Check if any positions should be closed based on their PNL
      CheckPositionsPNL();
      
      // Get the last bar time for this symbol
      static datetime lastBarTime = 0;
      datetime thisBarTime = iTime(m_symbol, PERIOD_CURRENT, 0);
      
      // Only check for signals on a new bar
      if(thisBarTime != lastBarTime)
      {
         lastBarTime = thisBarTime;
         CheckForSignals();
      }
   }
   
   // Getters
   string GetSymbol() { return m_symbol; }
   int GetMagicNumber() { return m_magicNumber; }
};

// Global variables
bool           g_isHedging = false;
datetime       g_lastDayChecked = 0;        // Last day we checked for profit reset
datetime       g_lastMonthChecked = 0;      // Last month we checked for profit reset
double         g_startDayBalance = 0;        // Balance at the start of the day
double         g_startMonthBalance = 0;     // Balance at the start of the month
double         g_monthlyPeakBalance = 0;    // Peak balance reached during the month
bool           g_dailyTargetReached = false; // Whether we've reached daily target
bool           g_monthlyTargetReached = false; // Whether we've reached monthly target
bool           g_drawdownReached = false;    // Whether maximum drawdown has been reached
int            g_consecutiveLosses = 0;      // Track consecutive losing trades

// Symbol traders array
CArrayString g_symbolList;
CSymbolTrader* g_symbolTraders[];

// Now we can include the display file after all globals are defined
#include "HA-EMA-Multi-DisplayInfo.mqh"

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
         double prevDayProfit = previousBalance - g_startDayBalance;
         string message = "DAILY SUMMARY: Previous day's final P&L: $" + DoubleToString(prevDayProfit, 2) + 
               " (Target was: $" + DoubleToString(InpDailyProfitTarget, 2) + ")";
         
         Print(message);
         // Only alert if we had significant profit/loss
         if(MathAbs(prevDayProfit) > 10.0)
         {
            Alert(message);
         }
      }
      
      g_startDayBalance = AccountInfoDouble(ACCOUNT_BALANCE);
      g_dailyTargetReached = false;
      g_lastDayChecked = todayStart;
      
      string message = "NEW DAY DETECTED. Resetting daily profit tracking. Starting balance: $" + DoubleToString(g_startDayBalance, 2) + 
                    " (Daily target: $" + DoubleToString(InpDailyProfitTarget, 2) + " including unrealized profits)";
      Print(message);
      Alert(message);
   }
}

//+------------------------------------------------------------------+
//| Reset monthly profit tracking at the start of a new month        |
//+------------------------------------------------------------------+
void CheckAndResetMonthlyProfit()
{
   // Get the current month
   MqlDateTime dt;
   TimeCurrent(dt);
   
   // Create a datetime for the first day of current month at 00:00:00
   MqlDateTime startOfMonth;
   startOfMonth.year = dt.year;
   startOfMonth.mon = dt.mon;
   startOfMonth.day = 1;
   startOfMonth.hour = 0;
   startOfMonth.min = 0;
   startOfMonth.sec = 0;
   
   datetime monthStart = StructToTime(startOfMonth);
   
   // If this is a new month, reset the profit tracking
   if(g_lastMonthChecked < monthStart)
   {
      // If we have previous month data, report final results
      if(g_lastMonthChecked > 0)
      {
         double previousBalance = AccountInfoDouble(ACCOUNT_BALANCE);
         double prevMonthProfit = previousBalance - g_startMonthBalance;
         
         // Get month name for better reporting
         MqlDateTime prevMonth;
         TimeToStruct(g_lastMonthChecked, prevMonth);
         string monthNames[] = {"January", "February", "March", "April", "May", "June", 
                               "July", "August", "September", "October", "November", "December"};
         string prevMonthName = monthNames[prevMonth.mon-1];
         
         string message = "MONTHLY SUMMARY: " + prevMonthName + "'s final P&L: $" + DoubleToString(prevMonthProfit, 2) + 
               " (Target was: $" + DoubleToString(InpMonthlyProfitTarget, 2) + ")";
         
         Print(message);
         // Always alert for monthly summary
         Alert(message);
      }
      
      g_startMonthBalance = AccountInfoDouble(ACCOUNT_BALANCE);
      g_monthlyPeakBalance = g_startMonthBalance;  // Initialize peak to starting balance
      g_monthlyTargetReached = false;
      g_drawdownReached = false;
      g_lastMonthChecked = monthStart;
      
      // Get current month name
      string monthNames[] = {"January", "February", "March", "April", "May", "June", 
                            "July", "August", "September", "October", "November", "December"};
      string currentMonthName = monthNames[dt.mon-1];
      
      string message = "NEW MONTH DETECTED (" + currentMonthName + "). Resetting monthly profit tracking. Starting balance: $" + 
                      DoubleToString(g_startMonthBalance, 2) + 
                      " (Monthly target: $" + DoubleToString(InpMonthlyProfitTarget, 2) + ")";
      Print(message);
      Alert(message);
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
   double unrealizedProfit = 0.0;
   
   // Calculate unrealized profit from all open positions
   int total = PositionsTotal();
   for(int i = 0; i < total; i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket <= 0)
         continue;
         
      // Check if the position belongs to our EA (check magic number)
      long magic = PositionGetInteger(POSITION_MAGIC);
      bool isOurPosition = false;
      
      // Check if this position has one of our magic numbers
      for(int j = 0; j < ArraySize(g_symbolTraders); j++)
      {
         if(magic == g_symbolTraders[j].GetMagicNumber())
         {
            isOurPosition = true;
            break;
         }
      }
      
      if(isOurPosition)
      {
         // Add this position's floating profit to our unrealized profit
         unrealizedProfit += PositionGetDouble(POSITION_PROFIT);
      }
   }
   
   // Calculate total profit: realized + unrealized
   double dailyProfit = (currentBalance - g_startDayBalance) + unrealizedProfit;
   
   // Log progress towards daily target every 25%
   static double lastReportedPercentage = 0.0;
   if(InpDailyProfitTarget > 0)
   {
      double currentPercentage = MathFloor(dailyProfit / InpDailyProfitTarget * 100 / 25) * 25;
      
      if(currentPercentage > lastReportedPercentage && currentPercentage < 100)
      {
         string message = "DAILY PROFIT PROGRESS: $" + DoubleToString(dailyProfit, 2) + 
               " (Realized: $" + DoubleToString(currentBalance - g_startDayBalance, 2) + 
               ", Unrealized: $" + DoubleToString(unrealizedProfit, 2) + 
               ") / $" + DoubleToString(InpDailyProfitTarget, 2) +
               " (" + DoubleToString(dailyProfit / InpDailyProfitTarget * 100, 1) + "% of daily target)";
               
         Print(message);
         // Only alert at 50% and 75% to avoid too many alerts
         if(currentPercentage == 50 || currentPercentage == 75)
         {
            Alert(message);
         }
         lastReportedPercentage = currentPercentage;
      }
   }
   
   if(dailyProfit >= InpDailyProfitTarget)
   {
      g_dailyTargetReached = true;
      string message = "DAILY PROFIT TARGET REACHED! Total profit: $" + DoubleToString(dailyProfit, 2) + 
                     " (Realized: $" + DoubleToString(currentBalance - g_startDayBalance, 2) + 
                     ", Unrealized: $" + DoubleToString(unrealizedProfit, 2) + 
                     "), Target: $" + DoubleToString(InpDailyProfitTarget, 2) + 
                     ". Closing all positions and stopping trading for today.";
      
      Print(message);
      Alert(message);
      
      // Close all open positions for all symbols
      for(int i = 0; i < ArraySize(g_symbolTraders); i++)
      {
         g_symbolTraders[i].CloseAllPositions();
      }
   }
   
   return g_dailyTargetReached;
}

//+------------------------------------------------------------------+
//| Check if monthly profit target has been reached                  |
//+------------------------------------------------------------------+
bool CheckMonthlyProfitTarget()
{
   if(!InpUseMonthlyProfitTarget || g_monthlyTargetReached)
      return g_monthlyTargetReached;
      
   double currentBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   double unrealizedProfit = 0.0;
   
   // Calculate unrealized profit from all open positions
   int total = PositionsTotal();
   for(int i = 0; i < total; i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket <= 0)
         continue;
         
      // Check if the position belongs to our EA (check magic number)
      long magic = PositionGetInteger(POSITION_MAGIC);
      bool isOurPosition = false;
      
      // Check if this position has one of our magic numbers
      for(int j = 0; j < ArraySize(g_symbolTraders); j++)
      {
         if(magic == g_symbolTraders[j].GetMagicNumber())
         {
            isOurPosition = true;
            break;
         }
      }
      
      if(isOurPosition)
      {
         // Add this position's floating profit to our unrealized profit
         unrealizedProfit += PositionGetDouble(POSITION_PROFIT);
      }
   }
   
   // Calculate total profit: realized + unrealized
   double monthlyProfit = (currentBalance - g_startMonthBalance) + unrealizedProfit;
   
   // Log progress towards monthly target every 25%
   static double lastReportedPercentage = 0.0;
   if(InpMonthlyProfitTarget > 0)
   {
      double currentPercentage = MathFloor(monthlyProfit / InpMonthlyProfitTarget * 100 / 25) * 25;
      
      if(currentPercentage > lastReportedPercentage && currentPercentage < 100)
      {
         string message = "MONTHLY PROFIT PROGRESS: $" + DoubleToString(monthlyProfit, 2) + 
               " (Realized: $" + DoubleToString(currentBalance - g_startMonthBalance, 2) + 
               ", Unrealized: $" + DoubleToString(unrealizedProfit, 2) + 
               ") / $" + DoubleToString(InpMonthlyProfitTarget, 2) +
               " (" + DoubleToString(monthlyProfit / InpMonthlyProfitTarget * 100, 1) + "% of monthly target)";
               
         Print(message);
         // Alert at 50%, 75% and 90% to make trader aware of approaching target
         if(currentPercentage == 50 || currentPercentage == 75 || currentPercentage == 90)
         {
            Alert(message);
         }
         lastReportedPercentage = currentPercentage;
      }
   }
   
   if(monthlyProfit >= InpMonthlyProfitTarget)
   {
      g_monthlyTargetReached = true;
      string message = "MONTHLY PROFIT TARGET REACHED! Total profit: $" + DoubleToString(monthlyProfit, 2) + 
                     " (Realized: $" + DoubleToString(currentBalance - g_startMonthBalance, 2) + 
                     ", Unrealized: $" + DoubleToString(unrealizedProfit, 2) + 
                     "), Target: $" + DoubleToString(InpMonthlyProfitTarget, 2) + 
                     ". Closing all positions and stopping trading for the rest of the month.";
      
      Print(message);
      Alert(message);
      
      // Close all open positions for all symbols
      for(int i = 0; i < ArraySize(g_symbolTraders); i++)
      {
         g_symbolTraders[i].CloseAllPositions();
      }
   }
   
   return g_monthlyTargetReached;
}

//+------------------------------------------------------------------+
//| Check if maximum drawdown has been reached                       |
//+------------------------------------------------------------------+
bool CheckMaxDrawdown()
{
   if(!InpUseMaxDrawdown || g_drawdownReached)
      return g_drawdownReached;
      
   double currentBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   double unrealizedProfit = 0.0;
   
   // Calculate unrealized profit from all open positions
   int total = PositionsTotal();
   for(int i = 0; i < total; i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket <= 0)
         continue;
         
      // Check if the position belongs to our EA (check magic number)
      long magic = PositionGetInteger(POSITION_MAGIC);
      bool isOurPosition = false;
      
      // Check if this position has one of our magic numbers
      for(int j = 0; j < ArraySize(g_symbolTraders); j++)
      {
         if(magic == g_symbolTraders[j].GetMagicNumber())
         {
            isOurPosition = true;
            break;
         }
      }
      
      if(isOurPosition)
      {
         // Add this position's floating profit to our unrealized profit
         unrealizedProfit += PositionGetDouble(POSITION_PROFIT);
      }
   }
   
   // Calculate total current value (balance + unrealized profit)
   double totalCurrentValue = currentBalance + unrealizedProfit;
   
   // Update the monthly peak balance if current value is higher
   if(totalCurrentValue > g_monthlyPeakBalance)
   {
      g_monthlyPeakBalance = totalCurrentValue;
      
      // Log when we reach new peak balance (only log significant changes)
      static double lastReportedPeak = 0.0;
      if(g_monthlyPeakBalance - lastReportedPeak > 20.0)  // Only report if peak increases by $20 or more
      {
         string message = "NEW MONTHLY PEAK BALANCE: $" + DoubleToString(g_monthlyPeakBalance, 2) + 
                         " (Account balance: $" + DoubleToString(currentBalance, 2) + 
                         ", Unrealized: $" + DoubleToString(unrealizedProfit, 2) + ")";
         Print(message);
         lastReportedPeak = g_monthlyPeakBalance;
      }
   }
   
   // Calculate drawdown from peak
   double drawdown = g_monthlyPeakBalance - totalCurrentValue;
   
   // Log progress towards maximum drawdown every $25
   static double lastReportedDrawdown = 0.0;
   if(drawdown > 25.0 && MathFloor(drawdown / 25.0) > MathFloor(lastReportedDrawdown / 25.0))
   {
      string message = "DRAWDOWN ALERT: Current drawdown is $" + DoubleToString(drawdown, 2) + 
                     " from peak of $" + DoubleToString(g_monthlyPeakBalance, 2) + 
                     " (Maximum allowed: $" + DoubleToString(InpMaxDrawdown, 2) + ")";
      Print(message);
      
      // Alert at 50%, 75% and 90% of maximum drawdown
      if(((drawdown >= InpMaxDrawdown * 0.5) && (lastReportedDrawdown < InpMaxDrawdown * 0.5)) ||
         ((drawdown >= InpMaxDrawdown * 0.75) && (lastReportedDrawdown < InpMaxDrawdown * 0.75)) ||
         ((drawdown >= InpMaxDrawdown * 0.9) && (lastReportedDrawdown < InpMaxDrawdown * 0.9)))
      {
         Alert(message);
      }
      
      lastReportedDrawdown = drawdown;
   }
   
   // Check if maximum drawdown is reached
   if(drawdown >= InpMaxDrawdown)
   {
      g_drawdownReached = true;
      string message = "MAXIMUM DRAWDOWN REACHED! Current drawdown: $" + DoubleToString(drawdown, 2) + 
                     " from peak of $" + DoubleToString(g_monthlyPeakBalance, 2) + 
                     " (Maximum allowed: $" + DoubleToString(InpMaxDrawdown, 2) + ")" + 
                     ". Closing all positions and stopping trading for the rest of the month.";
      
      Print(message);
      Alert(message);
      
      // Close all open positions for all symbols
      for(int i = 0; i < ArraySize(g_symbolTraders); i++)
      {
         g_symbolTraders[i].CloseAllPositions();
      }
   }
   
   return g_drawdownReached;
}

//+------------------------------------------------------------------+
//| Close all positions for all symbols                              |
//+------------------------------------------------------------------+
void CloseAllPositionsForAllSymbols()
{
   for(int i = 0; i < ArraySize(g_symbolTraders); i++)
   {
      g_symbolTraders[i].CloseAllPositions();
   }
}

//+------------------------------------------------------------------+
//| Custom function to trim spaces from a string                     |
//+------------------------------------------------------------------+
string TrimString(string str)
{
   // Trim leading spaces
   while(StringLen(str) > 0 && StringGetCharacter(str, 0) == ' ')
      str = StringSubstr(str, 1);
   
   // Trim trailing spaces
   int len = StringLen(str);
   while(len > 0 && StringGetCharacter(str, len - 1) == ' ')
   {
      str = StringSubstr(str, 0, len - 1);
      len = StringLen(str);
   }
   
   return str;
}

//+------------------------------------------------------------------+
//| Add the current chart symbol to the list                         |
//+------------------------------------------------------------------+
bool ParseSymbolList()
{
   g_symbolList.Clear();
   
   // Use the current chart's symbol only
   string symbol = _Symbol;
   
   // Verify the symbol is valid
   if(SymbolInfoInteger(symbol, SYMBOL_TRADE_MODE) == SYMBOL_TRADE_MODE_DISABLED)
   {
      Print("Error: Symbol '", symbol, "' is not available for trading.");
      return false;
   }
   
   // Skip symbols with zero Bid or Ask
   if(SymbolInfoDouble(symbol, SYMBOL_BID) == 0 || SymbolInfoDouble(symbol, SYMBOL_ASK) == 0)
   {
      Print("Error: Symbol '", symbol, "' has zero Bid or Ask price.");
      return false;
   }
   
   // Add the symbol to our list
   g_symbolList.Add(symbol);
   
   if(g_symbolList.Total() == 0)
   {
      Print("Error: No valid symbols found to trade. Please check Market Watch or symbol list.");
      return false;
   }
   
   Print("Found ", g_symbolList.Total(), " valid symbols to trade: ");
   string symbolsStr = "";
   for(int i = 0; i < g_symbolList.Total(); i++)
   {
      symbolsStr += g_symbolList.At(i);
      if(i < g_symbolList.Total() - 1)
         symbolsStr += ", ";
   }
   Print(symbolsStr);
   
   return true;
}

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   // Set the magic number for the display panel
   SetMagicNumber(InpMagicNumber);
   
   // Initialize hedging detection
   g_isHedging = ((ENUM_ACCOUNT_MARGIN_MODE)AccountInfoInteger(ACCOUNT_MARGIN_MODE) == ACCOUNT_MARGIN_MODE_RETAIL_HEDGING);
   
   // Initialize daily profit tracking
   g_startDayBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   g_lastDayChecked = 0; // Force check and reset on first tick
   g_dailyTargetReached = false;
   
   // Initialize monthly profit tracking and drawdown protection
   g_startMonthBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   g_monthlyPeakBalance = g_startMonthBalance;
   g_lastMonthChecked = 0; // Force check and reset on first tick
   g_monthlyTargetReached = false;
   g_drawdownReached = false;
   
   // Parse symbol list
   if(!ParseSymbolList())
   {
      return INIT_PARAMETERS_INCORRECT;
   }
   
   // Create symbol traders
   int symbolCount = g_symbolList.Total();
   ArrayResize(g_symbolTraders, symbolCount);
   
   for(int i = 0; i < symbolCount; i++)
   {
      string symbol = g_symbolList.At(i);
      g_symbolTraders[i] = new CSymbolTrader(symbol, InpMagicNumber, i);
      
      if(!g_symbolTraders[i].Initialize())
      {
         Print("Failed to initialize trader for symbol ", symbol);
         return INIT_FAILED;
      }
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
   
   // Add indicators to chart
   Print("Adding indicators to chart...");
   if(!AddHeikenAshiToChart())
   {
      Print("WARNING: Failed to add Heiken Ashi indicator to chart, but EA will still function.");
   }
   
   if(!AddEMAToChart())
   {
      Print("WARNING: Failed to add EMA indicator to chart, but EA will still function.");
   }
   
   // Redraw chart to ensure indicators are visible
   ChartRedraw();
   Print("Indicators added. EA initialization complete.");
   
   // Create info panel if enabled
   if(InpShowInfoPanel)
   {
      UpdateInfoPanel(g_startDayBalance, g_startMonthBalance, g_monthlyPeakBalance,
                     g_dailyTargetReached, g_monthlyTargetReached, g_drawdownReached,
                     InpMaxDrawdown);
      Print("Information panel created on chart.");
   }
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   // Remove info panel
   if(InpShowInfoPanel)
   {
      RemoveInfoPanel();
      Print("Information panel removed from chart.");
   }

   // Report trading statistics
   Print("Final trading statistics:");
   Print("  Consecutive losses at end: ", g_consecutiveLosses);
   Print("  Monthly profit: $", DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE) - g_startMonthBalance, 2));
   Print("  Monthly peak balance: $", DoubleToString(g_monthlyPeakBalance, 2));
   double currentDrawdown = g_monthlyPeakBalance - (AccountInfoDouble(ACCOUNT_BALANCE) + CalculateTotalUnrealizedProfit());
   Print("  Current drawdown: $", DoubleToString(currentDrawdown, 2), " (", 
         DoubleToString((currentDrawdown/g_monthlyPeakBalance)*100.0, 1), "%)");

   // Clean up symbol traders
   for(int i = 0; i < ArraySize(g_symbolTraders); i++)
   {
      delete g_symbolTraders[i];
   }
   ArrayFree(g_symbolTraders);
   
   // Note: We're not removing indicators from the chart on EA removal
   // This allows the user to still see the indicators if they want to
   // If you want to remove them, uncomment the code below:
   
   /*
   // Remove indicators from chart
   long chartID = ChartID();
   
   // Remove EMA indicator
   string emaName = "Moving Average";
   ChartIndicatorDelete(chartID, 0, emaName);
   
   // Remove Heiken Ashi indicator
   string haName = "Examples\\Heiken_Ashi";
   ChartIndicatorDelete(chartID, 0, haName);
   
   Print("Indicators removed from chart");
   */
}

//+------------------------------------------------------------------+
//| This function is not needed anymore as we only use chart symbol  |
//+------------------------------------------------------------------+
void CheckForNewSymbols()
{
   // Not needed - we only trade the current chart symbol
   return;
}

//+------------------------------------------------------------------+
//| Add Heiken Ashi indicator to the chart                           |
//+------------------------------------------------------------------+
bool AddHeikenAshiToChart()
{
   // Check if indicator already exists
   int window = 0;  // Use the main chart window
   long chartID = ChartID();
   string indicatorName = "Examples\\Heiken_Ashi";
   
   // Create the indicator handle
   int handle = iCustom(_Symbol, PERIOD_CURRENT, indicatorName);
   if(handle == INVALID_HANDLE)
   {
      Print("Failed to create Heiken Ashi indicator handle: ", GetLastError());
      return false;
   }
   
   // Apply indicator to the chart
   if(!ChartIndicatorAdd(chartID, window, handle))
   {
      Print("Failed to add Heiken Ashi indicator to chart: ", GetLastError());
      IndicatorRelease(handle);
      return false;
   }
   
   Print("Heiken Ashi indicator added to chart successfully");
   return true;
}

//+------------------------------------------------------------------+
//| Add EMA indicator to the chart                                   |
//+------------------------------------------------------------------+
bool AddEMAToChart()
{
   // Check if indicator already exists
   int window = 0;  // Use the main chart window
   long chartID = ChartID();
   string indicatorName = "Moving Average";
   
   // Set parameters for the indicator
   int MA_Period = InpEMAPeriod;
   ENUM_MA_METHOD MA_Method = MODE_EMA;
   ENUM_APPLIED_PRICE Applied_Price = PRICE_CLOSE;
   
   // Create the indicator handle
   int handle = iMA(_Symbol, PERIOD_CURRENT, MA_Period, 0, MA_Method, Applied_Price);
   if(handle == INVALID_HANDLE)
   {
      Print("Failed to create EMA indicator handle: ", GetLastError());
      return false;
   }
   
   // Apply indicator to the chart
   if(!ChartIndicatorAdd(chartID, window, handle))
   {
      Print("Failed to add EMA indicator to chart: ", GetLastError());
      IndicatorRelease(handle);
      return false;
   }
   
   // Unfortunately we can't change indicator properties directly in MQL5
   // The indicator will use default colors and line width
   
   Print("EMA indicator added to chart successfully");
   return true;
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // Check and reset daily profit tracking if needed
   CheckAndResetDailyProfit();
   
   // Check and reset monthly profit tracking if needed
   CheckAndResetMonthlyProfit();
   
   // Check if we just entered the weekend
   if(InpDisableWeekendTrading && JustEnteredWeekend())
   {
      string message = "WEEKEND DETECTED! Closing all positions and stopping trading until Monday.";
      Print(message);
      Alert(message);
      CloseAllPositionsForAllSymbols();
      return; // Skip further processing
   }
   
   // Skip trading on weekends if weekend trading is disabled
   if(InpDisableWeekendTrading && IsWeekend())
   {
      return;
   }
   
   // Check if maximum drawdown has been reached
   if(InpUseMaxDrawdown && CheckMaxDrawdown())
   {
      // Print status every hour
      static datetime lastDrawdownCheck = 0;
      datetime currentTime = TimeCurrent();
      
      if(currentTime - lastDrawdownCheck > 3600)  // 3600 seconds = 1 hour
      {
         lastDrawdownCheck = currentTime;
         double currentBalance = AccountInfoDouble(ACCOUNT_BALANCE);
         double drawdown = g_monthlyPeakBalance - currentBalance;
         Print("Maximum drawdown reached. Current drawdown: $", DoubleToString(drawdown, 2), 
               " from peak balance of $", DoubleToString(g_monthlyPeakBalance, 2),
               ". No more trading this month.");
      }
      return; // Skip further processing
   }
   
   // Check if monthly profit target reached
   if(InpUseMonthlyProfitTarget && CheckMonthlyProfitTarget())
   {
      // Print profit status every hour
      static datetime lastMonthlyCheck = 0;
      datetime currentTime = TimeCurrent();
      
      if(currentTime - lastMonthlyCheck > 3600)  // 3600 seconds = 1 hour
      {
         lastMonthlyCheck = currentTime;
         double currentBalance = AccountInfoDouble(ACCOUNT_BALANCE);
         double monthlyProfit = currentBalance - g_startMonthBalance;
         Print("Monthly profit target reached. Current profit: $", DoubleToString(monthlyProfit, 2), 
               ", no more trading this month.");
      }
      return; // Skip further processing
   }
   
   // Check if daily profit target reached
   if(InpUseDailyProfitTarget && CheckDailyProfitTarget())
   {
      // Print profit status every hour
      static datetime lastDailyCheck = 0;
      datetime currentTime = TimeCurrent();
      
      if(currentTime - lastDailyCheck > 3600)  // 3600 seconds = 1 hour
      {
         lastDailyCheck = currentTime;
         double currentBalance = AccountInfoDouble(ACCOUNT_BALANCE);
         double dailyProfit = currentBalance - g_startDayBalance;
         Print("Daily profit target reached. Current profit: $", DoubleToString(dailyProfit, 2), 
               ", no more trading today.");
      }
      return; // Skip further processing
   }
   
   // Check if we just exited the trading session
   if(JustExitedSession())
   {
      string message = "TRADING SESSION ENDED! Closing all positions until next session.";
      Print(message);
      Alert(message);
      CloseAllPositionsForAllSymbols();
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
   
   // No need to check for new symbols - we only trade the chart symbol
   datetime currentTime = TimeCurrent();
   
   // Get current bar time for main chart (used for coordination)
   datetime currentBarTime = iTime(_Symbol, PERIOD_CURRENT, 0);
   
   // Process each symbol
   for(int i = 0; i < ArraySize(g_symbolTraders); i++)
   {
      g_symbolTraders[i].OnTick(currentBarTime);
   }
   
   // Update info panel if enabled
   if(InpShowInfoPanel)
   {
      // Update panel at defined interval
      static datetime lastInfoUpdate = 0;
      
      if(currentTime - lastInfoUpdate > InpUpdateInterval)
      {
         UpdateInfoPanel(g_startDayBalance, g_startMonthBalance, g_monthlyPeakBalance,
                        g_dailyTargetReached, g_monthlyTargetReached, g_drawdownReached,
                        InpMaxDrawdown);
         lastInfoUpdate = currentTime;
      }
   }
}
//+------------------------------------------------------------------+
