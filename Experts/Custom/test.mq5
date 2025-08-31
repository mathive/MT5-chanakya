//+------------------------------------------------------------------+
//|                                      BTC_Analysis_H1.mq5       |
//|                                  Copyright 2025, Your Name Here |
//|                                      https://www.yourwebsite.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, Your Name Here"
#property link      "https://www.yourwebsite.com"
#property version   "1.10"
#property description "BTC/USD Technical Analysis on 1-hour timeframe with Auto Trading"
#property strict

#include <Trade\Trade.mqh>        // Include trade functions
#include <Trade\PositionInfo.mqh> // Include position information functions

// EA magic number - a unique identifier for this EA's trades
#define EXPERT_MAGIC 987654321

// Ensure we have the trade return codes properly defined
// You can comment these out if your MQL5 version already includes these constants
#ifndef TRADE_RETCODE_DONE
#define TRADE_RETCODE_DONE 10009        // Request completed
#define TRADE_RETCODE_DONE_PARTIAL 10010 // Only part of the request completed
#define TRADE_RETCODE_REJECT 10006      // Request rejected
#define TRADE_RETCODE_CANCEL 10007      // Request canceled by trader
#define TRADE_RETCODE_PLACED 10008      // Order placed
#define TRADE_RETCODE_ERROR 10016       // Request processing error
#define TRADE_RETCODE_TIMEOUT 10004     // Request canceled by timeout
#define TRADE_RETCODE_INVALID 10013     // Invalid request
#define TRADE_RETCODE_INVALID_VOLUME 10014  // Invalid volume
#define TRADE_RETCODE_INVALID_PRICE 10015   // Invalid price
#define TRADE_RETCODE_INVALID_STOPS 10016   // Invalid stops
#define TRADE_RETCODE_TRADE_DISABLED 10017  // Trade disabled
#define TRADE_RETCODE_MARKET_CLOSED 10018   // Market closed
#define TRADE_RETCODE_NO_MONEY 10019        // Not enough money
#define TRADE_RETCODE_PRICE_CHANGED 10020   // Price changed
#define TRADE_RETCODE_PRICE_OFF 10021       // No quotes
#define TRADE_RETCODE_INVALID_EXPIRATION 10022  // Invalid order expiration
#define TRADE_RETCODE_ORDER_CHANGED 10023   // Order state changed
#define TRADE_RETCODE_TOO_MANY_REQUESTS 10024   // Too many requests
#define TRADE_RETCODE_NO_CHANGES 10025      // No changes in request
#define TRADE_RETCODE_SERVER_DISABLES_AT 10026  // Autotrading disabled by server
#define TRADE_RETCODE_CLIENT_DISABLES_AT 10027  // Autotrading disabled by client
#define TRADE_RETCODE_LOCKED 10028          // Request locked for processing
#define TRADE_RETCODE_FROZEN 10029          // Order or position frozen
#define TRADE_RETCODE_INVALID_FILL 10030    // Invalid order filling type
#define TRADE_RETCODE_CONNECTION 10031      // No connection with server
#define TRADE_RETCODE_ONLY_REAL 10032       // Operation allowed only for live accounts
#define TRADE_RETCODE_LIMIT_ORDERS 10033    // Orders limit reached
#define TRADE_RETCODE_LIMIT_VOLUME 10034    // Volume limit reached
#define TRADE_RETCODE_POSITION_CLOSED 10035 // Position already closed
#define TRADE_RETCODE_INVALID_ORDER 10036   // Invalid order
#endif

// Input parameters
input string   Symbol_Name = "BTCUSD";    // Trading symbol
input ENUM_TIMEFRAMES Timeframe = PERIOD_H1; // Trading timeframe (default 1 hour)
input int      SMA50_Period = 50;         // SMA 50 Period
input int      SMA100_Period = 100;       // SMA 100 Period
input int      EMA12_Period = 12;         // EMA 12 Period
input int      EMA26_Period = 26;         // EMA 26 Period
input int      MACD_Signal_Period = 9;    // MACD Signal Period
input int      RSI_Period = 14;           // RSI Period
input int      BB_Period = 20;            // Bollinger Bands Period
input double   BB_Deviation = 2.0;        // Bollinger Bands Deviation
input int      Support_Resistance_Period = 24; // Support/Resistance Period (adjusted for H1)
input int      MFI_Period = 14;           // Money Flow Index Period
input bool     EnableVisualization = false;  // Enable chart visualization (OFF for faster testing)
input bool     UseBuiltInIndicators = true; // Use built-in MT5 indicators instead of custom drawing

// Alert settings
input bool     EnableAlerts = true;        // Enable pop-up alerts
input bool     EnableEmailAlerts = false;   // Enable email alerts
input bool     EnablePushNotifications = false; // Enable push notifications
input bool     AlertOnlyOnce = true;       // Alert only on new signals (no repeat)

// Global variables
int handle_sma50, handle_sma100;
int handle_ema12, handle_ema26;
int handle_bb;
int handle_macd;
int handle_rsi;
int handle_mfi;

// Alert variables
datetime last_alert_time = 0;
string last_signal = "";
bool buy_signal_triggered = false;
bool sell_signal_triggered = false;
const int ALERT_COOLDOWN = 3600;  // 1 hour in seconds

// Trading variables
input bool     EnableAutoTrading = true;   // Enable automatic trading
input double   TradingVolume = 0.01;      // Trading volume (lot size)
input int      StopLoss = 0;            // Stop Loss in points (0 = no SL)
input int      TakeProfit = 0;          // Take Profit in points (0 = no TP)
input bool     ForceTradeInTester = true; // Force trading in strategy tester
CTrade         trade;                      // Trade object
ulong          lastBuyTicket = 0;         // Ticket of the last BUY position
ulong          lastSellTicket = 0;        // Ticket of the last SELL position
datetime       lastTradeTime = 0;          // Time of the last trade
const int      TRADE_COOLDOWN = 3600;      // 1 hour between trades

// Arrays for indicator values
double SMA50[], SMA100[];
double EMA12[], EMA26[];
double Upper_BB[], Middle_BB[], Lower_BB[];
double MACD[], Signal[], MACD_Histogram[];
double RSI[];
double MFI[];
double High_Rolling[], Low_Rolling[];
double Pivot, R1, S1, R2, S2;

// Store indicator names for removal
string attached_indicators[];
int attached_indicator_count = 0;

//+------------------------------------------------------------------+
//| Attach built-in indicators to the chart                          |
//+------------------------------------------------------------------+
void AttachBuiltInIndicators()
{
   // Remove previously attached indicators
   for(int i=0; i<attached_indicator_count; i++)
   {
      if(attached_indicators[i] != "")
         ChartIndicatorDelete(0, 0, attached_indicators[i]);
   }
   
   // Reset the counter
   attached_indicator_count = 0;
   ArrayResize(attached_indicators, 10);
   
   // Attach Moving Averages
   attached_indicators[attached_indicator_count++] = "SMA50";
   ChartIndicatorAdd(0, 0, iMA(Symbol(), Timeframe, SMA50_Period, 0, MODE_SMA, PRICE_CLOSE));
   
   attached_indicators[attached_indicator_count++] = "SMA100";
   ChartIndicatorAdd(0, 0, iMA(Symbol(), Timeframe, SMA100_Period, 0, MODE_SMA, PRICE_CLOSE));
   
   attached_indicators[attached_indicator_count++] = "EMA12";
   ChartIndicatorAdd(0, 0, iMA(Symbol(), Timeframe, EMA12_Period, 0, MODE_EMA, PRICE_CLOSE));
   
   attached_indicators[attached_indicator_count++] = "EMA26";
   ChartIndicatorAdd(0, 0, iMA(Symbol(), Timeframe, EMA26_Period, 0, MODE_EMA, PRICE_CLOSE));
   
   // Attach Bollinger Bands
   attached_indicators[attached_indicator_count++] = "BBands";
   ChartIndicatorAdd(0, 0, iBands(Symbol(), Timeframe, BB_Period, 0, BB_Deviation, PRICE_CLOSE));
   
   // Attach MACD (to a separate window)
   attached_indicators[attached_indicator_count++] = "MACD";
   int macd_handle = iMACD(Symbol(), Timeframe, EMA12_Period, EMA26_Period, MACD_Signal_Period, PRICE_CLOSE);
   ChartIndicatorAdd(0, 1, macd_handle); // 1 = first subwindow
   
   // Attach RSI (to a separate window)
   attached_indicators[attached_indicator_count++] = "RSI";
   int rsi_handle = iRSI(Symbol(), Timeframe, RSI_Period, PRICE_CLOSE);
   ChartIndicatorAdd(0, 2, rsi_handle); // 2 = second subwindow
   
   // Attach MFI (to a separate window)
   attached_indicators[attached_indicator_count++] = "MFI";
   int mfi_handle = iMFI(Symbol(), Timeframe, MFI_Period, VOLUME_TICK);
   ChartIndicatorAdd(0, 3, mfi_handle); // 3 = third subwindow
   
   // Display current analysis as a comment
   string recommendation = CreateRecommendations();
   Comment(recommendation);
   
   // Add pivot lines as horizontal lines on the chart
   DrawSupportResistanceLines();
}

