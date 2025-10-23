//+------------------------------------------------------------------+
//|                                                GridReboot.mq5    |
//|                          Simple configurable Grid EA (MQL5)      |
//+------------------------------------------------------------------+
#property copyright "You"
#property version   "1.00"
#property strict

#include <Trade/Trade.mqh>
CTrade Trade;

//------------------------- Inputs ----------------------------------
enum Direction { DIR_BUY=0, DIR_SELL=1 };
enum GridType { GRID_AVG_CLOSE=0, GRID_TP=1 };
enum Trend { UPTREND=1, DOWNTREND=-1, SIDEWAY=0 };

input Direction  InpDirection        = DIR_BUY;   // หน้าเทรด: Buy / Sell
input GridType   InpGridType         = GRID_AVG_CLOSE; // ประเภทการเทรด Grid
input int        InpGridStepPoints   = 10000;       // ระยะห่างกริด (จุด)
input int        InpProfitTargetPts  = 3000;       // กำไรสะสม(จุด) เพื่อปิดทั้งชุด หรือ TP ของออเดอร์
input int        InpSlippage         = 20;        // Slippage (points)
input int        InpMaxOrders        = 0;         // จำกัดจำนวนออเดอร์ (0=ไม่จำกัด)
input long       InpMagic            = 20251023001;    // Magic number
input bool       InpCommentPriceLvl  = true;      // เขียนระดับราคาใน comment

// ความปลอดภัย: ป้องกันเปิดซ้ำระดับเดิม (เช็คช่วงกันชน 15% ของกริด)
input double     InpNoDupLevelRatio  = 0.0;      // 0.15*GridStep เป็นช่วงกันชน // 0 = ไม่ Block ช่วงราคา เข้าออเดอร์ได้เลย
input string     Input___Lot___Size___     = "=== Lot Size ===";
input double     InpLots             = 0.01;      // Lot เริ่มต้น
input double     InpMartingale = 1.1; // ตัวคูณ Martingale
input double     InpMaxLots = 0.2; // กำหนดขนาด Lots สูงสุด

input string   Input___New___Bar___Filter___     = "=== NEW BAR FILTER ===";
input bool       InpEnableNewBar = false; // เปิด/ปิด การเปิดออร์เดอร์เมื่อเปิดแท่งเทียนใหม่
input ENUM_TIMEFRAMES  InpNewBarTF = PERIOD_M1; // TF แท่งแท่งใหม่

input string   Input___Zone___Filter___     = "=== Zone FILTER ===";
input bool       InpEnablePriceZone = false; // เปิด/ปิด กรอบราคาออกการเปิดออเดอร์
input double     InpUpperPrice = 0.0; // กรอบราคาสูงสุด 0=ไม่กำหนด
input double     InpLowerPrice = 0.0; // กรอบราคาต่ำสูง 0=ไม่กำหนด

input string   Input___RSI___Filter___     = "=== RSI FILTER ===";
input bool             InpEnableRsiFilter = true; // เปิด/ปิด ตัวกรอง RSI Indicator
input ENUM_TIMEFRAMES  InpRsiTF = PERIOD_M1; // TF สำหรับ RSI Indicator
input int              InpRsiPeriod = 5; // RSI Period
input double           InpRsiOversold = 30.0; // RSI Oversold
input double           InpRsiOverbought = 70.0; // RSI Overbought

input string   Input___Stoch___Filter___     = "=== STOCH FILTER ===";
input bool             InpEnableStochFilter = false; // เปิด/ปิด ตัวกรอง Stoch Indicator
input ENUM_TIMEFRAMES  InpStochTF = PERIOD_M1; // TF สำหรับ Stoch Indicator
input int              InpStochK = 5; // Stock K
input int              InpStochD = 3; // Stock D
input int              InpStochSlowing = 3; // Stoch Slowing
input ENUM_MA_METHOD   InpStochMAMethod = MODE_SMA; // moving average method for stoch
input ENUM_STO_PRICE   InpStochPrice = STO_LOWHIGH; // calculation method (Low/High or Close/Close)
input double           InpStochOversold = 30.0; // Stoch Oversold
input double           InpStochOverbought = 70.0; // Stoch Overbought

input string   Input___Trend___Filter___     = "=== TREND FILTER ===";
input bool             InpEnableTrendFilter = false; // เปิด/ปิด ตัวกรองเทรนด์ด้วย EMA
input Trend            InpTradeFollowTrend = UPTREND; // เทรดตามเทรนด์
input ENUM_TIMEFRAMES  InpTrendTF = PERIOD_H1;   // TF สำหรับเทรนด์
input int              InpEmaFast = 50; // EMA เร็ว
input int              InpEmaSlow = 200; // EMA ช้า

