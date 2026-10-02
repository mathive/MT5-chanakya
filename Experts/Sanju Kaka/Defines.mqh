//+------------------------------------------------------------------+
//|                                                      Defines.mqh |
//|                                  Copyright 2026, Sanju Kaka Algo |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Sanju Kaka Algo"
#property link      "https://www.mql5.com"
#property strict

//--- Magic Numbers for 10 Modules + Optional Sniper + Hedge System
#define MAGIC_M1_RSI_EMA        1001
#define MAGIC_M2_BB_STOCH       1002
#define MAGIC_M3_MACD           1003
#define MAGIC_M4_HL_BREAKOUT    1004
#define MAGIC_M5_PSAR_EMA       1005
#define MAGIC_M6_ATR_VOLATILITY 1006
#define MAGIC_M7_DUAL_EMA       1007
#define MAGIC_M8_PRICE_ACTION   1008
#define MAGIC_M9_SUPERTREND     1009
#define MAGIC_M10_MASTER_GUARD  1010
#define MAGIC_M11_SNIPER        1011
#define MAGIC_HEDGE_BASE        1099

//--- Trade Signal Enum
enum ENUM_SIGNAL_TYPE
{
   SIGNAL_NONE = 0,
   SIGNAL_BUY  = 1,
   SIGNAL_SELL = -1
};

//--- Operation Mode for Dedicated Chart Tabs
enum ENUM_OPERATION_MODE
{
   MODE_ALL_MODULES_MASTER = 0, // Master Mode (All Modules on this Chart)
   MODE_MODULE_M1_RSI_EMA,      // Dedicated Tab: Module 1 (RSI + 50 EMA)
   MODE_MODULE_M2_BB_STOCH,     // Dedicated Tab: Module 2 (BB + Stochastic)
   MODE_MODULE_M3_MACD,         // Dedicated Tab: Module 3 (MACD Crossover)
   MODE_MODULE_M4_HL_BREAKOUT,  // Dedicated Tab: Module 4 (20-Bar Breakout)
   MODE_MODULE_M5_PSAR_EMA,     // Dedicated Tab: Module 5 (PSAR + 200 EMA)
   MODE_MODULE_M6_ATR_VOL,      // Dedicated Tab: Module 6 (ATR Volatility)
   MODE_MODULE_M7_DUAL_EMA,     // Dedicated Tab: Module 7 (Dual EMA 9/21)
   MODE_MODULE_M8_PRICE_ACTION, // Dedicated Tab: Module 8 (Price Action Engulfing)
   MODE_MODULE_M9_SUPERTREND,   // Dedicated Tab: Module 9 (Supertrend)
   MODE_MODULE_M10_MASTER_GUARD,// Dedicated Tab: Module 10 (Capital Defense Guard)
   MODE_MODULE_M11_SNIPER       // Dedicated Tab: Module 11 (Sniper Scalper)
};

//--- Strategy Module Identifier
enum ENUM_MODULE_ID
{
   MODULE_M1 = 0,
   MODULE_M2,
   MODULE_M3,
   MODULE_M4,
   MODULE_M5,
   MODULE_M6,
   MODULE_M7,
   MODULE_M8,
   MODULE_M9,
   MODULE_M10_GUARD,
   MODULE_SNIPER,
   MODULE_COUNT
};

//--- Virtual Stealth Position Tracking in RAM
struct SVirtualPosition
{
   ulong                ticket;           // Order / Position Ticket
   ulong                magic;            // Strategy Magic Number
   string               symbol;           // Trading Symbol
   ENUM_POSITION_TYPE   type;             // Position Type (Buy/Sell)
   double               openPrice;        // Open Price
   double               volume;           // Lot Volume
   datetime             openTime;         // Time of opening
   double               virtualTP;        // Virtual Take Profit (Price)
   double               virtualSL;        // Virtual Stop Loss (Price)
   double               highestPrice;     // Peak high since open (for buy TSL)
   double               lowestPrice;      // Peak low since open (for sell TSL)
   double               peakProfitUSD;    // Peak Dollar Profit Reached (for USD Trailing)
   bool                 isHedged;         // Is this position hedged
   bool                 isAmarvelLock;    // Is part of Amarvel lock
};

//--- Module Status Struct for GUI Dashboard
struct SModuleStatus
{
   ulong    magic;
   string   name;
   bool     isEnabled;
   int      openTrades;
   double   floatingProfit;
   double   totalVolume;
   bool     isHedged;
};

//--- Risk State Tracking
struct SGlobalRiskState
{
   double   initialBalance;
   double   peakEquity;
   double   currentEquity;
   double   currentDrawdownPct;
   bool     isAmarvelHedgeActive;
   bool     isKillSwitchTriggered;
   datetime killSwitchTriggerTime;
   bool     isCoolOffActive;
};
