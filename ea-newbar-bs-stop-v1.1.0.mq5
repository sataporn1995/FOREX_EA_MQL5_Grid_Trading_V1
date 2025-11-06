//+------------------------------------------------------------------+
//|                                              ea-newbar-bs-stop-v1.1.0.mq5 |
//|                                  Pending Order Management EA    |
//|                         Modified: Check Position Count Before Opening Orders |
//+------------------------------------------------------------------+
#property copyright "PendingOrderEA"
#property version   "1.10"
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
   RM_BOTH              // Break Even & Trailing Stop
};
input RiskManagementMode InpRMMode = RM_BREAKEVEN;              // Risk Management Mode

input group "=== Break Even Settings ==="
input int InpBEActivationPoints = 300;                           // Break Even Activation (points)
input int InpBEProfitPoints = 100;                                // Break Even Profit Lock (points)

input group "=== Trailing Stop Settings ==="
input int InpTrailingDistance = 300;                              // Trailing Distance (points)
input int InpTrailingStep = 200;                                  // Trailing Step (points)

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
input string InpStartTime = "06:00";                             // Start Time (HH:MM)
input string InpEndTime = "04:30";                               // End Time (HH:MM)

input group "=== EA Settings ==="
input int InpMagicNumber = 2025110601;                               // Magic Number
input string InpComment = "New Pending B/S Stop EA";             // Order Comment
input int InpMaxSpread = 200;                                    // Max Spread (points)

// Global Variables
CTrade trade;
datetime lastBarTime = 0;
bool breakEvenExecuted[];
int totalPositions = 0;
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
   
   Print("EA Initialized Successfully");
   Print("Timeframe: ", EnumToString(InpPeriod));
   Print("Order Mode: ", EnumToString(InpOrderMode));
   Print("Risk Management Mode: ", EnumToString(InpRMMode));
   Print("Lot Mode: ", EnumToString(InpLotMode));
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   Print("EA Deinitialized");
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // Check for new bar
   datetime currentBarTime = iTime(_Symbol, InpPeriod, 0);
   
   if(currentBarTime != lastBarTime)
   {
      lastBarTime = currentBarTime;
      
      // Check trading time
      if(IsWithinTradingHours())
      {
         OnNewBar();
      }
   }
   
   /*
   if (IsNewBar(InpPeriod)) {
      if(IsWithinTradingHours()) OnNewBar();
   }
   */
   
   // Manage active positions
   ManagePositions();
}

bool IsMySymbol(const string sym){ return (sym==_Symbol); }

bool IsNewBar(ENUM_TIMEFRAMES tf)
{
   MqlRates r[];
   if(CopyRates(_Symbol, tf, 0, 2, r) != 2) return false;
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
   // 1. Delete all pending orders
   DeleteAllPendingOrders();
   
   // 2. Place new pending orders
   PlacePendingOrders();
}

