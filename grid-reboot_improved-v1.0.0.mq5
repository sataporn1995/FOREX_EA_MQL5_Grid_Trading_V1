//+------------------------------------------------------------------+
//|                                                GridReboot.mq5    |
//|                          Simple configurable Grid EA (MQL5)      |
//|                          Enhanced: Buy & Sell simultaneously     |
//+------------------------------------------------------------------+
#property copyright "You"
#property version   "2.00"
#property strict

#include <Trade/Trade.mqh>
CTrade Trade;

//------------------------- Inputs ----------------------------------
enum DirectionEnum { DIR_BUY=0, DIR_SELL=1, DIR_BOTH=2 };
enum GridTypeEnum { GRID_AVG_CLOSE=0, GRID_TP=1 };
enum TrendEnum { UPTREND=1, DOWNTREND=-1, SIDEWAY=0 };
enum SumNetEnum { SUM_NET_POINTS=0, SUM_NET_AMOUNT=1 };

input DirectionEnum InpDirection = DIR_BOTH; // หน้าเทรด: Buy / Sell / Both
input GridTypeEnum InpGridType = GRID_AVG_CLOSE; // ประเภทการเทรด Grid
input int InpGridStepPoints = 10000; // ระยะห่างกริด (จุด)
input int InpMaxOrders = 0; // จำกัดจำนวนออเดอร์ (0=ไม่จำกัด)

// ความปลอดภัย: ป้องกันเปิดซ้ำระดับเดิม (เช็คช่วงกันชน 15% ของกริด)
input double InpNoDupLevelRatio  = 0.0;      // 0.15*GridStep เป็นช่วงกันชน // 0 = ไม่ Block ช่วงราคา เข้าออเดอร์ได้เลย

input string Input___Profit___ = "=== Profit ==="; 
input SumNetEnum InpSumNetType = SUM_NET_AMOUNT;
input int InpProfitTargetPts = 3000; // กำไรสะสม (จุด) เพื่อปิดทั้งชุด หรือ TP ของออเดอร์
input double InpProfitTargetAmount = 10.0; // กำไรสะสม (เงิน) เพื่อปิดทั้งชุด หรือ TP ของออเดอร์

input string Input___Lot___Size___ = "=== Lot Size ===";
input double InpLots             = 0.01;      // Lot เริ่มต้น
input double InpMartingale = 1.1; // ตัวคูณ Martingale
input double InpMaxLots = 0.2; // กำหนดขนาด Lots สูงสุด

input string Input___New___Bar___Filter___ = "=== NEW BAR FILTER ===";
input bool InpEnableNewBar = false; // เปิด/ปิด การเปิดออร์เดอร์เมื่อเปิดแท่งเทียนใหม่
input ENUM_TIMEFRAMES  InpNewBarTF = PERIOD_M1; // TF แท่งแท่งใหม่

input string Input___Zone___Filter___ = "=== Zone FILTER ===";
input bool InpEnablePriceZone = false; // เปิด/ปิด กรอบราคาออกการเปิดออเดอร์
input double InpUpperPrice = 0.0; // กรอบราคาสูงสุด 0=ไม่กำหนด
input double InpLowerPrice = 0.0; // กรอบราคาต่ำสุด 0=ไม่กำหนด

input string Input___RSI___Filter___ = "=== RSI FILTER ===";
input bool InpEnableRsiFilter = true; // เปิด/ปิด ตัวกรอง RSI Indicator
input ENUM_TIMEFRAMES InpRsiTF = PERIOD_M1; // TF สำหรับ RSI Indicator
input int InpRsiPeriod = 14; // RSI Period
input double InpRsiOversold = 30.0; // RSI Oversold
input double InpRsiOverbought = 70.0; // RSI Overbought

input string Input___Stoch___Filter___ = "=== STOCH FILTER ===";
input bool InpEnableStochFilter = false; // เปิด/ปิด ตัวกรอง Stoch Indicator
input ENUM_TIMEFRAMES InpStochTF = PERIOD_M1; // TF สำหรับ Stoch Indicator
input int InpStochK = 5; // Stock K
input int InpStochD = 3; // Stock D
input int InpStochSlowing = 3; // Stoch Slowing
input ENUM_MA_METHOD InpStochMAMethod = MODE_SMA; // moving average method for stoch
input ENUM_STO_PRICE InpStochPrice = STO_LOWHIGH; // calculation method (Low/High or Close/Close)
input double InpStochOversold = 30.0; // Stoch Oversold
input double InpStochOverbought = 70.0; // Stoch Overbought

