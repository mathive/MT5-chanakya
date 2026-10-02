//+------------------------------------------------------------------+
//|                                                SecurityGuard.mqh |
//|                                  Copyright 2026, Sanju Kaka Algo |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Sanju Kaka Algo"
#property link      "https://www.mql5.com"
#property strict

class CSecurityGuard
{
public:
   //--- Validate Account Binding / License Key
   static bool CheckAccountAuthorization(const string authorizedAccounts)
   {
      string trimmed = authorizedAccounts;
      StringTrimLeft(trimmed);
      StringTrimRight(trimmed);
      
      // If list is empty, EA is open for Demo/General use
      if(StringLen(trimmed) == 0)
         return true;
      
      long currentAccount = AccountInfoInteger(ACCOUNT_LOGIN);
      string currentAccountStr = IntegerToString(currentAccount);
      
      string accounts[];
      int total = StringSplit(trimmed, ',', accounts);
      
      for(int i = 0; i < total; i++)
      {
         string acc = accounts[i];
         StringTrimLeft(acc);
         StringTrimRight(acc);
         if(acc == currentAccountStr)
         {
            PrintFormat("[Security] Account %I64d is AUTHORIZED. License verified.", currentAccount);
            return true;
         }
      }
      
      PrintFormat("[SECURITY ALERT] Unauthorized Account: %I64d. EA Execution BLOCKED.", currentAccount);
      return false;
   }
   
   //--- Verify Trade Context & Broker Server readiness
   static bool IsTradeContextReady()
   {
      if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED))
      {
         Print("[Security Warning] Automated Trading is disabled in MetaTrader terminal settings.");
         return false;
      }
      if(!MQLInfoInteger(MQL_TRADE_ALLOWED))
      {
         Print("[Security Warning] Algo Trading is not permitted for this EA instance.");
         return false;
      }
      if(!AccountInfoInteger(ACCOUNT_TRADE_EXPERT))
      {
         Print("[Security Warning] Automated trading is not allowed on this account.");
         return false;
      }
      return true;
   }
};
