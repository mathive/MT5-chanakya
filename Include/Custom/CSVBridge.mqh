//+------------------------------------------------------------------+
//|                                                  CSVBridge.mqh |
//|                      Copyright 2025, CSV Bridge Communication  |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, CSV Bridge"
#property strict

//+------------------------------------------------------------------+
//| Functions to bridge communication between EA and CSV Writer      |
//+------------------------------------------------------------------+



//+------------------------------------------------------------------+
//| Write spread data to CSV file (only during initialization)       |
//+------------------------------------------------------------------+
bool WriteToCSV(string symbol, int spread, string signal, bool useCommonFolder = true)
{
   // Only write to CSV if this is the initialization signal
   if(signal != "INIT")
      return true; // Skip non-initialization writes
      
   // Prepare file path
   long id = AccountInfoInteger(ACCOUNT_LOGIN);
   
   // Create filename
   string filename = symbol + "_" + IntegerToString(id) + ".csv";
   
   // Determine file flags
   int fileFlags = FILE_WRITE|FILE_CSV|FILE_ANSI;
   if(useCommonFolder) fileFlags |= FILE_COMMON;
   
   // Print where the file will be saved
   if(useCommonFolder)
      Print("CSV file will be saved in common folder: ", TerminalInfoString(TERMINAL_COMMONDATA_PATH), "\\Files\\", filename);
   else
      Print("CSV file will be saved in terminal folder: ", TerminalInfoString(TERMINAL_DATA_PATH), "\\Files\\", filename);
   
   // Always create a new file with just the spread information
   int fileHandle;
   
   // Create new file with just spread information
   fileHandle = FileOpen(filename, fileFlags);
   
   if(fileHandle != INVALID_HANDLE)
   {
      // Write simplified content - just symbol and spread
      FileWrite(fileHandle, "Symbol", "Spread");
      FileWrite(fileHandle, symbol, IntegerToString(spread));
      
      // Close the file
      FileClose(fileHandle);
      
      Print("CSV file with spread information created: ", filename);
      return true;
   }
   else
   {
      Print("Failed to create spread CSV file. Error: ", GetLastError());
      return false;
   }
}