//+------------------------------------------------------------------+
//| Draw support and resistance lines as horizontal lines            |
//+------------------------------------------------------------------+
void DrawSupportResistanceLines()
{
   // Draw pivot lines
   string name = "BTC_Analysis_Pivot";
   if(ObjectCreate(0, name, OBJ_HLINE, 0, 0, Pivot))
   {
      ObjectSetInteger(0, name, OBJPROP_COLOR, clrYellow);
      ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_SOLID);
      ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
      ObjectSetString(0, name, OBJPROP_TEXT, "Pivot");
   }
   
   name = "BTC_Analysis_R1";
   if(ObjectCreate(0, name, OBJ_HLINE, 0, 0, R1))
   {
      ObjectSetInteger(0, name, OBJPROP_COLOR, clrRed);
      ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_DASH);
      ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
      ObjectSetString(0, name, OBJPROP_TEXT, "R1");
   }
   
   name = "BTC_Analysis_R2";
   if(ObjectCreate(0, name, OBJ_HLINE, 0, 0, R2))
   {
      ObjectSetInteger(0, name, OBJPROP_COLOR, clrRed);
      ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_DASH);
      ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
      ObjectSetString(0, name, OBJPROP_TEXT, "R2");
   }
   
   name = "BTC_Analysis_S1";
   if(ObjectCreate(0, name, OBJ_HLINE, 0, 0, S1))
   {
      ObjectSetInteger(0, name, OBJPROP_COLOR, clrGreen);
      ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_DASH);
      ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
      ObjectSetString(0, name, OBJPROP_TEXT, "S1");
   }
   
   name = "BTC_Analysis_S2";
   if(ObjectCreate(0, name, OBJ_HLINE, 0, 0, S2))
   {
      ObjectSetInteger(0, name, OBJPROP_COLOR, clrGreen);
      ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_DASH);
      ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
      ObjectSetString(0, name, OBJPROP_TEXT, "S2");
   }
}

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   // Ensure we have the correct symbol
   string current_symbol = Symbol();
   if(StringFind(current_symbol, "BTC") < 0 && StringFind(current_symbol, "btc") < 0)
   {
      Print("Warning: This EA is designed for BTCUSD but is running on ", current_symbol);
      // We'll continue anyway but with a warning
   }
   
   Print("Initializing indicators for ", Symbol(), " on ", EnumToString(Timeframe), " timeframe");
   
   // Initialize indicator handles
   handle_sma50 = iMA(Symbol(), Timeframe, SMA50_Period, 0, MODE_SMA, PRICE_CLOSE);
   if(handle_sma50 == INVALID_HANDLE) {
      Print("Failed to create SMA50 indicator handle. Error code: ", GetLastError());
      return INIT_FAILED;
   }
   
   handle_sma100 = iMA(Symbol(), Timeframe, SMA100_Period, 0, MODE_SMA, PRICE_CLOSE);
   if(handle_sma100 == INVALID_HANDLE) {
      Print("Failed to create SMA100 indicator handle. Error code: ", GetLastError());
      return INIT_FAILED;
   }
   
   handle_ema12 = iMA(Symbol(), Timeframe, EMA12_Period, 0, MODE_EMA, PRICE_CLOSE);
   if(handle_ema12 == INVALID_HANDLE) {
      Print("Failed to create EMA12 indicator handle. Error code: ", GetLastError());
      return INIT_FAILED;
   }
   
   handle_ema26 = iMA(Symbol(), Timeframe, EMA26_Period, 0, MODE_EMA, PRICE_CLOSE);
   if(handle_ema26 == INVALID_HANDLE) {
      Print("Failed to create EMA26 indicator handle. Error code: ", GetLastError());
      return INIT_FAILED;
   }
   
   handle_bb = iBands(Symbol(), Timeframe, BB_Period, 0, BB_Deviation, PRICE_CLOSE);
   if(handle_bb == INVALID_HANDLE) {
      Print("Failed to create Bollinger Bands indicator handle. Error code: ", GetLastError());
      return INIT_FAILED;
   }
   
   handle_macd = iMACD(Symbol(), Timeframe, EMA12_Period, EMA26_Period, MACD_Signal_Period, PRICE_CLOSE);
   if(handle_macd == INVALID_HANDLE) {
      Print("Failed to create MACD indicator handle. Error code: ", GetLastError());
      return INIT_FAILED;
   }
   
   handle_rsi = iRSI(Symbol(), Timeframe, RSI_Period, PRICE_CLOSE);
   if(handle_rsi == INVALID_HANDLE) {
      Print("Failed to create RSI indicator handle. Error code: ", GetLastError());
      return INIT_FAILED;
   }
   
   handle_mfi = iMFI(Symbol(), Timeframe, MFI_Period, VOLUME_TICK);
   if(handle_mfi == INVALID_HANDLE) {
      Print("Failed to create MFI indicator handle. Error code: ", GetLastError());
      return INIT_FAILED;
   }
   
   // Clean up any existing chart objects created by this EA
   ObjectsDeleteAll(0, "BTC_Analysis_");
   
   // Initialize alert variables
   last_alert_time = 0;
   last_signal = "";
   buy_signal_triggered = false;
   sell_signal_triggered = false;
   
   // Initialize trade variables
   lastTradeTime = 0;
   lastBuyTicket = 0;
   lastSellTicket = 0;
   
   // Configure trade settings
   trade.SetExpertMagicNumber(123456); // Unique identifier for this EA's trades
   trade.SetMarginMode();
   trade.SetTypeFillingBySymbol(Symbol());
   trade.SetDeviationInPoints(10); // Acceptable slippage in points
   
   // In Strategy Tester, force an initial trade to test functionality
   if(MQLInfoInteger(MQL_TESTER) && ForceTradeInTester) {
      Print("Strategy Tester detected - Will force trades during testing");
      ExecuteTrade("BUY"); // Execute an initial test trade
   }
   
   // Check trading settings
   Print("==== Trading Settings ====");
   Print("AutoTrading enabled: ", EnableAutoTrading ? "Yes" : "No");
   Print("Trade allowed by terminal: ", MQLInfoInteger(MQL_TRADE_ALLOWED) ? "Yes" : "No");
   Print("Symbol: ", Symbol(), ", Lot size: ", TradingVolume);
   Print("Stop Loss: ", StopLoss, " points, Take Profit: ", TakeProfit, " points");
   Print("=======================");
   
   Print("All indicators initialized successfully");
   
   // Check if indicators were created successfully
   if(handle_sma50 == INVALID_HANDLE || handle_sma100 == INVALID_HANDLE || 
      handle_ema12 == INVALID_HANDLE || handle_ema26 == INVALID_HANDLE || 
      handle_bb == INVALID_HANDLE || handle_macd == INVALID_HANDLE || 
      handle_rsi == INVALID_HANDLE || handle_mfi == INVALID_HANDLE)
   {
      Print("Failed to create indicators");
      return(INIT_FAILED);
   }
   
   // Allocate arrays for indicator data
   ArraySetAsSeries(SMA50, true);
   ArraySetAsSeries(SMA100, true);
   ArraySetAsSeries(EMA12, true);
   ArraySetAsSeries(EMA26, true);
   ArraySetAsSeries(Upper_BB, true);
   ArraySetAsSeries(Middle_BB, true);
   ArraySetAsSeries(Lower_BB, true);
   ArraySetAsSeries(MACD, true);
   ArraySetAsSeries(Signal, true);
   ArraySetAsSeries(MACD_Histogram, true);
   ArraySetAsSeries(RSI, true);
   ArraySetAsSeries(MFI, true);
   ArraySetAsSeries(High_Rolling, true);
   ArraySetAsSeries(Low_Rolling, true);
   
   // Initialize arrays with at least one element to avoid array out of range errors
   ArrayResize(SMA50, 100);
   ArrayResize(SMA100, 100);
   ArrayResize(EMA12, 100);
   ArrayResize(EMA26, 100);
   ArrayResize(Upper_BB, 100);
   ArrayResize(Middle_BB, 100);
   ArrayResize(Lower_BB, 100);
   ArrayResize(MACD, 100);
   ArrayResize(Signal, 100);
   ArrayResize(MACD_Histogram, 100);
   ArrayResize(RSI, 100);
   ArrayResize(MFI, 100);
   ArrayResize(High_Rolling, 100);
   ArrayResize(Low_Rolling, 100);
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   Print("Deinitializing EA with reason code: ", reason);
   
   // Delete chart objects created by this EA
   ObjectsDeleteAll(0, "BTC_Analysis_");
   
   // Remove attached indicators
   if(UseBuiltInIndicators)
   {
      for(int i=0; i<attached_indicator_count; i++)
      {
         if(attached_indicators[i] != "")
         {
            Print("Removing indicator: ", attached_indicators[i]);
            ChartIndicatorDelete(0, 0, attached_indicators[i]);
            
            // Try to remove from subwindows as well
            for(int subwin=1; subwin<=3; subwin++)
               ChartIndicatorDelete(0, subwin, attached_indicators[i]);
         }
      }
   }
   
   // Release indicator handles
   if(handle_sma50 != INVALID_HANDLE)
      IndicatorRelease(handle_sma50);
   if(handle_sma100 != INVALID_HANDLE)
      IndicatorRelease(handle_sma100);
   if(handle_ema12 != INVALID_HANDLE)
      IndicatorRelease(handle_ema12);
   if(handle_ema26 != INVALID_HANDLE)
      IndicatorRelease(handle_ema26);
   if(handle_bb != INVALID_HANDLE)
      IndicatorRelease(handle_bb);
   if(handle_macd != INVALID_HANDLE)
      IndicatorRelease(handle_macd);
   if(handle_rsi != INVALID_HANDLE)
      IndicatorRelease(handle_rsi);
   if(handle_mfi != INVALID_HANDLE)
      IndicatorRelease(handle_mfi);
      
   Print("All indicators released and chart objects deleted");
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // Process only on new bar (optimization for testing)
   static datetime last_bar_time = 0;
   datetime current_bar_time = iTime(Symbol(), Timeframe, 0);
   
   // Only process on a new bar or if it's the first time running
   if(current_bar_time == last_bar_time && last_bar_time != 0)
      return;
   
   last_bar_time = current_bar_time;
      
   // Calculate the available data - reduced number of bars for faster testing
   int available_bars = MathMin(iBars(Symbol(), Timeframe), 50);
   if(available_bars < 10) // Reduced minimum requirement
   {
      Print("Not enough historical data. Need at least 10 bars, have ", available_bars);
      return;
   }
   
   // Copy indicator data - more robust error handling
   bool success = true;
   
   if(CopyBuffer(handle_sma50, 0, 0, available_bars, SMA50) <= 0)
   {
      Print("Failed to copy SMA50 data: ", GetLastError());
      success = false;
   }
   
   if(CopyBuffer(handle_sma100, 0, 0, available_bars, SMA100) <= 0)
   {
      Print("Failed to copy SMA100 data: ", GetLastError());
      success = false;
   }
   
   if(CopyBuffer(handle_ema12, 0, 0, available_bars, EMA12) <= 0)
   {
      Print("Failed to copy EMA12 data: ", GetLastError());
      success = false;
   }
   
   if(CopyBuffer(handle_ema26, 0, 0, available_bars, EMA26) <= 0)
   {
      Print("Failed to copy EMA26 data: ", GetLastError());
      success = false;
   }
   
   if(CopyBuffer(handle_bb, 0, 0, available_bars, Upper_BB) <= 0)
   {
      Print("Failed to copy BB Upper data: ", GetLastError());
      success = false;
   }
   
   if(CopyBuffer(handle_bb, 1, 0, available_bars, Middle_BB) <= 0)
   {
      Print("Failed to copy BB Middle data: ", GetLastError());
      success = false;
   }
   
   if(CopyBuffer(handle_bb, 2, 0, available_bars, Lower_BB) <= 0)
   {
      Print("Failed to copy BB Lower data: ", GetLastError());
      success = false;
   }
   
   if(CopyBuffer(handle_macd, 0, 0, available_bars, MACD) <= 0)
   {
      Print("Failed to copy MACD data: ", GetLastError());
      success = false;
   }
   
   if(CopyBuffer(handle_macd, 1, 0, available_bars, Signal) <= 0)
   {
      Print("Failed to copy MACD Signal data: ", GetLastError());
      success = false;
   }
   
   // For MACD Histogram, we can calculate it manually if buffer 2 is not available
   int result = CopyBuffer(handle_macd, 2, 0, available_bars, MACD_Histogram);
   if(result <= 0)
   {
      Print("Failed to copy MACD Histogram data: ", GetLastError());
      Print("Calculating MACD Histogram manually as MACD - Signal");
      
      // Calculate the histogram manually as the difference between MACD and Signal
      for(int i=0; i<ArraySize(MACD) && i<ArraySize(Signal); i++)
      {
         if(i < ArraySize(MACD_Histogram))
            MACD_Histogram[i] = MACD[i] - Signal[i];
      }
   }
   
   if(CopyBuffer(handle_rsi, 0, 0, available_bars, RSI) <= 0)
   {
      Print("Failed to copy RSI data: ", GetLastError());
      success = false;
   }
   
   if(CopyBuffer(handle_mfi, 0, 0, available_bars, MFI) <= 0)
   {
      Print("Failed to copy MFI data: ", GetLastError());
      success = false;
   }
   
   if(!success)
   {
      Print("Some indicator data could not be copied. Analysis may be incomplete.");
      
      // Initialize arrays with default values if we had copying errors
      if(ArraySize(MACD_Histogram) < 1)
      {
         ArrayResize(MACD_Histogram, available_bars);
         ArrayFill(MACD_Histogram, 0, available_bars, 0.0);
      }
      
      if(ArraySize(RSI) < 1)
      {
         ArrayResize(RSI, available_bars);
         ArrayFill(RSI, 0, available_bars, 50.0);  // Neutral value
      }
      
      if(ArraySize(MFI) < 1)
      {
         ArrayResize(MFI, available_bars);
         ArrayFill(MFI, 0, available_bars, 50.0);  // Neutral value
      }
   }
   
   // Continue only if we have sufficient data
   int bars_in_history = MathMin(ArraySize(SMA50), ArraySize(SMA100));
   if(bars_in_history < 2)
   {
      Print("Insufficient historical data for calculations");
      Comment("Waiting for sufficient historical data...\nPlease ensure BTCUSD data is available in your terminal.");
      return;
   }

   // Calculate support and resistance levels
   CalculateSupportResistance();
   
   // Draw all indicators if visualization is enabled
   if(EnableVisualization)
   {
      if(UseBuiltInIndicators)
         AttachBuiltInIndicators();
      else
         DrawIndicators();
   }
   
   // Generate recommendations
   string recommendation = CreateRecommendations();
   
   // Display the recommendation on the chart (simple text is faster than full formatting)
   string signalType = GetSignalType();
   string short_recommendation = "BTC/USD: " + signalType;
   Comment(short_recommendation);
   
   // In Strategy Tester, force trading if enabled
   static datetime last_tester_trade = 0;
   datetime current_time = TimeCurrent();
   
   if(MQLInfoInteger(MQL_TESTER) && ForceTradeInTester && current_time - last_tester_trade > 3600*4) {
      if(signalType == "BUY" || signalType == "SELL") {
         Print("FORCING ", signalType, " TRADE IN TESTER");
         ExecuteTrade(signalType);
         last_tester_trade = current_time;
      }
   }
   
   Print("Signal generation - Quick signal: ", signalType, ", Full recommendation: ", 
         (recommendation.Length() > 100 ? StringSubstr(recommendation, 0, 100) + "..." : recommendation));
   
   // Skip file saving during testing for speed
   static datetime last_save_time = 0;
   // We already have current_time defined above, reuse it
   
   // Only save files in live mode, not during testing
   if(!MQLInfoInteger(MQL_TESTER) && current_time - last_save_time > 86400) // 86400 seconds = 1 day
   {
      SavePDF(recommendation);
      last_save_time = current_time;
   }
}