input string Input___Trend___Filter___ = "=== TREND FILTER ===";
input bool InpEnableTrendFilter = false; // เปิด/ปิด ตัวกรองเทรนด์ด้วย EMA
input TrendEnum InpTradeFollowTrend = UPTREND; // เทรดตามเทรนด์
input ENUM_TIMEFRAMES  InpTrendTF = PERIOD_H1;   // TF สำหรับเทรนด์
input int InpEmaFast = 50; // EMA เร็ว
input int InpEmaSlow = 150; // EMA ช้า

input string   Input___Other___ = "=== OTHER ===";
input long InpMagic = 20251101; // Magic number
input int InpSlippage = 20; // Slippage (points)
input bool InpCommentPriceLvl = true; // เขียนระดับราคาใน comment


//------------------------- State -----------------------------------
string Symb;
double PointV, TickSize;
double NoDupBand; // กันชนไม่ให้เปิดซ้ำระดับราคา
datetime      g_last_bar_time = 0;
int rsiHandle = INVALID_HANDLE;
int stochHandle = INVALID_HANDLE;
int emaFastHandle = INVALID_HANDLE;
int emaSlowHandle = INVALID_HANDLE;

bool IsNewBar(ENUM_TIMEFRAMES tf)
{
   static datetime last_time[9]; // พอสำหรับ TF ยอดฮิต; หรือ map เอง
   int idx = (int)tf % 9;        // ทางลัดแบบง่าย
   MqlRates r[]; if(CopyRates(_Symbol, tf, 0, 2, r) != 2) return false;
   if(last_time[idx] != r[0].time){ last_time[idx]=r[0].time; return true; }
   return false;
}

// ดึงทีละ ticket โดยใช้ index แล้วเลือกด้วย ticket แทน
bool GetPositionByIndex_UsingTicket(int index)
{
   ulong ticket = PositionGetTicket(index);
   if(ticket == 0) return false;
   if(!PositionSelectByTicket(ticket)) return false;
   return true;
}

//------------------------- Helpers ---------------------------------
bool IsOurPositionByIndex(int pos_index)
{
   if(!GetPositionByIndex_UsingTicket(pos_index)) return false;
   if(PositionGetString(POSITION_SYMBOL) != _Symbol) return false;
   if((long)PositionGetInteger(POSITION_MAGIC) != InpMagic) return false;
   return true;
}

// นับออเดอร์ตาม Position Type (Buy หรือ Sell)
int CountOurPositions(ENUM_POSITION_TYPE posType = -1)
{
   int total=0;
   for(int i=0;i<PositionsTotal();i++)
   {
      if(!IsOurPositionByIndex(i)) continue;
      
      // ถ้าระบุ posType ให้นับเฉพาะ type นั้น
      if(posType >= 0)
      {
         ENUM_POSITION_TYPE currentType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
         if(currentType != posType) continue;
      }
      
      total++;
   }
   return total;
}

double CalTagetPrice(double current_price, int points, bool isBuy)
{
   double point_size = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double price_change = points * point_size;
   double target_price = current_price + (isBuy ? price_change : -price_change);
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   return NormalizeDouble(target_price, digits);
}

