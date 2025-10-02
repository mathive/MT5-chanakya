//+------------------------------------------------------------------+
//|                                                  CSVWriter.mq5 |
//|                                      Copyright 2025, CSV Writer |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, CSV Writer"
#property version   "1.00"
#property script_show_inputs

// Include the CSV Bridge
#include <Custom\CSVBridge.mqh>

// Input parameters
input string InpSymbol = ""; // Symbol (empty = current symbol)
input string InpSpreadData = ""; // Spread data to record (empty = current spread)
input string InpSignal = ""; // Signal (BUY/SELL/empty)
input bool InpUseCommonFolder = true; // Save CSV in common folder

//+------------------------------------------------------------------+
//| Creates or updates a CSV file with symbol and spread data         |
//+------------------------------------------------------------------+
void OnStart()
{
   // This script is now simplified to only write spread information on EA initialization
   string symbolName;
   int spreadPoints;
   
   // Get symbol name (default to current if not provided)
   symbolName = (InpSymbol != "") ? InpSymbol : Symbol();
   
   // Get spread data
   if(InpSpreadData != "")
   {
      // Try to parse spread from input
      spreadPoints = (int)StringToInteger(InpSpreadData);
   }
   else
   {
      // Get current spread
      spreadPoints = (int)SymbolInfoInteger(symbolName, SYMBOL_SPREAD);
   }
   
   Print("CSVWriter script started for symbol: ", symbolName, " - Writing spread information only");
   
   // Create a simple CSV file with just spread information
   string filename = symbolName + "_" + IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN)) + ".csv";
   
   // Determine file flags
   int fileFlags = FILE_WRITE|FILE_CSV|FILE_ANSI;
   if(InpUseCommonFolder) fileFlags |= FILE_COMMON;
   
   // Create/overwrite file
   int fileHandle = FileOpen(filename, fileFlags);
   
   if(fileHandle != INVALID_HANDLE)
   {
      // Write just symbol and spread information
      FileWrite(fileHandle, "Symbol", "Spread");
      FileWrite(fileHandle, symbolName, IntegerToString(spreadPoints));
      
      // Close the file
      FileClose(fileHandle);
      
      // Print success message with file location
      string folderPath = InpUseCommonFolder ? 
                         TerminalInfoString(TERMINAL_COMMONDATA_PATH) + "\\Files\\" : 
                         TerminalInfoString(TERMINAL_DATA_PATH) + "\\Files\\";
                         
      Print("Spread information written to CSV file: ", folderPath, filename);
   }
   else
   {
      Print("Failed to create CSV file. Error: ", GetLastError());
   }
}