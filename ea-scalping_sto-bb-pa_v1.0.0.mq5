//+------------------------------------------------------------------+
//|                                                   ScalpingEA.mq5 |
//|                                  Expert Advisor สำหรับ Scalping |
//|                                      โดยใช้ Stochastic, BB, PA  |
//+------------------------------------------------------------------+
#property copyright "Scalping Strategy EA"
#property version   "1.00"
#property description "EA สำหรับ Scalping ด้วย Stochastic, Bollinger Bands และ Price Action"

// เพิ่ม Libraries ที่จำเป็น
#include <Trade\Trade.mqh>

// สร้างออบเจ็กต์สำหรับการเทรด
CTrade trade;

//+------------------------------------------------------------------+
//| พารามิเตอร์อินพุต (Input Parameters)                              |
//+------------------------------------------------------------------+

//--- การตั้งค่า Indicators
input group "=== ตัวชี้วัด Stochastic ==="
input int      StochK_Period = 5;           // Stochastic %K Period
input int      StochD_Period = 3;           // Stochastic %D Period
input int      StochSlowing = 3;            // Stochastic Slowing
input int      StochOversold = 20;          // Stochastic Oversold Level
input int      StochOverbought = 80;        // Stochastic Overbought Level

input group "=== ตัวชี้วัด Bollinger Bands ==="
input int      BB_Period = 20;              // Bollinger Bands Period
input double   BB_Deviation = 2.0;          // Bollinger Bands Deviation
input int      BB_Shift = 0;                // Bollinger Bands Shift

input group "=== การจัดการความเสี่ยง ==="
input double   LotSize = 0.01;              // ขนาดล็อต
input int      TakeProfit_Pips = 10;        // Take Profit (pips)
input int      StopLoss_Pips = 10;          // Stop Loss (pips)
input bool     UseATR_SL = false;           // ใช้ ATR สำหรับ Stop Loss
input double   ATR_Multiplier = 1.5;        // ATR Multiplier สำหรับ SL
input int      ATR_Period = 14;             // ATR Period

input group "=== การจัดการออเดอร์ ==="
input bool     CloseHalfAtHalfProfit = true; // ปิดครึ่งหนึ่งเมื่อได้กำไรครึ่ง
input bool     UseTrailingStop = true;       // ใช้ Trailing Stop
input int      TrailingStop_Pips = 5;        // Trailing Stop (pips)
input int      TrailingStep_Pips = 2;        // Trailing Step (pips)

input group "=== ตัวกรองเวลาเทรด ==="
input bool     UseTimeFilter = true;         // ใช้ตัวกรองเวลา
input int      StartHour = 7;                // เวลาเริ่มเทรด (GMT)
input int      EndHour = 16;                 // เวลาสิ้นสุด (GMT)

input group "=== การตั้งค่าเพิ่มเติม ==="
input bool     AllowMultipleOrders = false;  // อนุญาตหลายออเดอร์ในทิศทางเดียวกัน
input int      MagicNumber = 123456;         // Magic Number
input string   CommentOrder = "ScalpEA";     // คอมเมนต์ออเดอร์
input bool     ShowInfo = true;              // แสดงข้อมูลบนกราฟ

//+------------------------------------------------------------------+
//| ตัวแปรสำหรับ Indicators                                           |
//+------------------------------------------------------------------+
int    handleStochastic;    // Handle สำหรับ Stochastic
int    handleBB;            // Handle สำหรับ Bollinger Bands
int    handleATR;           // Handle สำหรับ ATR

double stochMain[];         // %K Line
double stochSignal[];       // %D Line
double bbUpper[];           // Bollinger Upper Band
double bbMiddle[];          // Bollinger Middle Band
double bbLower[];           // Bollinger Lower Band
double atrValue[];          // ATR Value

// ตัวแปรสำหรับการจัดการออเดอร์
bool   halfClosed = false;  // ตรวจสอบว่าปิดครึ่งแล้วหรือยัง

