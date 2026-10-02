//+------------------------------------------------------------------+
//|                                                SanjuKaka_EA.mq5  |
//|                                  Copyright 2026, Sanju Kaka Algo |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright   "Copyright 2026, Sanju Kaka Algo"
#property link        "https://www.mql5.com"
#property version     "1.00"
#property description "Institutional 10-Module Multi-Strategy EA with Amarvel Hedge, Cockroach Kill-Switch & Stealth Engine"

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include "Defines.mqh"
#include "SecurityGuard.mqh"
#include "NewsSpreadGuard.mqh"
#include "RiskManager.mqh"
#include "StealthGrid.mqh"
#include "Strategies.mqh"

//+------------------------------------------------------------------+
//| INPUT PARAMETERS                                                 |
//+------------------------------------------------------------------+
sinput string   Section_000               = "=== [0] CHART TAB & OPERATION MODE ===";
input ENUM_OPERATION_MODE InpTabMode      = MODE_ALL_MODULES_MASTER; // Chart Tab Strategy Assignment
input bool      InpAutoOpenModuleTabs     = false;                  // Auto-Spawn Dedicated Gold Chart Tabs

sinput string   Section_00                = "=== [1] SECURITY & ASSET LOCK ===";
input bool      InpGoldOnly               = true;        // Restrict Trading to GOLD (XAUUSD) Only
input string    InpAuthorizedAccounts     = "";          // Authorized Accounts (comma-separated, blank=Demo)

sinput string   Section_01                = "=== [2] CAPITAL & RISK DEFENSE ===";
input double    InpCockroachKillSwitchPct = 20.0;        // Cockroach Kill-Switch Drawdown % (Default: 20%)
input double    InpAmarvelHedgeDDPct      = 5.0;         // Amarvel Hedge Lock Trigger Drawdown % (Default: 5%)
input int       InpCoolOffHours           = 24;          // Cool-Off Period after Kill-Switch (Hours)
input int       InpSlippageBufferPoints   = 30;          // Slippage Buffer (Points)

sinput string   Section_02                = "=== [3] DOLLAR PROFIT, LOSS & TRAILING ($ USD) ===";
input bool      InpUseTrailingUSD         = true;        // Enable Dollar Trailing Stop Loss (True/False)
input double    InpTargetProfitUSD        = 15.0;        // Target Take Profit in Dollars ($ USD, 1:3 Ratio: $15)
input double    InpLossLimitUSD           = 5.0;         // Max Stop Loss Limit in Dollars ($ USD, 1:3 Ratio: $5)
input double    InpTrailingStartUSD       = 10.0;        // Trailing Start Profit in Dollars ($ USD, $10)
input double    InpTrailingStopUSD        = 3.0;         // Trailing Retrace Drop to Close in Dollars ($ USD, $3)
input double    InpTrailingStepUSD        = 1.0;         // Trailing Step Increment in Dollars ($ USD, $1)
input int       InpGridStepPoints         = 200;         // Smart Grid Pullback Spacing (Points)

sinput string   Section_03                = "=== [4] NEWS & SPREAD FILTERS ===";
input bool      InpUseNewsFilter          = true;        // Enable High-Impact News Filter
input int       InpNewsMinsBefore         = 15;          // Pause Trading Mins Before News
input int       InpNewsMinsAfter          = 15;          // Pause Trading Mins After News
input bool      InpUseSpreadFilter        = true;        // Enable Spread Spike Filter
input int       InpMaxSpreadPoints        = 35;          // Maximum Allowed Spread (Points)

