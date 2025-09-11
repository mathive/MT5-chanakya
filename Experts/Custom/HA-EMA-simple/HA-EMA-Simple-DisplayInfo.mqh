//+------------------------------------------------------------------+
//|                                    HA-EMA-Simple-DisplayInfo.mqh |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

// We need access to some global variables and inputs defined in the main EA file.
// The magic number is passed via function calls, not as a global variable
int g_baseMagicNumber = 123456; // Default value, will be updated from the main EA

// Panel configuration
#define INFO_PANEL_NAME "Info-Panel"
#define PANEL_X_MARGIN 20  // X distance from right side of chart
#define PANEL_Y_MARGIN 20  // Y distance from top of chart
#define PANEL_WIDTH 250    // Panel width in pixels
#define LINE_HEIGHT 20     // Height per text line
#define PANEL_BG_COLOR clrBlack   // Dark gray background
#define PANEL_BORDER_COLOR clrGray  // Gray border
#define TEXT_COLOR clrWhite
#define PROFIT_COLOR clrLime   // Green for profits
#define LOSS_COLOR clrRed     // Red for losses
#define WARNING_COLOR clrOrange  // Orange for warnings
#define HEADER_COLOR clrGold  // Gold for headers
#define FONT_NAME "Arial"
#define FONT_SIZE 9

//+------------------------------------------------------------------+
//| Create or update info panel on chart                             |
//+------------------------------------------------------------------+
void CreateInfoPanel()
{
   // Delete any existing panel first
   ObjectDelete(0, INFO_PANEL_NAME + "_BG");
   
   // Get chart dimensions
   long width, height;
   ChartGetInteger(0, CHART_WIDTH_IN_PIXELS, 0, width);
   ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS, 0, height);
   
   // Panel position - right aligned
   int x1 = (int)width - PANEL_WIDTH - PANEL_X_MARGIN;
   int y1 = PANEL_Y_MARGIN;
   
   // Create panel background
   ObjectCreate(0, INFO_PANEL_NAME + "_BG", OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, INFO_PANEL_NAME + "_BG", OBJPROP_XDISTANCE, x1);
   ObjectSetInteger(0, INFO_PANEL_NAME + "_BG", OBJPROP_YDISTANCE, y1);
   ObjectSetInteger(0, INFO_PANEL_NAME + "_BG", OBJPROP_XSIZE, PANEL_WIDTH);
   ObjectSetInteger(0, INFO_PANEL_NAME + "_BG", OBJPROP_YSIZE, LINE_HEIGHT * 16);  // Adjust height based on number of lines
   ObjectSetInteger(0, INFO_PANEL_NAME + "_BG", OBJPROP_BGCOLOR, PANEL_BG_COLOR);
   ObjectSetInteger(0, INFO_PANEL_NAME + "_BG", OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, INFO_PANEL_NAME + "_BG", OBJPROP_BORDER_COLOR, PANEL_BORDER_COLOR);
   ObjectSetInteger(0, INFO_PANEL_NAME + "_BG", OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, INFO_PANEL_NAME + "_BG", OBJPROP_ANCHOR, ANCHOR_LEFT_UPPER);
   ObjectSetInteger(0, INFO_PANEL_NAME + "_BG", OBJPROP_BACK, false);
   ObjectSetInteger(0, INFO_PANEL_NAME + "_BG", OBJPROP_SELECTABLE, false);
}

//+------------------------------------------------------------------+
//| Add a text label to the info panel                               |
//+------------------------------------------------------------------+
void AddInfoLabel(int line, string text, color textColor = TEXT_COLOR)
{
   string labelName = INFO_PANEL_NAME + "_L" + IntegerToString(line);
   
   // Get chart width
   long width;
   ChartGetInteger(0, CHART_WIDTH_IN_PIXELS, 0, width);
   
   // Text position - inside panel
   int x1 = (int)width - PANEL_WIDTH - PANEL_X_MARGIN + 5;  // +5 for padding
   int y1 = PANEL_Y_MARGIN + (line * LINE_HEIGHT) + 5;      // +5 for padding
   
   // Delete existing label if it exists
   ObjectDelete(0, labelName);
   
   // Create text label
   ObjectCreate(0, labelName, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, labelName, OBJPROP_XDISTANCE, x1);
   ObjectSetInteger(0, labelName, OBJPROP_YDISTANCE, y1);
   ObjectSetInteger(0, labelName, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, labelName, OBJPROP_ANCHOR, ANCHOR_LEFT_UPPER);
   ObjectSetString(0, labelName, OBJPROP_TEXT, text);
   ObjectSetString(0, labelName, OBJPROP_FONT, FONT_NAME);
   ObjectSetInteger(0, labelName, OBJPROP_FONTSIZE, FONT_SIZE);
   ObjectSetInteger(0, labelName, OBJPROP_COLOR, textColor);
   ObjectSetInteger(0, labelName, OBJPROP_BACK, false);
   ObjectSetInteger(0, labelName, OBJPROP_SELECTABLE, false);
}

