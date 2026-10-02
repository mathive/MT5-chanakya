//+------------------------------------------------------------------+
#property strict
#include <Trade/Trade.mqh>
CTrade trade;

enum ENUM_TRADE_DIRECTION
{
   TRADE_DIR_BOTH, // Both Buy and Sell
   TRADE_DIR_BUY,  // Buy Only
   TRADE_DIR_SELL  // Sell Only
};

enum ENUM_PROFIT_CURRENCY
{
   CURRENCY_USD, // USD ($)
   CURRENCY_INR  // INR (₹)
};

input double LotSize        = 0.01;
input ENUM_TRADE_DIRECTION InpTradeDirection = TRADE_DIR_BOTH; // Trading Direction
input ENUM_PROFIT_CURRENCY InpCurrency = CURRENCY_USD; // Profit/Loss Currency
input double Offset         = 1.0;   // Distance from open price
input double TargetProfit   = 0.00;  // Take Profit
input double StopLoss       = 0.00;  // Stop Loss
input double TrailingStart  = 0.00;  // Profit to activate trailing
input double TrailingLock   = 0.00;  // Profit to lock when activated
input double TrailingStep   = 0.00;  // Trailing step
input int    MagicNumber    = 5544;
input ENUM_TIMEFRAMES InpTimeframe = PERIOD_M1; // Working Timeframe
input int    CloseBeforeMinutes = 15; // Close positions minutes before market close
input double SLBufferPoints = 0.0; // Buffer for Stop Loss in points

datetime lastBarTime = 0;
double buyLevel = 0;
double sellLevel = 0;
bool monitorEntry = false;
datetime lastExecutionBar = 0;

//+------------------------------------------------------------------+
bool IsPositionOpen()
{
   for(int i=PositionsTotal()-1; i>=0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
      {
         if(PositionGetInteger(POSITION_MAGIC) == MagicNumber && PositionGetString(POSITION_SYMBOL) == _Symbol)
            return true;
      }
   }
   return false;
}
//+------------------------------------------------------------------+
bool IsMarketOpen()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   long daySeconds = dt.hour * 3600 + dt.min * 60 + dt.sec;
   
   long from, to;
   for(int i=0; i<10; i++)
   {
      if(!SymbolInfoSessionTrade(_Symbol, (ENUM_DAY_OF_WEEK)dt.day_of_week, i, from, to))
         break;
      if(daySeconds >= from && daySeconds < to)
         return true;
   }
   return false;
}

bool IsNearMarketClose()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   long daySeconds = dt.hour * 3600 + dt.min * 60 + dt.sec;
   
   long from, to;
   long lastSessionEnd = 0;
   
   for(int i=0; i<10; i++)
   {
      if(!SymbolInfoSessionTrade(_Symbol, (ENUM_DAY_OF_WEEK)dt.day_of_week, i, from, to))
         break;
      if(to > lastSessionEnd) lastSessionEnd = to;
   }
   
   if(lastSessionEnd == 0) return false;
   
   if(daySeconds >= (lastSessionEnd - CloseBeforeMinutes * 60) && daySeconds < lastSessionEnd)
      return true;
      
   return false;
}

void CloseAllPositions()
{
   for(int i=PositionsTotal()-1; i>=0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
      {
         if(PositionGetInteger(POSITION_MAGIC) == MagicNumber && PositionGetString(POSITION_SYMBOL) == _Symbol)
            trade.PositionClose(ticket);
      }
   }
}
//+------------------------------------------------------------------+
string GetSymbolWithSuffix(string base, string profit)
{
   string pair = base + profit;
   if(SymbolSelect(pair, true)) return pair;
   
   string currBase = SymbolInfoString(_Symbol, SYMBOL_CURRENCY_BASE);
   string currProfit = SymbolInfoString(_Symbol, SYMBOL_CURRENCY_PROFIT);
   
   if(currBase != "" && currProfit != "")
   {
      string currSuffix = "";
      if(StringLen(_Symbol) > (StringLen(currBase) + StringLen(currProfit)))
         currSuffix = StringSubstr(_Symbol, StringLen(currBase) + StringLen(currProfit));
      
      string pairSuffix = pair + currSuffix;
      if(SymbolSelect(pairSuffix, true)) return pairSuffix;
   }
   return "";
}