bool IsBuyPosByIndex(int pos_index)
{
   if(!GetPositionByIndex_UsingTicket(pos_index)) return false;
   return (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY;
}

// ราคาของออเดอร์ล่าสุด (ตามเวลาเปิดล่าสุด) ตาม Position Type
bool GetLastOpenPrice(double &price_out, ENUM_POSITION_TYPE posType)
{
   datetime latest=0; double p=0; bool found=false;
   for(int i=0;i<PositionsTotal();i++)
   {
      if(!IsOurPositionByIndex(i)) continue;
      
      ENUM_POSITION_TYPE currentType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      if(currentType != posType) continue;
      
      datetime t = (datetime)PositionGetInteger(POSITION_TIME);
      if(t>latest) { latest=t; p=PositionGetDouble(POSITION_PRICE_OPEN); found=true; }
   }
   if(found) price_out=p;
   return found;
}

// เช็คมีออเดอร์อยู่ใกล้ระดับ targetPrice ภายใน NoDupBand หรือไม่ (ตาม Position Type)
bool HasOrderNear(double targetPrice, ENUM_POSITION_TYPE posType)
{
   for(int i=0;i<PositionsTotal();i++)
   {
      if(!IsOurPositionByIndex(i)) continue;
      
      ENUM_POSITION_TYPE currentType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      if(currentType != posType) continue;
      
      double po = PositionGetDouble(POSITION_PRICE_OPEN);
      if(MathAbs(po - targetPrice) <= NoDupBand*_Point) return true;
   }
   return false;
}

// ผลรวม "กำไรเป็นจุด" ตาม Position Type
double SumNetPoints(ENUM_POSITION_TYPE posType = -1)
{
   double sumPts=0.0;
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   for(int i=0;i<PositionsTotal();i++)
   {
      if(!IsOurPositionByIndex(i)) continue;
      
      bool isBuy = IsBuyPosByIndex(i);
      ENUM_POSITION_TYPE currentType = isBuy ? POSITION_TYPE_BUY : POSITION_TYPE_SELL;
      
      // ถ้าระบุ posType ให้คำนวณเฉพาะ type นั้น
      if(posType >= 0 && currentType != posType) continue;
      
      double open = PositionGetDouble(POSITION_PRICE_OPEN);
      double pts  = isBuy ? (bid-open)/_Point : (open-ask)/_Point;
      sumPts += pts;
   }
   return sumPts;
}

// ผลรวมกำไรเป็นเงินจริง ตาม Position Type
double SumNetProfit(ENUM_POSITION_TYPE posType = -1)
{
   double sumProfit = 0.0;

   for(int i = 0; i < PositionsTotal(); i++)
   {
      if(!GetPositionByIndex_UsingTicket(i)) continue;

      string posSymbol = PositionGetString(POSITION_SYMBOL);
      if(posSymbol != _Symbol) continue;

      if(!IsOurPositionByIndex(i)) continue;
      
      // ถ้าระบุ posType ให้คำนวณเฉพาะ type นั้น
      if(posType >= 0)
      {
         ENUM_POSITION_TYPE currentType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
         if(currentType != posType) continue;
      }

      double posProfit = PositionGetDouble(POSITION_PROFIT);
      sumProfit += posProfit;
   }

   return sumProfit;
}

// ปิดออเดอร์ทั้งหมด หรือเฉพาะ Position Type ที่ระบุ
bool CloseAll(ENUM_POSITION_TYPE posType = -1)
{
   bool ok=true;
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      if(!IsOurPositionByIndex(i)) continue;
      
      // ถ้าระบุ posType ให้ปิดเฉพาะ type นั้น
      if(posType >= 0)
      {
         ENUM_POSITION_TYPE currentType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
         if(currentType != posType) continue;
      }
      
      ulong ticket=(ulong)PositionGetInteger(POSITION_TICKET);
      ok &= Trade.PositionClose(ticket, InpSlippage);
      if(!ok) Print("Close failed ticket=", ticket, " err=", _LastError);
   }
   return ok;
}

bool OpenStarter(DirectionEnum dir)
{
   MqlTick tk; if(!SymbolInfoTick(Symb, tk)) return false;
   Trade.SetExpertMagicNumber(InpMagic);
   
   bool ok=false;
   
   if(dir==DIR_BUY || dir==DIR_BOTH)
   {
      double tpPrice = 0;
      if (InpGridType == GRID_TP)
         tpPrice = CalTagetPrice(tk.ask, InpProfitTargetPts, true);
      
      string cmt = InpCommentPriceLvl ? StringFormat("Grid BUY start @%.2f", tk.ask) : "";
      ok = Trade.Buy(InpLots, Symb, tk.ask, 0, tpPrice, cmt);
      if(!ok) Print("OpenStarter BUY failed. err=", _LastError);
   }
   
   if(dir==DIR_SELL || dir==DIR_BOTH)
   {
      double tpPrice = 0;
      if (InpGridType == GRID_TP)
         tpPrice = CalTagetPrice(tk.bid, InpProfitTargetPts, false);
      
      string cmt = InpCommentPriceLvl ? StringFormat("Grid SELL start @%.2f", tk.bid) : "";
      ok = Trade.Sell(InpLots, Symb, tk.bid, 0, tpPrice, cmt);
      if(!ok) Print("OpenStarter SELL failed. err=", _LastError);
   }
   
   return ok;
}