sinput string   Section_04                = "=== [5] STRATEGY MODULE TOGGLES ===";
input bool      InpEnableM1_RSI_EMA       = true;        // Module 1: RSI + 50 EMA (Magic 1001)
input bool      InpEnableM2_BB_Stoch      = true;        // Module 2: BB + Stochastic (Magic 1002)
input bool      InpEnableM3_MACD          = true;        // Module 3: MACD Crossover (Magic 1003)
input bool      InpEnableM4_HL_Breakout   = true;        // Module 4: 20-Bar H/L Breakout (Magic 1004)
input bool      InpEnableM5_PSAR_EMA      = true;        // Module 5: PSAR + 200 EMA (Magic 1005)
input bool      InpEnableM6_ATR_Vol       = true;        // Module 6: ATR Volatility (Magic 1006)
input bool      InpEnableM7_Dual_EMA      = true;        // Module 7: Dual EMA 9/21 (Magic 1007)
input bool      InpEnableM8_PriceAction   = true;        // Module 8: Engulfing Pattern (Magic 1008)
input bool      InpEnableM9_Supertrend    = true;        // Module 9: Supertrend (Magic 1009)
input bool      InpEnableM10_MasterGuard  = true;        // Module 10: Master Capital Defense (Magic 1010)

sinput string   Section_05                = "=== [6] 11th SNIPER SCALPER MODULE ===";
input bool      InpEnableM11_Sniper       = false;       // Module 11: Sniper Scalper (Magic 1011)

sinput string   Section_06                = "=== [7] CHART DISPLAY & VISUALS ===";
input bool      InpHideIndicatorsFromChart = true;       // Hide Indicators from Chart (Clean Chart Mode)

//+------------------------------------------------------------------+
//| GLOBAL OBJECTS & STATE                                           |
//+------------------------------------------------------------------+
CTrade              g_trade;
CPositionInfo       g_position;
CRiskManager        g_risk;
CStealthGridEngine  g_stealth;
CStrategyEngine     g_strategies;
CNewsSpreadGuard    g_newsGuard;

datetime            g_lastBarTime = 0;
bool                g_isAuthorized = false;