double GetCurrencyFactor()
{
   string accCurrency = AccountInfoString(ACCOUNT_CURRENCY);
   
   if(InpCurrency == CURRENCY_USD)
   {
      if(accCurrency == "USD") return 1.0;
      if(accCurrency == "INR") 
      {
         string sym = GetSymbolWithSuffix("USD", "INR");
         if(sym != "" && SymbolInfoDouble(sym, SYMBOL_BID) > 0)
            return SymbolInfoDouble(sym, SYMBOL_BID);
         return 0.0;
      }
   }
   else if(InpCurrency == CURRENCY_INR)
   {
      if(accCurrency == "INR") return 1.0;
      if(accCurrency == "USD")
      {
         string sym = GetSymbolWithSuffix("USD", "INR");
         if(sym != "" && SymbolInfoDouble(sym, SYMBOL_ASK) > 0)
            return 1.0 / SymbolInfoDouble(sym, SYMBOL_ASK);
         return 0.0;
      }
   }
   return 1.0;
}
//+------------------------------------------------------------------+
void VerifyAndFixPosition(ulong ticket)
{
   for(int i=0; i<10; i++)
   {
      if(PositionSelectByTicket(ticket))
      {
         double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
         double currentSL = PositionGetDouble(POSITION_SL);
         double currentTP = PositionGetDouble(POSITION_TP);
         ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
         double vol = PositionGetDouble(POSITION_VOLUME);
         
         double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
         double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
         
         double expectedSL = 0;
         double expectedTP = 0;
         
         double currencyFactor = GetCurrencyFactor();
         if(currencyFactor <= 0) return;
         
         double minStopDist = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;
         double spread = SymbolInfoDouble(_Symbol, SYMBOL_ASK) - SymbolInfoDouble(_Symbol, SYMBOL_BID);
         double minRequiredDist = spread + minStopDist + 2 * _Point;
         
         double slDist = (StopLoss > 0 && tickValue > 0) ? (StopLoss * currencyFactor * tickSize) / (tickValue * vol) : 0;
         if(slDist > 0 && slDist < minRequiredDist) slDist = minRequiredDist;
         double tpDist = (TargetProfit > 0 && tickValue > 0) ? (TargetProfit * currencyFactor * tickSize) / (tickValue * vol) : 0;
         if(tpDist > 0 && tpDist < minStopDist) tpDist = minStopDist;
         
         if(type == POSITION_TYPE_BUY)
         {
            if(StopLoss > 0)
            {
               expectedSL = NormalizeDouble(openPrice - slDist, _Digits);
               if(SLBufferPoints > 0) expectedSL = NormalizeDouble(expectedSL - SLBufferPoints * _Point, _Digits);
            }
            else
            {
               expectedSL = NormalizeDouble(iLow(_Symbol, InpTimeframe, 1), _Digits);
               if(SLBufferPoints > 0) expectedSL = NormalizeDouble(expectedSL - SLBufferPoints * _Point, _Digits);
               
               // Ensure SL is valid (not too close to current price)
               if(SymbolInfoDouble(_Symbol, SYMBOL_BID) - expectedSL < minStopDist) expectedSL = NormalizeDouble(SymbolInfoDouble(_Symbol, SYMBOL_BID) - minStopDist - _Point, _Digits);
            }
               
            expectedTP = (tpDist > 0) ? NormalizeDouble(openPrice + tpDist, _Digits) : 0;
         }
         else
         {
            if(StopLoss > 0)
            {
               expectedSL = NormalizeDouble(openPrice + slDist, _Digits);
               if(SLBufferPoints > 0) expectedSL = NormalizeDouble(expectedSL + SLBufferPoints * _Point, _Digits);
            }
            else
            {
               expectedSL = NormalizeDouble(iHigh(_Symbol, InpTimeframe, 1), _Digits);
               if(SLBufferPoints > 0) expectedSL = NormalizeDouble(expectedSL + SLBufferPoints * _Point, _Digits);
               
               // Ensure SL is valid (not too close to current price)
               if(expectedSL - SymbolInfoDouble(_Symbol, SYMBOL_ASK) < minStopDist) expectedSL = NormalizeDouble(SymbolInfoDouble(_Symbol, SYMBOL_ASK) + minStopDist + _Point, _Digits);
            }
               
            expectedTP = (tpDist > 0) ? NormalizeDouble(openPrice - tpDist, _Digits) : 0;
         }
         
         if(MathAbs(currentSL - expectedSL) > _Point || MathAbs(currentTP - expectedTP) > _Point)
            trade.PositionModify(ticket, expectedSL, expectedTP);
            
         break;
      }
      Sleep(100);
   }
}
//+------------------------------------------------------------------+
bool WasTradeExecutedOnBar(datetime barTime)
{
   if(!HistorySelect(barTime, TimeCurrent() + 86400)) return false;
   
   for(int i = HistoryDealsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = HistoryDealGetTicket(i);
      if(HistoryDealGetInteger(ticket, DEAL_MAGIC) == MagicNumber && 
         HistoryDealGetString(ticket, DEAL_SYMBOL) == _Symbol &&
         HistoryDealGetInteger(ticket, DEAL_ENTRY) == DEAL_ENTRY_IN)
         return true;
   }
   return false;
}
//+------------------------------------------------------------------+
bool WasPositionClosedOnBar(datetime barTime)
{
   if(!HistorySelect(barTime, TimeCurrent() + 86400)) return false;
   
   for(int i = HistoryDealsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = HistoryDealGetTicket(i);
      if(HistoryDealGetInteger(ticket, DEAL_MAGIC) == MagicNumber && 
         HistoryDealGetString(ticket, DEAL_SYMBOL) == _Symbol &&
         HistoryDealGetInteger(ticket, DEAL_ENTRY) == DEAL_ENTRY_OUT)
         return true;
   }
   return false;
}
//+------------------------------------------------------------------+
string GetBarLockName()
{
   return "Pashya_Lock_" + (string)MagicNumber + "_" + _Symbol;
}
//+------------------------------------------------------------------+
bool IsStuckInLossRange()
{
   if(!HistorySelect(0, TimeCurrent() + 86400)) return false;
   
   long lossPositionIDs[5];
   int count = 0;
   
   for(int i = HistoryDealsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = HistoryDealGetTicket(i);
      if(HistoryDealGetInteger(ticket, DEAL_MAGIC) != MagicNumber) continue;
      if(HistoryDealGetString(ticket, DEAL_SYMBOL) != _Symbol) continue;
      if(HistoryDealGetInteger(ticket, DEAL_ENTRY) != DEAL_ENTRY_OUT) continue;
      
      double profit = HistoryDealGetDouble(ticket, DEAL_PROFIT);
      if(profit >= 0) return false; 
      
      if(count < 5)
      {
         lossPositionIDs[count] = HistoryDealGetInteger(ticket, DEAL_POSITION_ID);
         count++;
      }
      
      if(count == 5) break;
   }
   
   if(count < 5) return false;
   
   double maxEntry = 0;
   double minEntry = 1000000000.0;
   
   for(int i=0; i<5; i++)
   {
      if(HistorySelectByPosition(lossPositionIDs[i]))
      {
         for(int k=0; k<HistoryDealsTotal(); k++)
         {
            ulong ticket = HistoryDealGetTicket(k);
            if(HistoryDealGetInteger(ticket, DEAL_ENTRY) == DEAL_ENTRY_IN)
            {
               double price = HistoryDealGetDouble(ticket, DEAL_PRICE);
               if(price > maxEntry) maxEntry = price;
               if(price < minEntry) minEntry = price;
            }
         }
      }
   }
   
   if(maxEntry == 0 || minEntry == 1000000000.0) return false;
   
   double currentAsk = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double currentBid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   
   if(currentBid >= minEntry && currentAsk <= maxEntry)
      return true;
      
   return false;
}
//+------------------------------------------------------------------+
void OnTick()
{
   if(AccountInfoDouble(ACCOUNT_BALANCE) < 10.0)
   {
      Print("Critical: Balance is below $10. Stopping trading and removing EA.");
      ExpertRemove();
      return;
   }

   if(IsNearMarketClose())
   {
      CloseAllPositions();
      monitorEntry = false;
      return;
   }
   
   if(!IsMarketOpen())
   {
      monitorEntry = false;
      return;
   }

   datetime currentBar = iTime(_Symbol, InpTimeframe, 0);

   if(currentBar != lastBarTime)
   {
      lastBarTime = currentBar;
      
      double openPrice = iOpen(_Symbol, InpTimeframe, 0);
      buyLevel = NormalizeDouble(openPrice + Offset, _Digits);
      sellLevel = NormalizeDouble(openPrice - Offset, _Digits);
      
      if(currentBar == lastExecutionBar || WasTradeExecutedOnBar(currentBar) || (GlobalVariableGet(GetBarLockName()) == (double)currentBar))
         monitorEntry = false;
      else
         monitorEntry = true;
   }

   if(IsPositionOpen())
   {
      monitorEntry = false;
      ManagePositions();
      return;
   }

   if(monitorEntry)
   {
      if(currentBar == lastExecutionBar || WasTradeExecutedOnBar(currentBar) || (GlobalVariableGet(GetBarLockName()) == (double)currentBar))
      {
         monitorEntry = false;
         lastExecutionBar = currentBar;
         return;
      }
      
      if(WasPositionClosedOnBar(currentBar))
      {
         monitorEntry = false;
         return;
      }
      
      if(IsStuckInLossRange())
      {
         monitorEntry = false;
         return;
      }

      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      
      double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
      double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
      double slDist = 0;
      double tpDist = 0;
      
      double currencyFactor = GetCurrencyFactor();
      if(currencyFactor <= 0)
      {
         Print("Error: Currency conversion failed. Check USDINR symbol.");
         return;
      }
      
      double minStopDist = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;
      double spread = ask - bid;
      double minRequiredDist = spread + minStopDist + 2 * _Point;
      
      if(tickValue > 0 && tickSize > 0)
      {
         if(StopLoss > 0) slDist = (StopLoss * currencyFactor * tickSize) / (tickValue * LotSize);
         if(slDist > 0 && slDist < minRequiredDist) slDist = minRequiredDist;
         if(TargetProfit > 0) tpDist = (TargetProfit * currencyFactor * tickSize) / (tickValue * LotSize);
         if(tpDist > 0 && tpDist < minStopDist) tpDist = minStopDist;
      }
      
      trade.SetExpertMagicNumber(MagicNumber);
      
      if(ask >= buyLevel && InpTradeDirection != TRADE_DIR_SELL)
      {
         if(IsPositionOpen()) { monitorEntry = false; return; }
         
         double sl;
         if(StopLoss > 0)
         {
            sl = (slDist > 0) ? NormalizeDouble(ask - slDist, _Digits) : 0;
            if(SLBufferPoints > 0 && sl > 0) sl = NormalizeDouble(sl - SLBufferPoints * _Point, _Digits);
         }
         else
         {
            sl = NormalizeDouble(iLow(_Symbol, InpTimeframe, 1), _Digits);
            if(SLBufferPoints > 0) sl = NormalizeDouble(sl - SLBufferPoints * _Point, _Digits);
            
            // Ensure SL is valid (not too close to price)
            if(ask - sl < minRequiredDist) sl = NormalizeDouble(ask - minRequiredDist, _Digits);
         }
            
         double tp = (tpDist > 0) ? NormalizeDouble(ask + tpDist, _Digits) : 0;
         if(trade.Buy(LotSize, _Symbol, ask, sl, tp))
         {
            monitorEntry = false;
            lastExecutionBar = currentBar;
            GlobalVariableSet(GetBarLockName(), (double)currentBar);
            ulong ticket = trade.ResultOrder();
            if(ticket > 0) VerifyAndFixPosition(ticket);
         }
      }
      else if(bid <= sellLevel && InpTradeDirection != TRADE_DIR_BUY)
      {
         if(IsPositionOpen()) { monitorEntry = false; return; }
         
         double sl;
         if(StopLoss > 0)
         {
            sl = (slDist > 0) ? NormalizeDouble(bid + slDist, _Digits) : 0;
            if(SLBufferPoints > 0 && sl > 0) sl = NormalizeDouble(sl + SLBufferPoints * _Point, _Digits);
         }
         else
         {
            sl = NormalizeDouble(iHigh(_Symbol, InpTimeframe, 1), _Digits);
            if(SLBufferPoints > 0) sl = NormalizeDouble(sl + SLBufferPoints * _Point, _Digits);
            
            // Ensure SL is valid (not too close to price)
            if(sl - bid < minRequiredDist) sl = NormalizeDouble(bid + minRequiredDist, _Digits);
         }
            
         double tp = (tpDist > 0) ? NormalizeDouble(bid - tpDist, _Digits) : 0;
         if(trade.Sell(LotSize, _Symbol, bid, sl, tp))
         {
            monitorEntry = false;
            lastExecutionBar = currentBar;
            GlobalVariableSet(GetBarLockName(), (double)currentBar);
            ulong ticket = trade.ResultOrder();
            if(ticket > 0) VerifyAndFixPosition(ticket);
         }
      }
   }
}
//+------------------------------------------------------------------+