// เปิดกริดถัดไป ตาม Position Type
bool MaybeOpenNext(ENUM_POSITION_TYPE posType)
{
   if(InpMaxOrders>0 && CountOurPositions(posType) >= InpMaxOrders) return false;

   double lastOpen;
   if(!GetLastOpenPrice(lastOpen, posType)) return false;

   MqlTick tk; if(!SymbolInfoTick(Symb, tk)) return false;
   
   double nextLots = NormalizeDouble(InpLots * pow(InpMartingale, CountOurPositions(posType)), 2);
   if (nextLots > InpMaxLots) nextLots = InpMaxLots;

   if(posType == POSITION_TYPE_BUY)
   {
      double target = lastOpen - InpGridStepPoints*_Point;
      if(tk.ask <= target && !HasOrderNear(target, posType))
      {
         double tpPrice = 0;
         if (InpGridType == GRID_TP)
            tpPrice = CalTagetPrice(tk.ask, InpProfitTargetPts, true);
            
         Trade.SetExpertMagicNumber(InpMagic);
         string cmt = InpCommentPriceLvl ? StringFormat("Grid BUY @%.2f", tk.ask) : "";
         if(!Trade.Buy(nextLots, Symb, tk.ask, 0, tpPrice, cmt))
            Print("Buy grid failed. err=", _LastError);
         else return true;
      }
   }
   else if(posType == POSITION_TYPE_SELL)
   {
      double target = lastOpen + InpGridStepPoints*_Point;
      if(tk.bid >= target && !HasOrderNear(target, posType))
      {
         double tpPrice = 0;
         if (InpGridType == GRID_TP)
            tpPrice = CalTagetPrice(tk.bid, InpProfitTargetPts, false);
            
         Trade.SetExpertMagicNumber(InpMagic);
         string cmt = InpCommentPriceLvl ? StringFormat("Grid SELL @%.2f", tk.bid) : "";
         if(!Trade.Sell(nextLots, Symb, tk.bid, 0, tpPrice, cmt))
            Print("Sell grid failed. err=", _LastError);
         else return true;
      }
   }
   return false;
}

void FilterRsiCrossUpAndDown(bool& inputArray[])
{
   ArrayResize(inputArray, 2);
   inputArray[0] = false;
   inputArray[1] = false;
   
   double rsiArr[2];
   if(CopyBuffer(rsiHandle, 0, 1, 2, rsiArr) != 2)
   {
      Print("CopyBuffer RSI failed");
      return;
   }

   double rsi_last = rsiArr[0];
   double rsi_prev = rsiArr[1];

   bool rsi_cross_up   = (rsi_prev < InpRsiOversold) && (rsi_last > InpRsiOversold);
   bool rsi_cross_down = (rsi_prev > InpRsiOverbought) && (rsi_last < InpRsiOverbought);
   
   inputArray[0] = rsi_cross_up;
   inputArray[1] = rsi_cross_down;
}

void FilterStochCrossUpAndDown(bool& inputArray[])
{
   ArrayResize(inputArray, 2);
   inputArray[0] = false;
   inputArray[1] = false;
   
   double kArr[2], dArr[2];
   if(CopyBuffer(stochHandle, 0, 1, 2, kArr) != 2)
   {
      Print("CopyBuffer Stoch K failed");
      return;
   }
   if(CopyBuffer(stochHandle, 1, 1, 2, dArr) != 2)
   {
      Print("CopyBuffer Stoch D failed");
      return;
   }

   double k_last = kArr[0];
   double k_prev = kArr[1];
   double d_last = dArr[0];
   double d_prev = dArr[1];

   bool stoch_cross_up   = (k_prev < d_prev) && (k_last > d_last);
   bool stoch_cross_down = (k_prev > d_prev) && (k_last < d_last);
   
   inputArray[0] = stoch_cross_up;
   inputArray[1] = stoch_cross_down;
}

