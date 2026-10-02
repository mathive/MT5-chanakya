bool IsTimeframeInComment(string comment, string tfName)
{
   if(comment == "" || tfName == "")
      return false;

   int len_tf = StringLen(tfName);
   int pos = 0;
   while((pos = StringFind(comment, tfName, pos)) >= 0)
   {
      bool before_ok = (pos == 0) || (StringGetCharacter(comment, pos - 1) == ' ') || (StringGetCharacter(comment, pos - 1) == '_') || (StringGetCharacter(comment, pos - 1) == '-') || (StringGetCharacter(comment, pos - 1) == '[');
      int end_pos = pos + len_tf;
      bool after_ok = (end_pos >= StringLen(comment)) || (StringGetCharacter(comment, end_pos) == ' ') || (StringGetCharacter(comment, end_pos) == '_') || (StringGetCharacter(comment, end_pos) == '-') || (StringGetCharacter(comment, end_pos) == ']');

      if(before_ok && after_ok)
         return true;

      pos += len_tf;
   }
   return false;
}

//+------------------------------------------------------------------+
//|                                                   CSVTracker.mqh |
//|         Simple CSV tracking system for EA state persistence     |
//+------------------------------------------------------------------+

#include <Files\File.mqh>
#include "TimeFrameSelection.mqh"

//--- CSV file settings - make instance-specific using symbol and magic
struct CSVInstance {
    string fileName;
    string filePath;
    int magicNumber;
    string symbol;
};

CSVInstance csvInstance;

//+------------------------------------------------------------------+
//| Generate CSV filename with format: Symbol-ID-MagicNumber       |
//+------------------------------------------------------------------+
string GenerateCSVFilename(int magic)
{
    string filename = StringFormat("%s-%lld-%d.csv", _Symbol, AccountInfoInteger(ACCOUNT_LOGIN), magic);
    return filename;
}

//+------------------------------------------------------------------+
//| Initialize CSV tracking system with simple headers             |
//+------------------------------------------------------------------+
bool InitializeCSVTracker(int magic = 123456)
{
    // Skip CSV tracking in Strategy Tester
    if (MQLInfoInteger(MQL_TESTER))
    {
        Print("CSV Tracker: Disabled in Strategy Tester mode");
        return true;
    }

    // Store instance-specific data
    csvInstance.magicNumber = magic;
    csvInstance.symbol = _Symbol;

    // Generate filename using new format
    csvInstance.fileName = GenerateCSVFilename(magic);

    // Create CSV file path in modular/CSV tracker/ directory
    csvInstance.filePath = "CSV tracker\\" + csvInstance.fileName;

    // Check if file exists, if not create with headers
    int fileHandle = FileOpen(csvInstance.filePath, FILE_READ | FILE_WRITE | FILE_CSV, ",");
    if (fileHandle != INVALID_HANDLE)
    {
        // Check if file is empty (new file)
        if (FileSize(fileHandle) == 0)
        {
            // Write simple headers
            FileWrite(fileHandle, "Timeframe", "Completed", "ProfitTarget", "HasOrder", "OrderTicket", "OrderType", "OrderPrice", "LastUpdate");

            // Write initial status rows for system states
            FileWrite(fileHandle, "MAX_LOSS_STATUS", "FALSE", "0.00", "FALSE", "0", "NONE", "0.0", "1970.01.01 00:00");
            FileWrite(fileHandle, "MAX_PROFIT_STATUS", "FALSE", "0.00", "FALSE", "0", "NONE", "0.0", "1970.01.01 00:00");

            // Write initial rows for ALL SELECTED timeframes
            InitializeSelectedTimeframesInCSV(fileHandle);

            Print("CSV Tracker: Created new state file with fixed selected timeframes");
        }
        FileClose(fileHandle);
        
        // ALWAYS run cleanup on initialization to remove duplicates  
        CleanupCSVDuplicates();
        
        // Ensure all selected timeframes are present (in case of partial file)
        EnsureAllSelectedTimeframesExist();
        
        Print("CSV Tracker: Initialized successfully - File: ", csvInstance.filePath);
        return true;
    }
    else
    {
        Print("CSV Tracker: Failed to initialize - Error: ", GetLastError());
        return false;
    }
}

