//+------------------------------------------------------------------+
//|                              HH_LL_MarketStructure_EA.mq5        |
//|                              Copyright 2026, Antigravity AI      |
//|                              Multi-TF HH/LL Market Structure EA  |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Antigravity AI"
#property link      "https://mql5.com"
#property version   "10.10"
#property description "Multi-Timeframe HH/LL Market Structure EA v10.10"
#property description "Retracement Entry | Strict Trend Filter | Auto Trailing SL | USD PnL"

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\SymbolInfo.mqh>

//+------------------------------------------------------------------+
//| Enums                                                            |
//+------------------------------------------------------------------+
enum ENUM_TP_MODE
{
   TP_MODE_SWING_HL     = 0, // Swing High/Low (Realistic Market Structure TP)
   TP_MODE_RISK_REWARD  = 1, // Risk:Reward Ratio (e.g. 1:1.5)
   TP_MODE_FIXED_POINTS = 2  // Fixed Points (e.g. 5.0 pts)
};

enum ENUM_TRAIL_MODE
{
   TRAIL_SWING_HL        = 0, // Swing Structure (Trails behind newly formed HL/LH - Maximum Space)
   TRAIL_PREVIOUS_CANDLE = 1, // Previous Candle Low/High (Trails candle-by-candle with buffer)
   TRAIL_POINTS_DISTANCE = 2, // Points / Dollar Distance (Fixed trailing distance)
   TRAIL_BREAK_EVEN_ONLY = 3  // Break-Even Lock Only (Locks Entry price + buffer once in profit)
};

enum ENUM_TRADE_DIRECTION
{
   TRADE_DIR_BOTH      = 0, // Both BUY & SELL
   TRADE_DIR_BUY_ONLY  = 1, // BUY Only (Longs Only)
   TRADE_DIR_SELL_ONLY = 2  // SELL Only (Shorts Only)
};

//+------------------------------------------------------------------+
//| Swing Point                                                      |
//+------------------------------------------------------------------+
struct SSwingPoint
{
   double   price;
   datetime time;
   bool     isHigh;
   int      swingType; // 1=HH, 2=LH, 3=HL, 4=LL, 0=none
};

//+------------------------------------------------------------------+
//| Per-Timeframe Bot State                                          |
//+------------------------------------------------------------------+
struct STfBot
{
   ENUM_TIMEFRAMES period;
   string          name;
   bool            enabled;
   ulong           magic;

   // Swing data
   SSwingPoint     lastHigh;
   SSwingPoint     prevHigh;
   SSwingPoint     lastLow;
   SSwingPoint     prevLow;

   // Base boundaries for entry / SL / TP
   double          swingHighPrice; // Peak of the move
   double          swingLowPrice;  // Base of the move

   // Market structure
   string          structure;  // "BULLISH","BEARISH","RANGING","SCANNING"

   // Retracement zones
   double          buyZone;
   double          sellZone;
   bool            buyArmed;
   bool            sellArmed;

   // Open trade state
   string          tradeDir;   // "BUY","SELL","NONE"
   double          openPrice;
   double          slPrice;
   double          tpPrice;
   double          floatPnL;   // in USD

   // After TP: wait for opposite signal
   bool            waitOppSignal;
   bool            lastWasLong;

   // Anti-duplicate guards
   datetime        lastBarTime;
   datetime        lastEntryHighTime;
   datetime        lastEntryLowTime;
};

#define TOTAL_TF 9
STfBot g_bots[TOTAL_TF];

//+------------------------------------------------------------------+
//| Input Parameters                                                 |
//+------------------------------------------------------------------+
input group "=== Core Trading ==="
input ENUM_TRADE_DIRECTION InpTradeDirection    = TRADE_DIR_BOTH; // Allowed Trade Direction (Both / Buy Only / Sell Only)
input bool                 InpActiveChartOnly   = false;          // Trade ONLY current chart TF (false = All TFs trade independently)
input bool                 InpUseAutoLot        = false;          // Use Auto Lot Sizing (Risk %)
input double               InpRiskPct           = 1.0;            // Risk % per Trade (if Auto Lot is true)
input double               InpLotSize           = 0.01;           // Fixed Lot Size (if Auto Lot is false)
input double               InpRetracePct        = 50.0;           // Retracement % (50 = 50% Fib pullback)
input double               InpEntryTolerance    = 0.30;           // Entry Zone Tolerance (Points/Dollars on Gold - avoids 1-cent miss)
input int                  InpMaxSpread         = 50;             // Max Spread (Points) - 0 to disable
input ulong                InpBaseMagic         = 300000;         // Base Magic Number
input int                  InpSlippage          = 30;             // Max Slippage (Points)

input group "=== Stop Loss & Trailing ==="
input double           InpSlBuffer          = 3.0;                 // SL buffer beyond swing pivot (Points / Dollars on Gold)
input bool             InpTrailEnable       = true;                // Enable Auto Trailing Stop Loss
input ENUM_TRAIL_MODE  InpTrailMode         = TRAIL_SWING_HL;      // Trailing Mode (Swing HL/LH gives full breathing space!)
input double           InpTrailStart        = 5.0;                 // Points profit to activate Trailing / Break-Even ($5.00)
input double           InpTrailDistance     = 4.0;                 // Trail distance behind price (Used in Points mode)
input double           InpTrailStep         = 0.5;                 // Min step to move SL (Points / Dollars)

input group "=== Take Profit ==="
input ENUM_TP_MODE     InpTpMode            = TP_MODE_SWING_HL; // TP Mode
input double           InpRRRatio           = 1.5;   // R:R Ratio (TP_MODE_RISK_REWARD)
input double           InpFixedTpPts        = 5.0;   // Fixed TP Points (TP_MODE_FIXED_POINTS)

input group "=== Account ==="
input bool             InpForceCentAccount  = false;  // Force Cent/USC Account mode

input group "=== Timeframes ==="
input bool             InpM1                = true;   // M1
input bool             InpM2                = true;   // M2
input bool             InpM3                = true;   // M3
input bool             InpM4                = false;  // M4
input bool             InpM5                = true;   // M5
input bool             InpM10               = true;   // M10
input bool             InpM15               = true;   // M15
input bool             InpM30               = true;   // M30
input bool             InpH1                = true;   // H1

input group "=== Swing Detection ==="
input int              InpPivotBars         = 3;      // Pivot strength (bars each side)
input int              InpScanBars          = 100;    // History bars to scan

input group "=== Visuals ==="
input bool             InpDrawSwings        = true;   // Draw HH/HL/LH/LL labels on chart
input bool             InpDrawTradeLines    = true;   // Draw Entry/SL/TP/Zone lines
input bool             InpShowDashboard     = true;   // Show dashboard
input int              InpDashX             = 20;     // Dashboard X position
input int              InpDashY             = 30;     // Dashboard Y position

//+------------------------------------------------------------------+
//| Globals                                                          |
//+------------------------------------------------------------------+
CTrade        g_trade;
CPositionInfo g_pos;
CSymbolInfo   g_sym;
string        g_pfx = "HHLL_";

