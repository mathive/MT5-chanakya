//+------------------------------------------------------------------+
//|                                                   Strategies.mqh |
//|                                  Copyright 2026, Sanju Kaka Algo |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Sanju Kaka Algo"
#property link      "https://www.mql5.com"
#property strict

#include "Defines.mqh"

class CStrategyEngine
{
private:
   string            m_symbol;
   ENUM_TIMEFRAMES   m_timeframe;
   
   // Indicator Handles
   int               m_hRSI_M1;
   int               m_hEMA50_M1;
   
   int               m_hBands_M2;
   int               m_hStoch_M2;
   
   int               m_hMACD_M3;
   
   int               m_hSAR_M5;
   int               m_hEMA200_M5;
   
   int               m_hATR_M6;
   
   int               m_hEMA9_M7;
   int               m_hEMA21_M7;
   
   int               m_hATR_M9;
   
   // Supertrend State
   double            m_stUpperBand;
   double            m_stLowerBand;
   int               m_stDirection; // 1 = Bullish/Green, -1 = Bearish/Red

public:
   CStrategyEngine() :
      m_symbol(""),
      m_timeframe(PERIOD_M15),
      m_hRSI_M1(INVALID_HANDLE),
      m_hEMA50_M1(INVALID_HANDLE),
      m_hBands_M2(INVALID_HANDLE),
      m_hStoch_M2(INVALID_HANDLE),
      m_hMACD_M3(INVALID_HANDLE),
      m_hSAR_M5(INVALID_HANDLE),
      m_hEMA200_M5(INVALID_HANDLE),
      m_hATR_M6(INVALID_HANDLE),
      m_hEMA9_M7(INVALID_HANDLE),
      m_hEMA21_M7(INVALID_HANDLE),
      m_hATR_M9(INVALID_HANDLE),
      m_stUpperBand(0),
      m_stLowerBand(0),
      m_stDirection(1)
   {
   }
   
   ~CStrategyEngine()
   {
      ReleaseHandles();
   }
   
   bool Init(const string symbol, ENUM_TIMEFRAMES tf,
             bool enM1, bool enM2, bool enM3, bool enM5, bool enM6, bool enM7, bool enM9, bool enSniper)
   {
      m_symbol    = symbol;
      m_timeframe = tf;
      
      ReleaseHandles();
      
      // M1: RSI(14) + 50 EMA
      if(enM1 || enSniper)
      {
         m_hRSI_M1   = iRSI(m_symbol, m_timeframe, 14, PRICE_CLOSE);
         m_hEMA50_M1 = iMA(m_symbol, m_timeframe, 50, 0, MODE_EMA, PRICE_CLOSE);
      }
      
      // M2: BB(20, 2.0) + Stoch(5, 3, 3)
      if(enM2)
      {
         m_hBands_M2 = iBands(m_symbol, m_timeframe, 20, 0, 2.0, PRICE_CLOSE);
         m_hStoch_M2 = iStochastic(m_symbol, m_timeframe, 5, 3, 3, MODE_SMA, STO_LOWHIGH);
      }
      
      // M3: MACD(12, 26, 9)
      if(enM3)
      {
         m_hMACD_M3  = iMACD(m_symbol, m_timeframe, 12, 26, 9, PRICE_CLOSE);
      }
      
      // M5: PSAR(0.02, 0.2) + 200 EMA
      if(enM5)
      {
         m_hSAR_M5    = iSAR(m_symbol, m_timeframe, 0.02, 0.2);
         m_hEMA200_M5 = iMA(m_symbol, m_timeframe, 200, 0, MODE_EMA, PRICE_CLOSE);
      }
      
      // M6: ATR(14)
      if(enM6)
      {
         m_hATR_M6    = iATR(m_symbol, m_timeframe, 14);
      }
      
      // M7: EMA 9 & EMA 21
      if(enM7)
      {
         m_hEMA9_M7   = iMA(m_symbol, m_timeframe, 9, 0, MODE_EMA, PRICE_CLOSE);
         m_hEMA21_M7  = iMA(m_symbol, m_timeframe, 21, 0, MODE_EMA, PRICE_CLOSE);
      }
      
      // M9: ATR for Supertrend (10, 3.0)
      if(enM9)
      {
         m_hATR_M9    = iATR(m_symbol, m_timeframe, 10);
      }
      
      return true;
   }
   