//+------------------------------------------------------------------+
//| Initialize CSV with all selected timeframes                    |
//+------------------------------------------------------------------+
void InitializeSelectedTimeframesInCSV(int fileHandle)
{
    string defaultTime = "1970.01.01 00:00";
    
    // Get all selected timeframes
    ENUM_TIMEFRAMES selectedTFs[];
    GetSelectedTimeframes(selectedTFs);
    
    // Write entries for all selected timeframes
    for (int i = 0; i < ArraySize(selectedTFs); i++)
    {
        string tfName = GetTimeframeName(selectedTFs[i]);
        FileWrite(fileHandle, tfName, "FALSE", "0.00", "FALSE", "0", "NONE", "0.0", defaultTime);
        Print("CSV Init: Added fixed entry for ", tfName);
    }
    
    // Also ensure major timeframe is included if not already in selected list
    ENUM_TIMEFRAMES majorTF = GetMajorTimeframe();
    string majorTFName = GetTimeframeName(majorTF);
    bool majorInSelected = false;
    
    for (int i = 0; i < ArraySize(selectedTFs); i++)
    {
        if (selectedTFs[i] == majorTF)
        {
            majorInSelected = true;
            break;
        }
    }
    
    if (!majorInSelected)
    {
        FileWrite(fileHandle, majorTFName, "FALSE", "0.00", "FALSE", "0", "NONE", "0.0", defaultTime);
        Print("CSV Init: Added major timeframe ", majorTFName);
    }
}

//+------------------------------------------------------------------+
//| Ensure all selected timeframes exist in CSV                    |
//+------------------------------------------------------------------+
void EnsureAllSelectedTimeframesExist()
{
    // Skip in tester mode
    if (MQLInfoInteger(MQL_TESTER))
        return;
        
    // Get all selected timeframes
    ENUM_TIMEFRAMES selectedTFs[];
    GetSelectedTimeframes(selectedTFs);
    
    // Add major timeframe if not in selected list
    ENUM_TIMEFRAMES majorTF = GetMajorTimeframe();
    bool majorInSelected = false;
    for (int i = 0; i < ArraySize(selectedTFs); i++)
    {
        if (selectedTFs[i] == majorTF)
        {
            majorInSelected = true;
            break;
        }
    }
    
    // Create complete list including major timeframe
    ENUM_TIMEFRAMES allRequiredTFs[];
    int totalRequired = ArraySize(selectedTFs);
    if (!majorInSelected) totalRequired++;
    
    ArrayResize(allRequiredTFs, totalRequired);
    
    // Copy selected timeframes
    for (int i = 0; i < ArraySize(selectedTFs); i++)
    {
        allRequiredTFs[i] = selectedTFs[i];
    }
    
    // Add major timeframe if needed
    if (!majorInSelected)
    {
        allRequiredTFs[ArraySize(selectedTFs)] = majorTF;
    }
    
    // Check and add missing timeframes
    for (int i = 0; i < ArraySize(allRequiredTFs); i++)
    {
        string tfName = GetTimeframeName(allRequiredTFs[i]);
        TimeframeState state = GetTimeframeStateFromCSV(tfName);
        
        if (!state.isValid)
        {
            // Add missing timeframe
            string defaultTime = "1970.01.01 00:00";
            UpdateTimeframeState(tfName, false, 0.0, false, 0, "NONE", 0.0);
            Print("CSV Ensure: Added missing timeframe ", tfName);
        }
    }
}

//+------------------------------------------------------------------+
//| Check if timeframe is in selected list (validation)            |
//+------------------------------------------------------------------+
bool IsTimeframeSelected(string timeframeName)
{
    // Allow system status entries
    if (timeframeName == "MAX_LOSS_STATUS" || timeframeName == "MAX_PROFIT_STATUS")
        return true;
        
    // Get all selected timeframes
    ENUM_TIMEFRAMES selectedTFs[];
    GetSelectedTimeframes(selectedTFs);
    
    // Check selected timeframes
    for (int i = 0; i < ArraySize(selectedTFs); i++)
    {
        if (GetTimeframeName(selectedTFs[i]) == timeframeName)
            return true;
    }
    
    // Check major timeframe
    if (GetTimeframeName(GetMajorTimeframe()) == timeframeName)
        return true;
        
    return false;
}

//+------------------------------------------------------------------+
//| Simple position check for CSV synchronization                  |
//+------------------------------------------------------------------+
bool HasPositionForTimeframe_CSV(ENUM_TIMEFRAMES timeframe)
{
    string tfName = GetTimeframeName(timeframe);
    
    for (int i = 0; i < PositionsTotal(); i++)
    {
        if (PositionGetTicket(i) > 0)
        {
            if (PositionGetString(POSITION_SYMBOL) == _Symbol && 
                PositionGetInteger(POSITION_MAGIC) == csvInstance.magicNumber)
            {
                string comment = PositionGetString(POSITION_COMMENT);
                if (IsTimeframeInComment(comment, tfName))
                {
                    return true;
                }
            }
        }
    }
    return false;
}

