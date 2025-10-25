//+------------------------------------------------------------------+
//|                                           Grid Trading EA        |
//|                                                                  |
//+------------------------------------------------------------------+
#property copyright "Grid Trading System"
#property version   "1.00"
#property strict

//--- Input Parameters
enum ENUM_TRADE_MODE
{
   MODE_BUY_ONLY = 0,     // Buy Only
   MODE_SELL_ONLY = 1,    // Sell Only
   MODE_BOTH = 2          // Buy & Sell
};

input ENUM_TRADE_MODE TradeMode = MODE_BOTH;        // โหมดการเทรด
input double InitialLot = 0.01;                     // Lot เริ่มต้น
input int GridStep = 5000;                           // ระยะห่างของ Grid (จุด)
input int TakeProfit = 5000;                         // Take Profit (จุด)
input int MaxPendingOrders = 5;                     // จำนวน Pending Orders สูงสุดต่อฝั่ง
input double GridGap = 1.5;                         // ตัวคูณสำหรับปรับ Grid
input int MagicNumber = 20251025001;                     // Magic Number

//--- Global Variables
double PointValue;
int Digits_;

//-------------------- Utils --------------------
double NormalizeVolume(double vol){
   double step  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double minv  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxv  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   if(step<=0) step=0.01;
   double v = MathMax(minv, MathMin(maxv, MathFloor(vol/step+1e-9)*step));
   return v;
}
double NormalizePrice(double price){ return NormalizeDouble(price,(int)SymbolInfoInteger(_Symbol,SYMBOL_DIGITS)); }

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   PointValue = _Point;
   Digits_ = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   
   Print("Grid Trading EA เริ่มทำงาน");
   Print("โหมด: ", TradeMode == MODE_BUY_ONLY ? "Buy Only" : 
                    TradeMode == MODE_SELL_ONLY ? "Sell Only" : "Buy & Sell");
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   Print("Grid Trading EA หยุดทำงาน");
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // ตรวจสอบและจัดการ Grid
   if(TradeMode == MODE_BUY_ONLY || TradeMode == MODE_BOTH)
      ManageBuyGrid();
      
   if(TradeMode == MODE_SELL_ONLY || TradeMode == MODE_BOTH)
      ManageSellGrid();
}

//+------------------------------------------------------------------+
//| จัดการ Buy Grid                                                  |
//+------------------------------------------------------------------+
void ManageBuyGrid()
{
   int buyPendingCount = CountPendingOrders(ORDER_TYPE_BUY_STOP);
   double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   
   // ถ้ายังไม่มี Pending Order เลย ให้สร้างชุดแรก
   if(buyPendingCount == 0)
   {
      CreateInitialBuyGrid();
      return;
   }
   
   // หาราคา Pending Order Buy Stop ล่างสุดและบนสุด
   double lowestBuyStop = GetLowestBuyStop();
   double highestBuyStop = GetHighestBuyStop();
   
   // ตรวจสอบว่ามี Order ถึง TP หรือไม่ และเพิ่ม Pending Order ใหม่
   if(buyPendingCount < MaxPendingOrders)
   {
      double newPrice = highestBuyStop + (GridStep * PointValue);
      if(!IsPriceOccupied(newPrice, ORDER_TYPE_BUY_STOP))
         PlaceBuyStop(newPrice);
   }
   
   // ปรับ Grid เมื่อราคาลงต่ำ
   double gapDistance = GridStep * GridGap * PointValue;
   if(currentPrice < lowestBuyStop - gapDistance)
   {
      // เพิ่ม Pending Order ด้านล่าง
      double newPrice = lowestBuyStop - (GridStep * PointValue);
      if(!IsPriceOccupied(newPrice, ORDER_TYPE_BUY_STOP))
      {
         if(PlaceBuyStop(newPrice))
         {
            // ลบ Pending Order บนสุด
            DeleteHighestBuyStop();
         }
      }
   }
}

//+------------------------------------------------------------------+
//| จัดการ Sell Grid                                                 |
//+------------------------------------------------------------------+
void ManageSellGrid()
{
   int sellPendingCount = CountPendingOrders(ORDER_TYPE_SELL_STOP);
   double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   
   // ถ้ายังไม่มี Pending Order เลย ให้สร้างชุดแรก
   if(sellPendingCount == 0)
   {
      CreateInitialSellGrid();
      return;
   }
   
   // หาราคา Pending Order Sell Stop บนสุดและล่างสุด
   double highestSellStop = GetHighestSellStop();
   double lowestSellStop = GetLowestSellStop();
   
   // ตรวจสอบว่ามี Order ถึง TP หรือไม่ และเพิ่ม Pending Order ใหม่
   if(sellPendingCount < MaxPendingOrders)
   {
      double newPrice = lowestSellStop - (GridStep * PointValue);
      if(!IsPriceOccupied(newPrice, ORDER_TYPE_SELL_STOP))
         PlaceSellStop(newPrice);
   }
   
   // ปรับ Grid เมื่อราคาขึ้นสูง
   double gapDistance = GridStep * GridGap * PointValue;
   if(currentPrice > highestSellStop + gapDistance)
   {
      // เพิ่ม Pending Order ด้านบน
      double newPrice = highestSellStop + (GridStep * PointValue);
      if(!IsPriceOccupied(newPrice, ORDER_TYPE_SELL_STOP))
      {
         if(PlaceSellStop(newPrice))
         {
            // ลบ Pending Order ล่างสุด
            DeleteLowestSellStop();
         }
      }
   }
}