   void ReleaseHandles()
   {
      if(m_hRSI_M1 != INVALID_HANDLE)   IndicatorRelease(m_hRSI_M1);
      if(m_hEMA50_M1 != INVALID_HANDLE) IndicatorRelease(m_hEMA50_M1);
      if(m_hBands_M2 != INVALID_HANDLE) IndicatorRelease(m_hBands_M2);
      if(m_hStoch_M2 != INVALID_HANDLE) IndicatorRelease(m_hStoch_M2);
      if(m_hMACD_M3 != INVALID_HANDLE)  IndicatorRelease(m_hMACD_M3);
      if(m_hSAR_M5 != INVALID_HANDLE)   IndicatorRelease(m_hSAR_M5);
      if(m_hEMA200_M5 != INVALID_HANDLE)IndicatorRelease(m_hEMA200_M5);
      if(m_hATR_M6 != INVALID_HANDLE)   IndicatorRelease(m_hATR_M6);
      if(m_hEMA9_M7 != INVALID_HANDLE)  IndicatorRelease(m_hEMA9_M7);
      if(m_hEMA21_M7 != INVALID_HANDLE) IndicatorRelease(m_hEMA21_M7);
      if(m_hATR_M9 != INVALID_HANDLE)   IndicatorRelease(m_hATR_M9);
   }
   
   //==================================================================
   // Module 1: RSI(14) + EMA(50) Trend Engine (Magic 1001)
   // Strict CrossOver of RSI 30 / CrossDown of RSI 70
   //==================================================================
   ENUM_SIGNAL_TYPE GetSignal_M1()
   {
      double rsi[2], ema[2];
      MqlRates rates[2];
      
      if(CopyBuffer(m_hRSI_M1, 0, 1, 2, rsi) < 2) return SIGNAL_NONE;
      if(CopyBuffer(m_hEMA50_M1, 0, 1, 2, ema) < 2) return SIGNAL_NONE;
      if(CopyRates(m_symbol, m_timeframe, 1, 2, rates) < 2) return SIGNAL_NONE;
      
      // Buy: RSI crosses UP above 30 AND Close > 50 EMA
      if(rsi[0] <= 30.0 && rsi[1] > 30.0 && rates[1].close > ema[1])
         return SIGNAL_BUY;
      
      // Sell: RSI crosses DOWN below 70 AND Close < 50 EMA
      if(rsi[0] >= 70.0 && rsi[1] < 70.0 && rates[1].close < ema[1])
         return SIGNAL_SELL;
         
      return SIGNAL_NONE;
   }
   
   //==================================================================
   // Module 2: Bollinger Bands + Stochastic Mean Reversion (Magic 1002)
   // Strict BB Touch + Stoch %K / %D Crossover
   //==================================================================
   ENUM_SIGNAL_TYPE GetSignal_M2()
   {
      double upper[2], lower[2], stochK[2], stochD[2];
      MqlRates rates[2];
      
      if(CopyBuffer(m_hBands_M2, 1, 1, 2, upper) < 2) return SIGNAL_NONE; // Upper band
      if(CopyBuffer(m_hBands_M2, 2, 1, 2, lower) < 2) return SIGNAL_NONE; // Lower band
      if(CopyBuffer(m_hStoch_M2, 0, 1, 2, stochK) < 2) return SIGNAL_NONE; // %K
      if(CopyBuffer(m_hStoch_M2, 1, 1, 2, stochD) < 2) return SIGNAL_NONE; // %D
      if(CopyRates(m_symbol, m_timeframe, 1, 2, rates) < 2) return SIGNAL_NONE;
      
      // Buy: Low touches/crosses Lower BB AND Stoch %K crosses UP %D in oversold territory (< 25)
      if(rates[1].low <= lower[1] && stochK[0] <= stochD[0] && stochK[1] > stochD[1] && stochK[1] < 25.0)
         return SIGNAL_BUY;
      
      // Sell: High touches/crosses Upper BB AND Stoch %K crosses DOWN %D in overbought territory (> 75)
      if(rates[1].high >= upper[1] && stochK[0] >= stochD[0] && stochK[1] < stochD[1] && stochK[1] > 75.0)
         return SIGNAL_SELL;
         
      return SIGNAL_NONE;
   }
   