//+------------------------------------------------------------------+
//| Point / Price Conversion (Works for Gold $1.50 and Forex 15 pips)|
//+------------------------------------------------------------------+
double PointsToPrice(double pts)
{
   if(_Digits == 2 || _Digits == 3) // Gold (XAUUSD), Indices, JPY
      return pts; // 1.5 points = $1.50
   else if(_Digits == 5 || _Digits == 4) // 5-digit/4-digit Forex
      return pts * 10 * _Point;
   else
      return pts * _Point;
}

//+------------------------------------------------------------------+
//| USD Conversion                                                   |
//+------------------------------------------------------------------+
double GetUsdFactor()
{
   if(InpForceCentAccount) return 0.01;
   string cur = AccountInfoString(ACCOUNT_CURRENCY);
   StringToUpper(cur);
   if(cur == "USD") return 1.0;
   if(cur == "USC" || cur == "USX" || cur == "EUX" || cur == "GBX" ||
      StringFind(cur,"CENT") >= 0 || StringFind(cur,"USC") >= 0)
      return 0.01;
   double bid = SymbolInfoDouble(cur + "USD", SYMBOL_BID);
   if(bid > 0) return bid;
   bid = SymbolInfoDouble("USD" + cur, SYMBOL_BID);
   if(bid > 0) return 1.0 / bid;
   return 1.0;
}
double ToUsd(double amount) { return amount * GetUsdFactor(); }

//+------------------------------------------------------------------+
//| Magic number check                                               |
//+------------------------------------------------------------------+
bool IsOurMagic(ulong magic)
{
   for(int i = 0; i < TOTAL_TF; i++)
      if(g_bots[i].enabled && g_bots[i].magic == magic)
         return true;
   return false;
}

//+------------------------------------------------------------------+
//| Persistent state via GlobalVariables                             |
//+------------------------------------------------------------------+
void SaveState(int i)
{
   string key = g_pfx + _Symbol + "_" + g_bots[i].name;
   GlobalVariableSet(key + "_WAIT", g_bots[i].waitOppSignal ? 1.0 : 0.0);
   GlobalVariableSet(key + "_LAST", g_bots[i].lastWasLong   ? 1.0 : 0.0);
   GlobalVariableSet(key + "_EHT",  (double)g_bots[i].lastEntryHighTime);
   GlobalVariableSet(key + "_ELT",  (double)g_bots[i].lastEntryLowTime);
}

void LoadState(int i)
{
   string key = g_pfx + _Symbol + "_" + g_bots[i].name;
   if(GlobalVariableCheck(key + "_WAIT"))
      g_bots[i].waitOppSignal     = (GlobalVariableGet(key + "_WAIT") > 0.5);
   if(GlobalVariableCheck(key + "_LAST"))
      g_bots[i].lastWasLong       = (GlobalVariableGet(key + "_LAST") > 0.5);
   if(GlobalVariableCheck(key + "_EHT"))
      g_bots[i].lastEntryHighTime = (datetime)GlobalVariableGet(key + "_EHT");
   if(GlobalVariableCheck(key + "_ELT"))
      g_bots[i].lastEntryLowTime  = (datetime)GlobalVariableGet(key + "_ELT");
}

void ClearState(int i)
{
   string key = g_pfx + _Symbol + "_" + g_bots[i].name;
   GlobalVariableDel(key + "_WAIT");
   GlobalVariableDel(key + "_LAST");
   GlobalVariableDel(key + "_EHT");
   GlobalVariableDel(key + "_ELT");
}

//+------------------------------------------------------------------+
//| Forward declarations                                             |
//+------------------------------------------------------------------+
void DetectSwings(int i);
void CheckEntries(int i);
void ManageTrail(int i);
void SyncPositionsState();
void RedrawVisuals();
void RenderDashboard();
double CalcClosedPnL();
void DrawSwingLbl(string name, string txt, datetime t, double price, color clr, bool labelAbove);
void DrawHLine(string name, double price, color clr, ENUM_LINE_STYLE st, int w);
void UiLabel(string name, string txt, int x, int y, color clr, int sz, bool bold);
string RepeatStr(string s, int n);
string TfName(ENUM_TIMEFRAMES p);

//+------------------------------------------------------------------+
//| Initialize one TF bot                                            |
//+------------------------------------------------------------------+
void InitBot(int i, ENUM_TIMEFRAMES tf, string nm, bool enabled, ulong magicOff)
{
   g_bots[i].period  = tf;
   g_bots[i].name    = nm;
   g_bots[i].enabled = enabled;
   g_bots[i].magic   = InpBaseMagic + magicOff;

   g_bots[i].structure      = "SCANNING";
   g_bots[i].tradeDir       = "NONE";
   g_bots[i].buyArmed       = false;
   g_bots[i].sellArmed      = false;
   g_bots[i].buyZone        = 0;
   g_bots[i].sellZone       = 0;
   g_bots[i].swingHighPrice = 0;
   g_bots[i].swingLowPrice  = 0;
   g_bots[i].openPrice      = 0;
   g_bots[i].slPrice        = 0;
   g_bots[i].tpPrice        = 0;
   g_bots[i].floatPnL       = 0;

   g_bots[i].waitOppSignal     = false;
   g_bots[i].lastWasLong       = false;
   g_bots[i].lastBarTime       = 0;
   g_bots[i].lastEntryHighTime = 0;
   g_bots[i].lastEntryLowTime  = 0;

   ZeroMemory(g_bots[i].lastHigh);
   ZeroMemory(g_bots[i].prevHigh);
   ZeroMemory(g_bots[i].lastLow);
   ZeroMemory(g_bots[i].prevLow);

   LoadState(i);
}

//+------------------------------------------------------------------+
//| OnInit                                                           |
//+------------------------------------------------------------------+
int OnInit()
{
   if(!g_sym.Name(_Symbol)) { Print("[HHLL] ERROR: Cannot load symbol"); return INIT_FAILED; }
   g_sym.Refresh();
   g_trade.SetDeviationInPoints(InpSlippage);
   g_trade.SetTypeFillingBySymbol(_Symbol);

   InitBot(0, PERIOD_M1,  "M1",  InpM1,  1);
   InitBot(1, PERIOD_M2,  "M2",  InpM2,  2);
   InitBot(2, PERIOD_M3,  "M3",  InpM3,  3);
   InitBot(3, PERIOD_M4,  "M4",  InpM4,  4);
   InitBot(4, PERIOD_M5,  "M5",  InpM5,  5);
   InitBot(5, PERIOD_M10, "M10", InpM10, 10);
   InitBot(6, PERIOD_M15, "M15", InpM15, 15);
   InitBot(7, PERIOD_M30, "M30", InpM30, 30);
   InitBot(8, PERIOD_H1,  "H1",  InpH1,  60);

   // 1. Sync existing open positions directly from broker FIRST
   SyncPositionsState();

   // 2. Detect swings for all enabled TFs
   for(int i = 0; i < TOTAL_TF; i++)
      if(g_bots[i].enabled) DetectSwings(i);

   RedrawVisuals();
   EventSetTimer(1);
   if(InpShowDashboard) RenderDashboard();
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| OnDeinit                                                         |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   EventKillTimer();
   if(reason == REASON_REMOVE)
      for(int i = 0; i < TOTAL_TF; i++) ClearState(i);
   ObjectsDeleteAll(0, g_pfx);
   ChartRedraw(0);
}

