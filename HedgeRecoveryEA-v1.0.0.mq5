//+------------------------------------------------------------------+
//|                                           HedgeRecoveryEA.mq5    |
//|                                  Hedge and Recovery EA           |
//|                                                                  |
//+------------------------------------------------------------------+
#property copyright "Hedge Recovery EA"
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>

// Input parameters
input double RiskPercent = 2.0;              // เปอร์เซ็นต์ของ Margin ที่ใช้ต่อออเดอร์
input double TargetProfit = 10.0;           // กำไรเป้าหมาย (USD)
input int MagicNumber = 123456;             // Magic Number
input double AddPositionDistance = 50.0;    // ระยะห่างเพิ่มออเดอร์ (points)
input int MaxPositions = 10;                // จำนวนออเดอร์สูงสุดต่อทิศทาง

// Global variables
CTrade trade;
bool hasInitialPositions = false;
double initialBuyPrice = 0;
double initialSellPrice = 0;
double lastBuyPrice = 0;
double lastSellPrice = 0;
int buyPositions = 0;
int sellPositions = 0;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(10);
   trade.SetTypeFilling(ORDER_FILLING_FOK);
   
   Print("Hedge Recovery EA initialized");
   Print("Risk Percent: ", RiskPercent, "%");
   Print("Target Profit: $", TargetProfit);
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   Print("EA stopped");
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // ตรวจสอบกำไรรวม
   double totalProfit = CalculateTotalProfit();
   
   if(totalProfit >= TargetProfit)
   {
      Print("Target profit reached: $", totalProfit);
      CloseAllPositions();
      hasInitialPositions = false;
      return;
   }
   
   // เปิดออเดอร์เริ่มต้นถ้ายังไม่มี
   if(!hasInitialPositions)
   {
      if(CountPositions() == 0)
      {
         OpenInitialPositions();
      }
      return;
   }
   
   // ตรวจสอบและจัดการออเดอร์
   ManagePositions();
}

//+------------------------------------------------------------------+
//| คำนวณ Lot Size จาก % ของ Margin                                  |
//+------------------------------------------------------------------+
double CalculateLotSize()
{
   double accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskAmount = accountBalance * (RiskPercent / 100.0);
   
   // คำนวณ margin ที่ต้องการ
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   
   // คำนวณ lot size พื้นฐาน
   double marginRequired = 0;
   if(!OrderCalcMargin(ORDER_TYPE_BUY, _Symbol, minLot, SymbolInfoDouble(_Symbol, SYMBOL_ASK), marginRequired))
   {
      Print("Error calculating margin");
      return minLot;
   }
   
   double lotSize = (riskAmount / marginRequired) * minLot;
   
   // ปรับให้ตรงกับ lot step
   lotSize = MathFloor(lotSize / lotStep) * lotStep;
   
   // จำกัดค่า lot size
   if(lotSize < minLot) lotSize = minLot;
   if(lotSize > maxLot) lotSize = maxLot;
   
   return NormalizeDouble(lotSize, 2);
}

//+------------------------------------------------------------------+
//| เปิดออเดอร์เริ่มต้น (Buy และ Sell)                              |
//+------------------------------------------------------------------+
void OpenInitialPositions()
{
   double lotSize = CalculateLotSize();
   
   if(lotSize <= 0)
   {
      Print("Invalid lot size calculated");
      return;
   }
   
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   
   // เปิด Buy
   if(trade.Buy(lotSize, _Symbol, ask, 0, 0, "Initial Buy"))
   {
      initialBuyPrice = ask;
      lastBuyPrice = ask;
      buyPositions = 1;
      Print("Opened initial BUY position at ", ask, " with lot size ", lotSize);
   }
   else
   {
      Print("Error opening BUY position: ", GetLastError());
      return;
   }
   
   // เปิด Sell
   if(trade.Sell(lotSize, _Symbol, bid, 0, 0, "Initial Sell"))
   {
      initialSellPrice = bid;
      lastSellPrice = bid;
      sellPositions = 1;
      Print("Opened initial SELL position at ", bid, " with lot size ", lotSize);
      hasInitialPositions = true;
   }
   else
   {
      Print("Error opening SELL position: ", GetLastError());
   }
}