//+------------------------------------------------------------------+
//| Calculate support and resistance levels                          |
//+------------------------------------------------------------------+
void CalculateSupportResistance()
{
   static datetime last_calc_time = 0;
   datetime current_time = TimeCurrent();
   
   // Only recalculate every 10 minutes to save processing time during testing
   if(current_time - last_calc_time < 600 && last_calc_time != 0)
      return;
      
   last_calc_time = current_time;
   
   // Get price data - reduced period for faster calculation
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   int calc_period = MathMin(Support_Resistance_Period, 15); // Use smaller period during testing
   int copied = CopyRates(Symbol(), Timeframe, 0, calc_period+1, rates);
   
   if(copied <= 0)
   {
      Print("Failed to copy price data for support/resistance calculation");
      return;
   }
   
   // Safety check - make sure we have at least some data
   if(ArraySize(rates) < 1)
   {
      Print("Insufficient price data for support/resistance calculation");
      return;
   }
   
   // Initialize/resize High_Rolling and Low_Rolling arrays
   ArrayResize(High_Rolling, 1);
   ArrayResize(Low_Rolling, 1);
   
   // Calculate rolling high/low
   double high_max = rates[0].high;
   double low_min = rates[0].low;
   
   // Only process as many bars as we actually have, up to Support_Resistance_Period
   int bars_to_process = MathMin(ArraySize(rates), Support_Resistance_Period);
   
   for(int i=0; i<bars_to_process; i++)
   {
      if(rates[i].high > high_max) high_max = rates[i].high;
      if(rates[i].low < low_min) low_min = rates[i].low;
   }
   
   High_Rolling[0] = high_max;
   Low_Rolling[0] = low_min;
   
   // Calculate pivot points
   // Make sure we have at least 2 elements in the rates array
   if(ArraySize(rates) > 1)
   {
      Pivot = (High_Rolling[0] + Low_Rolling[0] + rates[1].close) / 3;
      R1 = 2 * Pivot - Low_Rolling[0];
      S1 = 2 * Pivot - High_Rolling[0];
      R2 = Pivot + (High_Rolling[0] - Low_Rolling[0]);
      S2 = Pivot - (High_Rolling[0] - Low_Rolling[0]);
   }
   else
   {
      // If we only have one element, use current close price instead
      Pivot = (High_Rolling[0] + Low_Rolling[0] + rates[0].close) / 3;
      R1 = 2 * Pivot - Low_Rolling[0];
      S1 = 2 * Pivot - High_Rolling[0];
      R2 = Pivot + (High_Rolling[0] - Low_Rolling[0]);
      S2 = Pivot - (High_Rolling[0] - Low_Rolling[0]);
      Print("Warning: Limited price data available for pivot calculation");
   }
   
   // Draw horizontal lines for support and resistance
   ObjectDelete(0, "R1");
   ObjectDelete(0, "R2");
   ObjectDelete(0, "S1");
   ObjectDelete(0, "S2");
   
   ObjectCreate(0, "R1", OBJ_HLINE, 0, 0, R1);
   ObjectCreate(0, "R2", OBJ_HLINE, 0, 0, R2);
   ObjectCreate(0, "S1", OBJ_HLINE, 0, 0, S1);
   ObjectCreate(0, "S2", OBJ_HLINE, 0, 0, S2);
   
   ObjectSetInteger(0, "R1", OBJPROP_COLOR, clrRed);
   ObjectSetInteger(0, "R2", OBJPROP_COLOR, clrRed);
   ObjectSetInteger(0, "S1", OBJPROP_COLOR, clrGreen);
   ObjectSetInteger(0, "S2", OBJPROP_COLOR, clrGreen);
   
   ObjectSetInteger(0, "R1", OBJPROP_STYLE, STYLE_DASH);
   ObjectSetInteger(0, "R2", OBJPROP_STYLE, STYLE_DASHDOT);
   ObjectSetInteger(0, "S1", OBJPROP_STYLE, STYLE_DASH);
   ObjectSetInteger(0, "S2", OBJPROP_STYLE, STYLE_DASHDOT);
   
   ObjectSetInteger(0, "R1", OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, "R2", OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, "S1", OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, "S2", OBJPROP_WIDTH, 1);
}