//+------------------------------------------------------------------+
//| Swing Detection — runs on every new bar                          |
//+------------------------------------------------------------------+
void DetectSwings(int idx)
{
   int lookback = MathMax(InpPivotBars, 1);
   int total    = MathMax(InpScanBars, lookback * 4 + 2);

   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   int copied = CopyRates(_Symbol, g_bots[idx].period, 0, total, rates);
   if(copied < lookback * 4) return;

   // Collect pivot highs and lows from oldest to newest
   SSwingPoint highs[30], lows[30];
   int hc = 0, lc = 0;

   for(int k = copied - lookback - 1; k >= lookback + 1; k--)
   {
      if(hc >= 30 && lc >= 30) break;

      // Pivot High check
      bool isH = true;
      for(int r = 1; r <= lookback && isH; r++)
         if(rates[k].high <= rates[k + r].high || rates[k].high < rates[k - r].high)
            isH = false;
      if(isH && hc < 30)
      {
         highs[hc].price   = rates[k].high;
         highs[hc].time    = rates[k].time;
         highs[hc].isHigh  = true;
         highs[hc].swingType = (hc == 0) ? 1 : ((highs[hc].price > highs[hc-1].price) ? 1 : 2);
         hc++;
      }

      // Pivot Low check
      bool isL = true;
      for(int r = 1; r <= lookback && isL; r++)
         if(rates[k].low >= rates[k + r].low || rates[k].low > rates[k - r].low)
            isL = false;
      if(isL && lc < 30)
      {
         lows[lc].price    = rates[k].low;
         lows[lc].time     = rates[k].time;
         lows[lc].isHigh   = false;
         lows[lc].swingType = (lc == 0) ? 4 : ((lows[lc].price > lows[lc-1].price) ? 3 : 4);
         lc++;
      }
   }

   if(hc < 1 || lc < 1) return;

   // Update last/prev swings
   g_bots[idx].lastHigh = highs[hc - 1];
   g_bots[idx].prevHigh = (hc >= 2) ? highs[hc - 2] : highs[0];
   g_bots[idx].lastLow  = lows[lc - 1];
   g_bots[idx].prevLow  = (lc >= 2) ? lows[lc - 2] : lows[0];

   // Market Structure: BULLISH = HH(1) + HL(3), BEARISH = LH(2) + LL(4)
   bool isBull = (g_bots[idx].lastHigh.swingType == 1 && g_bots[idx].lastLow.swingType == 3);
   bool isBear = (g_bots[idx].lastHigh.swingType == 2 && g_bots[idx].lastLow.swingType == 4);

   // Looser fallback when only one side confirmed
   if(!isBull && !isBear)
   {
      isBull = (g_bots[idx].lastHigh.swingType == 1);
      isBear = (g_bots[idx].lastLow.swingType  == 4);
   }

   if(isBull)      g_bots[idx].structure = "BULLISH";
   else if(isBear) g_bots[idx].structure = "BEARISH";
   else            g_bots[idx].structure = "RANGING";

   // Arm retracement zones — strictly trend-aligned, skip if in trade
   if(g_bots[idx].tradeDir == "NONE" && !g_bots[idx].waitOppSignal)
   {
      g_bots[idx].buyArmed  = false;
      g_bots[idx].sellArmed = false;
      g_bots[idx].buyZone   = 0;
      g_bots[idx].sellZone  = 0;

      if(isBull)
      {
         // Swing base low (origin of move up) and peak high
         double swingLow  = (g_bots[idx].prevLow.price > 0 && g_bots[idx].prevLow.price < g_bots[idx].lastHigh.price) ? g_bots[idx].prevLow.price : g_bots[idx].lastLow.price;
         double swingHigh = g_bots[idx].lastHigh.price;
         if(swingLow >= swingHigh && g_bots[idx].lastLow.price < swingHigh)
            swingLow = g_bots[idx].lastLow.price;

         double sr = swingHigh - swingLow;
         if(sr > 0)
         {
            g_bots[idx].swingHighPrice = swingHigh;
            g_bots[idx].swingLowPrice  = swingLow;
            double zone = swingHigh - sr * (InpRetracePct / 100.0);
            if(zone > swingLow && zone < swingHigh)
            {
               g_bots[idx].buyZone  = zone;
               g_bots[idx].buyArmed = true;
            }
         }
      }
      else if(isBear)
      {
         // Swing peak high (origin of move down) and base low
         double swingHigh = (g_bots[idx].prevHigh.price > 0 && g_bots[idx].prevHigh.price > g_bots[idx].lastLow.price) ? g_bots[idx].prevHigh.price : g_bots[idx].lastHigh.price;
         double swingLow  = g_bots[idx].lastLow.price;
         if(swingHigh <= swingLow && g_bots[idx].lastHigh.price > swingLow)
            swingHigh = g_bots[idx].lastHigh.price;

         double sr = swingHigh - swingLow;
         if(sr > 0)
         {
            g_bots[idx].swingHighPrice = swingHigh;
            g_bots[idx].swingLowPrice  = swingLow;
            double zone = swingLow + sr * (InpRetracePct / 100.0);
            if(zone > swingLow && zone < swingHigh)
            {
               g_bots[idx].sellZone  = zone;
               g_bots[idx].sellArmed = true;
            }
         }
      }
   }

   // Draw swing labels ONLY for active chart TF
   if(g_bots[idx].period == _Period && InpDrawSwings)
   {
      for(int k = 0; k < hc; k++)
      {
         string lbl = (highs[k].swingType == 1) ? "HH" : "LH";
         color  clr = (highs[k].swingType == 1) ? clrLime : clrOrangeRed;
         DrawSwingLbl(g_pfx + "SW_H_" + TimeToString(highs[k].time),
                      lbl, highs[k].time, highs[k].price, clr, false);
      }
      for(int k = 0; k < lc; k++)
      {
         string lbl = (lows[k].swingType == 3) ? "HL" : "LL";
         color  clr = (lows[k].swingType == 3) ? clrDeepSkyBlue : clrTomato;
         DrawSwingLbl(g_pfx + "SW_L_" + TimeToString(lows[k].time),
                      lbl, lows[k].time, lows[k].price, clr, true);
      }
   }
}

//+------------------------------------------------------------------+
//| Calculate Lot Size based on Risk %                               |
//+------------------------------------------------------------------+
double CalculateLotSize(double slDistPrice)
{
   if(!InpUseAutoLot) return InpLotSize;
   if(slDistPrice <= 0) return InpLotSize; // Fallback

   double riskMoney = AccountInfoDouble(ACCOUNT_EQUITY) * (InpRiskPct / 100.0);
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);

   if(tickSize <= 0 || tickValue <= 0) return InpLotSize;

   // Normalize SL distance to ticks
   double ticks = slDistPrice / tickSize;
   double riskPerLot = ticks * tickValue;

   if(riskPerLot <= 0) return InpLotSize;

   double lot = riskMoney / riskPerLot;

   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

   lot = MathFloor(lot / lotStep) * lotStep;
   if(lot < minLot) lot = minLot;
   if(lot > maxLot) lot = maxLot;

   return lot;
}