TrendEnum FilterTrend()
{
   double fArr[1], sArr[1];
   if(CopyBuffer(emaFastHandle, 0, 1, 1, fArr) != 1) return SIDEWAY;
   if(CopyBuffer(emaSlowHandle, 0, 1, 1, sArr) != 1) return SIDEWAY;
   return (fArr[0] > sArr[0]) ? UPTREND : DOWNTREND;
}

bool ValidateZone(DirectionEnum dir)
{
   double price = SymbolInfoDouble(_Symbol, dir == DIR_BUY ? SYMBOL_ASK: SYMBOL_BID);
   if (price >= InpUpperPrice && InpUpperPrice != 0.0 && dir == DIR_BUY) return false;
   else if (price <= InpLowerPrice && InpLowerPrice != 0.0 && dir == DIR_SELL) return false;
   else if (price <= InpLowerPrice || price >= InpUpperPrice) return false;
   return true;
}

/*
bool ValidateBuyZone()
{
   double price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   if (price >= InpUpperPrice && InpUpperPrice != 0.0) return false;
   return true;
}

bool ValidateSellZone()
{
   double price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if (price <= InpLowerPrice && InpLowerPrice != 0.0) return false;
   return true;
}
*/

// ตรวจสอบว่าควรเปิดออเดอร์หรือไม่ ตามทิศทาง
bool ShouldOpenOrder(DirectionEnum dir)
{
   bool rsiFilterArray[];
   bool stochFilterArray[];
   FilterRsiCrossUpAndDown(rsiFilterArray);
   FilterStochCrossUpAndDown(stochFilterArray);
   
   bool isRsiCrossUp = rsiFilterArray[0];
   bool isRsiCrossDown = rsiFilterArray[1];
   bool isStochCrossUp = stochFilterArray[0];
   bool isStochCrossDown = stochFilterArray[1];
   
   TrendEnum currentTrend = FilterTrend();
   bool isTradeZone = ValidateZone(dir);
   bool isNewBar = IsNewBar(InpNewBarTF);
   
   // Filter checks
   if (InpEnableNewBar && !isNewBar) return false;
   if (InpEnablePriceZone && !isTradeZone) return false;
   if (InpEnableTrendFilter && currentTrend != InpTradeFollowTrend) return false;
   
   // Direction-specific filters
   if (dir == DIR_BUY || dir == DIR_BOTH)
   {
      if (InpEnableRsiFilter && !isRsiCrossUp) 
      {
         if(dir == DIR_BUY) return false;
         // ถ้าเป็น BOTH ให้ข้ามเฉพาะ BUY
      }
      if (InpEnableStochFilter && !isStochCrossUp)
      {
         if(dir == DIR_BUY) return false;
      }
   }
   
   if (dir == DIR_SELL || dir == DIR_BOTH)
   {
      if (InpEnableRsiFilter && !isRsiCrossDown)
      {
         if(dir == DIR_SELL) return false;
      }
      if (InpEnableStochFilter && !isStochCrossDown)
      {
         if(dir == DIR_SELL) return false;
      }
   }
   
   return true;
}

void StartFirstOrder()
{
   if(!ShouldOpenOrder(InpDirection)) return;
   OpenStarter(InpDirection);
}

