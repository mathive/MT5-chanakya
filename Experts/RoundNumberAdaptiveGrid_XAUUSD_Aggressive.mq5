//+------------------------------------------------------------------+
//|                     RoundNumberAdaptiveGrid_XAUUSD_Aggressive.mq5 |
//+------------------------------------------------------------------+
#property copyright "Chanakya"
#property link      "https://www.mql5.com"
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>

enum ENUM_AUTO_TRADE_MODE
{
   MODE_BUY_ONLY = 0,
   MODE_SELL_ONLY = 1,
   MODE_BUY_AND_SELL = 2,
   MODE_NO_TRADE = 3
};

input group "Regime Selector"
input ENUM_TIMEFRAMES DecisionTimeframe = PERIOD_M5;
input int      FastEMAPeriod = 21;
input int      SlowEMAPeriod = 100;
input int      ADXPeriod = 14;
input double   ADXTrendThreshold = 22.0;
input int      ATRPeriod = 14;
input double   RangeATRMultiplier = 0.25;
input bool     UseNoTradeOnHighSpread = true;

input group "Grid Settings"
input double   LotSize = 0.01;
input double   RoundStepPrice = 1.0;
input int      MaxPendingLevels = 20;
input int      MaxCountPerSide = 3;
input double   TargetPriceDistance = 1.5;
input int      StopLossPoints = 250;

input group "Execution"
input int      MagicNumber = 455151;
input int      SlippagePoints = 3;
input int      MaxSpreadPoints = 40;
input bool     CloseOppositePositionsOnModeChange = false;

input group "Display"
input bool     ShowStatusLabel = true;
input int      StatusLabelFontSize = 14;

#define ADAPTIVE_VARIANT_TITLE "Aggressive"
#include "RoundNumberAdaptiveGrid_XAUUSD_Core.mqh"