//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   // 1. Suppress all visual indicator rendering immediately for maximum speed
   if(InpHideIndicatorsFromChart)
   {
      TesterHideIndicators(true);
      CleanIndicatorsFromChart();
   }
   
   // 2. Strict Asset Lock Check (GOLD / XAUUSD Only)
   if(InpGoldOnly && !IsGoldSymbol(_Symbol))
   {
      Alert(StringFormat("[GOLD LOCK ERROR] %s is not a Gold symbol! SanjuKaka EA is configured to operate strictly on GOLD (XAUUSD/GOLD).", _Symbol));
      Print(StringFormat("[Asset Firewall] Rejected initialization on %s. Please attach EA to XAUUSD / GOLD chart.", _Symbol));
      return INIT_FAILED;
   }
   
   // 3. Security & Account Binding Check
   g_isAuthorized = CSecurityGuard::CheckAccountAuthorization(InpAuthorizedAccounts);
   if(!g_isAuthorized)
   {
      Alert("[SECURITY ERROR] Unauthorized MetaTrader account. EA initialization aborted.");
      return INIT_FAILED;
   }
   
   if(!CSecurityGuard::IsTradeContextReady())
   {
      Print("[Warning] Algo Trading permissions are required for full execution.");
   }
   
   // 3. Initialize Risk Manager (Fixed 0.01 Lot)
   g_risk.Init(0.01, InpAmarvelHedgeDDPct, InpCockroachKillSwitchPct, InpCoolOffHours, InpSlippageBufferPoints);
   
   // 4. Initialize Stealth Dollar Engine (1:3 Target $15 Profit vs $5 Loss Limit in USD)
   g_stealth.Init(InpUseTrailingUSD, InpTargetProfitUSD, InpLossLimitUSD,
                  InpTrailingStartUSD, InpTrailingStopUSD, InpTrailingStepUSD,
                  InpGridStepPoints);
                  
   // 5. Initialize News & Spread Guard
   g_newsGuard.Init(InpUseNewsFilter, InpNewsMinsBefore, InpNewsMinsAfter, InpUseSpreadFilter, InpMaxSpreadPoints);
   
   // 6. Initialize Strategy Indicators (Configured according to Tab Mode)
   bool enM1  = (InpTabMode == MODE_ALL_MODULES_MASTER) ? InpEnableM1_RSI_EMA       : (InpTabMode == MODE_MODULE_M1_RSI_EMA);
   bool enM2  = (InpTabMode == MODE_ALL_MODULES_MASTER) ? InpEnableM2_BB_Stoch      : (InpTabMode == MODE_MODULE_M2_BB_STOCH);
   bool enM3  = (InpTabMode == MODE_ALL_MODULES_MASTER) ? InpEnableM3_MACD          : (InpTabMode == MODE_MODULE_M3_MACD);
   bool enM5  = (InpTabMode == MODE_ALL_MODULES_MASTER) ? InpEnableM5_PSAR_EMA      : (InpTabMode == MODE_MODULE_M5_PSAR_EMA);
   bool enM6  = (InpTabMode == MODE_ALL_MODULES_MASTER) ? InpEnableM6_ATR_Vol       : (InpTabMode == MODE_MODULE_M6_ATR_VOL);
   bool enM7  = (InpTabMode == MODE_ALL_MODULES_MASTER) ? InpEnableM7_Dual_EMA      : (InpTabMode == MODE_MODULE_M7_DUAL_EMA);
   bool enM9  = (InpTabMode == MODE_ALL_MODULES_MASTER) ? InpEnableM9_Supertrend    : (InpTabMode == MODE_MODULE_M9_SUPERTREND);
   bool enSnip= (InpTabMode == MODE_ALL_MODULES_MASTER) ? InpEnableM11_Sniper       : (InpTabMode == MODE_MODULE_M11_SNIPER);

   if(!g_strategies.Init(_Symbol, _Period, enM1, enM2, enM3, enM5, enM6, enM7, enM9, enSnip))
   {
      Print("[Error] Failed to initialize strategy indicators.");
      return INIT_FAILED;
   }
   
   g_trade.SetDeviationInPoints(InpSlippageBufferPoints);
   g_trade.SetTypeFilling(ORDER_FILLING_IOC);
   
   EventSetTimer(1); // 1-second GUI and Monitor timer
   
   if(InpHideIndicatorsFromChart)
      CleanIndicatorsFromChart();
      
   // Auto-spawn dedicated tabs on Gold chart if requested
   if(InpAutoOpenModuleTabs && InpTabMode == MODE_ALL_MODULES_MASTER && !MQLInfoInteger(MQL_TESTER))
   {
      SpawnDedicatedModuleTabs();
   }
      
   PrintFormat("[SanjuKaka EA] Initialized successfully. Tab Role: %s", EnumToString(InpTabMode));
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   EventKillTimer();
   Comment(""); // Clear chart HUD
   g_strategies.ReleaseHandles();
   PrintFormat("[SanjuKaka EA] Deinitialized. Reason code: %d", reason);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   if(!g_isAuthorized) return;
   
   int totalPositions = PositionsTotal();
   
   // 1. Real-time Stealth Virtual TP/SL and Dynamic Trailing Stop (Only when trades are open)
   if(totalPositions > 0)
   {
      g_stealth.OnTickProcess(_Symbol);
      
      // 2. Cockroach 80-20 Hard Kill-Switch & Amarvel Hedge Monitor
      if(InpEnableM10_MasterGuard || InpTabMode == MODE_MODULE_M10_MASTER_GUARD)
      {
         if(g_risk.CheckGlobalCockroachKillSwitch(_Symbol))
            return; // In 24-hour Cool-Off lock
            
         CheckAllModulesAmarvelHedge();
      }
   }
   
   // 3. Signal evaluation on new bar ONLY
   datetime curBarTime = iTime(_Symbol, _Period, 0);
   if(curBarTime == g_lastBarTime)
      return; // Skip tick if not a new candle
   
   g_lastBarTime = curBarTime;
   
   // Ensure chart remains clean on new candle
   if(InpHideIndicatorsFromChart)
      CleanIndicatorsFromChart();
   
   // 4. Spread and News Pre-Trade Filters
   if(!g_newsGuard.IsSpreadSafe(_Symbol)) return;
   if(!g_newsGuard.IsNewsSafe(_Symbol))   return;
   
   // 5. Execute Modular Strategy Signals
   ProcessModuleSignals();
}