//+------------------------------------------------------------------+
//| ฟังก์ชัน OnInit - เรียกครั้งเดียวตอนเริ่มต้น EA                   |
//+------------------------------------------------------------------+
int OnInit()
{
   // ตั้งค่า Array เป็น Series (ล่าสุดอยู่ index 0)
   ArraySetAsSeries(stochMain, true);
   ArraySetAsSeries(stochSignal, true);
   ArraySetAsSeries(bbUpper, true);
   ArraySetAsSeries(bbMiddle, true);
   ArraySetAsSeries(bbLower, true);
   ArraySetAsSeries(atrValue, true);
   
   // สร้าง Indicator Handles
   handleStochastic = iStochastic(_Symbol, PERIOD_CURRENT, 
                                  StochK_Period, StochD_Period, StochSlowing,
                                  MODE_SMA, STO_LOWHIGH);
   
   handleBB = iBands(_Symbol, PERIOD_CURRENT, 
                     BB_Period, BB_Shift, BB_Deviation, PRICE_CLOSE);
   
   handleATR = iATR(_Symbol, PERIOD_CURRENT, ATR_Period);
   
   // ตรวจสอบว่าสร้าง Indicators สำเร็จหรือไม่
   if(handleStochastic == INVALID_HANDLE || handleBB == INVALID_HANDLE || handleATR == INVALID_HANDLE)
   {
      Print("❌ ข้อผิดพลาด: ไม่สามารถสร้าง Indicator ได้!");
      return(INIT_FAILED);
   }
   
   Print("✅ EA เริ่มทำงานสำเร็จ - ", _Symbol, " Timeframe: ", EnumToString(Period()));
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| ฟังก์ชัน OnDeinit - เรียกเมื่อปิด EA                             |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   // ปล่อย Indicator Handles
   if(handleStochastic != INVALID_HANDLE) IndicatorRelease(handleStochastic);
   if(handleBB != INVALID_HANDLE) IndicatorRelease(handleBB);
   if(handleATR != INVALID_HANDLE) IndicatorRelease(handleATR);
   
   // ลบออบเจ็กต์บนกราฟ
   Comment("");
   ObjectsDeleteAll(0, "ScalpInfo");
   
   Print("EA หยุดทำงาน");
}

//+------------------------------------------------------------------+
//| ฟังก์ชัน OnTick - เรียกทุกครั้งที่มีการเปลี่ยนแปลงราคา            |
//+------------------------------------------------------------------+
void OnTick()
{
   // ตรวจสอบว่ามีแท่งเทียนใหม่หรือไม่
   static datetime lastBarTime = 0;
   datetime currentBarTime = iTime(_Symbol, PERIOD_CURRENT, 0);
   
   bool isNewBar = (currentBarTime != lastBarTime);
   
   if(isNewBar)
   {
      lastBarTime = currentBarTime;
      
      // อัพเดทข้อมูล Indicators
      if(!UpdateIndicators())
         return;
      
      // ตรวจสอบตัวกรองเวลา
      if(UseTimeFilter && !CheckTimeFilter())
         return;
      
      // ตรวจสอบสัญญาณการเทรด
      int signal = GetTradeSignal();
      
      // เปิดออเดอร์ตามสัญญาณ
      if(signal == 1) // Buy Signal
      {
         if(AllowMultipleOrders || !HasOpenPosition(ORDER_TYPE_BUY))
            OpenBuyOrder();
      }
      else if(signal == -1) // Sell Signal
      {
         if(AllowMultipleOrders || !HasOpenPosition(ORDER_TYPE_SELL))
            OpenSellOrder();
      }
   }
   
   // จัดการออเดอร์ที่เปิดอยู่
   ManageOpenPositions();
   
   // แสดงข้อมูลบนกราฟ
   if(ShowInfo)
      DisplayInfo();
}