//+------------------------------------------------------------------+
//| Create recommendations based on technical indicators             |
//+------------------------------------------------------------------+
string CreateRecommendations()
{
   string recommendation_text = "";
   
   // Current price
   double price = SymbolInfoDouble(Symbol(), SYMBOL_BID);
   
   // Moving Averages
   bool sma50_above_sma100 = SMA50[0] > SMA100[0];
   bool sma50_cross_sma100 = SMA50[1] < SMA100[1] && sma50_above_sma100;
   string sma_direction = (sma50_above_sma100) ? "upwards" : "downwards";
   string cross_direction = (sma50_above_sma100) ? "above" : "below";

   // MACD
   bool macd_above_signal = MACD[0] > Signal[0];
   bool macd_cross_signal = MACD[1] < Signal[1] && macd_above_signal;
   string signal_direction = (macd_above_signal) ? "above" : "below";
   
   // RSI and MFI values
   double rsi = RSI[0];
   double mfi = MFI[0];
   
   // Bollinger Bands
   double upper_band = Upper_BB[0];
   double lower_band = Lower_BB[0];
   double middle_band = Middle_BB[0];
   
   // Build recommendation text
   recommendation_text += "BTC/USD Analysis\n";
   recommendation_text += "-------------------\n\n";
   recommendation_text += StringFormat("1. Support Levels: S1: %.2f, S2: %.2f\n", S1, S2);
   recommendation_text += StringFormat("2. Resistance Levels: R1: %.2f, R2: %.2f\n", R1, R2);
   recommendation_text += StringFormat("3. The SMA50 is %s the SMA100, indicating a(n) %s trend.\n", 
                          cross_direction, sma_direction);
   recommendation_text += StringFormat("4. MACD line is %s the Signal line.\n", signal_direction);
   recommendation_text += StringFormat("5. RSI: %.2f\n", rsi);
   recommendation_text += StringFormat("6. MFI: %.2f\n", mfi);
   recommendation_text += StringFormat("7. Price: %.2f, Upper BB: %.2f, Middle BB: %.2f, Lower BB: %.2f\n", 
                          price, upper_band, middle_band, lower_band);
   
   // Calculate confidence levels for each condition
   double sma_confidence = (sma50_cross_sma100) ? 0.8 : 0.0;
   double macd_confidence = (macd_cross_signal) ? 0.7 : 0.0;
   double rsi_confidence = (rsi < 30) ? 0.6 : 0.0;
   double mfi_confidence = (mfi < 20) ? 0.5 : 0.0;
   double upper_band_confidence = (price > upper_band) ? 0.8 : 0.0;
   double lower_band_confidence = (price < lower_band) ? 0.8 : 0.0;
   
   // Calculate overall confidence level
   double confidence_array[6] = {sma_confidence, macd_confidence, rsi_confidence, mfi_confidence, 
                              upper_band_confidence, lower_band_confidence};
   double sum = 0;
   int count = 0;
   
   for(int i=0; i<6; i++)
   {
      if(confidence_array[i] > 0)
      {
         sum += confidence_array[i];
         count++;
      }
   }
   
   double confidence_level = (count > 0) ? (sum / count) : 0;
   
   // Determine recommendation based on highest confidence level
   string final_recommendation = "HOLD";
   bool strong_signal = false;
   
   if(sma50_cross_sma100)
   {
      final_recommendation = "BUY";
      strong_signal = true;
   }
   else if(macd_cross_signal)
   {
      final_recommendation = "BUY";
      strong_signal = true;
   }
   else if(rsi < 30)
   {
      final_recommendation = "BUY";
      strong_signal = true;
   }
   else if(mfi < 20)
   {
      final_recommendation = "BUY";
      strong_signal = true;
   }
   else if(price > upper_band)
   {
      final_recommendation = "SELL";
      strong_signal = true;
   }
   else if(price < lower_band)
   {
      final_recommendation = "BUY";
      strong_signal = true;
   }
   else
   {
      if(confidence_level > 0)
      {
         final_recommendation = (confidence_level >= 0.6) ? "BUY" : "SELL";
         strong_signal = (confidence_level >= 0.7);
      }
   }
   
   // Forcibly execute trade on strong signals
   static datetime last_force_trade = 0;
   datetime current_time = TimeCurrent();
   
   // Only force trade once per hour and on strong signals
   if(strong_signal && current_time - last_force_trade > 3600 && 
      (final_recommendation != last_signal || !AlertOnlyOnce))
   {
      Print("*** STRONG SIGNAL DETECTED: ", final_recommendation, " ***");
      ExecuteTrade(final_recommendation);
      last_force_trade = current_time;
   }
   
   // Add recommendation and confidence level to text
   recommendation_text += "\nRecommendation: " + final_recommendation;
   recommendation_text += StringFormat("\nConfidence Level: %.0f%%", confidence_level * 100);
   
   // Handle alerts
   if(EnableAlerts && CanSendAlert())
   {
      string symbol_name = Symbol();
      string timeframe_str = EnumToString(Timeframe);
      string alert_message = symbol_name + " " + timeframe_str + ": ";
      bool new_signal = false;
      
      if(final_recommendation == "BUY" && (!AlertOnlyOnce || !buy_signal_triggered))
      {
         alert_message += "BUY Signal - " + StringFormat("Confidence: %.0f%%", confidence_level * 100);
         buy_signal_triggered = true;
         sell_signal_triggered = false;
         new_signal = true;
      }
      else if(final_recommendation == "SELL" && (!AlertOnlyOnce || !sell_signal_triggered))
      {
         alert_message += "SELL Signal - " + StringFormat("Confidence: %.0f%%", confidence_level * 100);
         sell_signal_triggered = true;
         buy_signal_triggered = false;
         new_signal = true;
      }
      
      // Send the alert if it's a new signal
      if(new_signal && final_recommendation != last_signal)
      {
         SendAlerts(final_recommendation, alert_message);
         last_signal = final_recommendation;
         
         // Execute trade based on the recommendation
         if(final_recommendation == "BUY" || final_recommendation == "SELL")
         {
            ExecuteTrade(final_recommendation);
         }
      }
   }
   
   return recommendation_text;
}

//+------------------------------------------------------------------+
//| Draw indicator values on the chart                               |
//+------------------------------------------------------------------+
void DrawIndicators()
{
   // Get historical data to plot indicator lines
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   int copied = CopyRates(Symbol(), Timeframe, 0, 100, rates); // Get last 100 bars
   
   if(copied <= 0)
   {
      Print("Failed to copy price data for indicator drawing");
      return;
   }
   
   // Clear existing objects
   ClearIndicatorObjects();
   
   // Create sub-windows for different indicators
   // Main price chart is window 0, we'll create MACD, RSI, MFI windows
   
   // Draw SMA and EMA lines on main chart (window 0)
   DrawMALines(rates);
   
   // Draw Bollinger Bands on main chart (window 0)
   DrawBollingerBands(rates);
   
   // Draw MACD histogram and signal lines
   DrawMACDLines(rates);
   
   // Draw RSI line with overbought/oversold levels
   DrawRSILines(rates);
   
   // Draw MFI line with overbought/oversold levels
   DrawMFILines(rates);
   
   // Draw labels for current values
   DrawValueLabels();
   
   // Force chart redraw
   ChartRedraw();
}

//+------------------------------------------------------------------+
//| Clear all indicator objects from the chart                       |
//+------------------------------------------------------------------+
void ClearIndicatorObjects()
{
   // Delete objects by prefix to avoid removing support/resistance lines
   string prefixes[] = {"SMA50_", "SMA100_", "EMA12_", "EMA26_", 
                       "BB_Upper_", "BB_Middle_", "BB_Lower_",
                       "MACD_", "Signal_", "RSI_", "MFI_", 
                       "RSI_OB", "RSI_OS", "MFI_OB", "MFI_OS", "ValueLabel_"};
   
   for(int p = 0; p < ArraySize(prefixes); p++)
   {
      string prefix = prefixes[p];
      for(int i = ObjectsTotal(0) - 1; i >= 0; i--)
      {
         string name = ObjectName(0, i);
         if(StringSubstr(name, 0, StringLen(prefix)) == prefix)
            ObjectDelete(0, name);
      }
   }
}

