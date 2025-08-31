//+------------------------------------------------------------------+
//|                                                         5EMA.mq5 |
//|                                        Copyright 2025, Your Name |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, Your Name"
#property link      "https://www.mql5.com"
#property version   "1.00"
#property description "5 EMA Trading Strategy Expert Advisor"

//--- Input parameters
input int         EMAperiod = 5;                // EMA period
input double      NormalLots = 0.2;             // Normal position size (2/10)
input double      HighProbLots = 1.0;           // High probability position size (10/10)
input double      LowConfLots = 0.1;            // Low confidence position size (1/10)
input double      RiskRewardRatio = 3.0;        // Risk-Reward ratio for take profit
input bool        UseTrailingStop = true;       // Use trailing stop instead of fixed TP
input int         TrailingStopPoints = 50;      // Trailing stop in points
input bool        Trade5Min = true;             // Trade 5-minute chart (SELL opportunities)
input bool        Trade15Min = true;            // Trade 15-minute chart (BUY opportunities)
input bool        UseGapDetection = true;       // Detect gaps for high probability trades
input bool        UseRangeShiftDetection = true; // Detect range shifts for high probability trades

//--- Global variables
int EMA_Handle;
int SellSignal = 0;
int BuySignal = 0;
datetime LastTradeTime = 0;
double LastGapLevel = 0;
bool RangeShiftDetected = false;
int CurrentPositionType = 0; // 0 = no position, 1 = buy, -1 = sell

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   // Initialize EMA indicator with a shift of 5
   EMA_Handle = iMA(_Symbol, PERIOD_CURRENT, EMAperiod, 5, MODE_EMA, PRICE_CLOSE);
   
   if(EMA_Handle == INVALID_HANDLE)
   {
      Print("Failed to create EMA indicator handle");
      return(INIT_FAILED);
   }
   
   // Check if current timeframe matches the trading rules
   ENUM_TIMEFRAMES currentTF = Period();
   if((currentTF == PERIOD_M5 && !Trade5Min) || (currentTF == PERIOD_M15 && !Trade15Min))
   {
      Print("Warning: Current timeframe is not enabled for trading in settings");
   }
   
   // Clear all indicators from the chart for clean trading environment
   ChartIndicatorDelete(0, 0, "");
   
   // Add 5 EMA indicator to the chart with shift of 5
   string indicatorName = "5 EMA";
   bool added = ChartIndicatorAdd(0, 0, iMA(_Symbol, PERIOD_CURRENT, EMAperiod, 5, MODE_EMA, PRICE_CLOSE));
   if(!added)
      Print("Failed to add 5 EMA indicator to chart: ", GetLastError());
   else
      Print("5 EMA indicator added to chart successfully (with shift of 5)");
   
   // Add chart label to show EA is running
   ObjectCreate(0, "5EMA_Label", OBJ_LABEL, 0, 0, 0);
   ObjectSetString(0, "5EMA_Label", OBJPROP_TEXT, "5EMA Strategy Active");
   ObjectSetInteger(0, "5EMA_Label", OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, "5EMA_Label", OBJPROP_XDISTANCE, 10);
   ObjectSetInteger(0, "5EMA_Label", OBJPROP_YDISTANCE, 20);
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   // Clean up indicator handle
   if(EMA_Handle != INVALID_HANDLE)
      IndicatorRelease(EMA_Handle);
      
   // Delete chart objects
   ObjectDelete(0, "5EMA_Label");
   
   // Optional: Remove the 5 EMA indicator from chart when EA is removed
   // If you want the indicator to remain after EA is removed, comment this line
   ChartIndicatorDelete(0, 0, "Moving Average(5,5)");
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // Update current position status
   UpdatePositionStatus();
   
   // Only process on new candle
   if(!IsNewCandle())
      return;
      
   // Check for gaps if enabled
   if(UseGapDetection)
      DetectGaps();
      
   // Check for range shifts if enabled
   if(UseRangeShiftDetection)
      DetectRangeShifts();
   
   // Check for entry signals
   CheckEntrySignals();
   
   // Execute trades if signals exist
   ExecuteTrades();
}