//+------------------------------------------------------------------+
//| Process strategy signals for active tab/module                   |
//+------------------------------------------------------------------+
void ProcessModuleSignals()
{
   bool isMaster = (InpTabMode == MODE_ALL_MODULES_MASTER);
   
   // Module 1: RSI + EMA 50
   if((isMaster ? InpEnableM1_RSI_EMA : (InpTabMode == MODE_MODULE_M1_RSI_EMA)) && !g_risk.IsModuleAmarvelLocked(MODULE_M1))
      ExecuteTradeSignal(g_strategies.GetSignal_M1(), MAGIC_M1_RSI_EMA, "M1-RSI-EMA");
      
   // Module 2: BB + Stochastic
   if((isMaster ? InpEnableM2_BB_Stoch : (InpTabMode == MODE_MODULE_M2_BB_STOCH)) && !g_risk.IsModuleAmarvelLocked(MODULE_M2))
      ExecuteTradeSignal(g_strategies.GetSignal_M2(), MAGIC_M2_BB_STOCH, "M2-BB-Stoch");
      
   // Module 3: MACD
   if((isMaster ? InpEnableM3_MACD : (InpTabMode == MODE_MODULE_M3_MACD)) && !g_risk.IsModuleAmarvelLocked(MODULE_M3))
      ExecuteTradeSignal(g_strategies.GetSignal_M3(), MAGIC_M3_MACD, "M3-MACD");
      
   // Module 4: 20-bar Breakout
   if((isMaster ? InpEnableM4_HL_Breakout : (InpTabMode == MODE_MODULE_M4_HL_BREAKOUT)) && !g_risk.IsModuleAmarvelLocked(MODULE_M4))
      ExecuteTradeSignal(g_strategies.GetSignal_M4(), MAGIC_M4_HL_BREAKOUT, "M4-Breakout");
      
   // Module 5: PSAR + 200 EMA
   if((isMaster ? InpEnableM5_PSAR_EMA : (InpTabMode == MODE_MODULE_M5_PSAR_EMA)) && !g_risk.IsModuleAmarvelLocked(MODULE_M5))
      ExecuteTradeSignal(g_strategies.GetSignal_M5(), MAGIC_M5_PSAR_EMA, "M5-PSAR-EMA");
      
   // Module 6: ATR Volatility
   if((isMaster ? InpEnableM6_ATR_Vol : (InpTabMode == MODE_MODULE_M6_ATR_VOL)) && !g_risk.IsModuleAmarvelLocked(MODULE_M6))
      ExecuteTradeSignal(g_strategies.GetSignal_M6(), MAGIC_M6_ATR_VOLATILITY, "M6-ATR-Vol");
      
   // Module 7: Dual EMA 9/21
   if((isMaster ? InpEnableM7_Dual_EMA : (InpTabMode == MODE_MODULE_M7_DUAL_EMA)) && !g_risk.IsModuleAmarvelLocked(MODULE_M7))
      ExecuteTradeSignal(g_strategies.GetSignal_M7(), MAGIC_M7_DUAL_EMA, "M7-DualEMA");
      
   // Module 8: Price Action Engulfing
   if((isMaster ? InpEnableM8_PriceAction : (InpTabMode == MODE_MODULE_M8_PRICE_ACTION)) && !g_risk.IsModuleAmarvelLocked(MODULE_M8))
      ExecuteTradeSignal(g_strategies.GetSignal_M8(), MAGIC_M8_PRICE_ACTION, "M8-PriceAction");
      
   // Module 9: Supertrend (10, 3)
   if((isMaster ? InpEnableM9_Supertrend : (InpTabMode == MODE_MODULE_M9_SUPERTREND)) && !g_risk.IsModuleAmarvelLocked(MODULE_M9))
      ExecuteTradeSignal(g_strategies.GetSignal_M9(), MAGIC_M9_SUPERTREND, "M9-Supertrend");
      
   // Module 11: Optional Sniper Scalper
   if((isMaster ? InpEnableM11_Sniper : (InpTabMode == MODE_MODULE_M11_SNIPER)) && !g_risk.IsModuleAmarvelLocked(MODULE_SNIPER))
      ExecuteSniperSignal(g_strategies.GetSignal_Sniper());
}