//+------------------------------------------------------------------+
//| Direct CSV synchronization - rewrite entire file immediately   |
//+------------------------------------------------------------------+
bool SynchronizeCompleteCSVState()
{
    // Skip in tester mode
    if (MQLInfoInteger(MQL_TESTER))
        return true;
    
    Print("CSV Sync: Starting complete CSV state synchronization...");
    
    // Open file for complete rewrite
    int fileHandle = FileOpen(csvInstance.filePath, FILE_WRITE | FILE_TXT);
    if (fileHandle != INVALID_HANDLE)
    {
        // Write header
        FileWriteString(fileHandle, "Timeframe,Completed,ProfitTarget,HasOrder,OrderTicket,OrderType,OrderPrice,LastUpdate\n");
        
        // Write system status entries
        string currentTime = TimeToString(TimeCurrent(), TIME_DATE | TIME_MINUTES);
        FileWriteString(fileHandle, StringFormat("MAX_LOSS_STATUS,FALSE,0.00,FALSE,0,NONE,0.0,%s\n", currentTime));
        FileWriteString(fileHandle, StringFormat("MAX_PROFIT_STATUS,FALSE,0.00,FALSE,0,NONE,0.0,%s\n", currentTime));
        
        // Get all selected timeframes
        ENUM_TIMEFRAMES selectedTFs[];
        GetSelectedTimeframes(selectedTFs);
        
        // Add major timeframe if not in selected list
        ENUM_TIMEFRAMES majorTF = GetMajorTimeframe();
        bool majorInSelected = false;
        for (int i = 0; i < ArraySize(selectedTFs); i++)
        {
            if (selectedTFs[i] == majorTF)
            {
                majorInSelected = true;
                break;
            }
        }
        
        // Create complete list including major timeframe
        ENUM_TIMEFRAMES allRequiredTFs[];
        int totalRequired = ArraySize(selectedTFs);
        if (!majorInSelected) totalRequired++;
        
        ArrayResize(allRequiredTFs, totalRequired);
        
        // Copy selected timeframes
        for (int i = 0; i < ArraySize(selectedTFs); i++)
        {
            allRequiredTFs[i] = selectedTFs[i];
        }
        
        // Add major timeframe if needed
        if (!majorInSelected)
        {
            allRequiredTFs[ArraySize(selectedTFs)] = majorTF;
        }
        
        // Write current state for each required timeframe (using internal tracking)
        for (int i = 0; i < ArraySize(allRequiredTFs); i++)
        {
            string tfName = GetTimeframeName(allRequiredTFs[i]);
            
            // Check if timeframe has active position
            bool hasPosition = HasPositionForTimeframe_CSV(allRequiredTFs[i]);
            
            // Get order tracking data from main EA
            ulong orderTicket = 0;
            double orderPrice = 0.0;
            string orderType = "NONE";
            bool hasOrder = GetOrderTrackingData(allRequiredTFs[i], orderTicket, orderPrice, orderType);
            
            // Write timeframe state
            FileWriteString(fileHandle, StringFormat("%s,%s,0.00,%s,%llu,%s,%.5f,%s\n",
                           tfName,
                           hasPosition ? "TRUE" : "FALSE",
                           hasOrder ? "TRUE" : "FALSE",
                           orderTicket,
                           orderType,
                           orderPrice,
                           currentTime));
                           
            Print("CSV Sync: ", tfName, " -> Position:", hasPosition ? "TRUE" : "FALSE", 
                  " Order:", hasOrder ? "TRUE" : "FALSE", " Ticket:", orderTicket);
        }
        
        FileClose(fileHandle);
        Print("CSV Sync: Complete CSV state synchronization finished successfully");
        return true;
    }
    
    Print("CSV Sync: ERROR - Failed to open file for synchronization");
    return false;
}

//+------------------------------------------------------------------+
//| Fast CSV update for immediate state changes                    |
//+------------------------------------------------------------------+
bool FastUpdateCSVState(string timeframeName, bool completed, double profitTarget, bool hasOrder, ulong orderTicket, string orderType, double orderPrice)
{
    // Skip in tester mode
    if (MQLInfoInteger(MQL_TESTER))
        return true;

    // VALIDATION: Only allow updates for selected timeframes
    if (!IsTimeframeSelected(timeframeName))
    {
        Print("CSV Fast Update BLOCKED: ", timeframeName, " is not in selected timeframes list");
        return false;
    }
    
    // Use complete synchronization for immediate consistency
    bool result = SynchronizeCompleteCSVState();
    
    if (result)
    {
        Print("CSV Fast Update: ", timeframeName, " -> Completed:", completed ? "TRUE" : "FALSE", 
              " HasOrder:", hasOrder ? "TRUE" : "FALSE", " Ticket:", orderTicket);
    }
    
    return result;
}