//------------------------- EA events --------------------------------
int OnInit()
{
   Symb = _Symbol;
   PointV  = _Point;
   TickSize = SymbolInfoDouble(Symb, SYMBOL_TRADE_TICK_SIZE);
   NoDupBand = MathMax(1.0, InpNoDupLevelRatio * InpGridStepPoints);
   
   // create handles
   rsiHandle = iRSI(_Symbol, InpRsiTF, InpRsiPeriod, PRICE_CLOSE);
   stochHandle = iStochastic(_Symbol, InpStochTF,
                       InpStochK, InpStochD, InpStochSlowing,
                       InpStochMAMethod, InpStochPrice);
   emaFastHandle = iMA(_Symbol, InpTrendTF, InpEmaFast, 0, MODE_EMA, PRICE_CLOSE);
   emaSlowHandle = iMA(_Symbol, InpTrendTF, InpEmaSlow, 0, MODE_EMA, PRICE_CLOSE);
   
   if(rsiHandle == INVALID_HANDLE || stochHandle == INVALID_HANDLE || 
      emaFastHandle == INVALID_HANDLE || emaSlowHandle == INVALID_HANDLE)
   {
      Print("Indicator handle creation failed!");
      return INIT_FAILED;
   }
   
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   if(rsiHandle!=INVALID_HANDLE) IndicatorRelease(rsiHandle);
   if(stochHandle!=INVALID_HANDLE) IndicatorRelease(stochHandle);
   if(emaFastHandle!=INVALID_HANDLE) IndicatorRelease(emaFastHandle);
   if(emaSlowHandle!=INVALID_HANDLE) IndicatorRelease(emaSlowHandle);
}

void OnTick()
{  
   // 1) ถ้าไม่มีออเดอร์เลย -> เปิดเริ่มชุด
   int totalPositions = CountOurPositions();
   
   if(totalPositions == 0)
   {
      StartFirstOrder();
      return;
   }

   // 2) เงื่อนไขกำไรสะสมถึงเป้า (แยกตาม Position Type)
   if (InpGridType == GRID_AVG_CLOSE)
   {
      // ตรวจสอบ BUY positions
      if(InpDirection == DIR_BUY || InpDirection == DIR_BOTH)
      {
         if(CountOurPositions(POSITION_TYPE_BUY) > 0)
         {
            double netProfit = InpSumNetType == SUM_NET_POINTS ? 
                              SumNetPoints(POSITION_TYPE_BUY) : 
                              SumNetProfit(POSITION_TYPE_BUY);
            double targetProfit = InpSumNetType == SUM_NET_POINTS ? 
                                 InpProfitTargetPts : InpProfitTargetAmount;
            
            if(netProfit >= targetProfit)
            {
               if(CloseAll(POSITION_TYPE_BUY))
               {
                  Print("Closed all BUY positions with profit: ", netProfit);
                  if(InpDirection == DIR_BUY)
                     StartFirstOrder();
               }
            }
         }
      }
      
      // ตรวจสอบ SELL positions
      if(InpDirection == DIR_SELL || InpDirection == DIR_BOTH)
      {
         if(CountOurPositions(POSITION_TYPE_SELL) > 0)
         {
            double netProfit = InpSumNetType == SUM_NET_POINTS ? 
                              SumNetPoints(POSITION_TYPE_SELL) : 
                              SumNetProfit(POSITION_TYPE_SELL);
            double targetProfit = InpSumNetType == SUM_NET_POINTS ? 
                                 InpProfitTargetPts : InpProfitTargetAmount;
            
            if(netProfit >= targetProfit)
            {
               if(CloseAll(POSITION_TYPE_SELL))
               {
                  Print("Closed all SELL positions with profit: ", netProfit);
                  if(InpDirection == DIR_SELL)
                     StartFirstOrder();
               }
            }
         }
      }
   }

   // 3) เปิดกริดถัดไป
   if(InpDirection == DIR_BUY || InpDirection == DIR_BOTH)
   {
      if(CountOurPositions(POSITION_TYPE_BUY) > 0)
         MaybeOpenNext(POSITION_TYPE_BUY);
   }
   
   if(InpDirection == DIR_SELL || InpDirection == DIR_BOTH)
   {
      if(CountOurPositions(POSITION_TYPE_SELL) > 0)
         MaybeOpenNext(POSITION_TYPE_SELL);
   }
   
   // แสดงข้อมูลบน Chart
   int buyOrders = CountOurPositions(POSITION_TYPE_BUY);
   int sellOrders = CountOurPositions(POSITION_TYPE_SELL);
   Comment(StringFormat("Buy Orders: %d | Sell Orders: %d | Total: %d", 
           buyOrders, sellOrders, totalPositions));
}