//+------------------------------------------------------------------+
//| Execute Standard Module Trade with Direction Flip & Grid Spacing |
//+------------------------------------------------------------------+
void ExecuteTradeSignal(ENUM_SIGNAL_TYPE signal, ulong magic, string comment)
{
   if(signal == SIGNAL_NONE) return;
   
   int currentDir = g_stealth.GetModuleDirection(_Symbol, magic); // 1=Buy, -1=Sell, 0=None
   int signalDir  = (signal == SIGNAL_BUY) ? 1 : -1;
   
   // 1. Check for Direction Flip (Opposite signal received while holding positions)
   if(currentDir != 0 && currentDir != signalDir)
   {
      PrintFormat("[DIRECTION FLIP] Module Magic %I64d signal flipped from %s to %s. Closing old trades and opening new position...",
                  magic, (currentDir == 1 ? "BUY" : "SELL"), (signalDir == 1 ? "BUY" : "SELL"));
      g_stealth.CloseModulePositions(_Symbol, magic, "Direction Flip");
      // Old opposite positions are now closed, proceed to open new flipped trade
   }
   else if(currentDir == signalDir)
   {
      // 2. Same direction: Verify Grid step spacing before opening next averaging order
      if(!g_stealth.CanOpenGridOrder(_Symbol, magic, signal))
         return;
   }
       
   double lot = g_risk.CalculateLotSize(_Symbol); // Fixed 0.01 lot
   g_trade.SetExpertMagicNumber(magic);
   
   if(signal == SIGNAL_BUY)
   {
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      if(g_trade.Buy(lot, _Symbol, ask, 0, 0, comment))
      {
         PrintFormat("[%s BUY] Opened %.2f lots at %.5f (Magic: %I64d)", comment, lot, ask, magic);
      }
   }
   else if(signal == SIGNAL_SELL)
   {
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      if(g_trade.Sell(lot, _Symbol, bid, 0, 0, comment))
      {
         PrintFormat("[%s SELL] Opened %.2f lots at %.5f (Magic: %I64d)", comment, lot, bid, magic);
      }
   }
}

//+------------------------------------------------------------------+
//| Execute 11th Sniper Scalper Signal (Direction Flip Capable)      |
//+------------------------------------------------------------------+
void ExecuteSniperSignal(ENUM_SIGNAL_TYPE signal)
{
   if(signal == SIGNAL_NONE) return;
   
   int currentDir = g_stealth.GetModuleDirection(_Symbol, MAGIC_M11_SNIPER);
   int signalDir  = (signal == SIGNAL_BUY) ? 1 : -1;
   
   if(currentDir != 0 && currentDir != signalDir)
   {
      Print("[DIRECTION FLIP] Sniper signal flipped direction. Closing old sniper trade...");
      g_stealth.CloseModulePositions(_Symbol, MAGIC_M11_SNIPER, "Sniper Flip");
   }
   else if(currentDir == signalDir)
   {
      return; // Only 1 active sniper trade allowed in same direction
   }
   
   double lot = g_risk.CalculateLotSize(_Symbol); // Fixed 0.01 Lot
   g_trade.SetExpertMagicNumber(MAGIC_M11_SNIPER);
   
   if(signal == SIGNAL_BUY)
   {
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      g_trade.Buy(lot, _Symbol, ask, 0, 0, "M11-Sniper");
   }
   else if(signal == SIGNAL_SELL)
   {
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      g_trade.Sell(lot, _Symbol, bid, 0, 0, "M11-Sniper");
   }
}

