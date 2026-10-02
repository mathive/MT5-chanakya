//+------------------------------------------------------------------+
//|                                                   SimpleGrid.mq5 |
//|                                  Copyright 2024, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Gemini Code Assist"
#property link      "https://www.mql5.com"
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>

//--- Enums for Inputs
enum ENUM_TRADE_DIRECTION {
   DIR_BUY_ONLY,    // Buy Only
   DIR_SELL_ONLY,   // Sell Only
   DIR_BOTH         // Both Buy and Sell
};

enum ENUM_GRID_TYPE {
   GRID_LIMIT,      // Limit Orders (Retracement/Averaging)
   GRID_STOP        // Stop Orders (Breakout/Pyramiding)
};

//--- Input Parameters
input group "Grid Settings"
input ENUM_TRADE_DIRECTION InpDirection   = DIR_BOTH;      // Trade Direction
input ENUM_GRID_TYPE       InpGridType    = GRID_LIMIT;    // Grid Type (Limit/Stop)
input int                  InpTotalOrders = 5;             // Total Orders (Count)
input int                  InpDiffPoints  = 50;            // Difference (Step) in Points
input double               InpLotSize     = 0.01;          // Lot Size

input group "Price Range Filter"
input bool                 InpUsePriceRange = false;       // Enable Price Range Filter
input double               InpRangeMinPrice = 0.0;         // Range Lower Price (e.g. 4300.00)
input double               InpRangeMaxPrice = 0.0;         // Range Upper Price (e.g. 4305.00)

input group "Risk Management"
input int                  InpTakeProfit  = 100;           // Take Profit (Points)
input int                  InpStopLoss    = 0;             // Stop Loss (Points, 0=None)
input bool                 InpKeepSLLast  = true;          // Keep SL at Last Order Price
input bool                 InpReopenOnTP  = true;          // Reopen Order When TP Is Collected
input double               InpMaxProfit   = 0;             // Max Profit (Currency, 0=Disabled) - Closes all and stops EA
input double               InpDailyProfit = 0;             // Daily Profit (Currency, 0=Disabled) - Closes all for the day
input int                  InpCoolingPeriod = 30;          // Cooling Period (Minutes) after Max Profit

input group "System"
input int                  InpMagic       = 999888;        // Magic Number
input int                  InpSlippage    = 3;             // Slippage

//--- Global Objects
CTrade trade;

//--- Daily Profit Tracking
datetime g_daily_target_last_day;
bool     g_daily_target_reached = false;
datetime g_max_profit_reached_time = 0;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   // Set magic number for trade identification
   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(InpSlippage);
   
   // Validate inputs
   if(InpTotalOrders < 1)
     {
      Alert("Error: Total Orders must be at least 1");
      return(INIT_PARAMETERS_INCORRECT);
     }
     
   // Initialize Daily Profit Tracking
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   dt.hour = 0;
   dt.min = 0;
   dt.sec = 0;
   g_daily_target_last_day = StructToTime(dt);
   
   return(INIT_SUCCEEDED);
  }

//--- Helper: Check if price is within configured range
bool IsPriceInRange(const double price)
{
   if(!InpUsePriceRange)
      return true;

   double minP = InpRangeMinPrice;
   double maxP = InpRangeMaxPrice;

   if(minP > maxP && maxP > 0.0)
   {
      double tmp = minP;
      minP = maxP;
      maxP = tmp;
   }

   if(minP > 0.0 && price < minP - (_Point * 0.1))
      return false;

   if(maxP > 0.0 && price > maxP + (_Point * 0.1))
      return false;

   return true;
}