//------------------------- State -----------------------------------
string Symb;
double PointV, TickSize;
double NoDupBand; // กันชนไม่ให้เปิดซ้ำระดับราคา
datetime      g_last_bar_time = 0;
int rsiHandle = INVALID_HANDLE;
int stochHandle = INVALID_HANDLE;
int emaFastHandle = INVALID_HANDLE;
int emaSlowHandle = INVALID_HANDLE;

/*bool IsNewBar(ENUM_TIMEFRAMES tf)
{
   MqlRates r[];
   if(CopyRates(_Symbol, tf, 0, 2, r) != 2) return false;
   if(g_last_bar_time != r[0].time)
   {
      g_last_bar_time = r[0].time;
      return true;
   }
   return false;
}*/

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
   // ดึง ticket ของ position ตามลำดับ index
   ulong ticket = PositionGetTicket(index);  // ✅ ไม่มีการเรียก GetPositionByIndex_UsingTicket
   if(ticket == 0) return false;

   // เลือก position ด้วย ticket
   if(!PositionSelectByTicket(ticket)) return false;

   // ตอนนี้สามารถอ่านข้อมูลได้
   // ตัวอย่าง:
   // string sym  = PositionGetString(POSITION_SYMBOL);
   // long   type = PositionGetInteger(POSITION_TYPE);
   return true;
}

//------------------------- Helpers ---------------------------------
bool IsOurPositionByIndex(int pos_index)
{
   //if(!PositionSelectByTicket(pos_index)) return false;
   if(!GetPositionByIndex_UsingTicket(pos_index)) return false;
   if(PositionGetString(POSITION_SYMBOL) != _Symbol) return false;
   if((long)PositionGetInteger(POSITION_MAGIC) != InpMagic) return false;
   return true;
}

int CountOurPositions()
{
   int total=0;
   for(int i=0;i<PositionsTotal();i++)
      if(IsOurPositionByIndex(i)) total++;
   return total;
}

double CalTagetPrice(double current_price, int points) // Buy -> ask, Sell -> bid
{
   // ดึงค่า Point Size ของ Symbol ปัจจุบัน
   double point_size = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   
   // คำนวณการเปลี่ยนแปลงของราคา
   double price_change = InpProfitTargetPts * point_size;
   
   //double current_price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   
   // คำนวณราคาเป้าหมาย
   double target_price = current_price + (InpDirection == DIR_BUY ? price_change : -price_change);
   
   // หากต้องการให้ราคาอยู่ในรูปที่ถูกต้องตาม Tick Size (แนะนำ)
   // ควรใช้ฟังก์ชัน NormailzeDouble() เพื่อปรับทศนิยมให้ถูกต้องตาม Symbol's Digits
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   return NormalizeDouble(target_price, digits);
}

bool IsBuyPosByIndex(int pos_index)
{
   //if(!PositionSelectByTicket(pos_index)) return false;
   if(!GetPositionByIndex_UsingTicket(pos_index)) return false;
   return (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY;
}

// ราคาของออเดอร์ล่าสุด (ตามเวลาเปิดล่าสุด) ของชุดนี้
bool GetLastOpenPrice(double &price_out)
{
   datetime latest=0; double p=0; bool found=false;
   for(int i=0;i<PositionsTotal();i++)
   {
      if(!IsOurPositionByIndex(i)) continue;
      datetime t = (datetime)PositionGetInteger(POSITION_TIME);
      if(t>latest) { latest=t; p=PositionGetDouble(POSITION_PRICE_OPEN); found=true; }
   }
   if(found) price_out=p;
   return found;
}

// เช็คมีออเดอร์อยู่ใกล้ระดับ targetPrice ภายใน NoDupBand หรือไม่
bool HasOrderNear(double targetPrice)
{
   for(int i=0;i<PositionsTotal();i++)
   {
      if(!IsOurPositionByIndex(i)) continue;
      double po = PositionGetDouble(POSITION_PRICE_OPEN);
      if(MathAbs(po - targetPrice) <= NoDupBand*_Point) return true;
   }
   return false;
}

// ผลรวม "กำไรเป็นจุด" (สุทธิเป็นจุดของทุกออเดอร์)
double SumNetPoints()
{
   double sumPts=0.0;
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   for(int i=0;i<PositionsTotal();i++)
   {
      if(!IsOurPositionByIndex(i)) continue;
      bool isBuy = IsBuyPosByIndex(i);
      double open = PositionGetDouble(POSITION_PRICE_OPEN);
      double pts  = isBuy ? (bid-open)/_Point : (open-ask)/_Point;
      sumPts += pts;
   }
   return sumPts;
}

bool CloseAll()
{
   bool ok=true;
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      if(!IsOurPositionByIndex(i)) continue;
      ulong ticket=(ulong)PositionGetInteger(POSITION_TICKET);
      ok &= Trade.PositionClose(ticket, InpSlippage);
      if(!ok) Print("Close failed ticket=", ticket, " err=", _LastError);
   }
   return ok;
}