//+------------------------------------------------------------------+
//| ฟังก์ชันอัพเดทข้อมูล Indicators                                  |
//+------------------------------------------------------------------+
bool UpdateIndicators()
{
   // คัดลอกข้อมูล Stochastic
   if(CopyBuffer(handleStochastic, 0, 0, 3, stochMain) < 3 ||
      CopyBuffer(handleStochastic, 1, 0, 3, stochSignal) < 3)
   {
      Print("ไม่สามารถคัดลอกข้อมูล Stochastic");
      return false;
   }
   
   // คัดลอกข้อมูล Bollinger Bands
   if(CopyBuffer(handleBB, 0, 0, 3, bbMiddle) < 3 ||
      CopyBuffer(handleBB, 1, 0, 3, bbUpper) < 3 ||
      CopyBuffer(handleBB, 2, 0, 3, bbLower) < 3)
   {
      Print("ไม่สามารถคัดลอกข้อมูล Bollinger Bands");
      return false;
   }
   
   // คัดลอกข้อมูล ATR
   if(UseATR_SL)
   {
      if(CopyBuffer(handleATR, 0, 0, 2, atrValue) < 2)
      {
         Print("ไม่สามารถคัดลอกข้อมูล ATR");
         return false;
      }
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| ฟังก์ชันตรวจสอบสัญญาณการเทรด                                      |
//+------------------------------------------------------------------+
int GetTradeSignal()
{
   // ตรวจสอบสัญญาณ Stochastic
   bool stochBuySignal = CheckStochasticBuy();
   bool stochSellSignal = CheckStochasticSell();
   
   // ตรวจสอบสัญญาณ Bollinger Bands + Price Action
   bool bbBuySignal = CheckBollingerBuy();
   bool bbSellSignal = CheckBollingerSell();
   
   // รวมสัญญาณ
   if(stochBuySignal && bbBuySignal)
      return 1;  // Buy Signal
   
   if(stochSellSignal && bbSellSignal)
      return -1; // Sell Signal
   
   return 0; // No Signal
}

//+------------------------------------------------------------------+
//| ตรวจสอบสัญญาณ Stochastic Buy                                     |
//+------------------------------------------------------------------+
bool CheckStochasticBuy()
{
   // %K ตัดขึ้นเหนือ %D จากโซน Oversold
   bool crossOver = (stochMain[1] > stochSignal[1] && stochMain[2] <= stochSignal[2]);
   bool fromOversold = (stochMain[2] < StochOversold || stochSignal[2] < StochOversold);
   
   return (crossOver && fromOversold);
}

//+------------------------------------------------------------------+
//| ตรวจสอบสัญญาณ Stochastic Sell                                    |
//+------------------------------------------------------------------+
bool CheckStochasticSell()
{
   // %K ตัดลงใต้ %D จากโซน Overbought
   bool crossUnder = (stochMain[1] < stochSignal[1] && stochMain[2] >= stochSignal[2]);
   bool fromOverbought = (stochMain[2] > StochOverbought || stochSignal[2] > StochOverbought);
   
   return (crossUnder && fromOverbought);
}

//+------------------------------------------------------------------+
//| ตรวจสอบสัญญาณ Bollinger Bands Buy                                |
//+------------------------------------------------------------------+
bool CheckBollingerBuy()
{
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   
   if(CopyRates(_Symbol, PERIOD_CURRENT, 0, 3, rates) < 3)
      return false;
   
   // ราคาปิดต่ำกว่า Lower Band
   bool priceBelowLower = (rates[1].close < bbLower[1]);
   
   // ตรวจสอบ Price Action (Bullish Engulfing หรือ Pin Bar)
   bool bullishEngulfing = IsBullishEngulfing(rates);
   bool bullishPinBar = IsBullishPinBar(rates[1]);
   
   return (priceBelowLower && (bullishEngulfing || bullishPinBar));
}

//+------------------------------------------------------------------+
//| ตรวจสอบสัญญาณ Bollinger Bands Sell                               |
//+------------------------------------------------------------------+
bool CheckBollingerSell()
{
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   
   if(CopyRates(_Symbol, PERIOD_CURRENT, 0, 3, rates) < 3)
      return false;
   
   // ราคาปิดสูงกว่า Upper Band
   bool priceAboveUpper = (rates[1].close > bbUpper[1]);
   
   // ตรวจสอบ Price Action (Bearish Engulfing หรือ Pin Bar)
   bool bearishEngulfing = IsBearishEngulfing(rates);
   bool bearishPinBar = IsBearishPinBar(rates[1]);
   
   return (priceAboveUpper && (bearishEngulfing || bearishPinBar));
}

//+------------------------------------------------------------------+
//| ตรวจสอบรูปแบบ Bullish Engulfing                                  |
//+------------------------------------------------------------------+
bool IsBullishEngulfing(const MqlRates &rates[])
{
   // แท่งที่ 2 (ก่อนหน้า) เป็นแท่งแดง
   bool prevBearish = (rates[2].close < rates[2].open);
   
   // แท่งที่ 1 (ปัจจุบัน) เป็นแท่งเขียว
   bool currentBullish = (rates[1].close > rates[1].open);
   
   // แท่งเขียวกลืนแท่งแดง
   bool engulfing = (rates[1].open < rates[2].close && rates[1].close > rates[2].open);
   
   return (prevBearish && currentBullish && engulfing);
}

//+------------------------------------------------------------------+
//| ตรวจสอบรูปแบบ Bearish Engulfing                                  |
//+------------------------------------------------------------------+
bool IsBearishEngulfing(const MqlRates &rates[])
{
   // แท่งที่ 2 (ก่อนหน้า) เป็นแท่งเขียว
   bool prevBullish = (rates[2].close > rates[2].open);
   
   // แท่งที่ 1 (ปัจจุบัน) เป็นแท่งแดง
   bool currentBearish = (rates[1].close < rates[1].open);
   
   // แท่งแดงกลืนแท่งเขียว
   bool engulfing = (rates[1].open > rates[2].close && rates[1].close < rates[2].open);
   
   return (prevBullish && currentBearish && engulfing);
}

//+------------------------------------------------------------------+
//| ตรวจสอบรูปแบบ Bullish Pin Bar                                    |
//+------------------------------------------------------------------+
bool IsBullishPinBar(const MqlRates &rate)
{
   double bodySize = MathAbs(rate.close - rate.open);
   double upperWick = rate.high - MathMax(rate.close, rate.open);
   double lowerWick = MathMin(rate.close, rate.open) - rate.low;
   double totalRange = rate.high - rate.low;
   
   // หางล่างยาวกว่าตัวแท่ง 2 เท่า และหางบนสั้น
   bool longLowerWick = (lowerWick > bodySize * 2);
   bool shortUpperWick = (upperWick < bodySize * 0.5);
   bool significantWick = (lowerWick > totalRange * 0.6);
   
   return (longLowerWick && shortUpperWick && significantWick);
}

//+------------------------------------------------------------------+
//| ตรวจสอบรูปแบบ Bearish Pin Bar                                    |
//+------------------------------------------------------------------+
bool IsBearishPinBar(const MqlRates &rate)
{
   double bodySize = MathAbs(rate.close - rate.open);
   double upperWick = rate.high - MathMax(rate.close, rate.open);
   double lowerWick = MathMin(rate.close, rate.open) - rate.low;
   double totalRange = rate.high - rate.low;
   
   // หางบนยาวกว่าตัวแท่ง 2 เท่า และหางล่างสั้น
   bool longUpperWick = (upperWick > bodySize * 2);
   bool shortLowerWick = (lowerWick < bodySize * 0.5);
   bool significantWick = (upperWick > totalRange * 0.6);
   
   return (longUpperWick && shortLowerWick && significantWick);
}

//+------------------------------------------------------------------+
//| ฟังก์ชันเปิดออเดอร์ Buy                                          |
//+------------------------------------------------------------------+
void OpenBuyOrder()
{
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double sl = CalculateStopLoss(ORDER_TYPE_BUY, ask);
   double tp = CalculateTakeProfit(ORDER_TYPE_BUY, ask);
   
   // ปรับ SL และ TP ให้ถูกต้องตาม Tick Size
   sl = NormalizePrice(sl);
   tp = NormalizePrice(tp);
   
   if(trade.Buy(LotSize, _Symbol, ask, sl, tp, CommentOrder))
   {
      Print("✅ เปิดคำสั่ง BUY สำเร็จ - ราคา: ", ask, " SL: ", sl, " TP: ", tp);
      halfClosed = false;
   }
   else
   {
      Print("❌ ไม่สามารถเปิดคำสั่ง BUY - Error: ", GetLastError());
   }
}

//+------------------------------------------------------------------+
//| ฟังก์ชันเปิดออเดอร์ Sell                                         |
//+------------------------------------------------------------------+
void OpenSellOrder()
{
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double sl = CalculateStopLoss(ORDER_TYPE_SELL, bid);
   double tp = CalculateTakeProfit(ORDER_TYPE_SELL, bid);
   
   // ปรับ SL และ TP ให้ถูกต้องตาม Tick Size
   sl = NormalizePrice(sl);
   tp = NormalizePrice(tp);
   
   if(trade.Sell(LotSize, _Symbol, bid, sl, tp, CommentOrder))
   {
      Print("✅ เปิดคำสั่ง SELL สำเร็จ - ราคา: ", bid, " SL: ", sl, " TP: ", tp);
      halfClosed = false;
   }
   else
   {
      Print("❌ ไม่สามารถเปิดคำสั่ง SELL - Error: ", GetLastError());
   }
}

//+------------------------------------------------------------------+
//| คำนวณ Stop Loss                                                  |
//+------------------------------------------------------------------+
double CalculateStopLoss(ENUM_ORDER_TYPE orderType, double entryPrice)
{
   double sl = 0;
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   
   if(UseATR_SL && atrValue[0] > 0)
   {
      // ใช้ ATR สำหรับ Stop Loss
      double atrSL = atrValue[0] * ATR_Multiplier;
      
      if(orderType == ORDER_TYPE_BUY)
         sl = entryPrice - atrSL;
      else
         sl = entryPrice + atrSL;
   }
   else
   {
      // ใช้ Pips สำหรับ Stop Loss
      double slDistance = StopLoss_Pips * point * 10; // แปลง pips เป็น price
      
      if(orderType == ORDER_TYPE_BUY)
         sl = entryPrice - slDistance;
      else
         sl = entryPrice + slDistance;
   }
   
   return NormalizeDouble(sl, digits);
}

//+------------------------------------------------------------------+
//| คำนวณ Take Profit                                                |
//+------------------------------------------------------------------+
double CalculateTakeProfit(ENUM_ORDER_TYPE orderType, double entryPrice)
{
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   
   double tpDistance = TakeProfit_Pips * point * 10; // แปลง pips เป็น price
   
   double tp = 0;
   if(orderType == ORDER_TYPE_BUY)
      tp = entryPrice + tpDistance;
   else
      tp = entryPrice - tpDistance;
   
   return NormalizeDouble(tp, digits);
}

//+------------------------------------------------------------------+
//| ปรับราคาให้ตรงกับ Tick Size                                      |
//+------------------------------------------------------------------+
double NormalizePrice(double price)
{
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   
   return NormalizeDouble(MathRound(price / tickSize) * tickSize, digits);
}

//+------------------------------------------------------------------+
//| จัดการออเดอร์ที่เปิดอยู่                                         |
//+------------------------------------------------------------------+
void ManageOpenPositions()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket <= 0) continue;
      
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue;
      
      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double currentPrice = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? 
                            SymbolInfoDouble(_Symbol, SYMBOL_BID) : 
                            SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      
      double profit = PositionGetDouble(POSITION_PROFIT);
      double volume = PositionGetDouble(POSITION_VOLUME);
      
      // ปิดครึ่งหนึ่งเมื่อได้กำไรครึ่งทาง
      if(CloseHalfAtHalfProfit && !halfClosed)
      {
         double halfTP = (PositionGetDouble(POSITION_TP) - openPrice) / 2;
         bool reachedHalfProfit = false;
         
         if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
            reachedHalfProfit = (currentPrice >= openPrice + halfTP);
         else
            reachedHalfProfit = (currentPrice <= openPrice - halfTP);
         
         if(reachedHalfProfit && volume >= 0.02) // ตรวจสอบว่ามีขนาดพอปิดครึ่ง
         {
            double closeVolume = NormalizeDouble(volume / 2, 2);
            if(trade.PositionClosePartial(ticket, closeVolume))
            {
               Print("✅ ปิดครึ่งหนึ่งของออเดอร์ #", ticket, " Volume: ", closeVolume);
               halfClosed = true;
            }
         }
      }
      
      // Trailing Stop
      if(UseTrailingStop && profit > 0)
      {
         ApplyTrailingStop(ticket);
      }
   }
}

