//+------------------------------------------------------------------+
//|                                            SuperTrendIndicator.mqh |
//|                                       Copyright 2025, Supertrend |
//|                                                                  |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, Supertrend"
#property link      ""

//+------------------------------------------------------------------+
//| SuperTrend Indicator Class                                       |
//| Handles indicator initialization, buffer management and signals   |
//+------------------------------------------------------------------+
class CSuperTrendIndicator
{
private:
   string            m_symbol;           // Symbol to use
   ENUM_TIMEFRAMES   m_timeframe;        // Timeframe to use
   int               m_handle;           // SuperTrend indicator handle
   double            m_direction[];      // SuperTrend direction buffer
   double            m_upper[];          // SuperTrend upper line buffer
   double            m_lower[];          // SuperTrend lower line buffer
   int               m_last_signal;      // Last trading signal

public:
   // Constructor
                     CSuperTrendIndicator();
   // Destructor
                    ~CSuperTrendIndicator();
   
   // Initialization
   bool              Init(const string symbol, const ENUM_TIMEFRAMES timeframe, 
                         const double multiplier, const int atrPeriod);
   
   // Update indicator buffers
   bool              UpdateBuffers();
   
   // Get current signal (-1 = sell, 0 = no signal, 1 = buy)
   int               GetSignal();
   
   // Get SuperTrend line values
   double            GetUpperLine(const int shift = 1) const { 
      // Safety check for array bounds
      if(shift < 0 || shift >= ArraySize(m_direction) || shift >= ArraySize(m_upper))
      {
         Print("WARNING: GetUpperLine - Array index out of range: ", shift);
         return EMPTY_VALUE;
      }
      
      // For SELL signals, we want the upper line (red)
      if(m_direction[shift] == 1) // Downtrend
         return m_upper[shift]; 
      else
         return EMPTY_VALUE; // No upper line in uptrend
   }
   
   double            GetLowerLine(const int shift = 1) const { 
      // Safety check for array bounds
      if(shift < 0 || shift >= ArraySize(m_direction) || shift >= ArraySize(m_lower))
      {
         Print("WARNING: GetLowerLine - Array index out of range: ", shift);
         return EMPTY_VALUE;
      }
      
      // For BUY signals, we want the lower line (green)
      if(m_direction[shift] == 0) // Uptrend
         return m_lower[shift];
      else
         return EMPTY_VALUE; // No lower line in downtrend
   }
   
   // Get the SuperTrend line value for the current trend direction
   double            GetCurrentTrendLine(const int shift = 1) const {
      // Safety check for array bounds
      if(shift < 0 || shift >= ArraySize(m_direction) || 
         shift >= ArraySize(m_upper) || shift >= ArraySize(m_lower))
      {
         Print("WARNING: GetCurrentTrendLine - Array index out of range: ", shift);
         return EMPTY_VALUE;
      }
      
      if(m_direction[shift] == 0) // Uptrend - green line - lower band
         return m_lower[shift];
      else if(m_direction[shift] == 1) // Downtrend - red line - upper band
         return m_upper[shift];
      else
         return EMPTY_VALUE;
   }
   
   // Check if signal has changed
   bool              HasSignalChanged();
   
   // Get the last stored signal
   int               GetLastSignal() const { return m_last_signal; }
   
   // Update last signal
   void              SetLastSignal(const int signal) { m_last_signal = signal; }
};

//+------------------------------------------------------------------+
//| Constructor                                                       |
//+------------------------------------------------------------------+
CSuperTrendIndicator::CSuperTrendIndicator()
{
   m_handle = INVALID_HANDLE;
   m_last_signal = 0; // No signal initially
   ArraySetAsSeries(m_direction, true);
   ArraySetAsSeries(m_upper, true);
   ArraySetAsSeries(m_lower, true);
}

//+------------------------------------------------------------------+
//| Destructor                                                        |
//+------------------------------------------------------------------+
CSuperTrendIndicator::~CSuperTrendIndicator()
{
   // Release indicator handle
   if(m_handle != INVALID_HANDLE)
      IndicatorRelease(m_handle);
}

//+------------------------------------------------------------------+
//| Initialize the SuperTrend indicator                               |
//+------------------------------------------------------------------+
bool CSuperTrendIndicator::Init(const string symbol, const ENUM_TIMEFRAMES timeframe, 
                               const double multiplier, const int atrPeriod)
{
   m_symbol = symbol;
   m_timeframe = timeframe;
   
   // Create SuperTrend indicator handle
   m_handle = iCustom(symbol, timeframe, "Supertrend", 
                    "SPRTRND", // Objects Prefix
                    multiplier, // ATR Multiplier
                    atrPeriod, // ATR Period
                    10000, // ATR Max Bars
                    0, // Indicator shift
                    false, // Enable notifications feature
                    false, // Send alert notification
                    false, // Send push-notification to mobile
                    false, // Send notification via email
                    0); // TriggerCandle = Current (0)
                    
   if(m_handle == INVALID_HANDLE)
   {
      Print("Failed to create SuperTrend indicator handle. Error code:", GetLastError());
      return false;
   }
   
   Print("SuperTrend indicator initialized successfully");
   return true;
}