   //==================================================================
   // Module 3: MACD Histogram & Signal Crossover (Magic 1003)
   // Strict Signal Crossover on closed candle
   //==================================================================
   ENUM_SIGNAL_TYPE GetSignal_M3()
   {
      double main[2], signal[2];
      if(CopyBuffer(m_hMACD_M3, 0, 1, 2, main) < 2) return SIGNAL_NONE;
      if(CopyBuffer(m_hMACD_M3, 1, 1, 2, signal) < 2) return SIGNAL_NONE;
      
      double hist1 = main[1] - signal[1];
      
      // Buy: Main crosses Signal UP & Histogram is positive
      if(main[0] <= signal[0] && main[1] > signal[1] && hist1 > 0)
         return SIGNAL_BUY;
      
      // Sell: Main crosses Signal DOWN & Histogram is negative
      if(main[0] >= signal[0] && main[1] < signal[1] && hist1 < 0)
         return SIGNAL_SELL;
         
      return SIGNAL_NONE;
   }
   
   //==================================================================
   // Module 4: 20-Bar High/Low Support-Resistance Breakout (Magic 1004)
   // Fresh Breakout over 20-bar channel
   //==================================================================
   ENUM_SIGNAL_TYPE GetSignal_M4()
   {
      MqlRates rates[22];
      if(CopyRates(m_symbol, m_timeframe, 1, 22, rates) < 22) return SIGNAL_NONE;
      
      double highestHigh = rates[0].high;
      double lowestLow   = rates[0].low;
      
      for(int i = 0; i < 20; i++)
      {
         if(rates[i].high > highestHigh) highestHigh = rates[i].high;
         if(rates[i].low < lowestLow)   lowestLow   = rates[i].low;
      }
      
      // rates[20] is the completed bar 1; check for fresh breakout
      if(rates[20].close > highestHigh && rates[19].close <= highestHigh)
         return SIGNAL_BUY;
      if(rates[20].close < lowestLow && rates[19].close >= lowestLow)
         return SIGNAL_SELL;
         
      return SIGNAL_NONE;
   }
   
   //==================================================================
   // Module 5: Parabolic SAR + 200 EMA Trend Follower (Magic 1005)
   // Strict SAR Dot FLIP (Reversal Event) + 200 EMA Filter
   //==================================================================
   ENUM_SIGNAL_TYPE GetSignal_M5()
   {
      double sar[2], ema[2];
      MqlRates rates[2];
      
      if(CopyBuffer(m_hSAR_M5, 0, 1, 2, sar) < 2) return SIGNAL_NONE;
      if(CopyBuffer(m_hEMA200_M5, 0, 1, 2, ema) < 2) return SIGNAL_NONE;
      if(CopyRates(m_symbol, m_timeframe, 1, 2, rates) < 2) return SIGNAL_NONE;
      
      // Buy: SAR FLIPS from ABOVE to BELOW candle AND Close > 200 EMA
      if(sar[0] > rates[0].high && sar[1] < rates[1].low && rates[1].close > ema[1])
         return SIGNAL_BUY;
      
      // Sell: SAR FLIPS from BELOW to ABOVE candle AND Close < 200 EMA
      if(sar[0] < rates[0].low && sar[1] > rates[1].high && rates[1].close < ema[1])
         return SIGNAL_SELL;
         
      return SIGNAL_NONE;
   }
   
   //==================================================================
   // Module 6: Volatility Engine using ATR(14) Breakout (Magic 1006)
   // ATR Volume Surge + Bar Breakout
   //==================================================================
   ENUM_SIGNAL_TYPE GetSignal_M6()
   {
      double atr[21];
      MqlRates rates[2];
      
      if(CopyBuffer(m_hATR_M6, 0, 1, 21, atr) < 21) return SIGNAL_NONE;
      if(CopyRates(m_symbol, m_timeframe, 1, 2, rates) < 2) return SIGNAL_NONE;
      
      double atrSMA = 0.0;
      for(int i = 0; i < 20; i++) atrSMA += atr[i];
      atrSMA /= 20.0;
      
      // Buy: High Volatility Surge + Bar 1 closes above Bar 2 High
      if(atr[20] > (atrSMA * 1.1) && rates[1].close > rates[0].high)
         return SIGNAL_BUY;
         
      // Sell: High Volatility Surge + Bar 1 closes below Bar 2 Low
      if(atr[20] > (atrSMA * 1.1) && rates[1].close < rates[0].low)
         return SIGNAL_SELL;
         
      return SIGNAL_NONE;
   }
   