bool OpenStarter(Direction dir)
{
   MqlTick tk; if(!SymbolInfoTick(Symb, tk)) return false;
   Trade.SetExpertMagicNumber(InpMagic);
   string cmt = InpCommentPriceLvl ? StringFormat("Grid start @%.2f", (dir==DIR_BUY?tk.ask:tk.bid)) : "";
   bool ok=false;
   
   double tpPrice = 0;
   if (InpGridType == GRID_TP) {
      if(dir==DIR_BUY) tpPrice = CalTagetPrice(tk.ask, InpProfitTargetPts);
      else tpPrice = CalTagetPrice(tk.bid, InpProfitTargetPts);
   }
   
   if(dir==DIR_BUY) ok = Trade.Buy(InpLots, Symb, tk.ask, 0, tpPrice, cmt);
   else             ok = Trade.Sell(InpLots, Symb, tk.bid, 0, tpPrice, cmt);
   if(!ok) Print("OpenStarter failed. err=", _LastError);
   return ok;
}

// เปิดกริดถัดไป “เฉพาะทิศทางที่สวนทางราคา”
// - Buy: รอให้ราคาลงต่ำกว่า lastOpen - GridStep
// - Sell: รอให้ราคาขึ้นสูงกว่า lastOpen + GridStep
bool MaybeOpenNext(Direction dir)
{
   if(InpMaxOrders>0 && CountOurPositions() >= InpMaxOrders) return false;

   double lastOpen;
   if(!GetLastOpenPrice(lastOpen)) return false;

   MqlTick tk; if(!SymbolInfoTick(Symb, tk)) return false;
   
   double tpPrice = 0;
   if (InpGridType == GRID_TP) {
      if(dir==DIR_BUY) tpPrice = CalTagetPrice(tk.ask, InpProfitTargetPts);
      else tpPrice = CalTagetPrice(tk.bid, InpProfitTargetPts);
   }
   
   double nextLots = NormalizeDouble(InpLots * pow(InpMartingale, CountOurPositions()), 2);
   if (nextLots > InpMaxLots) nextLots = InpMaxLots;

   if(dir==DIR_BUY)
   {
      double target = lastOpen - InpGridStepPoints*_Point;
      if(tk.ask <= target && !HasOrderNear(target))
      {
         Trade.SetExpertMagicNumber(InpMagic);
         string cmt = InpCommentPriceLvl ? StringFormat("Grid BUY @%.2f", tk.ask) : "";
         if(!Trade.Buy(nextLots, Symb, tk.ask, 0, tpPrice, cmt))
            Print("Buy grid failed. err=", _LastError);
         else return true;
      }
   }
   else // DIR_SELL
   {
      double target = lastOpen + InpGridStepPoints*_Point;
      if(tk.bid >= target && !HasOrderNear(target))
      {
         Trade.SetExpertMagicNumber(InpMagic);
         string cmt = InpCommentPriceLvl ? StringFormat("Grid SELL @%.2f", tk.bid) : "";
         if(!Trade.Sell(nextLots, Symb, tk.bid, 0, tpPrice, cmt))
            Print("Sell grid failed. err=", _LastError);
         else return true;
      }
   }
   return false;
}