//+------------------------------------------------------------------+
//| Update timeframe state in CSV (DUPLICATE-SAFE + SELECTED-ONLY) |
//+------------------------------------------------------------------+
bool UpdateTimeframeState(string timeframeName, bool completed, double profitTarget, bool hasOrder, ulong orderTicket, string orderType, double orderPrice)
{
    // Skip in tester mode
    if (MQLInfoInteger(MQL_TESTER))
        return true;

    // VALIDATION: Only allow updates for selected timeframes
    if (!IsTimeframeSelected(timeframeName))
    {
        Print("CSV Update BLOCKED: ", timeframeName, " is not in selected timeframes list");
        return false;
    }

    string lines[];
    string newLines[];
    bool found = false;
    string currentTime = TimeToString(TimeCurrent(), TIME_DATE | TIME_MINUTES);

    // Read all lines from file
    int fileHandle = FileOpen(csvInstance.filePath, FILE_READ | FILE_TXT);
    if (fileHandle != INVALID_HANDLE)
    {
        int lineCount = 0;
        while (!FileIsEnding(fileHandle))
        {
            string line = FileReadString(fileHandle);
            if (line != "")
            {
                ArrayResize(lines, lineCount + 1);
                lines[lineCount] = line;
                lineCount++;
            }
        }
        FileClose(fileHandle);

        // Process lines and REMOVE ALL DUPLICATES
        ArrayResize(newLines, 0);
        int newLineCount = 0;
        
        for (int i = 0; i < lineCount; i++)
        {
            if (i == 0) // Header line
            {
                ArrayResize(newLines, newLineCount + 1);
                newLines[newLineCount] = lines[i];
                newLineCount++;
                continue;
            }

            string parts[];
            int count = StringSplit(lines[i], ',', parts);

            if (count >= 8 && parts[0] == timeframeName)
            {
                if (!found) // Only process the FIRST occurrence
                {
                    // Update this timeframe's data
                    ArrayResize(newLines, newLineCount + 1);
                    newLines[newLineCount] = StringFormat("%s,%s,%.2f,%s,%llu,%s,%.5f,%s",
                                               timeframeName,
                                               completed ? "TRUE" : "FALSE",
                                               profitTarget,
                                               hasOrder ? "TRUE" : "FALSE",
                                               orderTicket,
                                               orderType,
                                               orderPrice,
                                               currentTime);
                    newLineCount++;
                    found = true;
                }
                // Skip any subsequent duplicates for this timeframe
            }
            else
            {
                // Keep lines for other timeframes
                ArrayResize(newLines, newLineCount + 1);
                newLines[newLineCount] = lines[i];
                newLineCount++;
            }
        }

        // If timeframe not found, add new line
        if (!found)
        {
            ArrayResize(newLines, newLineCount + 1);
            newLines[newLineCount] = StringFormat("%s,%s,%.2f,%s,%llu,%s,%.5f,%s",
                                               timeframeName,
                                               completed ? "TRUE" : "FALSE",
                                               profitTarget,
                                               hasOrder ? "TRUE" : "FALSE",
                                               orderTicket,
                                               orderType,
                                               orderPrice,
                                               currentTime);
        }

        // Write all lines back
        fileHandle = FileOpen(csvInstance.filePath, FILE_WRITE | FILE_TXT);
        if (fileHandle != INVALID_HANDLE)
        {
            for (int i = 0; i < ArraySize(newLines); i++)
            {
                if (newLines[i] != "")
                    FileWriteString(fileHandle, newLines[i] + "\n");
            }
            FileClose(fileHandle);
            
            Print("CSV Update: ", timeframeName, " -> Completed:", completed ? "TRUE" : "FALSE", 
                  " HasOrder:", hasOrder ? "TRUE" : "FALSE", " Ticket:", orderTicket);
            
            return true;
        }
    }

    return false;
}

