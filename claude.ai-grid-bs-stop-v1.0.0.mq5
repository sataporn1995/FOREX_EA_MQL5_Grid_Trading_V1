//+------------------------------------------------------------------+
//|                                           Grid Trading EA        |
//|                                                                  |
//+------------------------------------------------------------------+
#property copyright "Grid Trading System"
#property version   "1.10"
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
input int GridStep = 500;                           // ระยะห่างของ Grid (จุด)
input int TakeProfit = 400;                         // Take Profit (จุด)
input int MaxPendingOrders = 3;                     // จำนวน Pending Orders สูงสุดต่อฝั่ง
input int GridAdjustDistance = 800;                 // ระยะห่างสำหรับปรับ Grid (จุด)
input int MagicNumber = 123456;                     // Magic Number

//--- Global Variables
double PointValue;
int Digits_;
datetime LastBuyAdjustTime = 0;      // เวลาที่ปรับ Buy Grid ล่าสุด
datetime LastSellAdjustTime = 0;     // เวลาที่ปรับ Sell Grid ล่าสุด
int AdjustCooldown = 60;             // Cooldown 60 วินาที

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
   
   // หาราคา Buy ล่างสุด (รวมทั้ง Pending และ Active)
   double lowestBuyPrice = GetLowestBuyPrice();
   
   // เงื่อนไขใหม่: ตรวจสอบว่าราคาลงห่างจากออเดอร์ล่างสุดเกิน GridAdjustDistance หรือไม่
   double adjustDistance = GridAdjustDistance * PointValue;
   
   // ตรวจสอบ Cooldown ป้องกันการปรับ Grid รัวๆ
   if(lowestBuyPrice > 0 && 
      currentPrice < lowestBuyPrice - adjustDistance &&
      TimeCurrent() - LastBuyAdjustTime > AdjustCooldown)
   {
      // ลบ Pending Buy Stop บนสุด
      if(DeleteHighestBuyStop())
      {
         // เปิด Pending Buy Stop ใหม่ด้านล่าง ห่างจากล่างสุด GridStep
         double newPrice = lowestBuyPrice - (GridStep * PointValue);
         if(!IsPriceOccupiedBuy(newPrice))
         {
            if(PlaceBuyStop(newPrice))
            {
               LastBuyAdjustTime = TimeCurrent(); // บันทึกเวลาที่ปรับ
               Print("ปรับ Buy Grid สำเร็จ - Cooldown ", AdjustCooldown, " วินาที");
            }
         }
      }
   }
   
   // ถ้ามี Pending น้อยกว่าสูงสุด ให้เพิ่มด้านบน
   if(buyPendingCount < MaxPendingOrders)
   {
      double highestBuyStop = GetHighestBuyStop();
      if(highestBuyStop > 0)
      {
         double newPrice = highestBuyStop + (GridStep * PointValue);
         if(!IsPriceOccupiedBuy(newPrice))
            PlaceBuyStop(newPrice);
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
   
   // หาราคา Sell บนสุด (รวมทั้ง Pending และ Active)
   double highestSellPrice = GetHighestSellPrice();
   
   // เงื่อนไขใหม่: ตรวจสอบว่าราคาขึ้นห่างจากออเดอร์บนสุดเกิน GridAdjustDistance หรือไม่
   double adjustDistance = GridAdjustDistance * PointValue;
   
   // ตรวจสอบ Cooldown ป้องกันการปรับ Grid รัวๆ
   if(highestSellPrice > 0 && 
      currentPrice > highestSellPrice + adjustDistance &&
      TimeCurrent() - LastSellAdjustTime > AdjustCooldown)
   {
      // ลบ Pending Sell Stop ล่างสุด
      if(DeleteLowestSellStop())
      {
         // เปิด Pending Sell Stop ใหม่ด้านบน ห่างจากบนสุด GridStep
         double newPrice = highestSellPrice + (GridStep * PointValue);
         if(!IsPriceOccupiedSell(newPrice))
         {
            if(PlaceSellStop(newPrice))
            {
               LastSellAdjustTime = TimeCurrent(); // บันทึกเวลาที่ปรับ
               Print("ปรับ Sell Grid สำเร็จ - Cooldown ", AdjustCooldown, " วินาที");
            }
         }
      }
   }
   
   // ถ้ามี Pending น้อยกว่าสูงสุด ให้เพิ่มด้านล่าง
   if(sellPendingCount < MaxPendingOrders)
   {
      double lowestSellStop = GetLowestSellStop();
      if(lowestSellStop > 0)
      {
         double newPrice = lowestSellStop - (GridStep * PointValue);
         if(!IsPriceOccupiedSell(newPrice))
            PlaceSellStop(newPrice);
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
   
   return (lowest == DBL_MAX) ? 0 : lowest;
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
   
   return (lowest == DBL_MAX) ? 0 : lowest;
}

//+------------------------------------------------------------------+
//| หาราคา Buy ล่างสุด (รวม Pending + Active Position)              |
//+------------------------------------------------------------------+
double GetLowestBuyPrice()
{
   double lowest = DBL_MAX;
   
   // ตรวจสอบ Pending Orders
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
   
   // ตรวจสอบ Active Positions (Buy)
   int posTotal = PositionsTotal();
   for(int i = 0; i < posTotal; i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0)
      {
         if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
            PositionGetInteger(POSITION_MAGIC) == MagicNumber &&
            PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
         {
            double price = PositionGetDouble(POSITION_PRICE_OPEN);
            if(price < lowest)
               lowest = price;
         }
      }
   }
   
   return (lowest == DBL_MAX) ? 0 : lowest;
}

//+------------------------------------------------------------------+
//| หาราคา Sell บนสุด (รวม Pending + Active Position)               |
//+------------------------------------------------------------------+
double GetHighestSellPrice()
{
   double highest = 0;
   
   // ตรวจสอบ Pending Orders
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
   
   // ตรวจสอบ Active Positions (Sell)
   int posTotal = PositionsTotal();
   for(int i = 0; i < posTotal; i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0)
      {
         if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
            PositionGetInteger(POSITION_MAGIC) == MagicNumber &&
            PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL)
         {
            double price = PositionGetDouble(POSITION_PRICE_OPEN);
            if(price > highest)
               highest = price;
         }
      }
   }
   
   return highest;
}