//+------------------------------------------------------------------+
//| Draw Moving Average lines on the chart                           |
//+------------------------------------------------------------------+
void DrawMALines(MqlRates &rates[])
{
   // Get time for x-axis
   datetime times[];
   ArraySetAsSeries(times, true);
   CopyTime(Symbol(), Timeframe, 0, 100, times);
   
   // Draw SMA50
   for(int i = 1; i < 100 && i < ArraySize(times); i++)
   {
      if(SMA50[i] == EMPTY_VALUE || SMA50[i-1] == EMPTY_VALUE)
         continue;
         
      string name = "BTC_Analysis_SMA50_" + IntegerToString(i);
      ObjectCreate(0, name, OBJ_TREND, 0, times[i], SMA50[i], times[i-1], SMA50[i-1]);
      ObjectSetInteger(0, name, OBJPROP_COLOR, clrBlue);
      ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_SOLID);
      ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
      ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, false);
   }
   
   // Draw SMA100
   for(int i = 1; i < 100 && i < ArraySize(times); i++)
   {
      if(SMA100[i] == EMPTY_VALUE || SMA100[i-1] == EMPTY_VALUE)
         continue;
         
      string name = "BTC_Analysis_SMA100_" + IntegerToString(i);
      ObjectCreate(0, name, OBJ_TREND, 0, times[i], SMA100[i], times[i-1], SMA100[i-1]);
      ObjectSetInteger(0, name, OBJPROP_COLOR, clrMagenta);
      ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_SOLID);
      ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
      ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, false);
   }
   
   // Draw EMA12
   for(int i = 1; i < 100 && i < ArraySize(times); i++)
   {
      if(EMA12[i] == EMPTY_VALUE || EMA12[i-1] == EMPTY_VALUE)
         continue;
         
      string name = "BTC_Analysis_EMA12_" + IntegerToString(i);
      ObjectCreate(0, name, OBJ_TREND, 0, times[i], EMA12[i], times[i-1], EMA12[i-1]);
      ObjectSetInteger(0, name, OBJPROP_COLOR, clrGreen);
      ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_SOLID);
      ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
      ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, false);
   }
   
   // Draw EMA26
   for(int i = 1; i < 100 && i < ArraySize(times); i++)
   {
      if(EMA26[i] == EMPTY_VALUE || EMA26[i-1] == EMPTY_VALUE)
         continue;
         
      string name = "BTC_Analysis_EMA26_" + IntegerToString(i);
      ObjectCreate(0, name, OBJ_TREND, 0, times[i], EMA26[i], times[i-1], EMA26[i-1]);
      ObjectSetInteger(0, name, OBJPROP_COLOR, clrRed);
      ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_SOLID);
      ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
      ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, false);
   }
   
   // Add a legend for MAs
   ObjectCreate(0, "BTC_Analysis_ValueLabel_SMA50", OBJ_LABEL, 0, 0, 0);
   ObjectSetString(0, "BTC_Analysis_ValueLabel_SMA50", OBJPROP_TEXT, "SMA50: " + DoubleToString(SMA50[0], 2));
   ObjectSetInteger(0, "BTC_Analysis_ValueLabel_SMA50", OBJPROP_COLOR, clrBlue);
   ObjectSetInteger(0, "BTC_Analysis_ValueLabel_SMA50", OBJPROP_CORNER, CORNER_RIGHT_UPPER);
   ObjectSetInteger(0, "BTC_Analysis_ValueLabel_SMA50", OBJPROP_XDISTANCE, 150);
   ObjectSetInteger(0, "BTC_Analysis_ValueLabel_SMA50", OBJPROP_YDISTANCE, 20);
   
   ObjectCreate(0, "BTC_Analysis_ValueLabel_SMA100", OBJ_LABEL, 0, 0, 0);
   ObjectSetString(0, "BTC_Analysis_ValueLabel_SMA100", OBJPROP_TEXT, "SMA100: " + DoubleToString(SMA100[0], 2));
   ObjectSetInteger(0, "BTC_Analysis_ValueLabel_SMA100", OBJPROP_COLOR, clrMagenta);
   ObjectSetInteger(0, "BTC_Analysis_ValueLabel_SMA100", OBJPROP_CORNER, CORNER_RIGHT_UPPER);
   ObjectSetInteger(0, "BTC_Analysis_ValueLabel_SMA100", OBJPROP_XDISTANCE, 150);
   ObjectSetInteger(0, "BTC_Analysis_ValueLabel_SMA100", OBJPROP_YDISTANCE, 40);
}

//+------------------------------------------------------------------+
//| Draw Bollinger Bands on the chart                                |
//+------------------------------------------------------------------+
void DrawBollingerBands(MqlRates &rates[])
{
   // Get time for x-axis
   datetime times[];
   ArraySetAsSeries(times, true);
   CopyTime(Symbol(), Timeframe, 0, 100, times);
   
   // Draw Upper Band
   for(int i = 1; i < 100 && i < ArraySize(times); i++)
   {
      if(Upper_BB[i] == EMPTY_VALUE || Upper_BB[i-1] == EMPTY_VALUE)
         continue;
         
      string name = "BTC_Analysis_BB_Upper_" + IntegerToString(i);
      ObjectCreate(0, name, OBJ_TREND, 0, times[i], Upper_BB[i], times[i-1], Upper_BB[i-1]);
      ObjectSetInteger(0, name, OBJPROP_COLOR, clrCyan);
      ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_DOT);
      ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
      ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, false);
   }
   
   // Draw Middle Band
   for(int i = 1; i < 100 && i < ArraySize(times); i++)
   {
      if(Middle_BB[i] == EMPTY_VALUE || Middle_BB[i-1] == EMPTY_VALUE)
         continue;
         
      string name = "BTC_Analysis_BB_Middle_" + IntegerToString(i);
      ObjectCreate(0, name, OBJ_TREND, 0, times[i], Middle_BB[i], times[i-1], Middle_BB[i-1]);
      ObjectSetInteger(0, name, OBJPROP_COLOR, clrCyan);
      ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_SOLID);
      ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
      ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, false);
   }
   
   // Draw Lower Band
   for(int i = 1; i < 100 && i < ArraySize(times); i++)
   {
      if(Lower_BB[i] == EMPTY_VALUE || Lower_BB[i-1] == EMPTY_VALUE)
         continue;
         
      string name = "BTC_Analysis_BB_Lower_" + IntegerToString(i);
      ObjectCreate(0, name, OBJ_TREND, 0, times[i], Lower_BB[i], times[i-1], Lower_BB[i-1]);
      ObjectSetInteger(0, name, OBJPROP_COLOR, clrCyan);
      ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_DOT);
      ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
      ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, false);
   }
   
   // Add BB values to chart
   ObjectCreate(0, "BTC_Analysis_ValueLabel_BB", OBJ_LABEL, 0, 0, 0);
   ObjectSetString(0, "BTC_Analysis_ValueLabel_BB", OBJPROP_TEXT, "BB Upper: " + DoubleToString(Upper_BB[0], 2) + 
                  " Middle: " + DoubleToString(Middle_BB[0], 2) + " Lower: " + DoubleToString(Lower_BB[0], 2));
   ObjectSetInteger(0, "BTC_Analysis_ValueLabel_BB", OBJPROP_COLOR, clrCyan);
   ObjectSetInteger(0, "BTC_Analysis_ValueLabel_BB", OBJPROP_CORNER, CORNER_RIGHT_UPPER);
   ObjectSetInteger(0, "BTC_Analysis_ValueLabel_BB", OBJPROP_XDISTANCE, 150);
   ObjectSetInteger(0, "BTC_Analysis_ValueLabel_BB", OBJPROP_YDISTANCE, 60);
}

//+------------------------------------------------------------------+
//| Draw MACD lines on the chart                                     |
//+------------------------------------------------------------------+
void DrawMACDLines(MqlRates &rates[])
{
   // Create subwindow for MACD if it doesn't exist
   int macd_window = ChartWindowFind(0, "MACD");
   if(macd_window == -1)
   {
      // MACD indicator might be added to chart - we'll use object drawing instead
      macd_window = 0;  // Default to main window if subwindow not found
   }
   
   // Get time for x-axis
   datetime times[];
   ArraySetAsSeries(times, true);
   CopyTime(Symbol(), Timeframe, 0, 100, times);
   
   // Calculate vertical scaling for MACD to fit in a subwindow
   double macd_max = MACD[ArrayMaximum(MACD, 0, 100)];
   double macd_min = MACD[ArrayMinimum(MACD, 0, 100)];
   double signal_max = Signal[ArrayMaximum(Signal, 0, 100)];
   double signal_min = Signal[ArrayMinimum(Signal, 0, 100)];
   double hist_max = MACD_Histogram[ArrayMaximum(MACD_Histogram, 0, 100)];
   double hist_min = MACD_Histogram[ArrayMinimum(MACD_Histogram, 0, 100)];
   
   double max_value = MathMax(MathMax(macd_max, signal_max), hist_max);
   double min_value = MathMin(MathMin(macd_min, signal_min), hist_min);
   
   double range = max_value - min_value;
   
   // Create zero line
   ObjectCreate(0, "BTC_Analysis_MACD_Zero", OBJ_HLINE, macd_window, 0, 0);
   ObjectSetInteger(0, "BTC_Analysis_MACD_Zero", OBJPROP_COLOR, clrGray);
   ObjectSetInteger(0, "BTC_Analysis_MACD_Zero", OBJPROP_STYLE, STYLE_DOT);
   ObjectSetInteger(0, "BTC_Analysis_MACD_Zero", OBJPROP_WIDTH, 1);
   
   // Draw MACD Line
   for(int i = 1; i < 100 && i < ArraySize(times); i++)
   {
      if(MACD[i] == EMPTY_VALUE || MACD[i-1] == EMPTY_VALUE)
         continue;
         
      string name = "BTC_Analysis_MACD_Line_" + IntegerToString(i);
      ObjectCreate(0, name, OBJ_TREND, macd_window, times[i], MACD[i], times[i-1], MACD[i-1]);
      ObjectSetInteger(0, name, OBJPROP_COLOR, clrBlue);
      ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_SOLID);
      ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
      ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, false);
   }
   
   // Draw Signal Line
   for(int i = 1; i < 100 && i < ArraySize(times); i++)
   {
      if(Signal[i] == EMPTY_VALUE || Signal[i-1] == EMPTY_VALUE)
         continue;
         
      string name = "BTC_Analysis_Signal_Line_" + IntegerToString(i);
      ObjectCreate(0, name, OBJ_TREND, macd_window, times[i], Signal[i], times[i-1], Signal[i-1]);
      ObjectSetInteger(0, name, OBJPROP_COLOR, clrRed);
      ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_SOLID);
      ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
      ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, false);
   }
   
   // Add MACD values to chart
   ObjectCreate(0, "BTC_Analysis_ValueLabel_MACD", OBJ_LABEL, 0, 0, 0);
   ObjectSetString(0, "BTC_Analysis_ValueLabel_MACD", OBJPROP_TEXT, "MACD: " + DoubleToString(MACD[0], 4) + 
                  " Signal: " + DoubleToString(Signal[0], 4));
   ObjectSetInteger(0, "BTC_Analysis_ValueLabel_MACD", OBJPROP_COLOR, clrWhite);
   ObjectSetInteger(0, "BTC_Analysis_ValueLabel_MACD", OBJPROP_CORNER, CORNER_RIGHT_UPPER);
   ObjectSetInteger(0, "BTC_Analysis_ValueLabel_MACD", OBJPROP_XDISTANCE, 150);
   ObjectSetInteger(0, "BTC_Analysis_ValueLabel_MACD", OBJPROP_YDISTANCE, 80);
}

