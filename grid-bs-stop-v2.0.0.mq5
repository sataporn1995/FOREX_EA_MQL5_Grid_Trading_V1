//+------------------------------------------------------------------+
//|                                            GridStopTrading.mq5 |
//|                                  Copyright 2025, Pong Trading   |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, Pong Trading"
#property link      ""
#property version   "1.00"

#include <Trade\Trade.mqh>

// Input Parameters
input group "=== Grid Settings ==="
input double GridStep = 5000;              // Grid Step (จุด)
input double PlacementDistance = 500;      // ระยะวาง Pending Order จากราคาปัจจุบัน (จุด)
input double MaxDistance = 800;            // ระยะสูงสุดก่อนวาง Order ใหม่ (จุด)

input group "=== Trading Mode ==="
enum ENUM_GRID_MODE
{
   MODE_BUY_STOP_ONLY,    // Buy Stop Only
   MODE_SELL_STOP_ONLY    // Sell Stop Only
};
input ENUM_GRID_MODE GridMode = MODE_BUY_STOP_ONLY;  // โหมดการเทรด

input group "=== Close Mode ==="
enum ENUM_CLOSE_MODE
{
   CLOSE_TP,              // TP Mode
   CLOSE_ALL              // Close All Mode
};
input ENUM_CLOSE_MODE CloseMode = CLOSE_TP;          // โหมดการปิด Order
input double TakeProfit = 5000;            // Take Profit (จุด) - สำหรับ TP Mode
input double CloseAllProfit = 3000;        // Close All Profit (จุด) - สำหรับ Close All Mode

input group "=== Order Settings ==="
input double LotSize = 0.01;               // Lot Size
input int MagicNumber = 123456;            // Magic Number
input string TradeComment = "GridStop";    // Order Comment

// Global Variables
CTrade trade;
double point_value;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(10);
   
   // คำนวณค่า point
   if(_Digits == 5 || _Digits == 3)
      point_value = _Point * 10;
   else
      point_value = _Point;
   
   Print("Grid Stop Trading EA เริ่มทำงาน");
   Print("โหมด: ", EnumToString(GridMode));
   Print("โหมดปิด: ", EnumToString(CloseMode));
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   Print("Grid Stop Trading EA หยุดทำงาน");
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // ตรวจสอบและจัดการ Close All Mode
   if(CloseMode == CLOSE_ALL)
   {
      CheckAndCloseAll();
   }
   
   // จัดการ Pending Orders ตามโหมด
   if(GridMode == MODE_BUY_STOP_ONLY)
   {
      ManageBuyStopOrders();
   }
   else if(GridMode == MODE_SELL_STOP_ONLY)
   {
      ManageSellStopOrders();
   }
}

//+------------------------------------------------------------------+
//| จัดการ Buy Stop Orders                                           |
//+------------------------------------------------------------------+
void ManageBuyStopOrders()
{
   int pendingBuyStop = CountPendingOrders(ORDER_TYPE_BUY_STOP);
   double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   
   if(pendingBuyStop == 0)
   {
      // หาตำแหน่ง Position Buy ล่างสุด
      double lowestBuyPrice = GetLowestBuyPosition();
      double orderPrice;
      
      if(lowestBuyPrice == 0) // ไม่มี Position Buy
      {
         orderPrice = currentPrice + (PlacementDistance * point_value);
      }
      else
      {
         // วาง Order ห่างจาก Position Buy ล่างสุด ลบ Grid Step
         orderPrice = lowestBuyPrice - (GridStep * point_value);
         
         // ตรวจสอบว่าไม่วาง Order ต่ำกว่า current price + PlacementDistance
         double minPrice = currentPrice + (PlacementDistance * point_value);
         if(orderPrice < minPrice)
            orderPrice = minPrice;
      }
      
      // วาง Buy Stop Order
      PlaceBuyStopOrder(orderPrice);
   }
   else
   {
      // ตรวจสอบ Pending Buy Stop Order ที่มีอยู่
      CheckAndUpdateBuyStopOrder(currentPrice);
   }
}

//+------------------------------------------------------------------+
//| จัดการ Sell Stop Orders                                          |
//+------------------------------------------------------------------+
void ManageSellStopOrders()
{
   int pendingSellStop = CountPendingOrders(ORDER_TYPE_SELL_STOP);
   double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   
   if(pendingSellStop == 0)
   {
      // หาตำแหน่ง Position Sell บนสุด
      double highestSellPrice = GetHighestSellPosition();
      double orderPrice;
      
      if(highestSellPrice == 0) // ไม่มี Position Sell
      {
         orderPrice = currentPrice - (PlacementDistance * point_value);
      }
      else
      {
         // วาง Order ห่างจาก Position Sell บนสุด บวก Grid Step
         orderPrice = highestSellPrice + (GridStep * point_value);
         
         // ตรวจสอบว่าไม่วาง Order สูงกว่า current price - PlacementDistance
         double maxPrice = currentPrice - (PlacementDistance * point_value);
         if(orderPrice > maxPrice)
            orderPrice = maxPrice;
      }
      
      // วาง Sell Stop Order
      PlaceSellStopOrder(orderPrice);
   }
   else
   {
      // ตรวจสอบ Pending Sell Stop Order ที่มีอยู่
      CheckAndUpdateSellStopOrder(currentPrice);
   }
}