   //==================================================================
   // Module 7: Dual Moving Average Crossover (9 EMA / 21 EMA) (Magic 1007)
   // Strict Fast EMA crossing Slow EMA
   //==================================================================
   ENUM_SIGNAL_TYPE GetSignal_M7()
   {
      double ema9[2], ema21[2];
      if(CopyBuffer(m_hEMA9_M7, 0, 1, 2, ema9) < 2) return SIGNAL_NONE;
      if(CopyBuffer(m_hEMA21_M7, 0, 1, 2, ema21) < 2) return SIGNAL_NONE;
      
      // Buy: 9 EMA crosses ABOVE 21 EMA
      if(ema9[0] <= ema21[0] && ema9[1] > ema21[1])
         return SIGNAL_BUY;
         
      // Sell: 9 EMA crosses BELOW 21 EMA
      if(ema9[0] >= ema21[0] && ema9[1] < ema21[1])
         return SIGNAL_SELL;
         
      return SIGNAL_NONE;
   }
   
   //==================================================================
   // Module 8: Pure Price Action Candlestick Pattern Engine (Magic 1008)
   // Bullish & Bearish Engulfing Candle Patterns
   //==================================================================
   ENUM_SIGNAL_TYPE GetSignal_M8()
   {
      MqlRates rates[2];
      if(CopyRates(m_symbol, m_timeframe, 1, 2, rates) < 2) return SIGNAL_NONE;
      
      // rates[0] = bar 2, rates[1] = bar 1
      bool prevBearish = (rates[0].close < rates[0].open);
      bool curBullish  = (rates[1].close > rates[1].open);
      
      bool prevBullish = (rates[0].close > rates[0].open);
      bool curBearish  = (rates[1].close < rates[1].open);
      
      // Bullish Engulfing
      if(prevBearish && curBullish && rates[1].open <= rates[0].close && rates[1].close > rates[0].open)
         return SIGNAL_BUY;
         
      // Bearish Engulfing
      if(prevBullish && curBearish && rates[1].open >= rates[0].close && rates[1].close < rates[0].open)
         return SIGNAL_SELL;
         
      return SIGNAL_NONE;
   }
   
   //==================================================================
   // Module 9: Supertrend (10, 3.0) Indicator Logic (Magic 1009)
   // Strict Trend Reversal / Color Flip
   //==================================================================
   ENUM_SIGNAL_TYPE GetSignal_M9()
   {
      double atr[2];
      MqlRates rates[2];
      
      if(CopyBuffer(m_hATR_M9, 0, 1, 2, atr) < 2) return SIGNAL_NONE;
      if(CopyRates(m_symbol, m_timeframe, 1, 2, rates) < 2) return SIGNAL_NONE;
      
      double hl2 = (rates[1].high + rates[1].low) / 2.0;
      double basicUpper = hl2 + (3.0 * atr[1]);
      double basicLower = hl2 - (3.0 * atr[1]);
      
      if(basicUpper < m_stUpperBand || rates[0].close > m_stUpperBand)
         m_stUpperBand = basicUpper;
      if(basicLower > m_stLowerBand || rates[0].close < m_stLowerBand)
         m_stLowerBand = basicLower;
         
      int prevDir = m_stDirection;
      if(rates[1].close > m_stUpperBand)
         m_stDirection = 1;
      else if(rates[1].close < m_stLowerBand)
         m_stDirection = -1;
         
      if(m_stDirection == 1 && prevDir == -1)
         return SIGNAL_BUY;
      if(m_stDirection == -1 && prevDir == 1)
         return SIGNAL_SELL;
         
      return SIGNAL_NONE;
   }
   
   //==================================================================
   // Module 11 (Optional): Sniper Scalper Module (Magic 1011)
   // Surge Momentum Bar + RSI Surge
   //==================================================================
   ENUM_SIGNAL_TYPE GetSignal_Sniper()
   {
      double rsi[2];
      MqlRates rates[2];
      if(CopyBuffer(m_hRSI_M1, 0, 1, 2, rsi) < 2) return SIGNAL_NONE;
      if(CopyRates(m_symbol, m_timeframe, 1, 2, rates) < 2) return SIGNAL_NONE;
      
      double candleBody = MathAbs(rates[1].close - rates[1].open);
      double totalRange = rates[1].high - rates[1].low;
      
      // Strict Momentum Expansion Candle (Body >= 75% of range) + RSI surge cross
      if(totalRange > 0 && (candleBody / totalRange) >= 0.75)
      {
         if(rates[1].close > rates[1].open && rsi[0] <= 55.0 && rsi[1] > 55.0 && rsi[1] < 70.0)
            return SIGNAL_BUY;
         if(rates[1].close < rates[1].open && rsi[0] >= 45.0 && rsi[1] < 45.0 && rsi[1] > 30.0)
            return SIGNAL_SELL;
      }
      
      return SIGNAL_NONE;
   }
};