//+------------------------------------------------------------------+
//| Draw RSI line on the chart                                       |
//+------------------------------------------------------------------+
void DrawRSILines(MqlRates &rates[])
{
   // Create subwindow for RSI if it doesn't exist
   int rsi_window = ChartWindowFind(0, "RSI");
   if(rsi_window == -1)
   {
      // RSI indicator might be added to chart - we'll use object drawing instead
      rsi_window = 0;  // Default to main window if subwindow not found
   }
   
   // Get time for x-axis
   datetime times[];
   ArraySetAsSeries(times, true);
   CopyTime(Symbol(), Timeframe, 0, 100, times);
   
   // Draw RSI Line
   for(int i = 1; i < 100 && i < ArraySize(times); i++)
   {
      if(RSI[i] == EMPTY_VALUE || RSI[i-1] == EMPTY_VALUE)
         continue;
         
      string name = "BTC_Analysis_RSI_Line_" + IntegerToString(i);
      ObjectCreate(0, name, OBJ_TREND, rsi_window, times[i], RSI[i], times[i-1], RSI[i-1]);
      ObjectSetInteger(0, name, OBJPROP_COLOR, clrBlue);
      ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_SOLID);
      ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
      ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, false);
   }
   
   // Create overbought and oversold lines
   ObjectCreate(0, "BTC_Analysis_RSI_OB", OBJ_HLINE, rsi_window, 0, 70);
   ObjectSetInteger(0, "BTC_Analysis_RSI_OB", OBJPROP_COLOR, clrRed);
   ObjectSetInteger(0, "BTC_Analysis_RSI_OB", OBJPROP_STYLE, STYLE_DASH);
   ObjectSetInteger(0, "BTC_Analysis_RSI_OB", OBJPROP_WIDTH, 1);
   
   ObjectCreate(0, "BTC_Analysis_RSI_OS", OBJ_HLINE, rsi_window, 0, 30);
   ObjectSetInteger(0, "BTC_Analysis_RSI_OS", OBJPROP_COLOR, clrGreen);
   ObjectSetInteger(0, "BTC_Analysis_RSI_OS", OBJPROP_STYLE, STYLE_DASH);
   ObjectSetInteger(0, "BTC_Analysis_RSI_OS", OBJPROP_WIDTH, 1);
   
   // Add RSI value to chart
   ObjectCreate(0, "BTC_Analysis_ValueLabel_RSI", OBJ_LABEL, 0, 0, 0);
   ObjectSetString(0, "BTC_Analysis_ValueLabel_RSI", OBJPROP_TEXT, "RSI: " + DoubleToString(RSI[0], 2));
   ObjectSetInteger(0, "BTC_Analysis_ValueLabel_RSI", OBJPROP_COLOR, clrWhite);
   ObjectSetInteger(0, "BTC_Analysis_ValueLabel_RSI", OBJPROP_CORNER, CORNER_RIGHT_UPPER);
   ObjectSetInteger(0, "BTC_Analysis_ValueLabel_RSI", OBJPROP_XDISTANCE, 150);
   ObjectSetInteger(0, "BTC_Analysis_ValueLabel_RSI", OBJPROP_YDISTANCE, 100);
}

//+------------------------------------------------------------------+
//| Draw MFI line on the chart                                       |
//+------------------------------------------------------------------+
void DrawMFILines(MqlRates &rates[])
{
   // Create subwindow for MFI if it doesn't exist
   int mfi_window = ChartWindowFind(0, "MFI");
   if(mfi_window == -1)
   {
      // MFI indicator might be added to chart - we'll use object drawing instead
      mfi_window = 0;  // Default to main window if subwindow not found
   }
   
   // Get time for x-axis
   datetime times[];
   ArraySetAsSeries(times, true);
   CopyTime(Symbol(), Timeframe, 0, 100, times);
   
   // Draw MFI Line
   for(int i = 1; i < 100 && i < ArraySize(times); i++)
   {
      if(MFI[i] == EMPTY_VALUE || MFI[i-1] == EMPTY_VALUE)
         continue;
         
      string name = "BTC_Analysis_MFI_Line_" + IntegerToString(i);
      ObjectCreate(0, name, OBJ_TREND, mfi_window, times[i], MFI[i], times[i-1], MFI[i-1]);
      ObjectSetInteger(0, name, OBJPROP_COLOR, clrBlue);
      ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_SOLID);
      ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
      ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, false);
   }
   
   // Create overbought and oversold lines
   ObjectCreate(0, "BTC_Analysis_MFI_OB", OBJ_HLINE, mfi_window, 0, 80);
   ObjectSetInteger(0, "BTC_Analysis_MFI_OB", OBJPROP_COLOR, clrRed);
   ObjectSetInteger(0, "BTC_Analysis_MFI_OB", OBJPROP_STYLE, STYLE_DASH);
   ObjectSetInteger(0, "BTC_Analysis_MFI_OB", OBJPROP_WIDTH, 1);
   
   ObjectCreate(0, "BTC_Analysis_MFI_OS", OBJ_HLINE, mfi_window, 0, 20);
   ObjectSetInteger(0, "BTC_Analysis_MFI_OS", OBJPROP_COLOR, clrGreen);
   ObjectSetInteger(0, "BTC_Analysis_MFI_OS", OBJPROP_STYLE, STYLE_DASH);
   ObjectSetInteger(0, "BTC_Analysis_MFI_OS", OBJPROP_WIDTH, 1);
   
   // Add MFI value to chart
   ObjectCreate(0, "BTC_Analysis_ValueLabel_MFI", OBJ_LABEL, 0, 0, 0);
   ObjectSetString(0, "BTC_Analysis_ValueLabel_MFI", OBJPROP_TEXT, "MFI: " + DoubleToString(MFI[0], 2));
   ObjectSetInteger(0, "BTC_Analysis_ValueLabel_MFI", OBJPROP_COLOR, clrWhite);
   ObjectSetInteger(0, "BTC_Analysis_ValueLabel_MFI", OBJPROP_CORNER, CORNER_RIGHT_UPPER);
   ObjectSetInteger(0, "BTC_Analysis_ValueLabel_MFI", OBJPROP_XDISTANCE, 150);
   ObjectSetInteger(0, "BTC_Analysis_ValueLabel_MFI", OBJPROP_YDISTANCE, 120);
}

//+------------------------------------------------------------------+
//| Draw value labels for current prices and indicator values         |
//+------------------------------------------------------------------+
void DrawValueLabels()
{
   double price = SymbolInfoDouble(Symbol(), SYMBOL_BID);
   
   // Add current price label
   ObjectCreate(0, "BTC_Analysis_ValueLabel_Price", OBJ_LABEL, 0, 0, 0);
   ObjectSetString(0, "BTC_Analysis_ValueLabel_Price", OBJPROP_TEXT, "Current Price: " + DoubleToString(price, 2));
   ObjectSetInteger(0, "BTC_Analysis_ValueLabel_Price", OBJPROP_COLOR, clrYellow);
   ObjectSetInteger(0, "BTC_Analysis_ValueLabel_Price", OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, "BTC_Analysis_ValueLabel_Price", OBJPROP_XDISTANCE, 10);
   ObjectSetInteger(0, "BTC_Analysis_ValueLabel_Price", OBJPROP_YDISTANCE, 20);
   
   // Create a text box with the analysis
   string macd_status = (MACD[0] > Signal[0]) ? "Bullish" : "Bearish";
   string rsi_status = (RSI[0] > 70) ? "Overbought" : (RSI[0] < 30) ? "Oversold" : "Neutral";
   string mfi_status = (MFI[0] > 80) ? "Overbought" : (MFI[0] < 20) ? "Oversold" : "Neutral";
   
   ObjectCreate(0, "BTC_Analysis_ValueLabel_Analysis", OBJ_LABEL, 0, 0, 0);
   ObjectSetString(0, "BTC_Analysis_ValueLabel_Analysis", OBJPROP_TEXT, "MACD: " + macd_status + " | RSI: " + rsi_status + " | MFI: " + mfi_status);
   ObjectSetInteger(0, "BTC_Analysis_ValueLabel_Analysis", OBJPROP_COLOR, clrAqua);
   ObjectSetInteger(0, "BTC_Analysis_ValueLabel_Analysis", OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, "BTC_Analysis_ValueLabel_Analysis", OBJPROP_XDISTANCE, 10);
   ObjectSetInteger(0, "BTC_Analysis_ValueLabel_Analysis", OBJPROP_YDISTANCE, 40);
}

