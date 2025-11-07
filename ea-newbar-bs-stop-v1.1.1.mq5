//+------------------------------------------------------------------+
//|                                    ea-newbar-bs-stop-v1.1.1.mq5 |
//|                                  Pending Order Management EA    |
//|                         Fixed: Risk Management & Array Logic    |
//+------------------------------------------------------------------+
#property copyright "PendingOrderEA"
#property version   "1.20"
#property strict

#include <Trade\Trade.mqh>

// Input Parameters
input group "=== Timeframe & Order Settings ==="
input ENUM_TIMEFRAMES InpPeriod = PERIOD_M5;                    // Timeframe
input int InpPendingDistance = 200;                              // Pending Order Distance (points)
input int InpStopLoss = 150;                                     // Stop Loss (points)
input double InpTPMultiplier = 2.5;                              // TP Multiplier

input group "=== Order Type Selection ==="
enum OrderTypeMode
{
   ORDER_BUY_ONLY,      // Buy Stop Only
   ORDER_SELL_ONLY,     // Sell Stop Only
   ORDER_BOTH           // Buy Stop & Sell Stop
};
input OrderTypeMode InpOrderMode = ORDER_BOTH;                   // Order Mode

input group "=== Risk Management Mode ==="
enum RiskManagementMode
{
   RM_DISABLE,          // Disable
   RM_BREAKEVEN,        // Break Even
   RM_TRAILING,         // Trailing Stop
   RM_BE_AND_TSL        // Break Even & Trailing Stop
};
input RiskManagementMode InpRMMode = RM_BREAKEVEN;              // Risk Management Mode

input group "=== Break Even Settings ==="
input int InpBEActivationPoints = 300;                           // Break Even Activation (points)
input int InpBEProfitPoints = 100;                               // Break Even Profit Lock (points)

input group "=== Trailing Stop Settings ==="
input int InpTrailingDistance = 300;                             // Trailing Distance (points)
input int InpTrailingStep = 200;                                 // Trailing Step (points)

input group "=== Lot Calculation ==="
enum LotCalculationMode
{
   LOT_FIXED,           // Fixed Lot
   LOT_RISK_PERCENT,    // % Risk per Trade
   LOT_RISK_MONEY       // Fixed Money
};
input LotCalculationMode InpLotMode = LOT_FIXED;                 // Lot Calculation Mode
input double InpFixedLot = 0.01;                                 // Fixed Lot Size
input double InpRiskPercent = 1.0;                               // Risk Percent (%)
input double InpRiskMoney = 10.0;                                // Risk Money

input group "=== Trading Time (Thai Time) ==="
input string InpStartTime = "00:00";                             // Start Time (HH:MM)
input string InpEndTime = "23:59";                               // End Time (HH:MM)

input group "=== EA Settings ==="
input int InpMagicNumber = 2025110601;                           // Magic Number
input string InpComment = "New Pending B/S Stop EA";             // Order Comment
input int InpMaxSpread = 200;                                    // Max Spread (points)

// Structures for Position Tracking
struct PositionTracker
{
   ulong ticket;
   bool breakEvenExecuted;
};