//--- Helper: Reopen closed TP position at original entry price
void ReopenOrderAtLevel(const ENUM_POSITION_TYPE pos_type, const double open_price, const double lot_size)
{
   if(!InpReopenOnTP)
      return;

   if(g_max_profit_reached_time > 0 || g_daily_target_reached)
      return;

   if(!IsPriceInRange(open_price))
      return;

   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   double sl = 0;
   double tp = 0;

   // Calculate SL/TP
   if(InpStopLoss > 0)
   {
      if(pos_type == POSITION_TYPE_BUY)
         sl = open_price - (InpStopLoss * point);
      else
         sl = open_price + (InpStopLoss * point);
      sl = NormalizeDouble(sl, _Digits);
   }

   if(InpTakeProfit > 0)
   {
      if(pos_type == POSITION_TYPE_BUY)
         tp = open_price + (InpTakeProfit * point);
      else
         tp = open_price - (InpTakeProfit * point);
      tp = NormalizeDouble(tp, _Digits);
   }

   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(InpSlippage);

   // Determine if we should place Limit, Stop, or Market based on current price
   if(pos_type == POSITION_TYPE_BUY)
   {
      if(open_price < ask - (_Point * 0.5))
      {
         trade.BuyLimit(lot_size, open_price, _Symbol, sl, tp, 0, 0, "Grid Buy Limit (TP Reopen)");
      }
      else if(open_price > ask + (_Point * 0.5))
      {
         trade.BuyStop(lot_size, open_price, _Symbol, sl, tp, 0, 0, "Grid Buy Stop (TP Reopen)");
      }
      else
      {
         trade.Buy(lot_size, _Symbol, 0, sl, tp, "Grid Buy Market (TP Reopen)");
      }
   }
   else // POSITION_TYPE_SELL
   {
      if(open_price > bid + (_Point * 0.5))
      {
         trade.SellLimit(lot_size, open_price, _Symbol, sl, tp, 0, 0, "Grid Sell Limit (TP Reopen)");
      }
      else if(open_price < bid - (_Point * 0.5))
      {
         trade.SellStop(lot_size, open_price, _Symbol, sl, tp, 0, 0, "Grid Sell Stop (TP Reopen)");
      }
      else
      {
         trade.Sell(lot_size, _Symbol, 0, sl, tp, "Grid Sell Market (TP Reopen)");
      }
   }
}

