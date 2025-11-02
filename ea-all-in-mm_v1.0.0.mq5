//+------------------------------------------------------------------+
//|                                                   AllIn_MM_EA.mq5 |
//|                                         All-in Trading System EA |
//|                                     with Money Management System |
//+------------------------------------------------------------------+
#property copyright "All-in MM EA"
#property link      ""
#property version   "1.00"
#property strict

//--- Input Parameters
input group "=== Order Settings ==="
input int    MaxOrders = 3;              // จำนวนออเดอร์สูงสุด (0=ไม่จำกัด)
input double ProfitPoints = 100.0;       // กำไรเป้าหมาย (จุด)

input group "=== Money Management ==="
input double MaxMarginPercent = 150.0;    // %Margin สูงสุดที่ใช้ได้
input double MinFreeMargin = 20.0;       // %Free Margin ขั้นต่ำ
input double LotMultiplier = 1.0;        // ตัวคูณ Lot สำหรับออเดอร์ต่อไป

input group "=== Grid Settings ==="
input double GridStep = 50.0;            // ระยะห่างระหว่างออเดอร์ (จุด)
input bool   UseGridSystem = false;       // ใช้ระบบ Grid

input group "=== Display Settings ==="
input bool   ShowPanel = false;           // แสดงแผงข้อมูล
input color  PanelColor = clrDarkSlateGray;
input color  TextColor = clrWhite;

//--- Global Variables
struct SymbolPositionData
{
   string symbol;
   ENUM_POSITION_TYPE type;
   int orderCount;
   double totalVolume;
   double avgPrice;
   double totalProfit;
   double lastOrderPrice;
};

//+------------------------------------------------------------------+
//| Expert initialization function                                     |
//+------------------------------------------------------------------+
int OnInit()
{
   Print("All-in MM EA initialized");
   Print("Max Orders: ", MaxOrders == 0 ? "Unlimited" : IntegerToString(MaxOrders));
   Print("Profit Target: ", ProfitPoints, " points");
   Print("Max Margin: ", MaxMarginPercent, "%");
   
   if(ShowPanel)
      CreateInfoPanel();
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                   |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(ShowPanel)
      DeleteInfoPanel();
   
   Print("All-in MM EA deinitialized");
}

//+------------------------------------------------------------------+
//| Expert tick function                                               |
//+------------------------------------------------------------------+
void OnTick()
{
   //--- ตรวจสอบและเปิดออเดอร์เพิ่ม
   CheckAndOpenNewOrders();
   
   //--- ตรวจสอบและปิดออเดอร์ตามกำไรเป้าหมาย
   CheckAndCloseOrders();
   
   //--- อัพเดทแผงข้อมูล
   if(ShowPanel)
      UpdateInfoPanel();
}