//+------------------------------------------------------------------+
//| Check Entries — runs every tick for all enabled TFs              |
//+------------------------------------------------------------------+
void CheckEntries(int idx)
{
   // Skip if already in a trade for this TF magic (In-memory guard)
   if(g_bots[idx].tradeDir != "NONE") return;

   // Hard Broker Lock: Verify directly on broker that no open position exists for this magic
   for(int p = PositionsTotal() - 1; p >= 0; p--)
   {
      if(g_pos.SelectByIndex(p))
      {
         if(g_pos.Symbol() == _Symbol && (ulong)g_pos.Magic() == g_bots[idx].magic)
         {
            g_bots[idx].tradeDir  = (g_pos.PositionType() == POSITION_TYPE_BUY) ? "BUY" : "SELL";
            g_bots[idx].openPrice = g_pos.PriceOpen();
            g_bots[idx].slPrice   = g_pos.StopLoss();
            g_bots[idx].tpPrice   = g_pos.TakeProfit();
            return; // Position exists on broker! DO NOT OPEN ANOTHER!
         }
      }
   }

   // Skip if waiting for opposite signal
   if(g_bots[idx].waitOppSignal)
   {
      bool flipped = false;
      if( g_bots[idx].lastWasLong  && g_bots[idx].structure == "BEARISH") flipped = true;
      if(!g_bots[idx].lastWasLong  && g_bots[idx].structure == "BULLISH") flipped = true;
      if(flipped)
      {
         g_bots[idx].waitOppSignal = false;
         SaveState(idx);
      }
      else return;
   }

   g_sym.RefreshRates();
   double ask = g_sym.Ask();
   double bid = g_sym.Bid();
   if(ask <= 0 || bid <= 0) return;

   if(InpMaxSpread > 0)
   {
      double spread = (ask - bid) / _Point;
      if(spread > InpMaxSpread) return;
   }

   g_trade.SetExpertMagicNumber(g_bots[idx].magic);

   // -------------------------------------------------------
   // BUY pullback (only if structure is BULLISH)
   // -------------------------------------------------------
   if(InpTradeDirection != TRADE_DIR_SELL_ONLY && g_bots[idx].buyArmed && g_bots[idx].buyZone > 0 && g_bots[idx].structure == "BULLISH")
   {
      if(g_bots[idx].lastEntryHighTime == g_bots[idx].lastHigh.time)
      {
         g_bots[idx].buyArmed = false;
         return;
      }

      double baseLow = (g_bots[idx].swingLowPrice > 0) ? g_bots[idx].swingLowPrice : g_bots[idx].lastLow.price;

      // Trigger: ask at or below the pullback zone (+ tolerance) AND above swing origin baseLow
      if(ask <= (g_bots[idx].buyZone + PointsToPrice(InpEntryTolerance)) && ask > (baseLow - PointsToPrice(1.0)))
      {
         double minSl = PointsToPrice(4.0); // Safe minimum SL buffer ($4.00 on Gold)
         double sl = NormalizeDouble(baseLow - PointsToPrice(InpSlBuffer), _Digits);
         if((ask - sl) < minSl)
            sl = NormalizeDouble(ask - minSl, _Digits);
         double slDist = ask - sl;

         double tp = 0;
         double targetHigh = (g_bots[idx].swingHighPrice > ask) ? g_bots[idx].swingHighPrice : g_bots[idx].lastHigh.price;
         if(InpTpMode == TP_MODE_SWING_HL && targetHigh > ask)
            tp = NormalizeDouble(targetHigh, _Digits);
         else if(InpTpMode == TP_MODE_FIXED_POINTS)
            tp = NormalizeDouble(ask + PointsToPrice(InpFixedTpPts), _Digits);
         else
            tp = NormalizeDouble(ask + slDist * InpRRRatio, _Digits);
         
         if(tp <= ask) tp = NormalizeDouble(ask + slDist * 1.5, _Digits);

         double lotSize = CalculateLotSize(slDist);

         string comment = "HHLL_" + g_bots[idx].name + "_BUY";
         if(g_trade.Buy(lotSize, _Symbol, ask, sl, tp, comment))
         {
            g_bots[idx].tradeDir            = "BUY";
            g_bots[idx].openPrice           = ask;
            g_bots[idx].slPrice             = sl;
            g_bots[idx].tpPrice             = tp;
            g_bots[idx].buyArmed            = false;
            g_bots[idx].lastEntryHighTime   = g_bots[idx].lastHigh.time;
            SaveState(idx);

            PrintFormat("[HHLL %s] BUY @ %.5f | SL=%.5f (Risk: $%.2f) | TP=%.5f | Struct=%s",
                        g_bots[idx].name, ask, sl, slDist, tp, g_bots[idx].structure);

            if(g_bots[idx].period == _Period && InpDrawTradeLines)
            {
               DrawHLine(g_pfx + "ENTRY_L", ask, clrGold,      STYLE_SOLID, 2);
               DrawHLine(g_pfx + "SL_L",    sl,  clrTomato,    STYLE_DASH,  2);
               DrawHLine(g_pfx + "TP_L",    tp,  clrLimeGreen, STYLE_DASH,  2);
               ObjectDelete(0, g_pfx + "TRAIL_L");
               DrawSwingLbl(g_pfx + "TRADE_" + TimeToString(TimeCurrent()),
                            StringFormat("[%s BUY] E:%.2f SL:%.2f TP:%.2f", g_bots[idx].name, ask, sl, tp),
                            TimeCurrent(), ask, clrLime, false);
            }
         }
         else
         {
            PrintFormat("[HHLL %s] BUY FAILED: %d - %s", g_bots[idx].name,
                        g_trade.ResultRetcode(), g_trade.ResultRetcodeDescription());
         }
      }
   }

   // -------------------------------------------------------
   // SELL pullback (only if structure is BEARISH)
   // -------------------------------------------------------
   if(InpTradeDirection != TRADE_DIR_BUY_ONLY && g_bots[idx].sellArmed && g_bots[idx].sellZone > 0 && g_bots[idx].structure == "BEARISH")
   {
      if(g_bots[idx].lastEntryLowTime == g_bots[idx].lastLow.time)
      {
         g_bots[idx].sellArmed = false;
         return;
      }

      double baseHigh = (g_bots[idx].swingHighPrice > 0) ? g_bots[idx].swingHighPrice : g_bots[idx].lastHigh.price;

      // Trigger: bid at or above the pullback zone (- tolerance) AND below swing origin baseHigh
      if(bid >= (g_bots[idx].sellZone - PointsToPrice(InpEntryTolerance)) && bid < (baseHigh + PointsToPrice(1.0)))
      {
         double minSl = PointsToPrice(4.0); // Safe minimum SL buffer ($4.00 on Gold)
         double sl = NormalizeDouble(baseHigh + PointsToPrice(InpSlBuffer), _Digits);
         if((sl - bid) < minSl)
            sl = NormalizeDouble(bid + minSl, _Digits);
         double slDist = sl - bid;

         double tp = 0;
         double targetLow = (g_bots[idx].swingLowPrice > 0 && g_bots[idx].swingLowPrice < bid) ? g_bots[idx].swingLowPrice : g_bots[idx].lastLow.price;
         if(InpTpMode == TP_MODE_SWING_HL && targetLow < bid && targetLow > 0)
            tp = NormalizeDouble(targetLow, _Digits);
         else if(InpTpMode == TP_MODE_FIXED_POINTS)
            tp = NormalizeDouble(bid - PointsToPrice(InpFixedTpPts), _Digits);
         else
            tp = NormalizeDouble(bid - slDist * InpRRRatio, _Digits);
         
         if(tp >= bid) tp = NormalizeDouble(bid - slDist * 1.5, _Digits);

         double lotSize = CalculateLotSize(slDist);

         string comment = "HHLL_" + g_bots[idx].name + "_SELL";
         if(g_trade.Sell(lotSize, _Symbol, bid, sl, tp, comment))
         {
            g_bots[idx].tradeDir          = "SELL";
            g_bots[idx].openPrice         = bid;
            g_bots[idx].slPrice           = sl;
            g_bots[idx].tpPrice           = tp;
            g_bots[idx].sellArmed         = false;
            g_bots[idx].lastEntryLowTime  = g_bots[idx].lastLow.time;
            SaveState(idx);

            PrintFormat("[HHLL %s] SELL @ %.5f | SL=%.5f | TP=%.5f | Struct=%s",
                        g_bots[idx].name, bid, sl, tp, g_bots[idx].structure);

            if(g_bots[idx].period == _Period && InpDrawTradeLines)
            {
               DrawHLine(g_pfx + "ENTRY_L", bid, clrGold,      STYLE_SOLID, 2);
               DrawHLine(g_pfx + "SL_L",    sl,  clrTomato,    STYLE_DASH,  2);
               DrawHLine(g_pfx + "TP_L",    tp,  clrLimeGreen, STYLE_DASH,  2);
               ObjectDelete(0, g_pfx + "TRAIL_L");
               DrawSwingLbl(g_pfx + "TRADE_" + TimeToString(TimeCurrent()),
                            StringFormat("[%s SELL] E:%.2f SL:%.2f TP:%.2f", g_bots[idx].name, bid, sl, tp),
                            TimeCurrent(), bid, clrTomato, true);
            }
         }
         else
         {
            PrintFormat("[HHLL %s] SELL FAILED: %d - %s", g_bots[idx].name,
                        g_trade.ResultRetcode(), g_trade.ResultRetcodeDescription());
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Auto Trailing Stop Loss (Supports 4 Modes)                       |
//+------------------------------------------------------------------+
void ManageTrail(int idx)
{
   if(!InpTrailEnable || g_bots[idx].tradeDir == "NONE") return;

   g_sym.RefreshRates();
   double trailDist  = PointsToPrice(InpTrailDistance);
   double trailStep  = PointsToPrice(InpTrailStep);
   double trailAct   = PointsToPrice(InpTrailStart);
   double stopsLevel = MathMax((double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point, PointsToPrice(0.5));

   for(int p = PositionsTotal() - 1; p >= 0; p--)
   {
      if(!g_pos.SelectByIndex(p)) continue;
      if(g_pos.Symbol() != _Symbol) continue;
      if((ulong)g_pos.Magic() != g_bots[idx].magic) continue;

      ulong  ticket = g_pos.Ticket();
      double curSl  = g_pos.StopLoss();
      double curTp  = g_pos.TakeProfit();
      double openPx = g_pos.PriceOpen();

      if(g_pos.PositionType() == POSITION_TYPE_BUY)
      {
         double bid  = g_sym.Bid();
         double prof = bid - openPx;
         if(prof < trailAct) continue;

         double newSl = 0.0;

         // Mode 0: Swing HL Structure Trailing (Maximum Breathing Room)
         if(InpTrailMode == TRAIL_SWING_HL)
         {
            // Only trail when a real new Higher Low forms ABOVE entry price
            if(g_bots[idx].lastLow.price > openPx && (bid - g_bots[idx].lastLow.price) >= PointsToPrice(2.5))
               newSl = NormalizeDouble(g_bots[idx].lastLow.price - PointsToPrice(InpSlBuffer), _Digits);
            else if(prof >= (curTp > openPx ? (curTp - openPx) * 0.5 : PointsToPrice(6.0)))
               newSl = NormalizeDouble(openPx + PointsToPrice(1.0), _Digits); // 50% target lock
         }
         // Mode 1: Previous Candle Low Trailing
         else if(InpTrailMode == TRAIL_PREVIOUS_CANDLE)
         {
            double pLow = iLow(_Symbol, g_bots[idx].period, 1);
            if(pLow > 0 && pLow < bid && (bid - pLow) >= PointsToPrice(2.5))
               newSl = NormalizeDouble(pLow - PointsToPrice(InpSlBuffer), _Digits);
         }
         // Mode 2: Fixed Points / Dollar Distance Trailing
         else if(InpTrailMode == TRAIL_POINTS_DISTANCE)
         {
            newSl = NormalizeDouble(bid - trailDist, _Digits);
         }
         // Mode 3: Break-Even Only
         else if(InpTrailMode == TRAIL_BREAK_EVEN_ONLY)
         {
            newSl = NormalizeDouble(openPx + PointsToPrice(1.0), _Digits);
         }

         // Validate new SL is higher than current SL, locks at least Break-Even, and satisfies broker stop level
         if(newSl > curSl + trailStep && newSl >= openPx && (bid - newSl) >= stopsLevel)
         {
            if(g_trade.PositionModify(ticket, newSl, curTp))
            {
               g_bots[idx].slPrice = newSl;
               PrintFormat("[HHLL %s] TRAIL BUY SL → %.5f (Bid: %.5f | Profit: +$%.2f)",
                           g_bots[idx].name, newSl, bid, prof);
               if(g_bots[idx].period == _Period && InpDrawTradeLines)
                  DrawHLine(g_pfx + "TRAIL_L", newSl, clrOrangeRed, STYLE_SOLID, 2);
            }
         }
      }
      else if(g_pos.PositionType() == POSITION_TYPE_SELL)
      {
         double ask  = g_sym.Ask();
         double prof = openPx - ask;
         if(prof < trailAct) continue;

         double newSl = 0.0;

         // Mode 0: Swing LH Structure Trailing (Maximum Breathing Room)
         if(InpTrailMode == TRAIL_SWING_HL)
         {
            // Only trail when a real new Lower High forms BELOW entry price
            if(g_bots[idx].lastHigh.price > 0 && g_bots[idx].lastHigh.price < openPx && (g_bots[idx].lastHigh.price - ask) >= PointsToPrice(2.5))
               newSl = NormalizeDouble(g_bots[idx].lastHigh.price + PointsToPrice(InpSlBuffer), _Digits);
            else if(prof >= (curTp < openPx && curTp > 0 ? (openPx - curTp) * 0.5 : PointsToPrice(6.0)))
               newSl = NormalizeDouble(openPx - PointsToPrice(1.0), _Digits); // 50% target lock
         }
         // Mode 1: Previous Candle High Trailing
         else if(InpTrailMode == TRAIL_PREVIOUS_CANDLE)
         {
            double pHigh = iHigh(_Symbol, g_bots[idx].period, 1);
            if(pHigh > 0 && pHigh > ask && (pHigh - ask) >= PointsToPrice(2.5))
               newSl = NormalizeDouble(pHigh + PointsToPrice(InpSlBuffer), _Digits);
         }
         // Mode 2: Fixed Points / Dollar Distance Trailing
         else if(InpTrailMode == TRAIL_POINTS_DISTANCE)
         {
            newSl = NormalizeDouble(ask + trailDist, _Digits);
         }
         // Mode 3: Break-Even Only
         else if(InpTrailMode == TRAIL_BREAK_EVEN_ONLY)
         {
            newSl = NormalizeDouble(openPx - PointsToPrice(1.0), _Digits);
         }

         // Validate new SL is lower than current SL, locks at least Break-Even, and satisfies broker stop level
         if((curSl == 0 || newSl < curSl - trailStep) && newSl <= openPx && (newSl - ask) >= stopsLevel && newSl > 0)
         {
            if(g_trade.PositionModify(ticket, newSl, curTp))
            {
               g_bots[idx].slPrice = newSl;
               PrintFormat("[HHLL %s] TRAIL SELL SL → %.5f (Ask: %.5f | Profit: +$%.2f)",
                           g_bots[idx].name, newSl, ask, prof);
               if(g_bots[idx].period == _Period && InpDrawTradeLines)
                  DrawHLine(g_pfx + "TRAIL_L", newSl, clrOrangeRed, STYLE_SOLID, 2);
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Sync each bot state with live broker positions                   |
//+------------------------------------------------------------------+
void SyncPositionsState()
{
   for(int i = 0; i < TOTAL_TF; i++)
   {
      if(!g_bots[i].enabled) continue;

      bool found = false;
      for(int p = PositionsTotal() - 1; p >= 0; p--)
      {
         if(!g_pos.SelectByIndex(p)) continue;
         if(g_pos.Symbol() != _Symbol) continue;
         if((ulong)g_pos.Magic() != g_bots[i].magic) continue;

         found = true;
         g_bots[i].tradeDir  = (g_pos.PositionType() == POSITION_TYPE_BUY) ? "BUY" : "SELL";
         g_bots[i].openPrice = g_pos.PriceOpen();
         g_bots[i].slPrice   = g_pos.StopLoss();
         g_bots[i].tpPrice   = g_pos.TakeProfit();
         g_bots[i].floatPnL  = ToUsd(g_pos.Profit() + g_pos.Swap() + g_pos.Commission());
         break;
      }

      if(!found && g_bots[i].tradeDir != "NONE")
      {
         // Position just closed — check if it was profitable (TP hit)
         if(HistorySelect(TimeCurrent() - 86400, TimeCurrent()))
         {
            int nd = HistoryDealsTotal();
            for(int d = nd - 1; d >= 0; d--)
            {
               ulong dt = HistoryDealGetTicket(d);
               if(HistoryDealGetString(dt, DEAL_SYMBOL) != _Symbol) continue;
               if((ulong)HistoryDealGetInteger(dt, DEAL_MAGIC) != g_bots[i].magic) continue;
               ENUM_DEAL_ENTRY de = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(dt, DEAL_ENTRY);
               if(de != DEAL_ENTRY_OUT && de != DEAL_ENTRY_INOUT) continue;

               double profit = HistoryDealGetDouble(dt, DEAL_PROFIT);
               if(profit > 0)
               {
                  g_bots[i].waitOppSignal = true;
                  g_bots[i].lastWasLong   = (g_bots[i].tradeDir == "BUY");
                  SaveState(i);
               }
               break;
            }
         }

         g_bots[i].tradeDir  = "NONE";
         g_bots[i].openPrice = 0;
         g_bots[i].slPrice   = 0;
         g_bots[i].tpPrice   = 0;
         g_bots[i].floatPnL  = 0;

         // Re-arm zone if not waiting for opposite signal
         if(!g_bots[i].waitOppSignal)
         {
            if(g_bots[i].structure == "BULLISH")
            {
               double swingLow  = (g_bots[i].swingLowPrice > 0) ? g_bots[i].swingLowPrice : g_bots[i].lastLow.price;
               double swingHigh = g_bots[i].lastHigh.price;
               double sr        = swingHigh - swingLow;
               if(sr > 0)
               {
                  double zone = swingHigh - sr * (InpRetracePct / 100.0);
                  if(zone > swingLow && zone < swingHigh)
                  {
                     g_bots[i].buyZone  = zone;
                     g_bots[i].buyArmed = true;
                  }
               }
            }
            else if(g_bots[i].structure == "BEARISH")
            {
               double swingHigh = (g_bots[i].swingHighPrice > 0) ? g_bots[i].swingHighPrice : g_bots[i].lastHigh.price;
               double swingLow  = g_bots[i].lastLow.price;
               double sr        = swingHigh - swingLow;
               if(sr > 0)
               {
                  double zone = swingLow + sr * (InpRetracePct / 100.0);
                  if(zone > swingLow && zone < swingHigh)
                  {
                     g_bots[i].sellZone  = zone;
                     g_bots[i].sellArmed = true;
                  }
               }
            }
         }
      }

      if(!found)
      {
         g_bots[i].tradeDir  = "NONE";
         g_bots[i].floatPnL  = 0;
      }
   }
}

//+------------------------------------------------------------------+
//| OnTick                                                           |
//+------------------------------------------------------------------+
void OnTick()
{
   SyncPositionsState();

   for(int i = 0; i < TOTAL_TF; i++)
   {
      if(!g_bots[i].enabled) continue;

      // Swing detection on new bar, or if uninitialized
      datetime barTime = iTime(_Symbol, g_bots[i].period, 0);
      if(barTime != g_bots[i].lastBarTime || g_bots[i].lastHigh.price == 0)
      {
         g_bots[i].lastBarTime = barTime;
         DetectSwings(i);
      }

      // Entry: only on active chart TF (or all TFs if InpActiveChartOnly=false)
      if(!InpActiveChartOnly || g_bots[i].period == _Period)
         CheckEntries(i);

      // Trailing SL: always, regardless of TF
      ManageTrail(i);
   }

   if(InpShowDashboard) RenderDashboard();
}

//+------------------------------------------------------------------+
//| OnTimer — heartbeat refresh                                      |
//+------------------------------------------------------------------+
void OnTimer()
{
   SyncPositionsState();
   if(InpShowDashboard) RenderDashboard();
}

//+------------------------------------------------------------------+
//| OnChartEvent — instant redraw on TF change                       |
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
   if(id == CHARTEVENT_CHART_CHANGE)
   {
      RedrawVisuals();
      if(InpShowDashboard) RenderDashboard();
   }
}

//+------------------------------------------------------------------+
//| Redraw all chart visuals (Swings for active TF + All Open Trades)|
//+------------------------------------------------------------------+
void RedrawVisuals()
{
   // Clear chart-specific objects
   ObjectsDeleteAll(0, g_pfx + "SW_");
   ObjectsDeleteAll(0, g_pfx + "TRADE_");
   ObjectsDeleteAll(0, g_pfx + "ZONE_");
   ObjectsDeleteAll(0, g_pfx + "ENTRY_");
   ObjectsDeleteAll(0, g_pfx + "SL_");
   ObjectsDeleteAll(0, g_pfx + "TP_");
   ObjectsDeleteAll(0, g_pfx + "TRAIL_");

   // 1. Draw Swings and Pullback Zones for Active Chart Timeframe
   int ai = -1;
   for(int i = 0; i < TOTAL_TF; i++)
      if(g_bots[i].period == _Period && g_bots[i].enabled) { ai = i; break; }

   if(ai >= 0)
   {
      DetectSwings(ai);

      // Pullback zone lines for active chart TF
      if(InpDrawTradeLines)
      {
         if(g_bots[ai].buyArmed  && g_bots[ai].buyZone  > 0)
            DrawHLine(g_pfx + "ZONE_BUY",  g_bots[ai].buyZone,  clrDeepSkyBlue, STYLE_DOT, 1);
         if(g_bots[ai].sellArmed && g_bots[ai].sellZone > 0)
            DrawHLine(g_pfx + "ZONE_SELL", g_bots[ai].sellZone, clrOrange,      STYLE_DOT, 1);
      }
   }

   // 2. Draw Entry, SL & TP Lines for ALL OPEN TRADES across ANY Timeframe!
   if(InpDrawTradeLines)
   {
      for(int i = 0; i < TOTAL_TF; i++)
      {
         if(g_bots[i].tradeDir != "NONE")
         {
            string tfName = g_bots[i].name;
            int width = (g_bots[i].period == _Period) ? 2 : 1;
            if(g_bots[i].openPrice > 0)
               DrawHLine(g_pfx + "ENTRY_" + tfName, g_bots[i].openPrice, clrGold,      STYLE_SOLID, width);
            if(g_bots[i].slPrice > 0)
               DrawHLine(g_pfx + "SL_" + tfName,    g_bots[i].slPrice,   clrTomato,    STYLE_DASH,  width);
            if(g_bots[i].tpPrice > 0)
               DrawHLine(g_pfx + "TP_" + tfName,    g_bots[i].tpPrice,   clrLimeGreen, STYLE_DASH,  width);
         }
      }
   }

   ChartRedraw(0);
}

//+------------------------------------------------------------------+
//| Dashboard                                                        |
//+------------------------------------------------------------------+
void RenderDashboard()
{
   int x  = InpDashX;
   int y  = InpDashY;
   int rh = 17;
   int totalRows = 4 + TOTAL_TF + 4;

   string bg = g_pfx + "BG";
   if(ObjectFind(0, bg) < 0)
   {
      ObjectCreate(0, bg, OBJ_RECTANGLE_LABEL, 0, 0, 0);
      ObjectSetInteger(0, bg, OBJPROP_CORNER,     CORNER_LEFT_UPPER);
      ObjectSetInteger(0, bg, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, bg, OBJPROP_BACK,       false);
   }
   ObjectSetInteger(0, bg, OBJPROP_XDISTANCE,   x - 10);
   ObjectSetInteger(0, bg, OBJPROP_YDISTANCE,   y - 8);
   ObjectSetInteger(0, bg, OBJPROP_XSIZE,       390);
   ObjectSetInteger(0, bg, OBJPROP_YSIZE,       totalRows * rh + 16);
   ObjectSetInteger(0, bg, OBJPROP_BGCOLOR,     C'18,22,30');
   ObjectSetInteger(0, bg, OBJPROP_BORDER_COLOR,C'50,60,90');
   ObjectSetInteger(0, bg, OBJPROP_BORDER_TYPE, BORDER_FLAT);

   UiLabel(g_pfx+"H1","=== HH/LL MARKET STRUCTURE EA v10.10 ===",x,y,clrGold,9,true);
   y += rh + 1;
   string dirStr = (InpTradeDirection == TRADE_DIR_BUY_ONLY) ? "BUY ONLY" : (InpTradeDirection == TRADE_DIR_SELL_ONLY) ? "SELL ONLY" : "BOTH";
   string lotStr = InpUseAutoLot ? StringFormat("AutoLot:%.1f%%", InpRiskPct) : StringFormat("Lot:%.2f", InpLotSize);
   UiLabel(g_pfx+"H2",
           StringFormat("%s | %s | %s | %s",
           _Symbol, dirStr,
           InpActiveChartOnly ? "Single-TF" : "Multi-TF",
           lotStr),
           x,y,clrSkyBlue,8,false);
   y += rh;
   UiLabel(g_pfx+"SEP1", RepeatStr("-",54), x, y, clrDarkGray, 8, false);
   y += rh - 3;

   // Per-TF rows
   for(int i = 0; i < TOTAL_TF; i++)
   {
      string lbl = g_pfx + "R_" + IntegerToString(i);
      color  clr = clrDarkGray;
      string txt;

      if(!g_bots[i].enabled)
      {
         txt = StringFormat("%-4s  OFF", g_bots[i].name);
         clr = clrDarkGray;
      }
      else if(g_bots[i].tradeDir == "BUY" || g_bots[i].tradeDir == "SELL")
      {
         string slStr = (g_bots[i].slPrice > 0) ? StringFormat("SL:%.2f", g_bots[i].slPrice) : "SL:---";
         string tpStr = (g_bots[i].tpPrice > 0) ? StringFormat("TP:%.2f", g_bots[i].tpPrice) : "TP:---";
         txt = StringFormat("%-4s  %-4s  %+.2f$  %s  %s",
               g_bots[i].name, g_bots[i].tradeDir,
               g_bots[i].floatPnL, slStr, tpStr);
         clr = (g_bots[i].floatPnL >= 0) ? clrLime : clrTomato;
      }
      else
      {
         string stateStr;
         if(g_bots[i].waitOppSignal)
            stateStr = StringFormat("Wait %s", g_bots[i].lastWasLong ? "SELL" : "BUY");
         else
            stateStr = g_bots[i].structure;

         string armStr = g_bots[i].buyArmed  ? StringFormat("ARM:BUY@%.2f",  g_bots[i].buyZone)  :
                         g_bots[i].sellArmed ? StringFormat("ARM:SELL@%.2f", g_bots[i].sellZone) :
                         "NoZone";
         txt = StringFormat("%-4s  NONE  %s  %s", g_bots[i].name, stateStr, armStr);
         clr = clrSilver;
      }

      UiLabel(lbl, txt, x, y, clr, 8, false);
      y += rh;
   }

   UiLabel(g_pfx+"SEP2", RepeatStr("-",54), x, y, clrDarkGray, 8, false);
   y += rh - 3;

   // Totals
   int nB = 0, nS = 0;
   double flt = 0, lots = 0;
   for(int p = PositionsTotal() - 1; p >= 0; p--)
   {
      if(!g_pos.SelectByIndex(p)) continue;
      if(g_pos.Symbol() != _Symbol) continue;
      if(!IsOurMagic((ulong)g_pos.Magic())) continue;
      if(g_pos.PositionType() == POSITION_TYPE_BUY) nB++; else nS++;
      flt  += ToUsd(g_pos.Profit() + g_pos.Swap() + g_pos.Commission());
      lots += g_pos.Volume();
   }
   double closed = CalcClosedPnL();
   double total  = flt + closed;

   UiLabel(g_pfx+"S1",
           StringFormat("Positions: %d (B:%d S:%d | %.2f lots)", nB+nS, nB, nS, lots),
           x, y, clrWhite, 8, false);
   y += rh;

   color fc = flt    > 0 ? clrLime : flt    < 0 ? clrTomato : clrWhite;
   color cc = closed > 0 ? clrLime : closed < 0 ? clrTomato : clrWhite;
   color tc = total  > 0 ? clrLime : total  < 0 ? clrTomato : clrWhite;

   UiLabel(g_pfx+"S2", StringFormat("Floating PnL :  $%.2f USD", flt),    x, y, fc, 9, true); y += rh;
   UiLabel(g_pfx+"S3", StringFormat("Closed PnL   :  $%.2f USD", closed), x, y, cc, 9, true); y += rh;
   UiLabel(g_pfx+"S4", StringFormat("TOTAL PnL    :  $%.2f USD", total),  x, y, tc, 9, true);

   ChartRedraw(0);
}

//+------------------------------------------------------------------+
//| Closed PnL for our magic numbers only                            |
//+------------------------------------------------------------------+
double CalcClosedPnL()
{
   static int lastDealsTotal = -1;
   static double cachedPnL = 0;

   if(!HistorySelect(0, TimeCurrent())) return cachedPnL;

   int nd = HistoryDealsTotal();
   if(nd == lastDealsTotal) return cachedPnL;

   ulong posIds[];
   ArrayResize(posIds, nd);
   int   posCount = 0;

   // Pass 1: collect position IDs opened by our magics
   for(int d = 0; d < nd; d++)
   {
      ulong dt = HistoryDealGetTicket(d);
      if(!dt) continue;
      if(HistoryDealGetString(dt, DEAL_SYMBOL) != _Symbol) continue;
      if(!IsOurMagic((ulong)HistoryDealGetInteger(dt, DEAL_MAGIC))) continue;
      ENUM_DEAL_ENTRY de = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(dt, DEAL_ENTRY);
      if(de != DEAL_ENTRY_IN && de != DEAL_ENTRY_INOUT) continue;
      ulong pid = (ulong)HistoryDealGetInteger(dt, DEAL_POSITION_ID);
      if(!pid) continue;
      bool found = false;
      for(int k = 0; k < posCount; k++) if(posIds[k] == pid) { found = true; break; }
      if(!found) { posIds[posCount++] = pid; }
   }

   // Pass 2: sum closing deals for those positions
   double total = 0;
   for(int d = 0; d < nd; d++)
   {
      ulong dt = HistoryDealGetTicket(d);
      if(!dt) continue;
      if(HistoryDealGetString(dt, DEAL_SYMBOL) != _Symbol) continue;
      ENUM_DEAL_ENTRY de = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(dt, DEAL_ENTRY);
      if(de != DEAL_ENTRY_OUT && de != DEAL_ENTRY_INOUT && de != DEAL_ENTRY_OUT_BY) continue;
      ulong pid = (ulong)HistoryDealGetInteger(dt, DEAL_POSITION_ID);
      bool match = false;
      for(int k = 0; k < posCount; k++) if(posIds[k] == pid) { match = true; break; }
      if(!match) continue;
      total += HistoryDealGetDouble(dt, DEAL_PROFIT)
             + HistoryDealGetDouble(dt, DEAL_SWAP)
             + HistoryDealGetDouble(dt, DEAL_COMMISSION)
             + HistoryDealGetDouble(dt, DEAL_FEE);
   }

   lastDealsTotal = nd;
   cachedPnL = ToUsd(total);
   return cachedPnL;
}

//+------------------------------------------------------------------+
//| Drawing helpers                                                  |
//+------------------------------------------------------------------+
void DrawSwingLbl(string name, string txt, datetime t, double price, color clr, bool labelAbove)
{
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_TEXT, 0, t, price);
   ObjectSetString(0,  name, OBJPROP_TEXT,     txt);
   ObjectSetInteger(0, name, OBJPROP_COLOR,    clr);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 9);
   ObjectSetString(0,  name, OBJPROP_FONT,     "Consolas Bold");
   ObjectSetInteger(0, name, OBJPROP_ANCHOR,   labelAbove ? ANCHOR_UPPER : ANCHOR_LOWER);
   ObjectSetDouble(0,  name, OBJPROP_PRICE,    price);
   ObjectSetInteger(0, name, OBJPROP_TIME,     t);
}

void DrawHLine(string name, double price, color clr, ENUM_LINE_STYLE st, int w)
{
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_HLINE, 0, 0, price);
   ObjectSetDouble(0,  name, OBJPROP_PRICE, price);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_STYLE, st);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, w);
   ObjectSetInteger(0, name, OBJPROP_BACK,  true);
}

void UiLabel(string name, string txt, int x, int y, color clr, int sz, bool bold)
{
   if(ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_CORNER,     CORNER_LEFT_UPPER);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_BACK,       false);
      ObjectSetInteger(0, name, OBJPROP_ZORDER,     10);
   }
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetString(0,  name, OBJPROP_TEXT,      txt);
   ObjectSetInteger(0, name, OBJPROP_COLOR,     clr);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE,  sz);
   ObjectSetString(0,  name, OBJPROP_FONT,      bold ? "Consolas Bold" : "Consolas");
   ObjectSetInteger(0, name, OBJPROP_BACK,      false);
   ObjectSetInteger(0, name, OBJPROP_ZORDER,    10);
}

string RepeatStr(string s, int n)
{
   string r = "";
   for(int i = 0; i < n; i++) r += s;
   return r;
}

string TfName(ENUM_TIMEFRAMES p)
{
   switch(p)
   {
      case PERIOD_M1:  return "M1";
      case PERIOD_M2:  return "M2";
      case PERIOD_M3:  return "M3";
      case PERIOD_M4:  return "M4";
      case PERIOD_M5:  return "M5";
      case PERIOD_M10: return "M10";
      case PERIOD_M15: return "M15";
      case PERIOD_M30: return "M30";
      case PERIOD_H1:  return "H1";
      default:         return "??";
   }
}
//+------------------------------------------------------------------+