//+------------------------------------------------------------------+
//| ใช้ Trailing Stop                                               |
//+------------------------------------------------------------------+
void ApplyTrailingStop(ulong ticket)
{
   if(!PositionSelectByTicket(ticket)) return;
   
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double trailDistance = TrailingStop_Pips * point * 10;
   double trailStep = TrailingStep_Pips * point * 10;
   
   double currentSL = PositionGetDouble(POSITION_SL);
   double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
   
   ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
   
   double newSL = 0;
   bool modifySL = false;
   
   if(posType == POSITION_TYPE_BUY)
   {
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      newSL = bid - trailDistance;
      
      // อัพเดท SL เฉพาะเมื่อราคาเคลื่อนที่เพียงพอ
      if(newSL > currentSL + trailStep || currentSL == 0)
      {
         newSL = NormalizePrice(newSL);
         if(newSL > currentSL)
            modifySL = true;
      }
   }
   else // SELL
   {
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      newSL = ask + trailDistance;
      
      if(newSL < currentSL - trailStep || currentSL == 0)
      {
         newSL = NormalizePrice(newSL);
         if(newSL < currentSL || currentSL == 0)
            modifySL = true;
      }
   }
   
   if(modifySL)
   {
      double tp = PositionGetDouble(POSITION_TP);
      if(trade.PositionModify(ticket, newSL, tp))
      {
         Print("✅ อัพเดท Trailing Stop #", ticket, " SL ใหม่: ", newSL);
      }
   }
}