//+------------------------------------------------------------------+
//| Monitor Amarvel Hedge & Module Daily 20% Kill-Switch             |
//+------------------------------------------------------------------+
void CheckAllModulesAmarvelHedge()
{
   // 1. Amarvel 5% Hedge Freeze Check
   g_risk.CheckAmarvelHedging(_Symbol, MAGIC_M1_RSI_EMA,        MODULE_M1);
   g_risk.CheckAmarvelHedging(_Symbol, MAGIC_M2_BB_STOCH,       MODULE_M2);
   g_risk.CheckAmarvelHedging(_Symbol, MAGIC_M3_MACD,           MODULE_M3);
   g_risk.CheckAmarvelHedging(_Symbol, MAGIC_M4_HL_BREAKOUT,    MODULE_M4);
   g_risk.CheckAmarvelHedging(_Symbol, MAGIC_M5_PSAR_EMA,       MODULE_M5);
   g_risk.CheckAmarvelHedging(_Symbol, MAGIC_M6_ATR_VOLATILITY, MODULE_M6);
   g_risk.CheckAmarvelHedging(_Symbol, MAGIC_M7_DUAL_EMA,       MODULE_M7);
   g_risk.CheckAmarvelHedging(_Symbol, MAGIC_M8_PRICE_ACTION,   MODULE_M8);
   g_risk.CheckAmarvelHedging(_Symbol, MAGIC_M9_SUPERTREND,     MODULE_M9);
   g_risk.CheckAmarvelHedging(_Symbol, MAGIC_M11_SNIPER,        MODULE_SNIPER);

   // 2. Module-Level Daily 20% Hard Kill-Switch Check
   g_risk.CheckModuleDailyKillSwitch(_Symbol, MAGIC_M1_RSI_EMA,        MODULE_M1);
   g_risk.CheckModuleDailyKillSwitch(_Symbol, MAGIC_M2_BB_STOCH,       MODULE_M2);
   g_risk.CheckModuleDailyKillSwitch(_Symbol, MAGIC_M3_MACD,           MODULE_M3);
   g_risk.CheckModuleDailyKillSwitch(_Symbol, MAGIC_M4_HL_BREAKOUT,    MODULE_M4);
   g_risk.CheckModuleDailyKillSwitch(_Symbol, MAGIC_M5_PSAR_EMA,       MODULE_M5);
   g_risk.CheckModuleDailyKillSwitch(_Symbol, MAGIC_M6_ATR_VOLATILITY, MODULE_M6);
   g_risk.CheckModuleDailyKillSwitch(_Symbol, MAGIC_M7_DUAL_EMA,       MODULE_M7);
   g_risk.CheckModuleDailyKillSwitch(_Symbol, MAGIC_M8_PRICE_ACTION,   MODULE_M8);
   g_risk.CheckModuleDailyKillSwitch(_Symbol, MAGIC_M9_SUPERTREND,     MODULE_M9);
   g_risk.CheckModuleDailyKillSwitch(_Symbol, MAGIC_M11_SNIPER,        MODULE_SNIPER);
}

