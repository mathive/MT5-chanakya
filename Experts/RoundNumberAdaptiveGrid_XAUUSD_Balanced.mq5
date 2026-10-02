//+------------------------------------------------------------------+
//|                       RoundNumberAdaptiveGrid_XAUUSD_Balanced.mq5 |
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
input ENUM_TIMEFRAMES DecisionTimeframe = PERIOD_M15;
input int      FastEMAPeriod = 34;
input int      SlowEMAPeriod = 200;
input int      ADXPeriod = 14;
input double   ADXTrendThreshold = 28.0;
input int      ATRPeriod = 14;
input double   RangeATRMultiplier = 0.18;
input bool     UseNoTradeOnHighSpread = true;

input group "Grid Settings"
input double   LotSize = 0.01;
input double   RoundStepPrice = 1.0;
input int      MaxPendingLevels = 12;
input int      MaxCountPerSide = 2;
input double   TargetPriceDistance = 2.0;
input int      StopLossPoints = 300;

input group "Execution"
input int      MagicNumber = 455152;
input int      SlippagePoints = 3;
input int      MaxSpreadPoints = 35;
input bool     CloseOppositePositionsOnModeChange = false;

input group "Display"
input bool     ShowStatusLabel = true;
input int      StatusLabelFontSize = 14;

#define ADAPTIVE_VARIANT_TITLE "Balanced"
#include "RoundNumberAdaptiveGrid_XAUUSD_Core.mqh"