/*
void FilterRsiAndStochCrossUpAndDown(bool& inputArray[]) // Buy & Sell Signal
{
   ArrayResize(inputArray, 2); // [isCrossUp, isCrossDown]
   // Initial
   inputArray[0] = false;
   inputArray[1] = false;
   
   // load indicator data for shifts 1 and 2 (1 = last closed, 2 = previous)
   double rsiArr[2];
   if(CopyBuffer(rsiHandle, 0, 1, 2, rsiArr) != 2)
     {
      Print("CopyBuffer RSI failed");
      return;
     }

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

   double rsi_last = rsiArr[0];   // shift 1 (last closed)
   double rsi_prev = rsiArr[1];   // shift 2

   double k_last = kArr[0];
   double k_prev = kArr[1];
   double d_last = dArr[0];
   double d_prev = dArr[1];

   // debug
   //PrintFormat("Bar %s | RSI prev=%.2f last=%.2f | K prev=%.2f last=%.2f | D prev=%.2f last=%.2f",
   //            TimeToString(closedBarTime,TIME_DATE|TIME_MINUTES), rsi_prev, rsi_last, k_prev,k_last,d_prev,d_last);

   // conditions
   bool rsi_cross_up   = (rsi_prev < InpRsiOversold) && (rsi_last > InpRsiOversold);
   bool rsi_cross_down = (rsi_prev > InpRsiOverbought) && (rsi_last < InpRsiOverbought);

   bool stoch_cross_up   = (k_prev < d_prev) && (k_last > d_last);
   bool stoch_cross_down = (k_prev > d_prev) && (k_last < d_last);
   
   bool is_cross_up = rsi_cross_up && stoch_cross_up;
   bool is_cross_down = rsi_cross_down && stoch_cross_down;
   
   inputArray[0] = is_cross_up;
   inputArray[1] = is_cross_down;
}
*/

void FilterRsiCrossUpAndDown(bool& inputArray[]) // Buy & Sell Signal
{
   ArrayResize(inputArray, 2); // [isCrossUp, isCrossDown]
   // Initial
   inputArray[0] = false;
   inputArray[1] = false;
   
   // load indicator data for shifts 1 and 2 (1 = last closed, 2 = previous)
   double rsiArr[2];
   if(CopyBuffer(rsiHandle, 0, 1, 2, rsiArr) != 2)
     {
      Print("CopyBuffer RSI failed");
      return;
     }

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

   double rsi_last = rsiArr[0];   // shift 1 (last closed)
   double rsi_prev = rsiArr[1];   // shift 2

   // debug
   //PrintFormat("Bar %s | RSI prev=%.2f last=%.2f | K prev=%.2f last=%.2f | D prev=%.2f last=%.2f",
   //            TimeToString(closedBarTime,TIME_DATE|TIME_MINUTES), rsi_prev, rsi_last, k_prev,k_last,d_prev,d_last);

   // conditions
   bool rsi_cross_up   = (rsi_prev < InpRsiOversold) && (rsi_last > InpRsiOversold);
   bool rsi_cross_down = (rsi_prev > InpRsiOverbought) && (rsi_last < InpRsiOverbought);
   
   inputArray[0] = rsi_cross_up;
   inputArray[1] = rsi_cross_down;
}

void FilterStochCrossUpAndDown(bool& inputArray[]) // Buy & Sell Signal
{
   ArrayResize(inputArray, 2); // [isCrossUp, isCrossDown]
   // Initial
   inputArray[0] = false;
   inputArray[1] = false;
   
   // load indicator data for shifts 1 and 2 (1 = last closed, 2 = previous)
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

   // debug
   //PrintFormat("Bar %s | RSI prev=%.2f last=%.2f | K prev=%.2f last=%.2f | D prev=%.2f last=%.2f",
   //            TimeToString(closedBarTime,TIME_DATE|TIME_MINUTES), rsi_prev, rsi_last, k_prev,k_last,d_prev,d_last);

   // conditions
   bool stoch_cross_up   = (k_prev < d_prev) && (k_last > d_last);
   bool stoch_cross_down = (k_prev > d_prev) && (k_last < d_last);
   
   inputArray[0] = stoch_cross_up;
   inputArray[1] = stoch_cross_down;
}

Trend FilterTrend() {
   //--- Trend filter
   //double emaVal[1];
   //if(CopyBuffer(emaHandle, 0, 0, 1, emaVal) < 1) return SIDEWAY;
   //double price = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   //bool upTrend = (price > emaVal[0]);
   //bool downTrend = (price < emaVal[0]);
   
   //double f = iMA(_Symbol, InpTrendTF, InpEmaFast, 0, MODE_EMA, PRICE_CLOSE);
   //double s = iMA(_Symbol, InpTrendTF, InpEmaSlow, 0, MODE_EMA, PRICE_CLOSE);
   
   //return (f > s) ? UPTREND: DOWNTREND;
   double fArr[1], sArr[1];
   if(CopyBuffer(emaFastHandle, 0, 1, 1, fArr) != 1) return SIDEWAY;
   if(CopyBuffer(emaSlowHandle, 0, 1, 1, sArr) != 1) return SIDEWAY;
   return (fArr[0] > sArr[0]) ? UPTREND : DOWNTREND;
}