//+------------------------------------------------------------------+
//| Check if a position of specified type is already open            |
//+------------------------------------------------------------------+
bool IsPositionOpen(ENUM_POSITION_TYPE posType)
{
   int totalPositions = PositionsTotal();
   Print("Checking for positions of type: ", EnumToString(posType), ", Total positions: ", totalPositions);
   
   for(int i = 0; i < totalPositions; i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket <= 0) continue;
      
      if(!PositionSelectByTicket(ticket)) {
         Print("Error selecting position by ticket: ", GetLastError());
         continue;
      }
      
      string symbol = PositionGetString(POSITION_SYMBOL);
      
      // Only look at positions for our symbol
      if(symbol == Symbol())
      {
         ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
         Print("Position found for symbol ", symbol, ", type: ", EnumToString(type));
         
         // If position type matches what we're looking for
         if(type == posType)
            return true;
      }
   }
   
   Print("No positions of type ", EnumToString(posType), " found for symbol ", Symbol());
   return false;
}

//+------------------------------------------------------------------+
//| Execute a trade based on signal type                             |
//+------------------------------------------------------------------+
void ExecuteTrade(string signal)
{
   Print("=== EXECUTE TRADE FUNCTION CALLED ===");
   Print("Signal: ", signal);
   
   // Only proceed if auto trading is enabled
   if(!EnableAutoTrading && !ForceTradeInTester) {
      Print("Auto trading is disabled. Enable it in EA settings to allow trading.");
      return;
   }
   
   // Skip cooldown check if we're in tester and forcing trade
   bool skipCooldown = (MQLInfoInteger(MQL_TESTER) && ForceTradeInTester);
   
   // Check if enough time has passed since last trade
   datetime current_time = TimeCurrent();
   if(!skipCooldown && current_time - lastTradeTime < TRADE_COOLDOWN) {
      Print("Trade cooldown period not elapsed. Time since last trade: ", (current_time - lastTradeTime), " seconds of ", TRADE_COOLDOWN, " required.");
      return;
   }
   
   Print("PLACING DIRECT ORDER - ", signal);
      
   // Get prices and trade details
   double ask = SymbolInfoDouble(Symbol(), SYMBOL_ASK);
   double bid = SymbolInfoDouble(Symbol(), SYMBOL_BID);
   int digits = (int)SymbolInfoInteger(Symbol(), SYMBOL_DIGITS);
   double point = SymbolInfoDouble(Symbol(), SYMBOL_POINT);
   
   // Use direct trade execution (more reliable in tester)
   MqlTradeRequest request;
   MqlTradeResult result;
   ZeroMemory(request);
   ZeroMemory(result);
   
   // Check for existing positions - we need to close opposite positions first
   bool hasBuyPosition = IsPositionOpen(POSITION_TYPE_BUY);
   bool hasSellPosition = IsPositionOpen(POSITION_TYPE_SELL);
   
   Print("Current positions - Buy: ", (hasBuyPosition ? "YES" : "NO"), ", Sell: ", (hasSellPosition ? "YES" : "NO"));
   
   // Set up trade request
   request.action = TRADE_ACTION_DEAL;
   request.symbol = Symbol();
   request.volume = TradingVolume;
   request.deviation = 10;
   request.magic = EXPERT_MAGIC;
   
   if(signal == "BUY") {
      // If we already have a BUY position, don't open another one
      if(hasBuyPosition) {
         Print("BUY position already exists - skipping trade");
         return;
      }
      
      // Close any SELL positions first
      if(hasSellPosition) {
         Print("Closing existing SELL positions before opening BUY position");
         ClosePositions(POSITION_TYPE_SELL);
         Sleep(1000); // Wait a bit for position to close
      }
      
      // BUY at market
      request.type = ORDER_TYPE_BUY;
      request.price = ask;
      
      if(StopLoss > 0)
         request.sl = NormalizeDouble(bid - StopLoss * point, digits);
      
      if(TakeProfit > 0)
         request.tp = NormalizeDouble(bid + TakeProfit * point, digits);
         
      request.comment = "BTC Analysis EA Buy";
      
      // Print full request details
      Print("Sending BUY order - Symbol: ", request.symbol, ", Price: ", request.price, 
            ", Volume: ", request.volume, ", SL: ", request.sl, ", TP: ", request.tp);
   }
   else if(signal == "SELL") {
      // If we already have a SELL position, don't open another one
      if(hasSellPosition) {
         Print("SELL position already exists - skipping trade");
         return;
      }
      
      // Close any BUY positions first
      if(hasBuyPosition) {
         Print("Closing existing BUY positions before opening SELL position");
         ClosePositions(POSITION_TYPE_BUY);
         Sleep(1000); // Wait a bit for position to close
      }
      
      // SELL at market
      request.type = ORDER_TYPE_SELL;
      request.price = bid;
      
      if(StopLoss > 0)
         request.sl = NormalizeDouble(ask + StopLoss * point, digits);
      
      if(TakeProfit > 0)
         request.tp = NormalizeDouble(ask - TakeProfit * point, digits);
         
      request.comment = "BTC Analysis EA Sell";
      
      // Print full request details
      Print("Sending SELL order - Symbol: ", request.symbol, ", Price: ", request.price, 
            ", Volume: ", request.volume, ", SL: ", request.sl, ", TP: ", request.tp);
   }
   else {
      Print("Invalid signal type: ", signal);
      return;
   }
   
   // Send the order
   Print("=== SENDING ORDER ===");
   
   // Magic number already set above, no need to set it again
   
   bool success = OrderSend(request, result);
   Print("OrderSend returned: ", success ? "true" : "false");
   
   // Check result
   if(success && result.retcode == TRADE_RETCODE_DONE) {
      Print("Order executed successfully!");
      Print("Order ticket: ", result.order);
      Print("Deal ticket: ", result.deal);
      Print("Volume executed: ", result.volume);
      Print("Request ID: ", result.retcode);
      
      lastTradeTime = current_time;
      if(signal == "BUY")
         lastBuyTicket = result.order;
      else
         lastSellTicket = result.order;
         
      // Check if position was actually opened
      Sleep(100); // Give the server a moment to process
      if(signal == "BUY" && !IsPositionOpen(POSITION_TYPE_BUY)) {
         Print("WARNING: Order was reported successful but no BUY position detected!");
      }
      else if(signal == "SELL" && !IsPositionOpen(POSITION_TYPE_SELL)) {
         Print("WARNING: Order was reported successful but no SELL position detected!");
      }
   }
   else {
      // Detailed error reporting
      Print("Failed to send order! Error code: ", GetLastError());
      Print("Result code: ", result.retcode, " - ", GetRetcodeDescription(result.retcode));
      Print("Result comment: ", result.comment);
      
      // Add specific troubleshooting for common errors
      if(result.retcode == TRADE_RETCODE_INVALID_VOLUME) {
         Print("Invalid volume. Current volume setting: ", request.volume);
         Print("Min volume: ", SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MIN));
         Print("Max volume: ", SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MAX));
         Print("Volume step: ", SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_STEP));
      }
      else if(result.retcode == TRADE_RETCODE_INVALID_PRICE) {
         Print("Invalid price. Requested price: ", request.price);
         Print("Current Bid: ", SymbolInfoDouble(Symbol(), SYMBOL_BID));
         Print("Current Ask: ", SymbolInfoDouble(Symbol(), SYMBOL_ASK));
      }
      else if(result.retcode == TRADE_RETCODE_INVALID_STOPS) {
         Print("Invalid stop levels. SL: ", request.sl, ", TP: ", request.tp);
         Print("StopLevel in points: ", SymbolInfoInteger(Symbol(), SYMBOL_TRADE_STOPS_LEVEL));
      }
   }
   
   Print("=== TRADE EXECUTION COMPLETE ===");
}