void ManagePositions()
{
   double low1 = iLow(_Symbol, InpTimeframe, 1);
   double high1 = iHigh(_Symbol, InpTimeframe, 1);

   if(low1 == 0 || high1 == 0) return;

   double currentAsk = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double currentBid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double minStopDist = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;

   for(int i=PositionsTotal()-1; i>=0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
      {
         if(PositionGetInteger(POSITION_MAGIC) != MagicNumber)
            continue;
         if(PositionGetString(POSITION_SYMBOL) != _Symbol)
            continue;

         ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
         double currentSL = PositionGetDouble(POSITION_SL);
         double currentTP = PositionGetDouble(POSITION_TP);
         double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
         double profit = PositionGetDouble(POSITION_PROFIT);
         double vol = PositionGetDouble(POSITION_VOLUME);
         double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
         double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);

         double newSL = 0;
         bool modify = false;
         
         // Calculate Profit Trailing Level
         double profitSL = 0;
         bool useProfitSL = false;
         
         double currencyFactor = GetCurrencyFactor();
         if(currencyFactor <= 0) continue;
         double trailingStartVal = TrailingStart * currencyFactor;
         double trailingStepVal = TrailingStep * currencyFactor;
         
         if(TrailingStart > 0 && profit >= trailingStartVal)
         {
            double level = (trailingStepVal > 0) ? MathFloor((profit - trailingStartVal) / trailingStepVal) : 0;
            double lockVal = (TrailingLock * currencyFactor) + (level * trailingStepVal);
            double lockDist = (tickValue > 0) ? (lockVal * tickSize) / (tickValue * vol) : 0;
            
            if(type == POSITION_TYPE_BUY)
            {
               profitSL = NormalizeDouble(openPrice + lockDist, _Digits);
               if(SLBufferPoints > 0) profitSL = NormalizeDouble(profitSL - SLBufferPoints * _Point, _Digits);
            }
            else
            {
               profitSL = NormalizeDouble(openPrice - lockDist, _Digits);
               if(SLBufferPoints > 0) profitSL = NormalizeDouble(profitSL + SLBufferPoints * _Point, _Digits);
            }
               
            useProfitSL = true;
         }
         
         if(type == POSITION_TYPE_BUY)
         {
            newSL = NormalizeDouble(low1, _Digits);
            if(SLBufferPoints > 0) newSL = NormalizeDouble(newSL - SLBufferPoints * _Point, _Digits);
            
            // Ensure SL is valid (not too close to current price)
            if(currentBid - newSL < minStopDist) newSL = NormalizeDouble(currentBid - minStopDist - _Point, _Digits);
            
            // Use whichever is in profit (better SL)
            if(useProfitSL && profitSL > newSL) newSL = profitSL;
            
            if(newSL > currentSL + _Point || currentSL == 0)
               modify = true;
         }
         else if(type == POSITION_TYPE_SELL)
         {
            newSL = NormalizeDouble(high1, _Digits);
            if(SLBufferPoints > 0) newSL = NormalizeDouble(newSL + SLBufferPoints * _Point, _Digits);
            
            // Ensure SL is valid (not too close to current price)
            if(newSL - currentAsk < minStopDist) newSL = NormalizeDouble(currentAsk + minStopDist + _Point, _Digits);
            
            // Use whichever is in profit (better SL)
            if(useProfitSL && profitSL < newSL) newSL = profitSL;
            
            if(newSL < currentSL - _Point || currentSL == 0)
               modify = true;
         }
         
         if(modify)
            trade.PositionModify(ticket, newSL, currentTP);
      }
   }
}