//+------------------------------------------------------------------+
//| Clean up duplicate entries in CSV file                         |
//+------------------------------------------------------------------+
bool CleanupCSVDuplicates()
{
    // Skip in tester mode
    if (MQLInfoInteger(MQL_TESTER))
        return true;
        
    string lines[];
    string cleanLines[];
    string processedTimeframes[];
    
    // Read all lines from file
    int fileHandle = FileOpen(csvInstance.filePath, FILE_READ | FILE_TXT);
    if (fileHandle != INVALID_HANDLE)
    {
        int lineCount = 0;
        while (!FileIsEnding(fileHandle))
        {
            string line = FileReadString(fileHandle);
            if (line != "")
            {
                ArrayResize(lines, lineCount + 1);
                lines[lineCount] = line;
                lineCount++;
            }
        }
        FileClose(fileHandle);

        if (lineCount == 0) return true;

        // Process lines and keep only unique timeframes
        ArrayResize(cleanLines, 0);
        ArrayResize(processedTimeframes, 0);
        int cleanCount = 0;
        int tfCount = 0;
        
        for (int i = 0; i < lineCount; i++)
        {
            if (i == 0) // Header line
            {
                ArrayResize(cleanLines, cleanCount + 1);
                cleanLines[cleanCount] = lines[i];
                cleanCount++;
                continue;
            }

            string parts[];
            int count = StringSplit(lines[i], ',', parts);

            if (count >= 8)
            {
                string timeframeName = parts[0];
                bool alreadyProcessed = false;
                
                // Check if we've already processed this timeframe
                for (int j = 0; j < tfCount; j++)
                {
                    if (processedTimeframes[j] == timeframeName)
                    {
                        alreadyProcessed = true;
                        break;
                    }
                }
                
                // ONLY KEEP SELECTED TIMEFRAMES
                if (!alreadyProcessed && IsTimeframeSelected(timeframeName))
                {
                    // Keep this line (first occurrence of selected timeframe)
                    ArrayResize(cleanLines, cleanCount + 1);
                    cleanLines[cleanCount] = lines[i];
                    cleanCount++;
                    
                    // Mark timeframe as processed
                    ArrayResize(processedTimeframes, tfCount + 1);
                    processedTimeframes[tfCount] = timeframeName;
                    tfCount++;
                }
                else if (!alreadyProcessed && !IsTimeframeSelected(timeframeName))
                {
                    Print("CSV Cleanup: Removed non-selected timeframe ", timeframeName);
                }
                else
                {
                    Print("CSV Cleanup: Removed duplicate entry for ", timeframeName);
                }
            }
        }

        // Write cleaned lines back
        fileHandle = FileOpen(csvInstance.filePath, FILE_WRITE | FILE_TXT);
        if (fileHandle != INVALID_HANDLE)
        {
            for (int i = 0; i < ArraySize(cleanLines); i++)
            {
                if (cleanLines[i] != "")
                    FileWriteString(fileHandle, cleanLines[i] + "\n");
            }
            FileClose(fileHandle);
            
            Print("CSV Cleanup: Processed ", lineCount, " lines -> ", ArraySize(cleanLines), " clean lines");
            return true;
        }
    }

    return false;
}

//+------------------------------------------------------------------+
//| Manually clean current CSV file (can be called anytime)       |
//+------------------------------------------------------------------+
bool ManualCleanupCSV()
{
    if (MQLInfoInteger(MQL_TESTER))
    {
        Print("Manual CSV Cleanup: Skipped in tester mode");
        return true;
    }
    
    Print("=== MANUAL CSV CLEANUP STARTED ===");
    bool result = CleanupCSVDuplicates();
    Print("=== MANUAL CSV CLEANUP COMPLETED ===");
    
    return result;
}

//+------------------------------------------------------------------+
//| Display current CSV structure for verification                 |
//+------------------------------------------------------------------+
void DisplayCSVStructure()
{
    if (MQLInfoInteger(MQL_TESTER))
    {
        Print("CSV Structure Display: Skipped in tester mode");
        return;
    }
    
    Print("=== CURRENT CSV STRUCTURE ===");
    
    // Get selected timeframes
    ENUM_TIMEFRAMES selectedTFs[];
    GetSelectedTimeframes(selectedTFs);
    
    Print("Selected Timeframes for CSV:");
    for (int i = 0; i < ArraySize(selectedTFs); i++)
    {
        Print("  - ", GetTimeframeName(selectedTFs[i]));
    }
    
    // Check major timeframe
    ENUM_TIMEFRAMES majorTF = GetMajorTimeframe();
    string majorTFName = GetTimeframeName(majorTF);
    bool majorInSelected = false;
    for (int i = 0; i < ArraySize(selectedTFs); i++)
    {
        if (selectedTFs[i] == majorTF)
        {
            majorInSelected = true;
            break;
        }
    }
    
    if (!majorInSelected)
    {
        Print("Major Timeframe (additional): ", majorTFName);
    }
    else
    {
        Print("Major Timeframe: ", majorTFName, " (already in selected list)");
    }
    
    Print("System Entries: MAX_LOSS_STATUS, MAX_PROFIT_STATUS");
    Print("=== END CSV STRUCTURE ===");
}