//+------------------------------------------------------------------+
//| จัดการออเดอร์                                                    |
//+------------------------------------------------------------------+
void ManagePositions()
{
   double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   
   // ตรวจสอบทิศทางที่กำไร
   double buyProfit = CalculateProfitByType(POSITION_TYPE_BUY);
   double sellProfit = CalculateProfitByType(POSITION_TYPE_SELL);
   
   // ถ้า Buy กำไร ปิด Sell และเพิ่ม Buy
   if(buyProfit > 0 && sellProfit < 0)
   {
      if(CountPositionsByType(POSITION_TYPE_SELL) > 0)
      {
         ClosePositionsByType(POSITION_TYPE_SELL);
         Print("Closed losing SELL positions");
      }
      
      // เพิ่ม Buy ถ้าราคาขยับไปตาม AddPositionDistance
      if(buyPositions < MaxPositions)
      {
         double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         if(ask >= lastBuyPrice + (AddPositionDistance * point))
         {
            double lotSize = CalculateLotSize();
            if(trade.Buy(lotSize, _Symbol, ask, 0, 0, "Add Buy"))
            {
               lastBuyPrice = ask;
               buyPositions++;
               Print("Added BUY position #", buyPositions, " at ", ask);
            }
         }
      }
   }
   // ถ้า Sell กำไร ปิด Buy และเพิ่ม Sell
   else if(sellProfit > 0 && buyProfit < 0)
   {
      if(CountPositionsByType(POSITION_TYPE_BUY) > 0)
      {
         ClosePositionsByType(POSITION_TYPE_BUY);
         Print("Closed losing BUY positions");
      }
      
      // เพิ่ม Sell ถ้าราคาขยับไปตาม AddPositionDistance
      if(sellPositions < MaxPositions)
      {
         double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         if(bid <= lastSellPrice - (AddPositionDistance * point))
         {
            double lotSize = CalculateLotSize();
            if(trade.Sell(lotSize, _Symbol, bid, 0, 0, "Add Sell"))
            {
               lastSellPrice = bid;
               sellPositions++;
               Print("Added SELL position #", sellPositions, " at ", bid);
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| คำนวณกำไรรวมทั้งหมด                                              |
//+------------------------------------------------------------------+
double CalculateTotalProfit()
{
   double totalProfit = 0;
   
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0)
      {
         if(PositionGetString(POSITION_SYMBOL) == _Symbol && 
            PositionGetInteger(POSITION_MAGIC) == MagicNumber)
         {
            totalProfit += PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
         }
      }
   }
   
   return totalProfit;
}

//+------------------------------------------------------------------+
//| คำนวณกำไรตามประเภทออเดอร์                                        |
//+------------------------------------------------------------------+
double CalculateProfitByType(ENUM_POSITION_TYPE type)
{
   double profit = 0;
   
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0)
      {
         if(PositionGetString(POSITION_SYMBOL) == _Symbol && 
            PositionGetInteger(POSITION_MAGIC) == MagicNumber &&
            PositionGetInteger(POSITION_TYPE) == type)
         {
            profit += PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
         }
      }
   }
   
   return profit;
}

//+------------------------------------------------------------------+
//| นับจำนวนออเดอร์ทั้งหมด                                           |
//+------------------------------------------------------------------+
int CountPositions()
{
   int count = 0;
   
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0)
      {
         if(PositionGetString(POSITION_SYMBOL) == _Symbol && 
            PositionGetInteger(POSITION_MAGIC) == MagicNumber)
         {
            count++;
         }
      }
   }
   
   return count;
}

//+------------------------------------------------------------------+
//| นับจำนวนออเดอร์ตามประเภท                                         |
//+------------------------------------------------------------------+
int CountPositionsByType(ENUM_POSITION_TYPE type)
{
   int count = 0;
   
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0)
      {
         if(PositionGetString(POSITION_SYMBOL) == _Symbol && 
            PositionGetInteger(POSITION_MAGIC) == MagicNumber &&
            PositionGetInteger(POSITION_TYPE) == type)
         {
            count++;
         }
      }
   }
   
   return count;
}

//+------------------------------------------------------------------+
//| ปิดออเดอร์ตามประเภท                                             |
//+------------------------------------------------------------------+
void ClosePositionsByType(ENUM_POSITION_TYPE type)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0)
      {
         if(PositionGetString(POSITION_SYMBOL) == _Symbol && 
            PositionGetInteger(POSITION_MAGIC) == MagicNumber &&
            PositionGetInteger(POSITION_TYPE) == type)
         {
            trade.PositionClose(ticket);
         }
      }
   }
   
   // รีเซ็ตตัวแปร
   if(type == POSITION_TYPE_BUY)
   {
      buyPositions = 0;
      lastBuyPrice = 0;
   }
   else
   {
      sellPositions = 0;
      lastSellPrice = 0;
   }
}

//+------------------------------------------------------------------+
//| ปิดออเดอร์ทั้งหมด                                               |
//+------------------------------------------------------------------+
void CloseAllPositions()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0)
      {
         if(PositionGetString(POSITION_SYMBOL) == _Symbol && 
            PositionGetInteger(POSITION_MAGIC) == MagicNumber)
         {
            trade.PositionClose(ticket);
         }
      }
   }
   
   // รีเซ็ตตัวแปรทั้งหมด
   buyPositions = 0;
   sellPositions = 0;
   lastBuyPrice = 0;
   lastSellPrice = 0;
   initialBuyPrice = 0;
   initialSellPrice = 0;
   hasInitialPositions = false;
}
//+------------------------------------------------------------------+