//+------------------------------------------------------------------+
//| Update the information panel with current trading statistics     |
//+------------------------------------------------------------------+
void UpdateInfoPanel(double startDayBalance, 
                    double startMonthBalance, 
                    double monthlyPeakBalance,
                    bool dailyTargetReached,
                    bool monthlyTargetReached,
                    bool drawdownReached,
                    double maxDrawdown)
{
   // Make sure panel exists
   CreateInfoPanel();
   
   // Calculate current trading information
   double currentBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   double unrealizedProfit = CalculateTotalUnrealizedProfit();
   double totalValue = currentBalance + unrealizedProfit;
   
   // Calculate profits/losses
   double dailyPL = currentBalance - startDayBalance;
   double dailyPLWithUnrealized = dailyPL + unrealizedProfit;
   double monthlyPL = currentBalance - startMonthBalance;
   double monthlyPLWithUnrealized = monthlyPL + unrealizedProfit;
   
   // Calculate drawdown
   double currentDrawdown = monthlyPeakBalance - totalValue;
   double drawdownPercent = monthlyPeakBalance > 0 ? (currentDrawdown / monthlyPeakBalance) * 100.0 : 0;
   
   // Get number of positions
   int positionsCount = PositionsTotal();
   
   // Get current time
   datetime currentTime = TimeCurrent();
   MqlDateTime dt;
   TimeToStruct(currentTime, dt);
   
   // Format dates
   string monthNames[] = {"January", "February", "March", "April", "May", "June", 
                         "July", "August", "September", "October", "November", "December"};
   string currentMonthName = monthNames[dt.mon-1];
   
   // Add the info labels - headers and data
   int line = 0;
   
   // Title and current time
   AddInfoLabel(line++, "HA-EMA Trading Statistics", HEADER_COLOR);
   AddInfoLabel(line++, "------------------------------------------------------", TEXT_COLOR);
   AddInfoLabel(line++, TimeToString(currentTime, TIME_DATE|TIME_MINUTES), TEXT_COLOR);
   
   // Account summary
   AddInfoLabel(line++, "------------------------------------------------------", TEXT_COLOR);
   AddInfoLabel(line++, "Account Balance: $" + DoubleToString(currentBalance, 2), TEXT_COLOR);
   AddInfoLabel(line++, "Open P/L: $" + DoubleToString(unrealizedProfit, 2), 
               unrealizedProfit >= 0 ? PROFIT_COLOR : LOSS_COLOR);
   AddInfoLabel(line++, "Total Value: $" + DoubleToString(totalValue, 2), TEXT_COLOR);
   AddInfoLabel(line++, "Open Positions: " + IntegerToString(positionsCount), TEXT_COLOR);
   
   // Daily stats
   AddInfoLabel(line++, "------------------------------------------------------", TEXT_COLOR);
   AddInfoLabel(line++, "Today's P/L: $" + DoubleToString(dailyPL, 2) + 
               " (incl. open: $" + DoubleToString(dailyPLWithUnrealized, 2) + ")",
               dailyPLWithUnrealized >= 0 ? PROFIT_COLOR : LOSS_COLOR);
   
   if(dailyTargetReached)
      AddInfoLabel(line++, "Daily Profit Target REACHED", WARNING_COLOR);
   
   // Monthly stats
   AddInfoLabel(line++, "------------------------------------------------------", TEXT_COLOR);
   AddInfoLabel(line++, currentMonthName + " P/L: $" + DoubleToString(monthlyPL, 2) + 
               " (incl. open: $" + DoubleToString(monthlyPLWithUnrealized, 2) + ")",
               monthlyPLWithUnrealized >= 0 ? PROFIT_COLOR : LOSS_COLOR);
   
   // Peak and drawdown
   AddInfoLabel(line++, "Monthly Peak: $" + DoubleToString(monthlyPeakBalance, 2), TEXT_COLOR);
   AddInfoLabel(line++, "Current Drawdown: $" + DoubleToString(currentDrawdown, 2) + 
                " (" + DoubleToString(drawdownPercent, 1) + "%)",
                currentDrawdown > maxDrawdown * 0.7 ? WARNING_COLOR : TEXT_COLOR);
   
   // Status messages
   if(monthlyTargetReached)
      AddInfoLabel(line++, "Monthly Profit Target REACHED", WARNING_COLOR);
   
   if(drawdownReached)
      AddInfoLabel(line++, "Maximum Drawdown REACHED", WARNING_COLOR);
}

//+------------------------------------------------------------------+
//| Calculate total unrealized profit from all EA positions          |
//+------------------------------------------------------------------+
double CalculateTotalUnrealizedProfit()
{
   double unrealizedProfit = 0.0;
   
   // Calculate unrealized profit from all open positions
   int total = PositionsTotal();
   for(int i = 0; i < total; i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket <= 0)
         continue;
      
      // Only count positions from our EA (using magic number)
      long magic = PositionGetInteger(POSITION_MAGIC);
      
      // Check if magic number belongs to our EA's range
      // Use the base magic number that was set from the main EA
      if(magic >= g_baseMagicNumber && magic < g_baseMagicNumber + 100)
      {
         // Add this position's floating profit to our unrealized profit
         unrealizedProfit += PositionGetDouble(POSITION_PROFIT);
      }
   }
   
   return unrealizedProfit;
}

//+------------------------------------------------------------------+
//| Remove all panel objects from chart                              |
//+------------------------------------------------------------------+
void RemoveInfoPanel()
{
   ObjectDelete(0, INFO_PANEL_NAME + "_BG");
   
   // Delete all labels
   for(int i = 0; i < 20; i++)  // Assuming max 20 labels
   {
      string labelName = INFO_PANEL_NAME + "_L" + IntegerToString(i);
      ObjectDelete(0, labelName);
   }
}

//+------------------------------------------------------------------+
//| Set the base magic number from the main EA                       |
//+------------------------------------------------------------------+
void SetMagicNumber(int magicNumber)
{
   g_baseMagicNumber = magicNumber;
}