//+------------------------------------------------------------------+
//| Load EA state from simple CSV format                           |
//+------------------------------------------------------------------+
bool LoadEAStateFromCSV()
{
    // Skip in tester mode
    if (MQLInfoInteger(MQL_TESTER))
    {
        Print("CSV Tracker: Skipping state load in tester mode");
        return true;
    }

    int fileHandle = FileOpen(csvInstance.filePath, FILE_READ | FILE_TXT);
    if (fileHandle == INVALID_HANDLE)
    {
        Print("CSV Tracker: No existing state file found - Starting fresh");
        return false;
    }

    // Skip header line
    string header = FileReadString(fileHandle);
    int restoredStates = 0;

    // Read each timeframe state
    while (!FileIsEnding(fileHandle))
    {
        string data = FileReadString(fileHandle);
        if (data == "")
            continue;

        string parts[];
        int count = StringSplit(data, ',', parts);

        if (count >= 8)
        {
            string timeframeName = parts[0];
            bool completed = (parts[1] == "TRUE");
            double profitTarget = StringToDouble(parts[2]);
            bool hasOrder = (parts[3] == "TRUE");
            ulong orderTicket = StringToInteger(parts[4]);
            string orderType = parts[5];
            double orderPrice = StringToDouble(parts[6]);
            string lastUpdate = parts[7];

            // Skip placeholder rows
            if (timeframeName == "MAX_LOSS_STATUS" || timeframeName == "MAX_PROFIT_STATUS")
                continue;

            // Convert timeframe name to ENUM_TIMEFRAMES
            ENUM_TIMEFRAMES tf = GetTimeframeFromName(timeframeName);
            if (tf == PERIOD_CURRENT)
            {
                Print("CSV Tracker: Invalid timeframe: ", timeframeName);
                continue; // Invalid timeframe
            }

            // Find the index in the tracking arrays
            int tfIndex = FindTimeframeIndex(tf);
            if (tfIndex == -1)
            {
                Print("CSV Tracker: Timeframe not tracked: ", timeframeName);
                continue; // Timeframe not tracked by current EA
            }

            // Restore order tracking if there's an active order
            if (hasOrder && orderTicket > 0)
            {
                // Verify order still exists before restoring
                if (OrderExists(orderTicket))
                {
                    lastOrderTickets[tfIndex] = orderTicket;
                    lastOrderPrices[tfIndex] = orderPrice;
                    Print("CSV Tracker: Restored order tracking - TF: ", timeframeName,
                          ", Ticket: ", orderTicket, ", Price: ", orderPrice);
                    restoredStates++;
                }
                else
                {
                    Print("CSV Tracker: Order ", orderTicket, " no longer exists for ", timeframeName);
                    // Clear the state since order doesn't exist
                    lastOrderTickets[tfIndex] = 0;
                    lastOrderPrices[tfIndex] = 0.0;
                }
            }
            else
            {
                // No active order for this timeframe
                lastOrderTickets[tfIndex] = 0;
                lastOrderPrices[tfIndex] = 0.0;
            }

            // Restore position execution status
            if (completed)
            {
                // Check if position is still open for this timeframe
                bool hasPosition = PositionExists(tf);
                hasExecutedPosition[tfIndex] = hasPosition;

                if (hasPosition)
                {
                    Print("CSV Tracker: Restored position status - TF: ", timeframeName, " (Position still open)");
                    restoredStates++;
                }
                else
                {
                    Print("CSV Tracker: Position closed for ", timeframeName, " - resetting status");
                    hasExecutedPosition[tfIndex] = false;
                }
            }
            else
            {
                hasExecutedPosition[tfIndex] = false;
            }
        }
    }

    FileClose(fileHandle);
    Print("=== CSV STATE LOADING COMPLETE - ", restoredStates, " states restored ===");
    return true;
}

//+------------------------------------------------------------------+
//| Immediate CSV update functions matching SuperTrend-Multi style |
//+------------------------------------------------------------------+
bool LogOrderPlaced(ENUM_TIMEFRAMES timeframe, ulong ticket, double price, string orderType)
{
    // Use fast update which triggers complete CSV synchronization
    bool result = FastUpdateCSVState(GetTimeframeName(timeframe), false, 0.0, true, ticket, orderType, price);
    if (result)
    {
        Print("CSV: Order placed for ", GetTimeframeName(timeframe), " - Ticket:", ticket, " Price:", price, " | CSV updated");
    }
    return result;
}

bool LogOrderCancelled(ENUM_TIMEFRAMES timeframe, ulong ticket, string reason)
{
    // Use fast update which triggers complete CSV synchronization  
    bool result = FastUpdateCSVState(GetTimeframeName(timeframe), false, 0.0, false, 0, "NONE", 0.0);
    if (result)
    {
        Print("CSV: Order cancelled for ", GetTimeframeName(timeframe), " - Ticket:", ticket, " Reason:", reason, " | CSV updated");
    }
    return result;
}