//+------------------------------------------------------------------+
//| Close all positions of the specified type                        |
//+------------------------------------------------------------------+
void ClosePositions(ENUM_POSITION_TYPE posType)
{
   Print("Attempting to close all positions of type: ", EnumToString(posType));
   
   // Store tickets in array to avoid issues with position shifting during closure
   ulong tickets[];
   ArrayResize(tickets, 0);
   
   // First collect all position tickets that need to be closed
   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket <= 0) continue;
      
      if(!PositionSelectByTicket(ticket)) {
         Print("Error selecting position by ticket: ", GetLastError());
         continue;
      }
      
      string symbol = PositionGetString(POSITION_SYMBOL);
      
      // Only close positions for our symbol
      if(symbol == Symbol())
      {
         ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
         
         // If position type matches what we're looking for
         if(type == posType)
         {
            int size = ArraySize(tickets);
            ArrayResize(tickets, size + 1);
            tickets[size] = ticket;
            Print("Adding ticket to close list: ", ticket, ", type: ", EnumToString(type));
         }
      }
   }
   
   // Now close each position by ticket
   int totalClosed = 0;
   int ticketsToClose = ArraySize(tickets);
   Print("Found ", ticketsToClose, " positions to close");
   
   for(int i = 0; i < ticketsToClose; i++)
   {
      ulong ticket = tickets[i];
      
      if(!PositionSelectByTicket(ticket)) {
         Print("Error selecting position by ticket before closing: ", GetLastError());
         continue;
      }
      
      if(trade.PositionClose(ticket))
      {
         Print("Position #", ticket, " closed successfully");
         totalClosed++;
      }
      else
      {
         Print("Failed to close position #", ticket, ". Error: ", trade.ResultRetcode(), " - ", 
               trade.ResultRetcodeDescription(), ", Error code: ", GetLastError());
      }
   }
   
   Print("Total positions closed: ", totalClosed, " out of ", ticketsToClose, " attempted");
}

//+------------------------------------------------------------------+
//| Get signal type (BUY/SELL/HOLD) without heavy calculations       |
//+------------------------------------------------------------------+
string GetSignalType()
{
   // Quick calculation of signal based on the most important indicators
   // For testing purposes, we use simplified logic
   
   double price = SymbolInfoDouble(Symbol(), SYMBOL_BID);
   
   if(ArraySize(SMA50) < 2 || ArraySize(SMA100) < 2)
      return "HOLD";
   
   // Simple trend detection
   bool uptrend = SMA50[0] > SMA100[0];
   bool downtrend = SMA50[0] < SMA100[0];
   
   // RSI oversold/overbought
   bool oversold = ArraySize(RSI) > 0 && RSI[0] < 30;
   bool overbought = ArraySize(RSI) > 0 && RSI[0] > 70;
   
   // Simple signal logic
   if(uptrend || oversold)
      return "BUY";
   else if(downtrend || overbought)
      return "SELL";
   else
      return "HOLD";
}

//+------------------------------------------------------------------+
//| Check if enough time has passed to send a new alert              |
//+------------------------------------------------------------------+
bool CanSendAlert()
{
   datetime current_time = TimeCurrent();
   
   // Check if the cooldown period has passed since the last alert
   if(current_time - last_alert_time > ALERT_COOLDOWN)
   {
      return true;
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| Send alerts based on the signal type                             |
//+------------------------------------------------------------------+
void SendAlerts(string signal_type, string message)
{
   // Only send alerts if enabled
   if(!EnableAlerts)
      return;
      
   // Update the last alert time
   last_alert_time = TimeCurrent();
   
   // Send pop-up alert
   Alert(message);
   
   // Send email if enabled
   if(EnableEmailAlerts)
      SendMail("BTC Analysis Alert: " + signal_type, message);
      
   // Send push notification if enabled
   if(EnablePushNotifications)
      SendNotification(message);
}

//+------------------------------------------------------------------+
//| Save analysis to CSV file                                        |
//+------------------------------------------------------------------+
void SavePDF(string recommendation)
{
   // Get the current date and time for filename
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   
   // Format the date for the filename
   string date_str = StringFormat("%04d%02d%02d_%02d%02d%02d", 
                                  dt.year, dt.mon, dt.day,
                                  dt.hour, dt.min, dt.sec);
   
   // Create directory if it doesn't exist
   string dir = "MQL5\\Files\\BTC_Analysis\\";
   if(!FolderCreate(dir))
   {
      int error_code = GetLastError();
      // Error 4301 means directory already exists, which is fine
      if(error_code != 4301)  // ERR_DIRECTORY = 4301
      {
         Print("Failed to create directory: ", error_code);
         return;
      }
   }
   
   // Define the filename with date
   string filename = dir + "BTC_Analysis_" + date_str + ".csv";
   
   // Open file for writing
   int file_handle = FileOpen(filename, FILE_WRITE|FILE_CSV|FILE_ANSI);
   
   if(file_handle != INVALID_HANDLE)
   {
      // Split recommendation into lines for CSV formatting
      string lines[];
      StringSplit(recommendation, '\n', lines);
      
      // Write header
      FileWrite(file_handle, "BTC/USD Technical Analysis Report");
      FileWrite(file_handle, "Generated on: " + TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS));
      FileWrite(file_handle, "Symbol: " + Symbol());
      FileWrite(file_handle, ""); // Empty line for better readability
      
      // Write all lines from recommendation
      for(int i = 0; i < ArraySize(lines); i++)
      {
         if(StringLen(lines[i]) > 0)
            FileWrite(file_handle, lines[i]);
      }
      
      // Add additional data (indicator values for reference)
      FileWrite(file_handle, "");
      FileWrite(file_handle, "Raw Indicator Values");
      FileWrite(file_handle, "SMA50," + DoubleToString(SMA50[0], 2));
      FileWrite(file_handle, "SMA100," + DoubleToString(SMA100[0], 2));
      FileWrite(file_handle, "EMA12," + DoubleToString(EMA12[0], 2));
      FileWrite(file_handle, "EMA26," + DoubleToString(EMA26[0], 2));
      FileWrite(file_handle, "MACD," + DoubleToString(MACD[0], 4));
      FileWrite(file_handle, "Signal," + DoubleToString(Signal[0], 4));
      FileWrite(file_handle, "RSI," + DoubleToString(RSI[0], 2));
      FileWrite(file_handle, "MFI," + DoubleToString(MFI[0], 2));
      FileWrite(file_handle, "Upper BB," + DoubleToString(Upper_BB[0], 2));
      FileWrite(file_handle, "Middle BB," + DoubleToString(Middle_BB[0], 2));
      FileWrite(file_handle, "Lower BB," + DoubleToString(Lower_BB[0], 2));
      FileWrite(file_handle, "Support S1," + DoubleToString(S1, 2));
      FileWrite(file_handle, "Support S2," + DoubleToString(S2, 2));
      FileWrite(file_handle, "Resistance R1," + DoubleToString(R1, 2));
      FileWrite(file_handle, "Resistance R2," + DoubleToString(R2, 2));
      
      // Close the file
      FileClose(file_handle);
      Print("Analysis saved to ", filename);
      
      // Alert the user that the report has been saved
      Alert("BTC/USD analysis report saved to ", filename);
   }
   else
   {
      Print("Failed to save analysis to file. Error code: ", GetLastError());
   }
}

//+------------------------------------------------------------------+
//| Get readable description for a trade return code                 |
//+------------------------------------------------------------------+
string GetRetcodeDescription(int retcode)
{
   switch(retcode)
   {
      // Successful execution
      case TRADE_RETCODE_DONE: return "Request executed successfully";
      case TRADE_RETCODE_DONE_PARTIAL: return "Request executed partially";
      case TRADE_RETCODE_PLACED: return "Order placed";
      
      // Common errors
      case TRADE_RETCODE_REQUOTE: return "Requote";
      case TRADE_RETCODE_REJECT: return "Request rejected";
      case TRADE_RETCODE_CANCEL: return "Request canceled by trader";
      case TRADE_RETCODE_ERROR: return "Request processing error";
      
      // Specific errors
      case TRADE_RETCODE_TIMEOUT: return "Request canceled by timeout";
      case TRADE_RETCODE_INVALID: return "Invalid request";
      case TRADE_RETCODE_INVALID_VOLUME: return "Invalid volume";
      case TRADE_RETCODE_INVALID_PRICE: return "Invalid price";
      case TRADE_RETCODE_INVALID_STOPS: return "Invalid stops";
      case TRADE_RETCODE_TRADE_DISABLED: return "Trading is disabled";
      case TRADE_RETCODE_MARKET_CLOSED: return "Market is closed";
      case TRADE_RETCODE_NO_MONEY: return "Not enough money";
      case TRADE_RETCODE_PRICE_CHANGED: return "Price changed";
      case TRADE_RETCODE_PRICE_OFF: return "No quotes to process request";
      case TRADE_RETCODE_INVALID_EXPIRATION: return "Invalid expiration date";
      case TRADE_RETCODE_ORDER_CHANGED: return "Order state changed";
      case TRADE_RETCODE_TOO_MANY_REQUESTS: return "Too many requests";
      case TRADE_RETCODE_NO_CHANGES: return "No changes in request";
      case TRADE_RETCODE_SERVER_DISABLES_AT: return "Autotrading disabled by server";
      case TRADE_RETCODE_CLIENT_DISABLES_AT: return "Autotrading disabled by client terminal";
      case TRADE_RETCODE_LOCKED: return "Request locked for processing";
      case TRADE_RETCODE_FROZEN: return "Order or position frozen";
      case TRADE_RETCODE_INVALID_FILL: return "Invalid order filling type";
      case TRADE_RETCODE_CONNECTION: return "No connection with trade server";
      case TRADE_RETCODE_ONLY_REAL: return "Operation allowed only for real accounts";
      case TRADE_RETCODE_LIMIT_ORDERS: return "Limit for orders reached";
      case TRADE_RETCODE_LIMIT_VOLUME: return "Limit for volume reached";
      case TRADE_RETCODE_POSITION_CLOSED: return "Position already closed";
      case TRADE_RETCODE_INVALID_ORDER: return "Invalid order";
      
      default: return "Unknown error code: " + IntegerToString(retcode);
   }
  }
