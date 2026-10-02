//+------------------------------------------------------------------+
//|                                              NewsSpreadGuard.mqh |
//|                                  Copyright 2026, Sanju Kaka Algo |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Sanju Kaka Algo"
#property link      "https://www.mql5.com"
#property strict

class CNewsSpreadGuard
{
private:
   bool     m_useNewsFilter;
   int      m_newsMinsBefore;
   int      m_newsMinsAfter;
   bool     m_useSpreadFilter;
   int      m_maxSpreadPoints;
   bool     m_isNewsActive;
   string   m_newsStatusText;

public:
   CNewsSpreadGuard() :
      m_useNewsFilter(true),
      m_newsMinsBefore(15),
      m_newsMinsAfter(15),
      m_useSpreadFilter(true),
      m_maxSpreadPoints(30),
      m_isNewsActive(false),
      m_newsStatusText("Normal")
   {
   }
   
   void Init(bool useNews, int minsBefore, int minsAfter, bool useSpread, int maxSpread)
   {
      m_useNewsFilter   = useNews;
      m_newsMinsBefore  = minsBefore;
      m_newsMinsAfter   = minsAfter;
      m_useSpreadFilter = useSpread;
      m_maxSpreadPoints = maxSpread;
      m_newsStatusText  = "Active (Monitoring)";
   }
   
   //--- Check if current spread is within safe threshold
   bool IsSpreadSafe(const string symbol)
   {
      if(!m_useSpreadFilter) return true;
      
      long currentSpread = SymbolInfoInteger(symbol, SYMBOL_SPREAD);
      if(currentSpread > m_maxSpreadPoints)
      {
         PrintFormat("[Spread Filter] Spread too high on %s: %d points (Max: %d). Skipping trade entry.",
                     symbol, currentSpread, m_maxSpreadPoints);
         return false;
      }
      return true;
   }
   
   //--- Check High Impact News Filter using MQL5 Calendar
   bool IsNewsSafe(const string symbol)
   {
      if(!m_useNewsFilter || MQLInfoInteger(MQL_TESTER))
      {
         m_newsStatusText = MQLInfoInteger(MQL_TESTER) ? "Tester Mode (News Bypassed)" : "News Filter Disabled";
         m_isNewsActive = false;
         return true;
      }
      
      datetime currentTime = TimeCurrent();
      datetime fromTime = currentTime - (datetime)(m_newsMinsAfter * 60);
      datetime toTime   = currentTime + (datetime)(m_newsMinsBefore * 60);
      
      MqlCalendarValue values[];
      ResetLastError();
      
      // Look up economic calendar values for the window
      int count = CalendarValueHistory(values, fromTime, toTime);
      if(count > 0)
      {
         for(int i = 0; i < count; i++)
         {
            MqlCalendarEvent event;
            if(CalendarEventById(values[i].event_id, event))
            {
               // Importance 3 = High Impact (Red Folder)
               if(event.importance == CALENDAR_IMPORTANCE_HIGH)
               {
                  m_isNewsActive = true;
                  MqlCalendarCountry country;
                  string ccy = "";
                  if(CalendarCountryById(event.country_id, country))
                     ccy = " (" + country.currency + ")";
                  m_newsStatusText = StringFormat("HIGH NEWS LOCK: %s%s", event.name, ccy);
                  return false;
               }
            }
         }
      }
      
      m_isNewsActive = false;
      m_newsStatusText = "Clean (No High-Impact News)";
      return true;
   }
   
   bool IsNewsActive() const { return m_isNewsActive; }
   string GetStatusText() const { return m_newsStatusText; }
};