bool LogOrderUpdated(ENUM_TIMEFRAMES timeframe, ulong ticket, double oldPrice, double newPrice) 
{ 
    // Get current order type for update
    string orderType = "NONE";
    if (OrderSelect(ticket))
    {
        ENUM_ORDER_TYPE ot = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
        if (ot == ORDER_TYPE_BUY_LIMIT) orderType = "BUY_LIMIT";
        else if (ot == ORDER_TYPE_SELL_LIMIT) orderType = "SELL_LIMIT";
        else if (ot == ORDER_TYPE_BUY_STOP) orderType = "BUY_STOP";
        else if (ot == ORDER_TYPE_SELL_STOP) orderType = "SELL_STOP";
    }
    
    // Use fast update which triggers complete CSV synchronization
    bool result = FastUpdateCSVState(GetTimeframeName(timeframe), false, 0.0, true, ticket, orderType, newPrice);
    if (result)
    {
        Print("CSV: Order updated for ", GetTimeframeName(timeframe), " - Ticket:", ticket, " NewPrice:", newPrice, " | CSV updated");
    }
    return result;
}

bool LogPositionOpened(ENUM_TIMEFRAMES timeframe, ulong ticket, string positionType, double openPrice)
{
    // Position opened - mark as completed in CSV
    bool result = FastUpdateCSVState(GetTimeframeName(timeframe), true, 0.0, false, 0, "NONE", 0.0);
    if (result)
    {
        Print("CSV: Position opened for ", GetTimeframeName(timeframe), " - Ticket:", ticket, " Type:", positionType, " | CSV updated");
    }
    return result;
}

bool LogPositionClosed(ENUM_TIMEFRAMES timeframe, ulong ticket, string reason, double closePrice)
{
    // Position closed - reset timeframe in CSV
    bool result = FastUpdateCSVState(GetTimeframeName(timeframe), false, 0.0, false, 0, "NONE", 0.0);
    if (result)
    {
        Print("CSV: Position closed for ", GetTimeframeName(timeframe), " - Ticket:", ticket, " Reason:", reason, " | CSV updated");
    }
    return result;
}

//+------------------------------------------------------------------+
//| Helper functions for CSV state restoration                     |
//+------------------------------------------------------------------+

// Convert timeframe name string to ENUM_TIMEFRAMES
ENUM_TIMEFRAMES GetTimeframeFromName(string tfName)
{
    if (tfName == "M1")
        return PERIOD_M1;
    if (tfName == "M5")
        return PERIOD_M5;
    if (tfName == "M15")
        return PERIOD_M15;
    if (tfName == "M30")
        return PERIOD_M30;
    if (tfName == "H1")
        return PERIOD_H1;
    if (tfName == "H4")
        return PERIOD_H4;
    if (tfName == "D1")
        return PERIOD_D1;
    if (tfName == "W1")
        return PERIOD_W1;
    if (tfName == "MN1")
        return PERIOD_MN1;

    return PERIOD_CURRENT; // Invalid timeframe
}

//+------------------------------------------------------------------+
//| External variable references from main.mq5                      |
//+------------------------------------------------------------------+
extern ulong lastOrderTickets[];
extern double lastOrderPrices[];
extern bool hasExecutedPosition[];
extern ENUM_TIMEFRAMES trackedTimeframes[];

//+------------------------------------------------------------------+
//| CSV State Verification and Synchronization Functions           |
//+------------------------------------------------------------------+

// Get timeframe state from CSV
struct TimeframeState
{
    bool completed;
    double profitTarget;
    bool hasOrder;
    ulong orderTicket;
    string orderType;
    double orderPrice;
    string lastUpdate;
    bool isValid;
};

//+------------------------------------------------------------------+
//| Get timeframe state from CSV file                              |
//+------------------------------------------------------------------+
TimeframeState GetTimeframeStateFromCSV(string timeframeName)
{
    TimeframeState state;
    state.isValid = false;

    if (MQLInfoInteger(MQL_TESTER))
        return state;

    int fileHandle = FileOpen(csvInstance.filePath, FILE_READ | FILE_TXT);
    if (fileHandle == INVALID_HANDLE)
        return state;

    string header = FileReadString(fileHandle); // Skip header

    while (!FileIsEnding(fileHandle))
    {
        string line = FileReadString(fileHandle);
        if (line == "")
            continue;

        string parts[];
        int count = StringSplit(line, ',', parts);

        if (count >= 8 && parts[0] == timeframeName)
        {
            state.completed = (parts[1] == "TRUE");
            state.profitTarget = StringToDouble(parts[2]);
            state.hasOrder = (parts[3] == "TRUE");
            state.orderTicket = (ulong)StringToInteger(parts[4]);
            state.orderType = parts[5];
            state.orderPrice = StringToDouble(parts[6]);
            state.lastUpdate = parts[7];
            state.isValid = true;
            break;
        }
    }

    FileClose(fileHandle);
    return state;
}