//+------------------------------------------------------------------+
//| ตรวจสอบว่ามีราคาซ้ำกันสำหรับ Buy หรือไม่                         |
//+------------------------------------------------------------------+
bool IsPriceOccupiedBuy(double checkPrice)
{
   double tolerance = GridStep * PointValue * 0.3;
   
   // ตรวจสอบ Pending Buy Stop Orders
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
            if(MathAbs(price - checkPrice) < tolerance)
               return true;
         }
      }
   }
   
   // ตรวจสอบ Active Buy Positions
   int posTotal = PositionsTotal();
   for(int i = 0; i < posTotal; i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0)
      {
         if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
            PositionGetInteger(POSITION_MAGIC) == MagicNumber &&
            PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
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
//| ตรวจสอบว่ามีราคาซ้ำกันสำหรับ Sell หรือไม่                        |
//+------------------------------------------------------------------+
bool IsPriceOccupiedSell(double checkPrice)
{
   double tolerance = GridStep * PointValue * 0.3;
   
   // ตรวจสอบ Pending Sell Stop Orders
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
            if(MathAbs(price - checkPrice) < tolerance)
               return true;
         }
      }
   }
   
   // ตรวจสอบ Active Sell Positions
   int posTotal = PositionsTotal();
   for(int i = 0; i < posTotal; i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0)
      {
         if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
            PositionGetInteger(POSITION_MAGIC) == MagicNumber &&
            PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL)
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
bool DeleteHighestBuyStop()
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
      
      if(OrderSend(request, result))
      {
         Print("ลบ Buy Stop บนสุดสำเร็จที่ ", highestPrice);
         return true;
      }
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| ลบ Sell Stop ล่างสุด                                            |
//+------------------------------------------------------------------+
bool DeleteLowestSellStop()
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
      
      if(OrderSend(request, result))
      {
         Print("ลบ Sell Stop ล่างสุดสำเร็จที่ ", lowestPrice);
         return true;
      }
   }
   
   return false;
}
//+------------------------------------------------------------------+