//+------------------------------------------------------------------+
//| Trade Transaction handler to detect TP fills and reopen          |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
{
   if(!InpReopenOnTP)
      return;

   if(trans.symbol != _Symbol)
      return;

   // When a deal is added to history
   if(trans.type == TRADE_TRANSACTION_DEAL_ADD)
   {
      ulong deal_ticket = trans.deal;
      if(deal_ticket <= 0)
         return;

      if(!HistoryDealSelect(deal_ticket))
         return;

      long deal_magic = HistoryDealGetInteger(deal_ticket, DEAL_MAGIC);
      if(deal_magic != InpMagic)
         return;

      ENUM_DEAL_ENTRY entry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(deal_ticket, DEAL_ENTRY);
      // Only process deals that closed a position (out deals)
      if(entry == DEAL_ENTRY_OUT || entry == DEAL_ENTRY_OUT_BY)
      {
         double profit = HistoryDealGetDouble(deal_ticket, DEAL_PROFIT);
         ENUM_DEAL_REASON reason = (ENUM_DEAL_REASON)HistoryDealGetInteger(deal_ticket, DEAL_REASON);

         // Check if closed by TP or in positive profit
         if(reason == DEAL_REASON_TP || profit > 0.0)
         {
            ENUM_DEAL_TYPE deal_type = (ENUM_DEAL_TYPE)HistoryDealGetInteger(deal_ticket, DEAL_TYPE);
            double volume = HistoryDealGetDouble(deal_ticket, DEAL_VOLUME);
            double reopen_price = 0.0;
            ENUM_POSITION_TYPE original_pos_type;

            if(deal_type == DEAL_TYPE_SELL)
            {
               // Closing a BUY position
               original_pos_type = POSITION_TYPE_BUY;
               // Target entry price is TP price minus TakeProfit distance
               reopen_price = NormalizeDouble(HistoryDealGetDouble(deal_ticket, DEAL_PRICE) - (InpTakeProfit * _Point), _Digits);
            }
            else
            {
               // Closing a SELL position
               original_pos_type = POSITION_TYPE_SELL;
               // Target entry price is TP price plus TakeProfit distance
               reopen_price = NormalizeDouble(HistoryDealGetDouble(deal_ticket, DEAL_PRICE) + (InpTakeProfit * _Point), _Digits);
            }

            if(reopen_price > 0.0 && volume > 0.0)
            {
               Print("Take-Profit collected! Reopening ", (original_pos_type == POSITION_TYPE_BUY ? "BUY" : "SELL"),
                     " order at original level: ", DoubleToString(reopen_price, _Digits));
               ReopenOrderAtLevel(original_pos_type, reopen_price, volume);
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
   // Check Daily Profit Target
   if(CheckDailyProfit()) return; // If target is met, stop all activity for the day

   // Check Max Profit
   if(CheckMaxProfit()) return;

   // Check Cooldown after Max Profit
   if(g_max_profit_reached_time > 0)
     {
      long coolingSeconds = InpCoolingPeriod * 60;
      if(TimeCurrent() - g_max_profit_reached_time < coolingSeconds)
        {
         Comment("Max Profit Target Reached. Waiting ", InpCoolingPeriod, " minutes... Time remaining: ", 
                 (int)((coolingSeconds - (TimeCurrent() - g_max_profit_reached_time))/60), " min");
         return;
        }
      else
        {
         g_max_profit_reached_time = 0;
         Comment("");
        }
     }

   // Only place orders if no orders/positions exist for this magic number
   if(CountOrders() == 0)
     {
      // Place Buy Grid
      if(InpDirection == DIR_BUY_ONLY || InpDirection == DIR_BOTH)
        {
         PlaceGridOrders(POSITION_TYPE_BUY);
        }
        
      // Place Sell Grid
      if(InpDirection == DIR_SELL_ONLY || InpDirection == DIR_BOTH)
        {
         PlaceGridOrders(POSITION_TYPE_SELL);
        }
     }
  }

//+------------------------------------------------------------------+
//| Helper: Count active positions and pending orders                |
//+------------------------------------------------------------------+
int CountOrders()
  {
   int count = 0;
   
   // Check Positions
   for(int i=PositionsTotal()-1; i>=0; i--)
     {
      if(PositionSelectByTicket(PositionGetTicket(i)))
        {
         if(PositionGetInteger(POSITION_MAGIC) == InpMagic && 
            PositionGetString(POSITION_SYMBOL) == _Symbol)
            count++;
        }
     }
     
   // Check Pending Orders
   for(int i=OrdersTotal()-1; i>=0; i--)
     {
      if(OrderSelect(OrderGetTicket(i)))
        {
         if(OrderGetInteger(ORDER_MAGIC) == InpMagic && 
            OrderGetString(ORDER_SYMBOL) == _Symbol)
            count++;
        }
     }
     
   return count;
  }

//+------------------------------------------------------------------+
//| Helper: Place Grid Orders                                        |
//+------------------------------------------------------------------+
void PlaceGridOrders(ENUM_POSITION_TYPE type)
  {
   double priceStart = 0;
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   
   // Determine starting price
   if(type == POSITION_TYPE_BUY)
      priceStart = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   else
      priceStart = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      
   double commonSL = 0;
   // Calculate Common SL if the option is enabled
   if(InpKeepSLLast)
     {
      double maxDistance = (InpTotalOrders - 1) * InpDiffPoints * point;
      double lastOrderPrice = 0;

      if(type == POSITION_TYPE_BUY)
        {
         lastOrderPrice = (InpGridType == GRID_LIMIT) ? priceStart - maxDistance : priceStart + maxDistance;
         commonSL = lastOrderPrice - (InpDiffPoints * point);
        }
      else // SELL
        {
         lastOrderPrice = (InpGridType == GRID_LIMIT) ? priceStart + maxDistance : priceStart - maxDistance;
         commonSL = lastOrderPrice + (InpDiffPoints * point);
        }
      commonSL = NormalizeDouble(commonSL, _Digits);
     }
      
   for(int i=0; i<InpTotalOrders; i++)
     {
      double openPrice = 0;
      double sl = 0;
      double tp = 0;
      
      // Calculate Open Price based on Grid Type and Index
      double distance = i * InpDiffPoints * point;
      
      if(InpGridType == GRID_LIMIT)
        {
         // Limit: Buy Lower, Sell Higher
         if(type == POSITION_TYPE_BUY)
            openPrice = priceStart - distance;
         else
            openPrice = priceStart + distance;
        }
      else // GRID_STOP
        {
         // Stop: Buy Higher, Sell Lower
         if(type == POSITION_TYPE_BUY)
            openPrice = priceStart + distance;
         else
            openPrice = priceStart - distance;
        }
        
      openPrice = NormalizeDouble(openPrice, _Digits);
      
      // Calculate SL/TP
      if(InpKeepSLLast)
        {
         sl = commonSL;
        }
      else if(InpStopLoss > 0)
        {
         if(type == POSITION_TYPE_BUY)
            sl = openPrice - (InpStopLoss * point);
         else
            sl = openPrice + (InpStopLoss * point);
         sl = NormalizeDouble(sl, _Digits);
        }
        
      if(InpTakeProfit > 0)
        {
         if(type == POSITION_TYPE_BUY)
            tp = openPrice + (InpTakeProfit * point);
         else
            tp = openPrice - (InpTakeProfit * point);
         tp = NormalizeDouble(tp, _Digits);
        }
        
      // Execute Order
      // First order (i=0) is Market only if current price is in range
      if(i == 0)
        {
         if(!IsPriceInRange(priceStart))
            continue; // Skip market execution if starting price is outside range

         if(type == POSITION_TYPE_BUY)
           {
            // Send with 0 SL/TP first to get exact execution price
            if(trade.Buy(InpLotSize, _Symbol, 0, 0, 0, "Grid Buy Market"))
              {
               // Recalibrate SL/TP based on actual execution price
               double execPrice = trade.ResultPrice();
               if(execPrice > 0)
                 {
                  double newSL = 0;
                  if(InpKeepSLLast)
                    {
                     newSL = commonSL;
                    }
                  else if(InpStopLoss > 0)
                    {
                     newSL = execPrice - (InpStopLoss * point);
                    }
                  double newTP = (InpTakeProfit > 0) ? execPrice + (InpTakeProfit * point) : 0;
                  trade.PositionModify(trade.ResultOrder(), NormalizeDouble(newSL, _Digits), NormalizeDouble(newTP, _Digits));
                 }
              }
           }
         else
           {
            if(trade.Sell(InpLotSize, _Symbol, 0, 0, 0, "Grid Sell Market"))
              {
               double execPrice = trade.ResultPrice();
               if(execPrice > 0)
                 {
                  double newSL = 0;
                  if(InpKeepSLLast)
                    {
                     newSL = commonSL;
                    }
                  else if(InpStopLoss > 0)
                    {
                     newSL = execPrice + (InpStopLoss * point);
                    }
                  double newTP = (InpTakeProfit > 0) ? execPrice - (InpTakeProfit * point) : 0;
                  trade.PositionModify(trade.ResultOrder(), NormalizeDouble(newSL, _Digits), NormalizeDouble(newTP, _Digits));
                 }
              }
           }
        }
      else
        {
         // Pending Orders - only place if openPrice falls within the price range
         if(!IsPriceInRange(openPrice))
            continue;

         if(InpGridType == GRID_LIMIT)
           {
            if(type == POSITION_TYPE_BUY)
               trade.BuyLimit(InpLotSize, openPrice, _Symbol, sl, tp, 0, 0, "Grid Buy Limit");
            else
               trade.SellLimit(InpLotSize, openPrice, _Symbol, sl, tp, 0, 0, "Grid Sell Limit");
           }
         else // GRID_STOP
           {
            if(type == POSITION_TYPE_BUY)
               trade.BuyStop(InpLotSize, openPrice, _Symbol, sl, tp, 0, 0, "Grid Buy Stop");
            else
               trade.SellStop(InpLotSize, openPrice, _Symbol, sl, tp, 0, 0, "Grid Sell Stop");
           }
        }
     }
     
   //--- Verification Step: Ensure all orders have correct SL/TP
   // Check Positions
   for(int i=PositionsTotal()-1; i>=0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
        {
         if(PositionGetInteger(POSITION_MAGIC) == InpMagic && 
            PositionGetString(POSITION_SYMBOL) == _Symbol &&
            PositionGetInteger(POSITION_TYPE) == type)
           {
            double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
            double currSL = PositionGetDouble(POSITION_SL);
            double currTP = PositionGetDouble(POSITION_TP);
            double newSL = 0;
            double newTP = 0;
            
            // Calculate expected SL
            if(InpKeepSLLast)
               newSL = commonSL;
            else if(InpStopLoss > 0)
              {
               if(type == POSITION_TYPE_BUY) newSL = openPrice - (InpStopLoss * point);
               else newSL = openPrice + (InpStopLoss * point);
               newSL = NormalizeDouble(newSL, _Digits);
              }
              
            // Calculate expected TP
            if(InpTakeProfit > 0)
              {
               if(type == POSITION_TYPE_BUY) newTP = openPrice + (InpTakeProfit * point);
               else newTP = openPrice - (InpTakeProfit * point);
               newTP = NormalizeDouble(newTP, _Digits);
              }
              
            if(MathAbs(currSL - newSL) > point/10 || MathAbs(currTP - newTP) > point/10)
              {
               trade.PositionModify(ticket, newSL, newTP);
              }
           }
        }
     }

   // Check Pending Orders
   for(int i=OrdersTotal()-1; i>=0; i--)
     {
      ulong ticket = OrderGetTicket(i);
      if(OrderSelect(ticket))
        {
         if(OrderGetInteger(ORDER_MAGIC) == InpMagic && 
            OrderGetString(ORDER_SYMBOL) == _Symbol)
           {
            ENUM_ORDER_TYPE orderType = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
            bool typeMatch = false;
            if(type == POSITION_TYPE_BUY && (orderType == ORDER_TYPE_BUY_LIMIT || orderType == ORDER_TYPE_BUY_STOP)) typeMatch = true;
            if(type == POSITION_TYPE_SELL && (orderType == ORDER_TYPE_SELL_LIMIT || orderType == ORDER_TYPE_SELL_STOP)) typeMatch = true;
            
            if(typeMatch)
              {
               double openPrice = OrderGetDouble(ORDER_PRICE_OPEN);
               double currSL = OrderGetDouble(ORDER_SL);
               double currTP = OrderGetDouble(ORDER_TP);
               double newSL = 0;
               double newTP = 0;
               
               // Calculate expected SL
               if(InpKeepSLLast)
                  newSL = commonSL;
               else if(InpStopLoss > 0)
                 {
                  if(type == POSITION_TYPE_BUY) newSL = openPrice - (InpStopLoss * point);
                  else newSL = openPrice + (InpStopLoss * point);
                  newSL = NormalizeDouble(newSL, _Digits);
                 }
                 
               // Calculate expected TP
               if(InpTakeProfit > 0)
                 {
                  if(type == POSITION_TYPE_BUY) newTP = openPrice + (InpTakeProfit * point);
                  else newTP = openPrice - (InpTakeProfit * point);
                  newTP = NormalizeDouble(newTP, _Digits);
                 }
                 
               if(MathAbs(currSL - newSL) > point/10 || MathAbs(currTP - newTP) > point/10)
                 {
                  trade.OrderModify(ticket, openPrice, newSL, newTP, (ENUM_ORDER_TYPE_TIME)OrderGetInteger(ORDER_TYPE_TIME), (datetime)OrderGetInteger(ORDER_TIME_EXPIRATION));
                 }
              }
           }
        }
     }
  }

//+------------------------------------------------------------------+
//| Helper: Check and Close if Max Profit Reached                    |
//+------------------------------------------------------------------+
bool CheckMaxProfit()
  {
   if(InpMaxProfit <= 0) return false;

   double totalProfit = 0;
   
   for(int i=PositionsTotal()-1; i>=0; i--)
     {
      if(PositionSelectByTicket(PositionGetTicket(i)))
        {
         if(PositionGetInteger(POSITION_MAGIC) == InpMagic && 
            PositionGetString(POSITION_SYMBOL) == _Symbol)
           {
            totalProfit += PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
           }
        }
     }
     
   if(totalProfit >= InpMaxProfit)
     {
      g_max_profit_reached_time = TimeCurrent();
      Print("Max profit limit reached. Closing trades and pausing for ", InpCoolingPeriod, " minutes.");

      // Close Positions
      for(int i=PositionsTotal()-1; i>=0; i--)
        {
         ulong ticket = PositionGetTicket(i);
         if(PositionSelectByTicket(ticket))
           {
            if(PositionGetInteger(POSITION_MAGIC) == InpMagic && 
               PositionGetString(POSITION_SYMBOL) == _Symbol)
               trade.PositionClose(ticket);
           }
        }
        
      // Delete Pending Orders
      for(int i=OrdersTotal()-1; i>=0; i--)
        {
         ulong ticket = OrderGetTicket(i);
         if(OrderSelect(ticket))
           {
            if(OrderGetInteger(ORDER_MAGIC) == InpMagic && 
               OrderGetString(ORDER_SYMBOL) == _Symbol)
               trade.OrderDelete(ticket);
           }
        }
      return true;
     }
   return false;
  }

//+------------------------------------------------------------------+
//| Helper: Check and handle Daily Profit Target                     |
//+------------------------------------------------------------------+
bool CheckDailyProfit()
  {
   if(InpDailyProfit <= 0) return false; // Feature disabled

   // --- Check for a new day ---
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   dt.hour = 0;
   dt.min = 0;
   dt.sec = 0;
   datetime today = StructToTime(dt);

   if(today > g_daily_target_last_day)
     {
      g_daily_target_last_day = today;
      g_daily_target_reached = false; // Reset for the new day
      Print("New day started. Daily profit target has been reset.");
     }

   // If target for today is already reached, stop trading
   if(g_daily_target_reached)
     {
      return true; // Indicates that trading should be stopped for the day
     }

   // --- Calculate today's profit (Realized + Floating) ---
   double totalProfit = 0;
   
   // 1. Calculate Realized Profit for today
   if(HistorySelect(today, TimeCurrent()))
     {
      int total_deals = HistoryDealsTotal();
      for(int i = 0; i < total_deals; i++)
        {
         ulong ticket = HistoryDealGetTicket(i);
         if(ticket > 0)
           {
            if(HistoryDealGetInteger(ticket, DEAL_MAGIC) == InpMagic &&
               HistoryDealGetString(ticket, DEAL_SYMBOL) == _Symbol)
              {
               totalProfit += HistoryDealGetDouble(ticket, DEAL_PROFIT) + 
                              HistoryDealGetDouble(ticket, DEAL_SWAP) + 
                              HistoryDealGetDouble(ticket, DEAL_COMMISSION);
              }
           }
        }
     }

   // 2. Add Floating Profit from Open Positions
   for(int i=PositionsTotal()-1; i>=0; i--)
     {
      if(PositionSelectByTicket(PositionGetTicket(i)))
        {
         if(PositionGetInteger(POSITION_MAGIC) == InpMagic &&
            PositionGetString(POSITION_SYMBOL) == _Symbol)
           {
            totalProfit += PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
           }
        }
     }

   if(totalProfit >= InpDailyProfit)
     {
      Print("Daily profit target of ", InpDailyProfit, " reached. Total profit: ", totalProfit);
      g_daily_target_reached = true; // Mark target as reached for the day

      // Close Positions
      for(int i=PositionsTotal()-1; i>=0; i--)
        {
         ulong ticket = PositionGetTicket(i);
         if(PositionSelectByTicket(ticket))
           {
            if(PositionGetInteger(POSITION_MAGIC) == InpMagic &&
               PositionGetString(POSITION_SYMBOL) == _Symbol)
               trade.PositionClose(ticket);
           }
        }

      // Delete Pending Orders
      for(int i=OrdersTotal()-1; i>=0; i--)
        {
         ulong ticket = OrderGetTicket(i);
         if(OrderSelect(ticket))
           {
            if(OrderGetInteger(ORDER_MAGIC) == InpMagic &&
               OrderGetString(ORDER_SYMBOL) == _Symbol)
               trade.OrderDelete(ticket);
           }
        }
      Alert("Daily profit target reached. Trading is stopped for the rest of the day.");
      return true; // Stop further processing
     }

   return false; // Target not reached
  }