//+------------------------------------------------------------------+
//| Check if this is a new candle                                    |
//+------------------------------------------------------------------+
bool IsNewCandle()
{
   static datetime previous_time = 0;
   datetime current_time = iTime(_Symbol, Period(), 0);
   
   if(previous_time != current_time)
   {
      previous_time = current_time;
      return true;
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| Update current position status                                   |
//+------------------------------------------------------------------+
void UpdatePositionStatus()
{
   CurrentPositionType = 0; // Reset
   
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
      {
         if(PositionGetString(POSITION_SYMBOL) == _Symbol)
         {
            if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
               CurrentPositionType = 1;
            else if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL)
               CurrentPositionType = -1;
               
            // Apply trailing stop if enabled
            if(UseTrailingStop)
               ApplyTrailingStop(ticket);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Apply trailing stop to open position                             |
//+------------------------------------------------------------------+
void ApplyTrailingStop(ulong ticket)
{
   if(!PositionSelectByTicket(ticket))
      return;
      
   double currentSL = PositionGetDouble(POSITION_SL);
   double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
   double currentPrice = 0;
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   int posType = (int)PositionGetInteger(POSITION_TYPE);
   
   // Get minimum stop level in points
   int stopLevel = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   
   if(posType == POSITION_TYPE_BUY)
   {
      currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double newSL = currentPrice - TrailingStopPoints * point;
      
      // Check if new SL respects minimum stop level
      double minStopLevel = currentPrice - stopLevel * point;
      if(newSL > minStopLevel)
         newSL = minStopLevel;
      
      if(newSL > currentSL && newSL > openPrice)
      {
         MqlTradeRequest request = {};
         MqlTradeResult result = {};
         
         request.action = TRADE_ACTION_SLTP;
         request.position = ticket;
         request.symbol = _Symbol;
         request.sl = NormalizeDouble(newSL, SymbolInfoInteger(_Symbol, SYMBOL_DIGITS));
         request.tp = PositionGetDouble(POSITION_TP);
         
         if(!OrderSend(request, result))
            Print("Failed to modify SL: ", GetLastError(), " - SL: ", request.sl, ", Current Price: ", currentPrice);
      }
   }
   else if(posType == POSITION_TYPE_SELL)
   {
      currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double newSL = currentPrice + TrailingStopPoints * point;
      
      // Check if new SL respects minimum stop level
      double minStopLevel = currentPrice + stopLevel * point;
      if(newSL < minStopLevel)
         newSL = minStopLevel;
      
      if(newSL < currentSL || currentSL == 0 || (newSL < openPrice && currentSL > openPrice))
      {
         MqlTradeRequest request = {};
         MqlTradeResult result = {};
         
         request.action = TRADE_ACTION_SLTP;
         request.position = ticket;
         request.symbol = _Symbol;
         request.sl = NormalizeDouble(newSL, SymbolInfoInteger(_Symbol, SYMBOL_DIGITS));
         request.tp = PositionGetDouble(POSITION_TP);
         
         if(!OrderSend(request, result))
            Print("Failed to modify SL: ", GetLastError(), " - SL: ", request.sl, ", Current Price: ", currentPrice);
      }
   }
}


//+------------------------------------------------------------------+
//| Detect gaps between candles for high probability trades          |
//+------------------------------------------------------------------+
void DetectGaps()
{
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   if(CopyRates(_Symbol, Period(), 0, 3, rates) < 3)
      return;
      
   // Check for a gap between previous candle close and current candle open
   double gapSize = MathAbs(rates[1].close - rates[0].open);
   double avgCandleSize = (rates[1].high - rates[1].low + rates[2].high - rates[2].low) / 2;
   
   // If gap is significant (>50% of average candle size)
   if(gapSize > avgCandleSize * 0.5)
   {
      LastGapLevel = rates[1].close;
      Print("Gap detected at price: ", LastGapLevel);
   }
   else
   {
      // Reset gap level if price has moved far away
      if(MathAbs(rates[0].close - LastGapLevel) > avgCandleSize * 3)
         LastGapLevel = 0;
   }
}

//+------------------------------------------------------------------+
//| Detect range shifts (trend changes)                              |
//+------------------------------------------------------------------+
void DetectRangeShifts()
{
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   if(CopyRates(_Symbol, Period(), 0, 20, rates) < 20)
      return;
   
   int higherHighs = 0;
   int lowerLows = 0;
   
   // Count higher highs and lower lows in last 10 candles compared to previous 10
   for(int i = 0; i < 10; i++)
   {
      if(rates[i].high > rates[i+10].high)
         higherHighs++;
         
      if(rates[i].low < rates[i+10].low)
         lowerLows++;
   }
   
   // If we have a significant shift (7 or more out of 10)
   if(higherHighs >= 7 && lowerLows <= 3)
   {
      RangeShiftDetected = true;
      Print("Range shift detected: Bullish trend");
   }
   else if(lowerLows >= 7 && higherHighs <= 3)
   {
      RangeShiftDetected = true;
      Print("Range shift detected: Bearish trend");
   }
   else
   {
      // Reset after some time
      RangeShiftDetected = false;
   }
}

//+------------------------------------------------------------------+
//| Check for entry signals based on 5 EMA strategy                  |
//+------------------------------------------------------------------+
void CheckEntrySignals()
{
   // Reset signals
   SellSignal = 0;
   BuySignal = 0;
   
   // Get EMA values
   double EMABuffer[];
   ArraySetAsSeries(EMABuffer, true);
   
   if(CopyBuffer(EMA_Handle, 0, 0, 3, EMABuffer) < 3)
   {
      Print("Failed to copy EMA buffer");
      return;
   }
   
   // Get price data
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   
   if(CopyRates(_Symbol, Period(), 0, 3, rates) < 3)
   {
      Print("Failed to copy price data");
      return;
   }
   
   // Entry logic:
   // 1. Previous candle closed fully above/below 5 EMA (body not touching)
   // 2. Current candle breaks opposite direction
   
   // Check for SELL signal (on 5-minute chart)
   if(Period() == PERIOD_M5 && Trade5Min)
   {
      // Previous candle closed above EMA (body not touching)
      if(rates[1].close > EMABuffer[1] && rates[1].open > EMABuffer[1])
      {
         // Current candle breaks below the low of previous candle
         if(rates[0].low < rates[1].low)
         {
            SellSignal = 1;
            
            // Check for high probability conditions
            if((LastGapLevel > 0 && MathAbs(rates[0].close - LastGapLevel) < 10 * _Point) || 
               RangeShiftDetected)
            {
               SellSignal = 2; // High probability signal
            }
         }
      }
   }
   
   // Check for BUY signal (on 15-minute chart)
   if(Period() == PERIOD_M15 && Trade15Min)
   {
      // Previous candle closed below EMA (body not touching)
      if(rates[1].close < EMABuffer[1] && rates[1].open < EMABuffer[1])
      {
         // Current candle breaks above the high of previous candle
         if(rates[0].high > rates[1].high)
         {
            BuySignal = 1;
            
            // Check for high probability conditions
            if((LastGapLevel > 0 && MathAbs(rates[0].close - LastGapLevel) < 10 * _Point) || 
               RangeShiftDetected)
            {
               BuySignal = 2; // High probability signal
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Execute trades based on signals                                  |
//+------------------------------------------------------------------+
void ExecuteTrades()
{
   // Check if we already have a position
   if(CurrentPositionType != 0)
      return;
      
   // Check if minimum time between trades has elapsed
   if(TimeCurrent() - LastTradeTime < 300) // 5 minutes minimum
      return;
      
   MqlTradeRequest request = {};
   MqlTradeResult result = {};
   
   // Get price data for SL calculation
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   
   if(CopyRates(_Symbol, Period(), 0, 2, rates) < 2)
      return;
      
   // Execute SELL
   if(SellSignal > 0)
   {
      // Calculate position size based on signal strength
      double lotSize = NormalLots;
      
      if(SellSignal == 2) // High probability
         lotSize = HighProbLots;
      else if(SellSignal == -1) // Low confidence
         lotSize = LowConfLots;
         
      // Calculate stop loss just above the signal candle high
      double stopLoss = rates[1].high + 10 * _Point;
      double entryPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      
      // Ensure SL respects minimum stop level
      int stopLevel = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
      double minStopLevel = entryPrice + stopLevel * _Point;
      
      // If calculated SL is too close, adjust it
      if(stopLoss < minStopLevel)
         stopLoss = minStopLevel;
      
      // Calculate risk in points
      double riskPoints = stopLoss - entryPrice;
      
      // Calculate take profit based on risk:reward ratio
      double takeProfit = 0;
      if(!UseTrailingStop)
         takeProfit = entryPrice - (riskPoints * RiskRewardRatio);
      
      // Prepare trade request
      request.action = TRADE_ACTION_DEAL;
      request.symbol = _Symbol;
      request.volume = lotSize;
      request.type = ORDER_TYPE_SELL;
      request.price = entryPrice;
      request.sl = NormalizeDouble(stopLoss, SymbolInfoInteger(_Symbol, SYMBOL_DIGITS));
      request.tp = NormalizeDouble(takeProfit, SymbolInfoInteger(_Symbol, SYMBOL_DIGITS));
      request.deviation = 5;
      request.type_filling = ORDER_FILLING_FOK;
      
      // Execute the trade
      if(OrderSend(request, result))
      {
         Print("SELL Order placed successfully: ", result.order);
         LastTradeTime = TimeCurrent();
      }
      else
      {
         Print("Error placing SELL order: ", GetLastError());
      }
   }
   
   // Execute BUY
   if(BuySignal > 0)
   {
      // Calculate position size based on signal strength
      double lotSize = NormalLots;
      
      if(BuySignal == 2) // High probability
         lotSize = HighProbLots;
      else if(BuySignal == -1) // Low confidence
         lotSize = LowConfLots;
         
      // Calculate stop loss just below the signal candle low
      double stopLoss = rates[1].low - 10 * _Point;
      double entryPrice = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      
      // Ensure SL respects minimum stop level
      int stopLevel = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
      double minStopLevel = entryPrice - stopLevel * _Point;
      
      // If calculated SL is too close, adjust it
      if(stopLoss > minStopLevel)
         stopLoss = minStopLevel;
      
      // Calculate risk in points
      double riskPoints = entryPrice - stopLoss;
      
      // Calculate take profit based on risk:reward ratio
      double takeProfit = 0;
      if(!UseTrailingStop)
         takeProfit = entryPrice + (riskPoints * RiskRewardRatio);
      
      // Prepare trade request
      request.action = TRADE_ACTION_DEAL;
      request.symbol = _Symbol;
      request.volume = lotSize;
      request.type = ORDER_TYPE_BUY;
      request.price = entryPrice;
      request.sl = NormalizeDouble(stopLoss, SymbolInfoInteger(_Symbol, SYMBOL_DIGITS));
      request.tp = NormalizeDouble(takeProfit, SymbolInfoInteger(_Symbol, SYMBOL_DIGITS));
      request.deviation = 5;
      request.type_filling = ORDER_FILLING_FOK;
      
      // Execute the trade
      if(OrderSend(request, result))
      {
         Print("BUY Order placed successfully: ", result.order);
         LastTradeTime = TimeCurrent();
      }
      else
      {
         Print("Error placing BUY order: ", GetLastError());
      }
   }
}