//+------------------------------------------------------------------+
//| Update SuperTrend buffers with the latest values                 |
//+------------------------------------------------------------------+
bool CSuperTrendIndicator::UpdateBuffers()
{
   // Ensure buffers are properly sized before accessing
   ArrayResize(m_upper, 3);
   ArrayResize(m_lower, 3);
   ArrayResize(m_direction, 3);
   
   // Copy SuperTrend main buffer values (buffer 0 - main line)
   if(CopyBuffer(m_handle, 0, 0, 3, m_upper) <= 0)
   {
      Print("Failed to copy SuperTrend main buffer. Error:", GetLastError());
      return false;
   }
   
   // Copy SuperTrend direction values (buffer 2 - trend direction)
   if(CopyBuffer(m_handle, 2, 0, 3, m_direction) <= 0)
   {
      Print("Failed to copy SuperTrend direction buffer. Error:", GetLastError());
      return false;
   }
   
   // Initialize lower buffer with EMPTY_VALUE
   ArrayInitialize(m_lower, EMPTY_VALUE);
   
   // For the SuperTrend indicator, there's only one visible line
   // The value is stored in buffer 0, but we need to determine if it's an upper or lower line
   // based on the direction buffer (0 = uptrend/lower line, 1 = downtrend/upper line)
   for(int i = 0; i < ArraySize(m_direction) && i < ArraySize(m_upper) && i < ArraySize(m_lower); i++)
   {
      // Safety check for valid values
      if(m_direction[i] == EMPTY_VALUE)
         continue;
         
      if(m_direction[i] == 0) // Uptrend (green)
      {
         m_lower[i] = m_upper[i]; // The visible line is a lower line
         m_upper[i] = EMPTY_VALUE; // Upper line doesn't exist during uptrend
      }
      else if(m_direction[i] == 1) // Downtrend (red)
      {
         // Upper line stays as is
         m_lower[i] = EMPTY_VALUE; // Lower line doesn't exist during downtrend
      }
      else
      {
         m_upper[i] = EMPTY_VALUE;
         m_lower[i] = EMPTY_VALUE;
      }
   }
   
   // Debug current values (only log if arrays have data and if it's a new bar)
   static datetime last_debug_time = 0;
   datetime current_time = iTime(m_symbol, m_timeframe, 0);
   
   if(last_debug_time != current_time && 
      ArraySize(m_direction) > 1 && ArraySize(m_upper) > 1 && ArraySize(m_lower) > 1)
   {
      Print("DEBUG: Direction [0] = ", m_direction[0], ", [1] = ", m_direction[1]);
      Print("DEBUG: Upper line [0] = ", m_upper[0] == EMPTY_VALUE ? "EMPTY" : DoubleToString(m_upper[0]), 
            ", [1] = ", m_upper[1] == EMPTY_VALUE ? "EMPTY" : DoubleToString(m_upper[1]));
      Print("DEBUG: Lower line [0] = ", m_lower[0] == EMPTY_VALUE ? "EMPTY" : DoubleToString(m_lower[0]), 
            ", [1] = ", m_lower[1] == EMPTY_VALUE ? "EMPTY" : DoubleToString(m_lower[1]));
      
      last_debug_time = current_time;
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| Get current SuperTrend signal                                     |
//+------------------------------------------------------------------+
int CSuperTrendIndicator::GetSignal()
{
   // Safety check for array bounds
   if(ArraySize(m_direction) < 2)
   {
      Print("WARNING: GetSignal - Direction array too small");
      return 0;  // No signal
   }
   
   // Check if TrendDirection buffer has valid values
   if(m_direction[1] == EMPTY_VALUE)
      return 0;  // No signal
      
   // Current trend (0 = uptrend/green, 1 = downtrend/red)
   int trend_current = (int)m_direction[1];
   
   // Convert to signal (1 = buy, -1 = sell)
   int signal = (trend_current == 0) ? 1 : -1;
   
   // Debug signal generation - only if it has changed
   static int last_logged_signal = -999;
   if(signal != last_logged_signal)
   {
      Print("Signal generation: Direction=", trend_current, ", Signal=", signal);
      last_logged_signal = signal;
   }
   
   return signal;
}

//+------------------------------------------------------------------+
//| Check if signal has changed                                       |
//+------------------------------------------------------------------+
bool CSuperTrendIndicator::HasSignalChanged()
{
   int current_signal = GetSignal();
   return (current_signal != m_last_signal && current_signal != 0);
}