//+------------------------------------------------------------------+
//| Timer function for Real-Time HUD Dashboard                       |
//+------------------------------------------------------------------+
void OnTimer()
{
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double equity  = AccountInfoDouble(ACCOUNT_EQUITY);
   double margin  = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   double ddPct   = g_risk.GetCurrentDDPct();
   
   string coolOffStr = g_risk.IsCoolOffActive() ? 
      StringFormat(" [ACTIVE LOCK until %s]", TimeToString(g_risk.GetCoolOffExpiry(), TIME_DATE|TIME_MINUTES)) : " [Normal / Trading]";
      
   string dashboard = "";
   dashboard += "====================================================\n";
   dashboard += "           SANJU KAKA MULTI-STRATEGY INSTITUTIONAL EA\n";
   dashboard += "====================================================\n";
   dashboard += StringFormat(" Chart Tab Role: [%s]\n", EnumToString(InpTabMode));
   dashboard += StringFormat(" Account: %I64d | Server Time: %s\n", AccountInfoInteger(ACCOUNT_LOGIN), TimeToString(TimeCurrent(), TIME_SECONDS));
   dashboard += StringFormat(" Balance: $%.2f | Equity: $%.2f | Free Margin: $%.2f\n", balance, equity, margin);
   dashboard += StringFormat(" Peak Equity: $%.2f | Current Drawdown: %.2f%% (Max Cut: %.1f%%)\n", g_risk.GetPeakEquity(), ddPct, InpCockroachKillSwitchPct);
   dashboard += "----------------------------------------------------\n";
   dashboard += StringFormat(" Cockroach Kill-Switch (20%%): %s\n", coolOffStr);
   dashboard += StringFormat(" Amarvel 5%% Hedge Engine: %s\n", InpEnableM10_MasterGuard ? "ACTIVE (Netting Freeze Ready)" : "DISABLED");
   dashboard += StringFormat(" Stealth 1:3 Dollar Target: TP=+$%.2f | SL=-$%.2f | Trail=$%.2f/$%.2f\n", InpTargetProfitUSD, InpLossLimitUSD, InpTrailingStartUSD, InpTrailingStopUSD);
   dashboard += StringFormat(" News Guard: %s\n", g_newsGuard.GetStatusText());
   dashboard += StringFormat(" Spread Filter: Current %d pts (Max: %d pts)\n", (int)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD), InpMaxSpreadPoints);
   dashboard += "----------------------------------------------------\n";
   dashboard += " Active Modules: [M1:RSI/EMA] [M2:BB/Stoch] [M3:MACD] [M4:H/L Break]\n";
   dashboard += "                 [M5:PSAR] [M6:ATR] [M7:DualEMA] [M8:PriceAct] [M9:Supertrend]\n";
   dashboard += StringFormat(" Total Live Positions: %d | Total Floating PnL: $%.2f\n", PositionsTotal(), (equity - balance));
   dashboard += "====================================================\n";
   
   Comment(dashboard);
}

//+------------------------------------------------------------------+
//| Auto-spawn 10 dedicated Gold chart tabs in MetaTrader terminal   |
//+------------------------------------------------------------------+
void SpawnDedicatedModuleTabs()
{
   Print("[Auto Tab Spawner] Spawning dedicated Gold chart tabs...");
   for(int i = 1; i <= 9; i++)
   {
      long newChart = ChartOpen(_Symbol, _Period);
      if(newChart > 0)
      {
         PrintFormat("[Auto Tab Spawner] Opened dedicated Gold chart tab for Module %d (ChartID: %I64d)", i, newChart);
      }
   }
}

//+------------------------------------------------------------------+
//| Clean indicators and subwindows from chart for Clean Chart Mode  |
//+------------------------------------------------------------------+
void CleanIndicatorsFromChart()
{
   if(!InpHideIndicatorsFromChart) return;
   
   long chartId = ChartID();
   int windows = (int)ChartGetInteger(chartId, CHART_WINDOWS_TOTAL);
   
   // Loop through all windows (subwindows and main window) and delete indicators
   for(int w = windows - 1; w >= 0; w--)
   {
      int totalInd = ChartIndicatorsTotal(chartId, w);
      for(int i = totalInd - 1; i >= 0; i--)
      {
         string indName = ChartIndicatorName(chartId, w, i);
         if(indName != "")
         {
            ChartIndicatorDelete(chartId, w, indName);
         }
      }
   }
   
   ChartRedraw(chartId);
}

//+------------------------------------------------------------------+
//| Check if symbol is a Gold contract (XAUUSD, GOLD, etc.)          |
//+------------------------------------------------------------------+
bool IsGoldSymbol(const string symbol)
{
   string sym = symbol;
   StringToUpper(sym);
   return (StringFind(sym, "XAU") >= 0 || StringFind(sym, "GOLD") >= 0);
}