//+------------------------------------------------------------------+
//| สร้าง Buy Grid เริ่มต้น                                         |
//+------------------------------------------------------------------+
void CreateInitialBuyGrid()
{
   double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   
   for(int i = 1; i <= MaxPendingOrders; i++)
   {
      double price = currentPrice + (i * GridStep * PointValue);
      PlaceBuyStop(price);
   }
}

//+------------------------------------------------------------------+
//| สร้าง Sell Grid เริ่มต้น                                        |
//+------------------------------------------------------------------+
void CreateInitialSellGrid()
{
   double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   
   for(int i = 1; i <= MaxPendingOrders; i++)
   {
      double price = currentPrice - (i * GridStep * PointValue);
      PlaceSellStop(price);
   }
}

//+------------------------------------------------------------------+
//| วาง Buy Stop Order                                               |
//+------------------------------------------------------------------+
bool PlaceBuyStop(double price)
{
   MqlTradeRequest request = {};
   MqlTradeResult result = {};
   
   double tp = price + (TakeProfit * PointValue);
   
   request.action = TRADE_ACTION_PENDING;
   request.symbol = _Symbol;
   request.volume = InitialLot;
   request.type = ORDER_TYPE_BUY_STOP;
   request.price = NormalizeDouble(price, Digits_);
   request.tp = NormalizeDouble(tp, Digits_);
   request.sl = 0;
   request.magic = MagicNumber;
   request.comment = "Buy Grid";
   
   if(OrderSend(request, result))
   {
      Print("Buy Stop สร้างสำเร็จที่ ", price, " TP: ", tp);
      return true;
   }
   else
   {
      Print("ไม่สามารถสร้าง Buy Stop: ", result.retcode);
      return false;
   }
}

//+------------------------------------------------------------------+
//| วาง Sell Stop Order                                              |
//+------------------------------------------------------------------+
bool PlaceSellStop(double price)
{
   MqlTradeRequest request = {};
   MqlTradeResult result = {};
   
   double tp = price - (TakeProfit * PointValue);
   
   request.action = TRADE_ACTION_PENDING;
   request.symbol = _Symbol;
   request.volume = InitialLot;
   request.type = ORDER_TYPE_SELL_STOP;
   request.price = NormalizeDouble(price, Digits_);
   request.tp = NormalizeDouble(tp, Digits_);
   request.sl = 0;
   request.magic = MagicNumber;
   request.comment = "Sell Grid";
   
   if(OrderSend(request, result))
   {
      Print("Sell Stop สร้างสำเร็จที่ ", price, " TP: ", tp);
      return true;
   }
   else
   {
      Print("ไม่สามารถสร้าง Sell Stop: ", result.retcode);
      return false;
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
//| หาราคา Buy Stop ล่างสุด                                         |
//+------------------------------------------------------------------+
double GetLowestBuyStop()
{
   double lowest = DBL_MAX;
   int total = OrdersTotal();
   
   for(int i = 0; i < total; i++)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket > 0)
      {
         if(OrderGetString(ORDER_SYMBOL) == _Symbol &&
            OrderGetInteger(ORDER_MAGIC) == MagicNumber &&
            OrderGetInteger(ORDER_TYPE) == ORDER_TYPE_BUY_STOP)
         {
            double price = OrderGetDouble(ORDER_PRICE_OPEN);
            if(price < lowest)
               lowest = price;
         }
      }
   }
   
   return lowest;
}

//+------------------------------------------------------------------+
//| หาราคา Buy Stop บนสุด                                           |
//+------------------------------------------------------------------+
double GetHighestBuyStop()
{
   double highest = 0;
   int total = OrdersTotal();
   
   for(int i = 0; i < total; i++)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket > 0)
      {
         if(OrderGetString(ORDER_SYMBOL) == _Symbol &&
            OrderGetInteger(ORDER_MAGIC) == MagicNumber &&
            OrderGetInteger(ORDER_TYPE) == ORDER_TYPE_BUY_STOP)
         {
            double price = OrderGetDouble(ORDER_PRICE_OPEN);
            if(price > highest)
               highest = price;
         }
      }
   }
   
   return highest;
}