//+------------------------------------------------------------------+
//| นับจำนวน Pending Orders                                          |
//+------------------------------------------------------------------+
int CountPendingOrders(ENUM_ORDER_TYPE orderType)
{
   int count = 0;
   int total = OrdersTotal();
   
   for(int i = 0; i < total; i++)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket > 0)
      {
         if(OrderGetString(ORDER_SYMBOL) == _Symbol &&
            OrderGetInteger(ORDER_MAGIC) == MagicNumber &&
            OrderGetInteger(ORDER_TYPE) == orderType)
         {
            count++;
         }
      }
   }
   
   return count;
}

//+------------------------------------------------------------------+
//| หาราคา Position Buy ล่างสุด                                     |
//+------------------------------------------------------------------+
double GetLowestBuyPosition()
{
   double lowestPrice = 0;
   int total = PositionsTotal();
   
   for(int i = 0; i < total; i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0)
      {
         if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
            PositionGetInteger(POSITION_MAGIC) == MagicNumber &&
            PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
         {
            double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
            if(lowestPrice == 0 || openPrice < lowestPrice)
               lowestPrice = openPrice;
         }
      }
   }
   
   return lowestPrice;
}

//+------------------------------------------------------------------+
//| หาราคา Position Sell บนสุด                                      |
//+------------------------------------------------------------------+
double GetHighestSellPosition()
{
   double highestPrice = 0;
   int total = PositionsTotal();
   
   for(int i = 0; i < total; i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0)
      {
         if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
            PositionGetInteger(POSITION_MAGIC) == MagicNumber &&
            PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL)
         {
            double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
            if(openPrice > highestPrice)
               highestPrice = openPrice;
         }
      }
   }
   
   return highestPrice;
}

//+------------------------------------------------------------------+
//| วาง Buy Stop Order                                               |
//+------------------------------------------------------------------+
void PlaceBuyStopOrder(double price)
{
   double tp = 0;
   if(CloseMode == CLOSE_TP)
      tp = price + (TakeProfit * point_value);
   
   price = NormalizeDouble(price, _Digits);
   if(tp > 0)
      tp = NormalizeDouble(tp, _Digits);
   
   if(trade.BuyStop(LotSize, price, _Symbol, 0, tp, ORDER_TIME_GTC, 0, TradeComment))
   {
      Print("วาง Buy Stop Order สำเร็จ ที่ราคา: ", price);
   }
   else
   {
      Print("วาง Buy Stop Order ไม่สำเร็จ: ", GetLastError());
   }
}

//+------------------------------------------------------------------+
//| วาง Sell Stop Order                                              |
//+------------------------------------------------------------------+
void PlaceSellStopOrder(double price)
{
   double tp = 0;
   if(CloseMode == CLOSE_TP)
      tp = price - (TakeProfit * point_value);
   
   price = NormalizeDouble(price, _Digits);
   if(tp > 0)
      tp = NormalizeDouble(tp, _Digits);
   
   if(trade.SellStop(LotSize, price, _Symbol, 0, tp, ORDER_TIME_GTC, 0, TradeComment))
   {
      Print("วาง Sell Stop Order สำเร็จ ที่ราคา: ", price);
   }
   else
   {
      Print("วาง Sell Stop Order ไม่สำเร็จ: ", GetLastError());
   }
}

//+------------------------------------------------------------------+
//| ตรวจสอบและอัพเดท Buy Stop Order                                 |
//+------------------------------------------------------------------+
void CheckAndUpdateBuyStopOrder(double currentPrice)
{
   int total = OrdersTotal();
   
   for(int i = total - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket > 0)
      {
         if(OrderGetString(ORDER_SYMBOL) == _Symbol &&
            OrderGetInteger(ORDER_MAGIC) == MagicNumber &&
            OrderGetInteger(ORDER_TYPE) == ORDER_TYPE_BUY_STOP)
         {
            double orderPrice = OrderGetDouble(ORDER_PRICE_OPEN);
            double distance = (orderPrice - currentPrice) / point_value;
            
            // ถ้าห่างจากราคาปัจจุบันมากกว่าหรือเท่ากับ MaxDistance และไม่เลื่อนขึ้น
            if(distance >= MaxDistance)
            {
               // ลบ Order เก่า
               if(trade.OrderDelete(ticket))
               {
                  Print("ลบ Buy Stop Order เก่าที่ห่างเกินไป: ", ticket);
                  
                  // วาง Order ใหม่
                  double lowestBuyPrice = GetLowestBuyPosition();
                  double newOrderPrice;
                  
                  if(lowestBuyPrice == 0)
                  {
                     newOrderPrice = currentPrice + (PlacementDistance * point_value);
                  }
                  else
                  {
                     newOrderPrice = lowestBuyPrice - (GridStep * point_value);
                     double minPrice = currentPrice + (PlacementDistance * point_value);
                     
                     // ไม่วาง Order สูงกว่า Position Buy ล่างสุด
                     if(newOrderPrice > lowestBuyPrice)
                        return;
                     
                     // ไม่วาง Order ต่ำกว่า minPrice
                     if(newOrderPrice < minPrice)
                        newOrderPrice = minPrice;
                  }
                  
                  PlaceBuyStopOrder(newOrderPrice);
               }
            }
            break;
         }
      }
   }
}