//+------------------------------------------------------------------+
//| Check if EA can place order based on CSV state                 |
//+------------------------------------------------------------------+
bool CanPlaceOrderForTimeframe(ENUM_TIMEFRAMES timeframe, string reason = "")
{
    string tfName = GetTimeframeName(timeframe);
    TimeframeState csvState = GetTimeframeStateFromCSV(tfName);

    // If CSV state not found, allow order placement
    if (!csvState.isValid)
    {
        return true;
    }

    // Check if position is already completed (open)
    if (csvState.completed)
    {
        // Verify position still exists
        bool actuallyHasPosition = HasOpenPositionForTimeframe(timeframe);
        if (actuallyHasPosition)
        {
            return false;
        }
        else
        {
            Print("CSV Check: CSV shows completed but no position found for ", tfName, " - allowing order (will sync CSV)");
            // Update CSV to reflect reality
            UpdateTimeframeState(tfName, false, 0.0, false, 0, "NONE", 0.0);
            return true;
        }
    }

    // Check if order already exists
    if (csvState.hasOrder && csvState.orderTicket > 0)
    {
        // Verify order still exists
        if (OrderExists(csvState.orderTicket))
        {
            Print("CSV Check: Active order exists for ", tfName, " (Ticket: ", csvState.orderTicket, ") - allowing update");
            return true; // Allow updates to existing orders
        }
        else
        {
            Print("CSV Check: CSV shows order but order doesn't exist for ", tfName, " - allowing new order (will sync CSV)");
            // Update CSV to reflect reality
            UpdateTimeframeState(tfName, false, 0.0, false, 0, "NONE", 0.0);
            return true;
        }
    }

    Print("CSV Check: No conflicts found for ", tfName, " - allowing order placement");
    return true;
}

//+------------------------------------------------------------------+
//| IMMEDIATE CSV SYNCHRONIZATION - Match SuperTrend-Multi Logic   |
//+------------------------------------------------------------------+
void SynchronizeOrdersWithCSV()
{
    if (MQLInfoInteger(MQL_TESTER))
        return;
        
    Print("=== CSV SYNC: Starting order synchronization (SuperTrend-Multi style) ===");
    
    int existingOrders = 0;
    
    // Count existing orders for our symbol and magic
    for (int i = 0; i < OrdersTotal(); i++)
    {
        ulong t = OrderGetTicket(i);
        if (t > 0)
        {
            if (OrderGetString(ORDER_SYMBOL) == _Symbol && 
                OrderGetInteger(ORDER_MAGIC) == csvInstance.magicNumber)
            {
                existingOrders++;
            }
        }
    }
    
    if (existingOrders > 0)
    {
        Print("CSV Sync: Found ", existingOrders, " existing orders - updating CSV to match broker state");
        SynchronizeCompleteCSVState();
    }
    else
    {
        Print("CSV Sync: No existing orders found - CSV will be updated as new orders are placed");
        // Still sync to clean up any stale CSV data
        SynchronizeCompleteCSVState();
    }
    
    Print("=== CSV SYNC: Order synchronization completed ===");
}

//+------------------------------------------------------------------+
//| Enhanced CSV state sync compatible with SuperTrend-Multi       |
//+------------------------------------------------------------------+
void SynchronizeCSVWithMT5State()
{
    if (MQLInfoInteger(MQL_TESTER))
        return;

    Print("=== CSV SYNC: FULL SYNCHRONIZATION (SuperTrend-Multi Compatible) ===");
    
    // Use the immediate synchronization approach
    SynchronizeOrdersWithCSV();
    
    // Additional cleanup
    CleanupCSVDuplicates();
    
    Print("=== CSV SYNC COMPLETE ===");
}

//+------------------------------------------------------------------+
//| Enhanced HasOpenPositionForTimeframe with immediate CSV sync   |
//+------------------------------------------------------------------+
bool HasOpenPositionForTimeframe_Synced(ENUM_TIMEFRAMES timeframe)
{
    // First check actual MT5 state
    bool actualHasPosition = HasOpenPositionForTimeframe(timeframe);

    // Get CSV state
    string tfName = GetTimeframeName(timeframe);
    TimeframeState csvState = GetTimeframeStateFromCSV(tfName);

    // If states don't match, immediately sync the entire CSV
    if (csvState.isValid && csvState.completed != actualHasPosition)
    {
        Print("CSV State Mismatch for ", tfName, " - CSV:", csvState.completed ? "TRUE" : "FALSE", 
              " MT5:", actualHasPosition ? "TRUE" : "FALSE", " - Syncing immediately");
        
        // Use fast update which triggers complete synchronization
        FastUpdateCSVState(tfName, actualHasPosition, 0.0, csvState.hasOrder, csvState.orderTicket, csvState.orderType, csvState.orderPrice);
    }

    return actualHasPosition;
}

// Additional logging functions for compatibility
bool LogSignalDetected(ENUM_TIMEFRAMES timeframe, ENUM_ST_SIGNAL signal, double linePrice, bool aligned) { return true; }
bool LogCandleClose(ENUM_TIMEFRAMES timeframe) { return true; }