//+------------------------------------------------------------------+
//| Check if current spread is acceptable                            |
//+------------------------------------------------------------------+
bool CheckSpread()
{
   long spread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   
   if(spread > InpMaxSpread)
   {
      Print("Spread too high: ", spread, " points (Max: ", InpMaxSpread, " points)");
      return false;
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| Delete All Pending Orders for current symbol                    |
//+------------------------------------------------------------------+
void DeleteAllPendingOrders()
{
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket > 0)
      {
         if(OrderGetString(ORDER_SYMBOL) == _Symbol && 
            OrderGetInteger(ORDER_MAGIC) == InpMagicNumber)
         {
            trade.OrderDelete(ticket);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Count Position Types                                            |
//+------------------------------------------------------------------+
void CountPositionTypes(int &buyCount, int &sellCount)
{
   buyCount = 0;
   sellCount = 0;
   
   int posTotal = PositionsTotal();
   
   for(int i = 0; i < posTotal; i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0)
      {
         if(PositionGetString(POSITION_SYMBOL) == _Symbol && 
            PositionGetInteger(POSITION_MAGIC) == InpMagicNumber)
         {
            if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
               buyCount++;
            else if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL)
               sellCount++;
         }
      }
   }
}

int CountPositionsByType(ENUM_POSITION_TYPE type)
{
  int total = PositionsTotal();
  int count = 0;
  for(int i=0; i<total; i++){
    ulong ticket = PositionGetTicket(i);
    if(ticket==0) continue;
    if(!PositionSelectByTicket(ticket)) continue;
    if(!IsMySymbol((string)PositionGetString(POSITION_SYMBOL))) continue;
    
    if(/*!IncludeForeignPositions && */(long)PositionGetInteger(POSITION_MAGIC)!=InpMagicNumber) 
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
   if (!CheckSpread()) {
      Print("Place order cancelled due to high spread");
      return;
   }
   
   // Count existing positions by type
   //int buyCount = 0, sellCount = 0;
   //CountPositionTypes(buyCount, sellCount);
   
   int buyCount = CountPositionsByType(POSITION_TYPE_BUY);
   int sellCount = CountPositionsByType(POSITION_TYPE_SELL);
   
   double openPrice = iOpen(_Symbol, InpPeriod, 0);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   
   double pendingDistance = InpPendingDistance * point;
   double slDistance = InpStopLoss * point;
   double tpDistance = slDistance * InpTPMultiplier;
   
   // Calculate lot size
   double lotSize = CalculateLotSize(slDistance);
   
   if(lotSize < SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN))
   {
      Print("Calculated lot size too small. Order not placed.");
      return;
   }
   
   // Place Buy Stop Order (only if no Buy position exists)
   if((InpOrderMode == ORDER_BUY_ONLY || InpOrderMode == ORDER_BOTH) && buyCount == 0)
   {
      double buyPrice = NormalizeDouble(openPrice + pendingDistance, digits);
      double buySL = NormalizeDouble(buyPrice - slDistance, digits);
      double buyTP = NormalizeDouble(buyPrice + tpDistance, digits);
      
      trade.BuyStop(lotSize, buyPrice, _Symbol, buySL, buyTP, 
                    ORDER_TIME_GTC, 0, InpComment);
   }
   else if((InpOrderMode == ORDER_BUY_ONLY || InpOrderMode == ORDER_BOTH) && buyCount > 0)
   {
      Print("Buy Stop Order not placed - Already have ", buyCount, " Buy position(s)");
   }
   
   // Place Sell Stop Order (only if no Sell position exists)
   if((InpOrderMode == ORDER_SELL_ONLY || InpOrderMode == ORDER_BOTH) && sellCount == 0)
   {
      double sellPrice = NormalizeDouble(openPrice - pendingDistance, digits);
      double sellSL = NormalizeDouble(sellPrice + slDistance, digits);
      double sellTP = NormalizeDouble(sellPrice - tpDistance, digits);
      
      trade.SellStop(lotSize, sellPrice, _Symbol, sellSL, sellTP, 
                     ORDER_TIME_GTC, 0, InpComment);
   }
   else if((InpOrderMode == ORDER_SELL_ONLY || InpOrderMode == ORDER_BOTH) && sellCount > 0)
   {
      Print("Sell Stop Order not placed - Already have ", sellCount, " Sell position(s)");
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
//| Manage Active Positions                                         |
//+------------------------------------------------------------------+
void ManagePositions()
{
   if(InpRMMode == RM_DISABLE)
      return;
   
   // Resize array if needed
   int posTotal = PositionsTotal();
   if(ArraySize(breakEvenExecuted) != posTotal)
      ArrayResize(breakEvenExecuted, posTotal);
   
   for(int i = posTotal - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0)
      {
         if(PositionGetString(POSITION_SYMBOL) == _Symbol && 
            PositionGetInteger(POSITION_MAGIC) == InpMagicNumber)
         {
            double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
            double currentSL = PositionGetDouble(POSITION_SL);
            double currentPrice = PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY ? 
                                 SymbolInfoDouble(_Symbol, SYMBOL_BID) : 
                                 SymbolInfoDouble(_Symbol, SYMBOL_ASK);
            double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
            int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
            
            if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
            {
               ManageBuyPosition(ticket, openPrice, currentSL, currentPrice, point, digits, i);
            }
            else if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL)
            {
               ManageSellPosition(ticket, openPrice, currentSL, currentPrice, point, digits, i);
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Manage Buy Position                                             |
//+------------------------------------------------------------------+
void ManageBuyPosition(ulong ticket, double openPrice, double currentSL, 
                       double currentPrice, double point, int digits, int index)
{
   double profit = (currentPrice - openPrice) / point;
   double newSL = currentSL;
   bool modifySL = false;
   
   // Break Even Logic
   if((InpRMMode == RM_BREAKEVEN || InpRMMode == RM_BOTH) && 
      !breakEvenExecuted[index])
   {
      if(profit >= InpBEActivationPoints)
      {
         newSL = NormalizeDouble(openPrice + InpBEProfitPoints * point, digits);
         if(newSL > currentSL)
         {
            breakEvenExecuted[index] = true;
            modifySL = true;
         }
      }
   }
   
   // Trailing Stop Logic
   if((InpRMMode == RM_TRAILING || 
      (InpRMMode == RM_BOTH && breakEvenExecuted[index])))
   {
      double trailingSL = NormalizeDouble(currentPrice - InpTrailingStep * point, digits);
      
      if(profit >= InpTrailingDistance && trailingSL > currentSL)
      {
         newSL = trailingSL;
         modifySL = true;
      }
   }
   
   // Modify SL if needed
   if(modifySL && newSL != currentSL)
   {
      double tp = PositionGetDouble(POSITION_TP);
      trade.PositionModify(ticket, newSL, tp);
   }
}

//+------------------------------------------------------------------+
//| Manage Sell Position                                            |
//+------------------------------------------------------------------+
void ManageSellPosition(ulong ticket, double openPrice, double currentSL, 
                        double currentPrice, double point, int digits, int index)
{
   double profit = (openPrice - currentPrice) / point;
   double newSL = currentSL;
   bool modifySL = false;
   
   // Break Even Logic
   if((InpRMMode == RM_BREAKEVEN || InpRMMode == RM_BOTH) && 
      !breakEvenExecuted[index])
   {
      if(profit >= InpBEActivationPoints)
      {
         newSL = NormalizeDouble(openPrice - InpBEProfitPoints * point, digits);
         if(newSL < currentSL || currentSL == 0)
         {
            breakEvenExecuted[index] = true;
            modifySL = true;
         }
      }
   }
   
   // Trailing Stop Logic
   if((InpRMMode == RM_TRAILING || 
      (InpRMMode == RM_BOTH && breakEvenExecuted[index])))
   {
      double trailingSL = NormalizeDouble(currentPrice + InpTrailingStep * point, digits);
      
      if(profit >= InpTrailingDistance && (trailingSL < currentSL || currentSL == 0))
      {
         newSL = trailingSL;
         modifySL = true;
      }
   }
   
   // Modify SL if needed
   if(modifySL && newSL != currentSL)
   {
      double tp = PositionGetDouble(POSITION_TP);
      trade.PositionModify(ticket, newSL, tp);
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
   StringSplit(InpStartTime, ':', startParts);
   StringSplit(InpEndTime, ':', endParts);
   
   int startMinutes = (int)StringToInteger(startParts[0]) * 60 + 
                      (int)StringToInteger(startParts[1]);
   int endMinutes = (int)StringToInteger(endParts[0]) * 60 + 
                    (int)StringToInteger(endParts[1]);
   
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