// Global Variables
CTrade trade;
datetime lastBarTime = 0;
PositionTracker positionTrackers[];
datetime g_last_bar_time = 0;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(10);
   trade.SetTypeFilling(ORDER_FILLING_FOK);
   trade.SetAsyncMode(false);
   
   lastBarTime = 0;
   ArrayResize(positionTrackers, 0);
   
   // Validation
   if(InpBEActivationPoints < 0 || InpBEProfitPoints < 0 || 
      InpTrailingDistance < 0 || InpTrailingStep < 0)
   {
      Print("Error: Risk Management parameters cannot be negative");
      return(INIT_PARAMETERS_INCORRECT);
   }
   
   if(InpStopLoss <= 0)
   {
      Print("Error: Stop Loss must be greater than 0");
      return(INIT_PARAMETERS_INCORRECT);
   }
   
   if(InpTPMultiplier <= 0)
   {
      Print("Error: TP Multiplier must be greater than 0");
      return(INIT_PARAMETERS_INCORRECT);
   }
   
   Print("═══════════════════════════════════════════════════════");
   Print("EA Initialized Successfully - Version 1.20");
   Print("═══════════════════════════════════════════════════════");
   Print("Timeframe: ", EnumToString(InpPeriod));
   Print("Order Mode: ", EnumToString(InpOrderMode));
   Print("Risk Management Mode: ", EnumToString(InpRMMode));
   Print("Lot Mode: ", EnumToString(InpLotMode));
   Print("Trading Time: ", InpStartTime, " - ", InpEndTime, " (Thai Time)");
   Print("═══════════════════════════════════════════════════════");
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   Print("EA Deinitialized - Reason: ", reason);
   ArrayFree(positionTrackers);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // Check for new bar
   if(IsNewBar(InpPeriod))
   {
      if(IsWithinTradingHours())
      {
         OnNewBar();
      }
   }
   
   // Manage active positions (รันทุก tick)
   ManagePositions();
}

//+------------------------------------------------------------------+
//| Check if current symbol matches                                 |
//+------------------------------------------------------------------+
bool IsMySymbol(const string sym)
{
   return (sym == _Symbol);
}