bool ValidateZone() {
   double price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if (price >= InpUpperPrice && InpUpperPrice != 0.0) return false;
   else if (price <= InpLowerPrice && InpLowerPrice != 0.0) return false;
   
   return true;
}

void StartFirstOrder() {
   bool rsiFilterArray[];
   bool stochFilterArray[];
   bool isRsiCrossUp = false;
   bool isRsiCrossDown = false;
   bool isStochCrossUp = false;
   bool isStochCrossDown = false;
   FilterRsiCrossUpAndDown(rsiFilterArray); // Pass the array by reference
   FilterStochCrossUpAndDown(stochFilterArray); // Pass the array by reference
   isRsiCrossUp = rsiFilterArray[0];
   isRsiCrossDown = rsiFilterArray[1];
   isStochCrossUp = stochFilterArray[0];
   isStochCrossDown = stochFilterArray[1];
   
   Trend currentTrend = FilterTrend();
   
   bool isTradeZone = ValidateZone();
   bool isNewBar = IsNewBar(InpNewBarTF);
   
   if (InpEnableRsiFilter && InpDirection == DIR_BUY && !isRsiCrossUp) return;
   if (InpEnableRsiFilter && InpDirection == DIR_SELL && !isRsiCrossDown) return;
   if (InpEnableStochFilter && InpDirection == DIR_BUY && !isStochCrossUp) return;
   if (InpEnableStochFilter && InpDirection == DIR_SELL && !isStochCrossDown) return;
   if (InpEnableNewBar && !isNewBar) return;
   if (InpEnablePriceZone && !isTradeZone) return;
   if (InpEnableTrendFilter && currentTrend != InpTradeFollowTrend) return;
   OpenStarter(InpDirection);
}

//------------------------- EA events --------------------------------
int OnInit()
{
   Symb = _Symbol;
   PointV  = _Point;
   TickSize = SymbolInfoDouble(Symb, SYMBOL_TRADE_TICK_SIZE);
   NoDupBand = MathMax(1.0, InpNoDupLevelRatio * InpGridStepPoints); // หน่วย: points (ก่อนคูณ _Point)
   
   // create handles
   rsiHandle = iRSI(_Symbol, InpRsiTF, InpRsiPeriod, PRICE_CLOSE);
   stochHandle = iStochastic(_Symbol, InpStochTF,
                       InpStochK, InpStochD, InpStochSlowing,
                       InpStochMAMethod, InpStochPrice);
   emaFastHandle = iMA(_Symbol, InpTrendTF, InpEmaFast, 0, MODE_EMA, PRICE_CLOSE);
   emaSlowHandle = iMA(_Symbol, InpTrendTF, InpEmaSlow, 0, MODE_EMA, PRICE_CLOSE);
   if(rsiHandle == INVALID_HANDLE || stochHandle == INVALID_HANDLE || emaFastHandle == INVALID_HANDLE || emaSlowHandle == INVALID_HANDLE)
   {
      Print("Indicator handle creation failed!");
      return INIT_FAILED;
   }
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(rsiHandle!=INVALID_HANDLE) IndicatorRelease(rsiHandle);
   if(stochHandle!=INVALID_HANDLE) IndicatorRelease(stochHandle);
   if(emaFastHandle!=INVALID_HANDLE) IndicatorRelease(emaFastHandle);
   if(emaSlowHandle!=INVALID_HANDLE) IndicatorRelease(emaSlowHandle);
}

void OnTick()
{  

   // 1) ถ้าไม่มีออเดอร์ -> เปิดเริ่มชุด
   if(CountOurPositions()==0)
   {
      StartFirstOrder();
      return;
   }

   // 2) เงื่อนไขกำไรสะสมถึงเป้า (เป็น “จุดสุทธิรวม”)
   if (InpGridType == GRID_AVG_CLOSE) {
      double netPts = SumNetPoints();
      if(netPts >= InpProfitTargetPts)
      {
         // ปิดทั้งชุด แล้วเปิดตามทิศที่ตั้งไว้ (เริ่มชุดใหม่)
         if(CloseAll())
         {
            StartFirstOrder();
         }
         return; // รอบนี้จบ
      }
   }

   // 3) เปิดกริดถัดไปเมื่อราคาเดินทางสวนมาจนถึงระยะ GridStep จาก "ออเดอร์ล่าสุด"
   if (CountOurPositions() > 0) MaybeOpenNext(InpDirection);
   
   //Comment("Orders:" + CountOurPositions());
}

// (ถ้าต้องการความเสถียรเพิ่มเติม อาจย้ายบาง logic ไป OnTimer พร้อมตั้ง EventSetTimer)
