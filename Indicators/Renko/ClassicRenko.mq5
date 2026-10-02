//+------------------------------------------------------------------+
//|                                                 ClassicRenko.mq5 |
//|                 Classic fixed-box Renko chart indicator for MT5 |
//+------------------------------------------------------------------+
#property copyright "2026"
#property version   "1.00"
#property description "Builds classic Renko bricks in a separate indicator window."

#property indicator_separate_window
#property indicator_buffers 5
#property indicator_plots   1
#property indicator_label1  "Renko Open;Renko High;Renko Low;Renko Close"
#property indicator_type1   DRAW_COLOR_CANDLES
#property indicator_color1  clrLimeGreen,clrTomato
#property indicator_width1  1

input double InpBrickSizePoints = 100.0; // Brick size (points)
input int    InpHistoryBars     = 5000;  // Source candles to process
input bool   InpShowWicks       = true;  // Show price excursions as wicks

double OpenBuffer[];
double HighBuffer[];
double LowBuffer[];
double CloseBuffer[];
double ColorBuffer[];

double BrickOpen[];
double BrickHigh[];
double BrickLow[];
double BrickClose[];
double BrickColor[];
int    BrickCount=0;
double LastClose=0.0;
int    LastDirection=0;
double ExcursionHigh=0.0;
double ExcursionLow=0.0;
double BrickSize=0.0;

//+------------------------------------------------------------------+
int OnInit()
  {
   if(InpBrickSizePoints<=0.0 || InpHistoryBars<2)
     {
      Print("ClassicRenko: brick size must be positive and history must be at least 2 bars.");
      return(INIT_PARAMETERS_INCORRECT);
     }

   SetIndexBuffer(0,OpenBuffer,INDICATOR_DATA);
   SetIndexBuffer(1,HighBuffer,INDICATOR_DATA);
   SetIndexBuffer(2,LowBuffer,INDICATOR_DATA);
   SetIndexBuffer(3,CloseBuffer,INDICATOR_DATA);
   SetIndexBuffer(4,ColorBuffer,INDICATOR_COLOR_INDEX);
   PlotIndexSetDouble(0,PLOT_EMPTY_VALUE,EMPTY_VALUE);
   IndicatorSetInteger(INDICATOR_DIGITS,_Digits);
   IndicatorSetString(INDICATOR_SHORTNAME,
                      "Classic Renko ("+DoubleToString(InpBrickSizePoints,1)+" pts)");
   BrickSize=InpBrickSizePoints*_Point;
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
void ResetBuilder(const int capacity,const double start_price)
  {
   ArrayResize(BrickOpen,capacity);
   ArrayResize(BrickHigh,capacity);
   ArrayResize(BrickLow,capacity);
   ArrayResize(BrickClose,capacity);
   ArrayResize(BrickColor,capacity);
   BrickCount=0;
   LastClose=NormalizeDouble(MathFloor(start_price/BrickSize)*BrickSize,_Digits);
   LastDirection=0;
   ExcursionHigh=start_price;
   ExcursionLow=start_price;
  }

//+------------------------------------------------------------------+
void AddBrick(const int direction,const double price_before_brick)
  {
   if(BrickCount>=ArraySize(BrickOpen))
      return;

   double brick_open=LastClose;
   // A classic reversal starts one box away and requires a two-box move.
   if(LastDirection!=0 && direction!=LastDirection)
      brick_open=LastClose-direction*BrickSize;

   double brick_close=brick_open+direction*BrickSize;
   BrickOpen[BrickCount]=NormalizeDouble(brick_open,_Digits);
   BrickClose[BrickCount]=NormalizeDouble(brick_close,_Digits);
   BrickHigh[BrickCount]=MathMax(brick_open,brick_close);
   BrickLow[BrickCount]=MathMin(brick_open,brick_close);

   if(InpShowWicks)
     {
      if(direction>0)
         BrickLow[BrickCount]=MathMin(BrickLow[BrickCount],ExcursionLow);
      else
         BrickHigh[BrickCount]=MathMax(BrickHigh[BrickCount],ExcursionHigh);
     }

   BrickColor[BrickCount]=(direction>0 ? 0.0 : 1.0);
   BrickCount++;
   LastClose=NormalizeDouble(brick_close,_Digits);
   LastDirection=direction;
   ExcursionHigh=MathMax(LastClose,price_before_brick);
   ExcursionLow=MathMin(LastClose,price_before_brick);
  }

//+------------------------------------------------------------------+
void ProcessPrice(const double price)
  {
   ExcursionHigh=MathMax(ExcursionHigh,price);
   ExcursionLow=MathMin(ExcursionLow,price);

   while(BrickCount<ArraySize(BrickOpen))
     {
      double up_trigger=LastClose+BrickSize;
      double down_trigger=LastClose-BrickSize;
      if(LastDirection<0)
         up_trigger=LastClose+2.0*BrickSize;
      else if(LastDirection>0)
         down_trigger=LastClose-2.0*BrickSize;

      if(price>=up_trigger-(_Point*0.1))
         AddBrick(1,price);
      else if(price<=down_trigger+(_Point*0.1))
         AddBrick(-1,price);
      else
         break;
     }
  }

//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,const int prev_calculated,
                const datetime &time[],const double &open[],
                const double &high[],const double &low[],
                const double &close[],const long &tick_volume[],
                const long &volume[],const int &spread[])
  {
   if(rates_total<2)
      return(0);

   ArraySetAsSeries(open,false);
   ArraySetAsSeries(high,false);
   ArraySetAsSeries(low,false);
   ArraySetAsSeries(close,false);
   ArraySetAsSeries(OpenBuffer,false);
   ArraySetAsSeries(HighBuffer,false);
   ArraySetAsSeries(LowBuffer,false);
   ArraySetAsSeries(CloseBuffer,false);
   ArraySetAsSeries(ColorBuffer,false);

   ArrayInitialize(OpenBuffer,EMPTY_VALUE);
   ArrayInitialize(HighBuffer,EMPTY_VALUE);
   ArrayInitialize(LowBuffer,EMPTY_VALUE);
   ArrayInitialize(CloseBuffer,EMPTY_VALUE);
   ArrayInitialize(ColorBuffer,0.0);

   int first=MathMax(0,rates_total-InpHistoryBars);
   ResetBuilder(rates_total,open[first]);

   for(int i=first;i<rates_total && BrickCount<rates_total;i++)
     {
      ProcessPrice(open[i]);
      // This deterministic path reduces the ambiguity inside an OHLC candle.
      if(close[i]>=open[i])
        {
         ProcessPrice(low[i]);
         ProcessPrice(high[i]);
        }
      else
        {
         ProcessPrice(high[i]);
         ProcessPrice(low[i]);
        }
      ProcessPrice(close[i]);
     }

   int visible=MathMin(BrickCount,rates_total);
   int source=BrickCount-visible;
   int target=rates_total-visible;
   for(int j=0;j<visible;j++)
     {
      OpenBuffer[target+j]=BrickOpen[source+j];
      HighBuffer[target+j]=BrickHigh[source+j];
      LowBuffer[target+j]=BrickLow[source+j];
      CloseBuffer[target+j]=BrickClose[source+j];
      ColorBuffer[target+j]=BrickColor[source+j];
     }

   return(rates_total);
  }
//+------------------------------------------------------------------+