//+------------------------------------------------------------------+
//| ตรวจสอบว่ามีออเดอร์เปิดอยู่หรือไม่                               |
//+------------------------------------------------------------------+
bool HasOpenPosition(ENUM_ORDER_TYPE orderType)
{
   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket <= 0) continue;
      
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue;
      
      ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      
      if((orderType == ORDER_TYPE_BUY && posType == POSITION_TYPE_BUY) ||
         (orderType == ORDER_TYPE_SELL && posType == POSITION_TYPE_SELL))
      {
         return true;
      }
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| ตรวจสอบตัวกรองเวลา                                               |
//+------------------------------------------------------------------+
bool CheckTimeFilter()
{
   MqlDateTime timeNow;
   TimeGMT(timeNow);
   
   int currentHour = timeNow.hour;
   
   // ตรวจสอบว่าอยู่ในช่วงเวลาที่อนุญาต
   if(StartHour <= EndHour)
   {
      return (currentHour >= StartHour && currentHour < EndHour);
   }
   else // กรณีข้ามวัน เช่น 22:00 - 02:00
   {
      return (currentHour >= StartHour || currentHour < EndHour);
   }
}

//+------------------------------------------------------------------+
//| แสดงข้อมูลบนกราฟ                                                |
//+------------------------------------------------------------------+
void DisplayInfo()
{
   int totalPositions = 0;
   double totalProfit = 0;
   
   // นับจำนวนออเดอร์และกำไรรวม
   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket <= 0) continue;
      
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue;
      
      totalPositions++;
      totalProfit += PositionGetDouble(POSITION_PROFIT);
   }
   
   // คำนวณเวลาที่เหลือก่อนแท่งใหม่
   datetime currentBarTime = iTime(_Symbol, PERIOD_CURRENT, 0);
   datetime nextBarTime = currentBarTime + PeriodSeconds();
   datetime currentTime = TimeCurrent();
   int secondsRemaining = (int)(nextBarTime - currentTime);
   int minutesRemaining = secondsRemaining / 60;
   secondsRemaining = secondsRemaining % 60;
   
   // สร้างข้อความแสดงผล
   string info = "\n";
   info += "══════════════════════════════════\n";
   info += "    🤖 SCALPING EA - " + _Symbol + "\n";
   info += "══════════════════════════════════\n";
   info += "📊 จำนวนออเดอร์: " + IntegerToString(totalPositions) + "\n";
   info += "💰 กำไรรวม: " + DoubleToString(totalProfit, 2) + " " + AccountInfoString(ACCOUNT_CURRENCY) + "\n";
   info += "⏰ เวลาก่อนแท่งใหม่: " + IntegerToString(minutesRemaining) + ":" + 
           StringFormat("%02d", secondsRemaining) + "\n";
   info += "══════════════════════════════════\n";
   info += "📈 Stochastic: %K=" + DoubleToString(stochMain[0], 2) + 
           " / %D=" + DoubleToString(stochSignal[0], 2) + "\n";
   info += "📊 BB Upper: " + DoubleToString(bbUpper[0], (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS)) + "\n";
   info += "📊 BB Lower: " + DoubleToString(bbLower[0], (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS)) + "\n";
   
   if(UseATR_SL)
      info += "📉 ATR: " + DoubleToString(atrValue[0], (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS)) + "\n";
   
   info += "══════════════════════════════════\n";
   
   Comment(info);
}

//+------------------------------------------------------------------+
//| สิ้นสุดโปรแกรม                                                   |
//+------------------------------------------------------------------+