//+------------------------------------------------------------------+
//| ตรวจสอบและอัพเดท Sell Stop Order                                |
//+------------------------------------------------------------------+
void CheckAndUpdateSellStopOrder(double currentPrice)
{
   int total = OrdersTotal();
   
   for(int i = total - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket > 0)
      {
         if(OrderGetString(ORDER_SYMBOL) == _Symbol &&
            OrderGetInteger(ORDER_MAGIC) == MagicNumber &&
            OrderGetInteger(ORDER_TYPE) == ORDER_TYPE_SELL_STOP)
         {
            double orderPrice = OrderGetDouble(ORDER_PRICE_OPEN);
            double distance = (currentPrice - orderPrice) / point_value;
            
            // ถ้าห่างจากราคาปัจจุบันน้อยกว่าหรือเท่ากับ MaxDistance และไม่เลื่อนลง
            if(distance >= MaxDistance)
            {
               // ลบ Order เก่า
               if(trade.OrderDelete(ticket))
               {
                  Print("ลบ Sell Stop Order เก่าที่ห่างเกินไป: ", ticket);
                  
                  // วาง Order ใหม่
                  double highestSellPrice = GetHighestSellPosition();
                  double newOrderPrice;
                  
                  if(highestSellPrice == 0)
                  {
                     newOrderPrice = currentPrice - (PlacementDistance * point_value);
                  }
                  else
                  {
                     newOrderPrice = highestSellPrice + (GridStep * point_value);
                     double maxPrice = currentPrice - (PlacementDistance * point_value);
                     
                     // ไม่วาง Order ต่ำกว่า Position Sell บนสุด
                     if(newOrderPrice < highestSellPrice)
                        return;
                     
                     // ไม่วาง Order สูงกว่า maxPrice
                     if(newOrderPrice > maxPrice)
                        newOrderPrice = maxPrice;
                  }
                  
                  PlaceSellStopOrder(newOrderPrice);
               }
            }
            break;
         }
      }
   }
}

//+------------------------------------------------------------------+
//| ตรวจสอบและปิด Order ทั้งหมดตามโหมด Close All                    |
//+------------------------------------------------------------------+
void CheckAndCloseAll()
{
   // ตรวจสอบ Buy Positions
   double buyProfit = CalculateAverageProfitPoints(POSITION_TYPE_BUY);
   if(buyProfit >= CloseAllProfit)
   {
      CloseAllPositions(POSITION_TYPE_BUY);
   }
   
   // ตรวจสอบ Sell Positions
   double sellProfit = CalculateAverageProfitPoints(POSITION_TYPE_SELL);
   if(sellProfit >= CloseAllProfit)
   {
      CloseAllPositions(POSITION_TYPE_SELL);
   }
}

//+------------------------------------------------------------------+
//| คำนวณกำไรเฉลี่ยเป็นจุด                                          |
//+------------------------------------------------------------------+
double CalculateAverageProfitPoints(ENUM_POSITION_TYPE posType)
{
   double totalPrice = 0;
   double totalVolume = 0;
   double currentPrice = (posType == POSITION_TYPE_BUY) ? 
                         SymbolInfoDouble(_Symbol, SYMBOL_BID) : 
                         SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   
   int total = PositionsTotal();
   
   for(int i = 0; i < total; i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0)
      {
         if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
            PositionGetInteger(POSITION_MAGIC) == MagicNumber &&
            PositionGetInteger(POSITION_TYPE) == posType)
         {
            double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
            double volume = PositionGetDouble(POSITION_VOLUME);
            
            totalPrice += openPrice * volume;
            totalVolume += volume;
         }
      }
   }
   
   if(totalVolume == 0)
      return 0;
   
   double averagePrice = totalPrice / totalVolume;
   double profitPoints = 0;
   
   if(posType == POSITION_TYPE_BUY)
      profitPoints = (currentPrice - averagePrice) / point_value;
   else
      profitPoints = (averagePrice - currentPrice) / point_value;
   
   return profitPoints;
}

//+------------------------------------------------------------------+
//| ปิด Position ทั้งหมดตามประเภท                                   |
//+------------------------------------------------------------------+
void CloseAllPositions(ENUM_POSITION_TYPE posType)
{
   int total = PositionsTotal();
   
   for(int i = total - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0)
      {
         if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
            PositionGetInteger(POSITION_MAGIC) == MagicNumber &&
            PositionGetInteger(POSITION_TYPE) == posType)
         {
            if(trade.PositionClose(ticket))
            {
               Print("ปิด Position สำเร็จ: ", ticket);
            }
         }
      }
   }
}
//+------------------------------------------------------------------+