//+------------------------------------------------------------------+
//| หาราคา Sell Stop บนสุด                                          |
//+------------------------------------------------------------------+
double GetHighestSellStop()
{
   double highest = 0;
   int total = OrdersTotal();
   
   for(int i = 0; i < total; i++)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket > 0)
      {
         if(OrderGetString(ORDER_SYMBOL) == _Symbol &&
            OrderGetInteger(ORDER_MAGIC) == MagicNumber &&
            OrderGetInteger(ORDER_TYPE) == ORDER_TYPE_SELL_STOP)
         {
            double price = OrderGetDouble(ORDER_PRICE_OPEN);
            if(price > highest)
               highest = price;
         }
      }
   }
   
   return highest;
}

//+------------------------------------------------------------------+
//| หาราคา Sell Stop ล่างสุด                                        |
//+------------------------------------------------------------------+
double GetLowestSellStop()
{
   double lowest = DBL_MAX;
   int total = OrdersTotal();
   
   for(int i = 0; i < total; i++)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket > 0)
      {
         if(OrderGetString(ORDER_SYMBOL) == _Symbol &&
            OrderGetInteger(ORDER_MAGIC) == MagicNumber &&
            OrderGetInteger(ORDER_TYPE) == ORDER_TYPE_SELL_STOP)
         {
            double price = OrderGetDouble(ORDER_PRICE_OPEN);
            if(price < lowest)
               lowest = price;
         }
      }
   }
   
   return lowest;
}

//+------------------------------------------------------------------+
//| ตรวจสอบว่ามีราคาซ้ำกันหรือไม่                                    |
//+------------------------------------------------------------------+
bool IsPriceOccupied(double checkPrice, ENUM_ORDER_TYPE orderType)
{
   int total = OrdersTotal();
   double tolerance = GridStep * PointValue * 0.5; // ครึ่งหนึ่งของ GridStep
   
   for(int i = 0; i < total; i++)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket > 0)
      {
         if(OrderGetString(ORDER_SYMBOL) == _Symbol &&
            OrderGetInteger(ORDER_MAGIC) == MagicNumber &&
            OrderGetInteger(ORDER_TYPE) == orderType)
         {
            double price = OrderGetDouble(ORDER_PRICE_OPEN);
            if(MathAbs(price - checkPrice) < tolerance)
               return true;
         }
      }
   }
   
   // ตรวจสอบ Position ที่เปิดอยู่
   int posTotal = PositionsTotal();
   for(int i = 0; i < posTotal; i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0)
      {
         if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
            PositionGetInteger(POSITION_MAGIC) == MagicNumber)
         {
            double price = PositionGetDouble(POSITION_PRICE_OPEN);
            if(MathAbs(price - checkPrice) < tolerance)
               return true;
         }
      }
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| ลบ Buy Stop บนสุด                                               |
//+------------------------------------------------------------------+
void DeleteHighestBuyStop()
{
   ulong highestTicket = 0;
   double highestPrice = 0;
   int total = OrdersTotal();
   
   for(int i = 0; i < total; i++)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket > 0)
      {
         if(OrderGetString(ORDER_SYMBOL) == _Symbol &&
            OrderGetInteger(ORDER_MAGIC) == MagicNumber &&
            OrderGetInteger(ORDER_TYPE) == ORDER_TYPE_BUY_STOP)
         {
            double price = OrderGetDouble(ORDER_PRICE_OPEN);
            if(price > highestPrice)
            {
               highestPrice = price;
               highestTicket = ticket;
            }
         }
      }
   }
   
   if(highestTicket > 0)
   {
      MqlTradeRequest request = {};
      MqlTradeResult result = {};
      
      request.action = TRADE_ACTION_REMOVE;
      request.order = highestTicket;
      
      bool ok = OrderSend(request, result);
      //if(!ok)
      //{
         //PrintFormat("OrderSend failed ret=%d comment=%s", res.retcode, res.comment);
         //PrintFormat("OrderSend failed ret=%d", res.retcode);
      //}
   }
}

//+------------------------------------------------------------------+
//| ลบ Sell Stop ล่างสุด                                            |
//+------------------------------------------------------------------+
void DeleteLowestSellStop()
{
   ulong lowestTicket = 0;
   double lowestPrice = DBL_MAX;
   int total = OrdersTotal();
   
   for(int i = 0; i < total; i++)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket > 0)
      {
         if(OrderGetString(ORDER_SYMBOL) == _Symbol &&
            OrderGetInteger(ORDER_MAGIC) == MagicNumber &&
            OrderGetInteger(ORDER_TYPE) == ORDER_TYPE_SELL_STOP)
         {
            double price = OrderGetDouble(ORDER_PRICE_OPEN);
            if(price < lowestPrice)
            {
               lowestPrice = price;
               lowestTicket = ticket;
            }
         }
      }
   }
   
   if(lowestTicket > 0)
   {
      MqlTradeRequest request = {};
      MqlTradeResult result = {};
      
      request.action = TRADE_ACTION_REMOVE;
      request.order = lowestTicket;
      
      bool ok = OrderSend(request, result);
   }
}
//+------------------------------------------------------------------+