//+------------------------------------------------------------------+
//| Check for new bar                                               |
//+------------------------------------------------------------------+
bool IsNewBar(ENUM_TIMEFRAMES tf)
{
   MqlRates r[];
   if(CopyRates(_Symbol, tf, 0, 2, r) != 2)
      return false;
      
   if(g_last_bar_time != r[0].time)
   {
      g_last_bar_time = r[0].time;
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| New Bar Event                                                    |
//+------------------------------------------------------------------+
void OnNewBar()
{
   Print("─────────────────────────────────────────────────────");
   Print("New Bar Detected at ", TimeToString(TimeCurrent()));
   
   // 1. Delete all pending orders
   DeleteAllPendingOrders();
   
   // 2. Place new pending orders
   PlacePendingOrders();
   
   Print("─────────────────────────────────────────────────────");
}

//+------------------------------------------------------------------+
//| Check if current spread is acceptable                            |
//+------------------------------------------------------------------+
bool CheckSpread()
{
   long spread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   
   if(spread > InpMaxSpread)
   {
      Print("⚠ Spread too high: ", spread, " points (Max: ", InpMaxSpread, " points)");
      return false;
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| Delete All Pending Orders for current symbol                    |
//+------------------------------------------------------------------+
void DeleteAllPendingOrders()
{
   int deletedCount = 0;
   
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket > 0)
      {
         if(OrderGetString(ORDER_SYMBOL) == _Symbol && 
            OrderGetInteger(ORDER_MAGIC) == InpMagicNumber)
         {
            if(trade.OrderDelete(ticket))
            {
               deletedCount++;
               Print("✓ Deleted pending order #", ticket);
            }
            else
            {
               Print("✗ Failed to delete order #", ticket, " - Error: ", GetLastError());
            }
         }
      }
   }
   
   if(deletedCount > 0)
      Print("Deleted ", deletedCount, " pending order(s)");
}

//+------------------------------------------------------------------+
//| Count Positions by Type (Fixed version)                         |
//+------------------------------------------------------------------+
int CountPositionsByType(ENUM_POSITION_TYPE type)
{
   int count = 0;
   int total = PositionsTotal();
   
   for(int i = 0; i < total; i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;
         
      if(PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;
         
      if(PositionGetInteger(POSITION_MAGIC) != InpMagicNumber)
         continue;
         
      if((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) == type)
         count++;
   }
   
   return count;
}

//+------------------------------------------------------------------+
//| Place Pending Orders                                            |
//+------------------------------------------------------------------+
void PlacePendingOrders()
{
   if(!CheckSpread())
   {
      Print("⚠ Place order cancelled due to high spread");
      return;
   }
   
   // Count existing positions by type
   int buyCount = CountPositionsByType(POSITION_TYPE_BUY);
   int sellCount = CountPositionsByType(POSITION_TYPE_SELL);
   
   Print("Current Positions - Buy: ", buyCount, ", Sell: ", sellCount);
   
   double openPrice = iOpen(_Symbol, InpPeriod, 0);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   
   double pendingDistance = InpPendingDistance * point;
   double slDistance = InpStopLoss * point;
   double tpDistance = slDistance * InpTPMultiplier;
   
   // Calculate lot size
   double lotSize = CalculateLotSize(slDistance);
   
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   if(lotSize < minLot)
   {
      Print("✗ Calculated lot size (", lotSize, ") too small. Minimum: ", minLot);
      return;
   }
   
   Print("Calculated Lot Size: ", lotSize);
   Print("Open Price: ", openPrice, ", Pending Distance: ", pendingDistance);
   
   // Place Buy Stop Order (only if no Buy position exists)
   if((InpOrderMode == ORDER_BUY_ONLY || InpOrderMode == ORDER_BOTH) && buyCount == 0)
   {
      double buyPrice = NormalizeDouble(openPrice + pendingDistance, digits);
      double buySL = NormalizeDouble(buyPrice - slDistance, digits);
      double buyTP = NormalizeDouble(buyPrice + tpDistance, digits);
      
      if(trade.BuyStop(lotSize, buyPrice, _Symbol, buySL, buyTP, 
                       ORDER_TIME_GTC, 0, InpComment))
      {
         Print("✓ Buy Stop Order placed: Price=", buyPrice, ", SL=", buySL, ", TP=", buyTP);
      }
      else
      {
         Print("✗ Failed to place Buy Stop Order - Error: ", GetLastError());
      }
   }
   else if((InpOrderMode == ORDER_BUY_ONLY || InpOrderMode == ORDER_BOTH) && buyCount > 0)
   {
      Print("⊗ Buy Stop Order skipped - Already have ", buyCount, " Buy position(s)");
   }
   
   // Place Sell Stop Order (only if no Sell position exists)
   if((InpOrderMode == ORDER_SELL_ONLY || InpOrderMode == ORDER_BOTH) && sellCount == 0)
   {
      double sellPrice = NormalizeDouble(openPrice - pendingDistance, digits);
      double sellSL = NormalizeDouble(sellPrice + slDistance, digits);
      double sellTP = NormalizeDouble(sellPrice - tpDistance, digits);
      
      if(trade.SellStop(lotSize, sellPrice, _Symbol, sellSL, sellTP, 
                        ORDER_TIME_GTC, 0, InpComment))
      {
         Print("✓ Sell Stop Order placed: Price=", sellPrice, ", SL=", sellSL, ", TP=", sellTP);
      }
      else
      {
         Print("✗ Failed to place Sell Stop Order - Error: ", GetLastError());
      }
   }
   else if((InpOrderMode == ORDER_SELL_ONLY || InpOrderMode == ORDER_BOTH) && sellCount > 0)
   {
      Print("⊗ Sell Stop Order skipped - Already have ", sellCount, " Sell position(s)");
   }
}

//+------------------------------------------------------------------+
//| Calculate Lot Size based on mode                                |
//+------------------------------------------------------------------+
double CalculateLotSize(double slDistance)
{
   double lotSize = InpFixedLot;
   
   if(InpLotMode == LOT_RISK_PERCENT)
   {
      double equity = AccountInfoDouble(ACCOUNT_EQUITY);
      double riskAmount = equity * InpRiskPercent / 100.0;
      double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
      double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
      
      if(tickSize > 0 && tickValue > 0)
      {
         double slInTicks = slDistance / tickSize;
         lotSize = riskAmount / (slInTicks * tickValue);
      }
      else
      {
         Print("⚠ Warning: Invalid tick values, using fixed lot");
         lotSize = InpFixedLot;
      }
   }
   else if(InpLotMode == LOT_RISK_MONEY)
   {
      double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
      double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
      
      if(tickSize > 0 && tickValue > 0)
      {
         double slInTicks = slDistance / tickSize;
         lotSize = InpRiskMoney / (slInTicks * tickValue);
      }
      else
      {
         Print("⚠ Warning: Invalid tick values, using fixed lot");
         lotSize = InpFixedLot;
      }
   }
   
   // Normalize lot size
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   
   lotSize = MathMax(minLot, MathMin(maxLot, lotSize));
   lotSize = MathFloor(lotSize / lotStep) * lotStep;
   
   return NormalizeDouble(lotSize, 2);
}

//+------------------------------------------------------------------+
//| Update Position Tracker Array                                   |
//+------------------------------------------------------------------+
void UpdatePositionTrackers()
{
   int posTotal = PositionsTotal();
   int trackerCount = 0;
   
   // Create temporary array for current positions
   PositionTracker tempTrackers[];
   ArrayResize(tempTrackers, posTotal);
   
   for(int i = 0; i < posTotal; i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0)
      {
         if(PositionGetString(POSITION_SYMBOL) == _Symbol && 
            PositionGetInteger(POSITION_MAGIC) == InpMagicNumber)
         {
            // Check if ticket already exists in trackers
            bool found = false;
            for(int j = 0; j < ArraySize(positionTrackers); j++)
            {
               if(positionTrackers[j].ticket == ticket)
               {
                  tempTrackers[trackerCount] = positionTrackers[j];
                  found = true;
                  break;
               }
            }
            
            // If not found, create new tracker
            if(!found)
            {
               tempTrackers[trackerCount].ticket = ticket;
               tempTrackers[trackerCount].breakEvenExecuted = false;
            }
            
            trackerCount++;
         }
      }
   }
   
   // Resize and copy
   ArrayResize(tempTrackers, trackerCount);
   ArrayResize(positionTrackers, trackerCount);
   
   for(int i = 0; i < trackerCount; i++)
   {
      positionTrackers[i] = tempTrackers[i];
   }
}

//+------------------------------------------------------------------+
//| Get Tracker Index by Ticket                                     |
//+------------------------------------------------------------------+
int GetTrackerIndex(ulong ticket)
{
   for(int i = 0; i < ArraySize(positionTrackers); i++)
   {
      if(positionTrackers[i].ticket == ticket)
         return i;
   }
   return -1;
}

//+------------------------------------------------------------------+
//| Manage Active Positions (FIXED VERSION)                         |
//+------------------------------------------------------------------+
void ManagePositions()
{
   if(InpRMMode == RM_DISABLE)
      return;
   
   // Update position trackers
   UpdatePositionTrackers();
   
   int posTotal = PositionsTotal();
   
   for(int i = 0; i < posTotal; i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;
         
      if(PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;
         
      if(PositionGetInteger(POSITION_MAGIC) != InpMagicNumber)
         continue;
      
      // Get tracker index
      int trackerIndex = GetTrackerIndex(ticket);
      if(trackerIndex < 0)
         continue;
      
      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double currentSL = PositionGetDouble(POSITION_SL);
      double currentPrice = PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY ? 
                           SymbolInfoDouble(_Symbol, SYMBOL_BID) : 
                           SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
      int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
      
      if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
      {
         ManageBuyPosition(ticket, openPrice, currentSL, currentPrice, point, digits, trackerIndex);
      }
      else if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL)
      {
         ManageSellPosition(ticket, openPrice, currentSL, currentPrice, point, digits, trackerIndex);
      }
   }
}

//+------------------------------------------------------------------+
//| Manage Buy Position (FIXED VERSION)                             |
//+------------------------------------------------------------------+
void ManageBuyPosition(ulong ticket, double openPrice, double currentSL, 
                       double currentPrice, double point, int digits, int trackerIndex)
{
   double profit = (currentPrice - openPrice) / point;
   double newSL = currentSL;
   bool modifySL = false;
   string modifyReason = "";
   
   // ===== MODE 1: BREAK EVEN ONLY =====
   if(InpRMMode == RM_BREAKEVEN)
   {
      if(!positionTrackers[trackerIndex].breakEvenExecuted && 
         profit >= InpBEActivationPoints)
      {
         double beSL = NormalizeDouble(openPrice + InpBEProfitPoints * point, digits);
         if(beSL > currentSL)
         {
            newSL = beSL;
            positionTrackers[trackerIndex].breakEvenExecuted = true;
            modifySL = true;
            modifyReason = "Break Even";
         }
      }
   }
   
   // ===== MODE 2: TRAILING STOP ONLY =====
   else if(InpRMMode == RM_TRAILING)
   {
      if(profit >= InpTrailingDistance)
      {
         double trailingSL = NormalizeDouble(currentPrice - InpTrailingStep * point, digits);
         if(trailingSL > currentSL)
         {
            newSL = trailingSL;
            modifySL = true;
            modifyReason = "Trailing Stop";
         }
      }
   }
   
   // ===== MODE 3: BREAK EVEN & TRAILING STOP (FIXED) =====
   else if(InpRMMode == RM_BE_AND_TSL)
   {
      // Step 1: Check Break Even first
      if(!positionTrackers[trackerIndex].breakEvenExecuted && 
         profit >= InpBEActivationPoints)
      {
         double beSL = NormalizeDouble(openPrice + InpBEProfitPoints * point, digits);
         if(beSL > currentSL)
         {
            newSL = beSL;
            positionTrackers[trackerIndex].breakEvenExecuted = true;
            modifySL = true;
            modifyReason = "Break Even (Step 1)";
         }
         else
         {
            // ถ้า beSL ไม่มากกว่า currentSL แต่ profit เกิน BE แล้ว
            // ให้ set flag เป็น true เพื่อให้ Trailing ทำงานได้
            positionTrackers[trackerIndex].breakEvenExecuted = true;
         }
      }
      
      // Step 2: Check Trailing Stop (after BE is executed or skipped)
      if(positionTrackers[trackerIndex].breakEvenExecuted && 
         profit >= InpTrailingDistance)
      {
         double trailingSL = NormalizeDouble(currentPrice - InpTrailingStep * point, digits);
         
         // Compare with current newSL (which might be BE SL)
         double compareSL = modifySL ? newSL : currentSL;
         
         if(trailingSL > compareSL)
         {
            newSL = trailingSL;
            modifySL = true;
            modifyReason = "Trailing Stop (Step 2)";
         }
      }
   }
   
   // Modify SL if needed
   if(modifySL && newSL != currentSL)
   {
      double tp = PositionGetDouble(POSITION_TP);
      if(trade.PositionModify(ticket, newSL, tp))
      {
         Print("✓ [BUY #", ticket, "] ", modifyReason, " - Profit: ", (int)profit, 
               " pts, Old SL: ", currentSL, " → New SL: ", newSL);
      }
      else
      {
         Print("✗ Failed to modify position #", ticket, " - Error: ", GetLastError());
      }
   }
}

//+------------------------------------------------------------------+
//| Manage Sell Position (FIXED VERSION)                            |
//+------------------------------------------------------------------+
void ManageSellPosition(ulong ticket, double openPrice, double currentSL, 
                        double currentPrice, double point, int digits, int trackerIndex)
{
   double profit = (openPrice - currentPrice) / point;
   double newSL = currentSL;
   bool modifySL = false;
   string modifyReason = "";
   
   // ===== MODE 1: BREAK EVEN ONLY =====
   if(InpRMMode == RM_BREAKEVEN)
   {
      if(!positionTrackers[trackerIndex].breakEvenExecuted && 
         profit >= InpBEActivationPoints)
      {
         double beSL = NormalizeDouble(openPrice - InpBEProfitPoints * point, digits);
         if(beSL < currentSL || currentSL == 0)
         {
            newSL = beSL;
            positionTrackers[trackerIndex].breakEvenExecuted = true;
            modifySL = true;
            modifyReason = "Break Even";
         }
      }
   }
   
   // ===== MODE 2: TRAILING STOP ONLY =====
   else if(InpRMMode == RM_TRAILING)
   {
      if(profit >= InpTrailingDistance)
      {
         double trailingSL = NormalizeDouble(currentPrice + InpTrailingStep * point, digits);
         if(trailingSL < currentSL || currentSL == 0)
         {
            newSL = trailingSL;
            modifySL = true;
            modifyReason = "Trailing Stop";
         }
      }
   }
   
   // ===== MODE 3: BREAK EVEN & TRAILING STOP (FIXED) =====
   else if(InpRMMode == RM_BE_AND_TSL)
   {
      // Step 1: Check Break Even first
      if(!positionTrackers[trackerIndex].breakEvenExecuted && 
         profit >= InpBEActivationPoints)
      {
         double beSL = NormalizeDouble(openPrice - InpBEProfitPoints * point, digits);
         if(beSL < currentSL || currentSL == 0)
         {
            newSL = beSL;
            positionTrackers[trackerIndex].breakEvenExecuted = true;
            modifySL = true;
            modifyReason = "Break Even (Step 1)";
         }
         else
         {
            // ถ้า beSL ไม่น้อยกว่า currentSL แต่ profit เกิน BE แล้ว
            // ให้ set flag เป็น true เพื่อให้ Trailing ทำงานได้
            positionTrackers[trackerIndex].breakEvenExecuted = true;
         }
      }
      
      // Step 2: Check Trailing Stop (after BE is executed or skipped)
      if(positionTrackers[trackerIndex].breakEvenExecuted && 
         profit >= InpTrailingDistance)
      {
         double trailingSL = NormalizeDouble(currentPrice + InpTrailingStep * point, digits);
         
         // Compare with current newSL (which might be BE SL)
         double compareSL = modifySL ? newSL : currentSL;
         
         if(trailingSL < compareSL || compareSL == 0)
         {
            newSL = trailingSL;
            modifySL = true;
            modifyReason = "Trailing Stop (Step 2)";
         }
      }
   }
   
   // Modify SL if needed
   if(modifySL && newSL != currentSL)
   {
      double tp = PositionGetDouble(POSITION_TP);
      if(trade.PositionModify(ticket, newSL, tp))
      {
         Print("✓ [SELL #", ticket, "] ", modifyReason, " - Profit: ", (int)profit, 
               " pts, Old SL: ", currentSL, " → New SL: ", newSL);
      }
      else
      {
         Print("✗ Failed to modify position #", ticket, " - Error: ", GetLastError());
      }
   }
}

//+------------------------------------------------------------------+
//| Check if within trading hours (Thai Time)                       |
//+------------------------------------------------------------------+
bool IsWithinTradingHours()
{
   MqlDateTime timeNow;
   TimeToStruct(TimeCurrent(), timeNow);
   
   int currentMinutes = timeNow.hour * 60 + timeNow.min;
   
   // Parse start and end time
   string startParts[];
   string endParts[];
   
   if(StringSplit(InpStartTime, ':', startParts) != 2 || 
      StringSplit(InpEndTime, ':', endParts) != 2)
   {
      Print("⚠ Warning: Invalid time format");
      return false;
   }
   
   int startMinutes = (int)StringToInteger(startParts[0]) * 60 + 
                      (int)StringToInteger(startParts[1]);
   int endMinutes = (int)StringToInteger(endParts[0]) * 60 + 
                    (int)StringToInteger(endParts[1]);
   
   // Validate time ranges
   if(startMinutes < 0 || startMinutes >= 1440 || 
      endMinutes < 0 || endMinutes >= 1440)
   {
      Print("⚠ Warning: Time out of range (0-23:59)");
      return false;
   }
   
   // Handle overnight trading
   if(endMinutes < startMinutes)
   {
      // Trading period crosses midnight
      return (currentMinutes >= startMinutes || currentMinutes <= endMinutes);
   }
   else
   {
      // Normal trading period within same day
      return (currentMinutes >= startMinutes && currentMinutes <= endMinutes);
   }
}

//+------------------------------------------------------------------+