//+------------------------------------------------------------------+
//| ตรวจสอบและเปิดออเดอร์เพิ่ม                                        |
//+------------------------------------------------------------------+
void CheckAndOpenNewOrders()
{
   //--- รับรายการ Symbol ที่มีออเดอร์เปิดอยู่
   string symbols[];
   ENUM_POSITION_TYPE types[];
   GetOpenPositionSymbols(symbols, types);
   
   //--- วนลูปตรวจสอบแต่ละ Symbol และ Position Type
   for(int i = 0; i < ArraySize(symbols); i++)
   {
      SymbolPositionData data;
      if(GetSymbolPositionData(symbols[i], types[i], data))
      {
         //--- ตรวจสอบว่าสามารถเปิดออเดอร์เพิ่มได้หรือไม่
         if(CanOpenNewOrder(data))
         {
            //--- คำนวณ Lot ที่เหมาะสม
            double lotSize = CalculateSafeLotSize(data);
            
            if(lotSize > 0)
            {
               //--- เปิดออเดอร์ใหม่
               OpenNewOrder(data.symbol, data.type, lotSize);
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| ตรวจสอบและปิดออเดอร์ตามกำไรเป้าหมาย                              |
//+------------------------------------------------------------------+
void CheckAndCloseOrders()
{
   //--- รับรายการ Symbol ที่มีออเดอร์เปิดอยู่
   string symbols[];
   ENUM_POSITION_TYPE types[];
   GetOpenPositionSymbols(symbols, types);
   
   //--- วนลูปตรวจสอบแต่ละ Symbol และ Position Type
   for(int i = 0; i < ArraySize(symbols); i++)
   {
      SymbolPositionData data;
      if(GetSymbolPositionData(symbols[i], types[i], data))
      {
         //--- คำนวณกำไรจากราคาเฉลี่ย
         double currentPrice = (data.type == POSITION_TYPE_BUY) ? 
                               SymbolInfoDouble(data.symbol, SYMBOL_BID) :
                               SymbolInfoDouble(data.symbol, SYMBOL_ASK);
         
         double priceMove = (data.type == POSITION_TYPE_BUY) ?
                           (currentPrice - data.avgPrice) :
                           (data.avgPrice - currentPrice);
         
         double pointSize = SymbolInfoDouble(data.symbol, SYMBOL_POINT);
         double points = priceMove / pointSize;
         
         //--- ถ้าถึงเป้าหมายกำไรแล้ว
         if(points >= ProfitPoints)
         {
            Print("Profit target reached for ", data.symbol, " ", 
                  EnumToString(data.type), ": ", points, " points");
            CloseAllPositions(data.symbol, data.type);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| ตรวจสอบว่าสามารถเปิดออเดอร์ใหม่ได้หรือไม่                          |
//+------------------------------------------------------------------+
bool CanOpenNewOrder(SymbolPositionData &data)
{
   //--- ตรวจสอบจำนวนออเดอร์สูงสุด
   if(MaxOrders > 0 && data.orderCount >= MaxOrders)
      return false;
   
   //--- ตรวจสอบระยะห่างจากออเดอร์ล่าสุด (สำหรับระบบ Grid)
   if(UseGridSystem && data.orderCount > 0)
   {
      double currentPrice = (data.type == POSITION_TYPE_BUY) ?
                           SymbolInfoDouble(data.symbol, SYMBOL_ASK) :
                           SymbolInfoDouble(data.symbol, SYMBOL_BID);
      
      double pointSize = SymbolInfoDouble(data.symbol, SYMBOL_POINT);
      double distance = MathAbs(currentPrice - data.lastOrderPrice) / pointSize;
      
      if(distance < GridStep)
         return false;
   }
   
   //--- ตรวจสอบ Margin
   if(!CheckMarginSafety())
      return false;
   
   return true;
}

//+------------------------------------------------------------------+
//| คำนวณ Lot ที่ปลอดภัย                                              |
//+------------------------------------------------------------------+
double CalculateSafeLotSize(SymbolPositionData &data)
{
   double accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   double accountEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   double accountMargin = AccountInfoDouble(ACCOUNT_MARGIN);
   double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   
   //--- คำนวณ Margin ที่ใช้ได้
   double usedMarginPercent = (accountMargin / accountEquity) * 100.0;
   double availableMarginPercent = MaxMarginPercent - usedMarginPercent;
   
   if(availableMarginPercent <= 0)
      return 0;
   
   //--- คำนวณ Lot จาก Free Margin ที่เหลือ
   double minLot = SymbolInfoDouble(data.symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(data.symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(data.symbol, SYMBOL_VOLUME_STEP);
   
   //--- Lot สำหรับออเดอร์ใหม่ (คูณจากออเดอร์แรก)
   double baseLot = (data.orderCount == 0) ? minLot : (data.totalVolume / data.orderCount);
   double newLot = NormalizeDouble(baseLot * LotMultiplier, 2);
   
   //--- ตรวจสอบ Margin ที่ต้องการ
   double requiredMargin = GetRequiredMargin(data.symbol, newLot);
   double maxAllowedMargin = (accountEquity * (MaxMarginPercent / 100.0)) - accountMargin;
   
   //--- ปรับ Lot ให้เหมาะสมกับ Margin
   if(requiredMargin > maxAllowedMargin)
   {
      newLot = newLot * (maxAllowedMargin / requiredMargin);
      newLot = NormalizeDouble(newLot, 2);
   }
   
   //--- ตรวจสอบขอบเขต Lot
   if(newLot < minLot)
      newLot = minLot;
   if(newLot > maxLot)
      newLot = maxLot;
   
   //--- ปรับให้ตรงกับ Lot Step
   newLot = MathFloor(newLot / lotStep) * lotStep;
   
   //--- ตรวจสอบความปลอดภัยอีกครั้ง
   requiredMargin = GetRequiredMargin(data.symbol, newLot);
   double projectedMarginPercent = ((accountMargin + requiredMargin) / accountEquity) * 100.0;
   
   if(projectedMarginPercent > MaxMarginPercent)
   {
      Print("Warning: Projected margin (", projectedMarginPercent, 
            "%) exceeds maximum (", MaxMarginPercent, "%)");
      return 0;
   }
   
   double projectedFreeMarginPercent = ((freeMargin - requiredMargin) / accountEquity) * 100.0;
   
   if(projectedFreeMarginPercent < MinFreeMargin)
   {
      Print("Warning: Insufficient free margin. Required: ", MinFreeMargin, 
            "%, Projected: ", projectedFreeMarginPercent, "%");
      return 0;
   }
   
   return newLot;
}

//+------------------------------------------------------------------+
//| คำนวณ Margin ที่ต้องการ                                           |
//+------------------------------------------------------------------+
double GetRequiredMargin(string symbol, double lots)
{
   double margin = 0;
   
   if(!OrderCalcMargin(ORDER_TYPE_BUY, symbol, lots, 
                       SymbolInfoDouble(symbol, SYMBOL_ASK), margin))
   {
      Print("Error calculating margin: ", GetLastError());
      return 0;
   }
   
   return margin;
}

//+------------------------------------------------------------------+
//| ตรวจสอบความปลอดภัยของ Margin                                      |
//+------------------------------------------------------------------+
bool CheckMarginSafety()
{
   double accountEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   double accountMargin = AccountInfoDouble(ACCOUNT_MARGIN);
   double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   
   double usedMarginPercent = (accountMargin / accountEquity) * 100.0;
   double freeMarginPercent = (freeMargin / accountEquity) * 100.0;
   
   if(usedMarginPercent >= MaxMarginPercent)
   {
      Print("Margin limit reached: ", usedMarginPercent, "%");
      return false;
   }
   
   if(freeMarginPercent <= MinFreeMargin)
   {
      Print("Free margin too low: ", freeMarginPercent, "%");
      return false;
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| เปิดออเดอร์ใหม่                                                   |
//+------------------------------------------------------------------+
void OpenNewOrder(string symbol, ENUM_POSITION_TYPE type, double lots)
{
   MqlTradeRequest request = {};
   MqlTradeResult result = {};
   
   double price = (type == POSITION_TYPE_BUY) ?
                  SymbolInfoDouble(symbol, SYMBOL_ASK) :
                  SymbolInfoDouble(symbol, SYMBOL_BID);
   
   request.action = TRADE_ACTION_DEAL;
   request.symbol = symbol;
   request.volume = lots;
   request.type = (type == POSITION_TYPE_BUY) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   request.price = price;
   request.deviation = 10;
   request.magic = 12345;
   request.comment = "AllIn_MM";
   
   if(OrderSend(request, result))
   {
      if(result.retcode == TRADE_RETCODE_DONE)
      {
         Print("Order opened successfully: ", symbol, " ", EnumToString(type), 
               " Lots: ", lots, " Price: ", price);
      }
      else
      {
         Print("Order failed: ", result.retcode, " - ", result.comment);
      }
   }
   else
   {
      Print("OrderSend error: ", GetLastError());
   }
}

//+------------------------------------------------------------------+
//| ปิดออเดอร์ทั้งหมดของ Symbol และ Position Type                     |
//+------------------------------------------------------------------+
void CloseAllPositions(string symbol, ENUM_POSITION_TYPE type)
{
   int total = PositionsTotal();
   
   for(int i = total - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      
      if(ticket > 0)
      {
         if(PositionGetString(POSITION_SYMBOL) == symbol &&
            PositionGetInteger(POSITION_TYPE) == type)
         {
            MqlTradeRequest request = {};
            MqlTradeResult result = {};
            
            request.action = TRADE_ACTION_DEAL;
            request.position = ticket;
            request.symbol = symbol;
            request.volume = PositionGetDouble(POSITION_VOLUME);
            request.type = (type == POSITION_TYPE_BUY) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
            request.price = (type == POSITION_TYPE_BUY) ?
                           SymbolInfoDouble(symbol, SYMBOL_BID) :
                           SymbolInfoDouble(symbol, SYMBOL_ASK);
            request.deviation = 10;
            request.magic = 12345;
            
            if(OrderSend(request, result))
            {
               Print("Position closed: ", ticket);
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| รับรายการ Symbol ที่มีออเดอร์เปิดอยู่                             |
//+------------------------------------------------------------------+
void GetOpenPositionSymbols(string &symbols[], ENUM_POSITION_TYPE &types[])
{
   ArrayResize(symbols, 0);
   ArrayResize(types, 0);
   
   int total = PositionsTotal();
   
   for(int i = 0; i < total; i++)
   {
      ulong ticket = PositionGetTicket(i);
      
      if(ticket > 0)
      {
         string symbol = PositionGetString(POSITION_SYMBOL);
         ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
         
         //--- ตรวจสอบว่ามีใน Array แล้วหรือยัง
         bool found = false;
         for(int j = 0; j < ArraySize(symbols); j++)
         {
            if(symbols[j] == symbol && types[j] == type)
            {
               found = true;
               break;
            }
         }
         
         if(!found)
         {
            int size = ArraySize(symbols);
            ArrayResize(symbols, size + 1);
            ArrayResize(types, size + 1);
            symbols[size] = symbol;
            types[size] = type;
         }
      }
   }
}

//+------------------------------------------------------------------+
//| รับข้อมูลออเดอร์ของ Symbol และ Position Type                      |
//+------------------------------------------------------------------+
bool GetSymbolPositionData(string symbol, ENUM_POSITION_TYPE type, SymbolPositionData &data)
{
   data.symbol = symbol;
   data.type = type;
   data.orderCount = 0;
   data.totalVolume = 0;
   data.avgPrice = 0;
   data.totalProfit = 0;
   data.lastOrderPrice = 0;
   
   double totalPrice = 0;
   int total = PositionsTotal();
   
   for(int i = 0; i < total; i++)
   {
      ulong ticket = PositionGetTicket(i);
      
      if(ticket > 0)
      {
         if(PositionGetString(POSITION_SYMBOL) == symbol &&
            PositionGetInteger(POSITION_TYPE) == type)
         {
            double volume = PositionGetDouble(POSITION_VOLUME);
            double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
            double profit = PositionGetDouble(POSITION_PROFIT);
            
            data.orderCount++;
            data.totalVolume += volume;
            totalPrice += openPrice * volume;
            data.totalProfit += profit;
            data.lastOrderPrice = openPrice;
         }
      }
   }
   
   if(data.orderCount > 0)
   {
      data.avgPrice = totalPrice / data.totalVolume;
      return true;
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| สร้างแผงข้อมูล                                                    |
//+------------------------------------------------------------------+
void CreateInfoPanel()
{
   int x = 10;
   int y = 20;
   int width = 300;
   int height = 200;
   
   //--- สร้างพื้นหลัง
   ObjectCreate(0, "PanelBG", OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, "PanelBG", OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, "PanelBG", OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, "PanelBG", OBJPROP_XSIZE, width);
   ObjectSetInteger(0, "PanelBG", OBJPROP_YSIZE, height);
   ObjectSetInteger(0, "PanelBG", OBJPROP_BGCOLOR, PanelColor);
   ObjectSetInteger(0, "PanelBG", OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, "PanelBG", OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, "PanelBG", OBJPROP_BACK, false);
   ObjectSetInteger(0, "PanelBG", OBJPROP_SELECTABLE, false);
   
   //--- สร้างข้อความหัวเรื่อง
   ObjectCreate(0, "PanelTitle", OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, "PanelTitle", OBJPROP_XDISTANCE, x + 10);
   ObjectSetInteger(0, "PanelTitle", OBJPROP_YDISTANCE, y + 5);
   ObjectSetInteger(0, "PanelTitle", OBJPROP_COLOR, TextColor);
   ObjectSetInteger(0, "PanelTitle", OBJPROP_FONTSIZE, 10);
   ObjectSetString(0, "PanelTitle", OBJPROP_TEXT, "All-in MM EA");
   ObjectSetString(0, "PanelTitle", OBJPROP_FONT, "Arial Bold");
   
   //--- สร้างข้อความข้อมูล
   for(int i = 0; i < 8; i++)
   {
      string objName = "PanelText" + IntegerToString(i);
      ObjectCreate(0, objName, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, objName, OBJPROP_XDISTANCE, x + 10);
      ObjectSetInteger(0, objName, OBJPROP_YDISTANCE, y + 30 + (i * 20));
      ObjectSetInteger(0, objName, OBJPROP_COLOR, TextColor);
      ObjectSetInteger(0, objName, OBJPROP_FONTSIZE, 8);
      ObjectSetString(0, objName, OBJPROP_FONT, "Arial");
   }
}

//+------------------------------------------------------------------+
//| อัพเดทแผงข้อมูล                                                  |
//+------------------------------------------------------------------+
void UpdateInfoPanel()
{
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double margin = AccountInfoDouble(ACCOUNT_MARGIN);
   double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   double marginPercent = (margin / equity) * 100.0;
   double freeMarginPercent = (freeMargin / equity) * 100.0;
   
   int totalPositions = PositionsTotal();
   double totalProfit = 0;
   
   for(int i = 0; i < totalPositions; i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0)
         totalProfit += PositionGetDouble(POSITION_PROFIT);
   }
   
   ObjectSetString(0, "PanelText0", OBJPROP_TEXT, "Balance: " + DoubleToString(balance, 2));
   ObjectSetString(0, "PanelText1", OBJPROP_TEXT, "Equity: " + DoubleToString(equity, 2));
   ObjectSetString(0, "PanelText2", OBJPROP_TEXT, "Margin: " + DoubleToString(marginPercent, 2) + "%");
   ObjectSetString(0, "PanelText3", OBJPROP_TEXT, "Free Margin: " + DoubleToString(freeMarginPercent, 2) + "%");
   ObjectSetString(0, "PanelText4", OBJPROP_TEXT, "Total Positions: " + IntegerToString(totalPositions));
   ObjectSetString(0, "PanelText5", OBJPROP_TEXT, "Total Profit: " + DoubleToString(totalProfit, 2));
   ObjectSetString(0, "PanelText6", OBJPROP_TEXT, "Max Orders: " + (MaxOrders == 0 ? "Unlimited" : IntegerToString(MaxOrders)));
   ObjectSetString(0, "PanelText7", OBJPROP_TEXT, "Target: " + DoubleToString(ProfitPoints, 0) + " pts");
}

//+------------------------------------------------------------------+
//| ลบแผงข้อมูล                                                      |
//+------------------------------------------------------------------+
void DeleteInfoPanel()
{
   ObjectDelete(0, "PanelBG");
   ObjectDelete(0, "PanelTitle");
   
   for(int i = 0; i < 8; i++)
   {
      ObjectDelete(0, "PanelText" + IntegerToString(i));
   }
}

//+------------------------------------------------------------------+
