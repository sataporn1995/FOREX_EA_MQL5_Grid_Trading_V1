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
//enum TradeSide
//{
//   BUY_ONLY = 0,
//   SELL_ONLY = 1,
//   BOTH_SIDES = 2
//};

input string   Inp___Trend___     = "=== TREND SETTINGS ===";
input int      InpFastEMA         = 50;          // EMA สั้น (เช็คเทรนด์ + จุดเข้า)
input int      InpSlowEMA         = 200;         // EMA ยาว (เช็คเทรนด์)
input ENUM_TIMEFRAMES InpTrendTF  = PERIOD_H1;   // TF ใช้เช็คเทรนด์ (D1/H4/H1/M30/M15/ฯลฯ)

input string   Inp___Side___      = "=== SIDE CONTROL ===";
//input TradeSide InpTradeSide      = BOTH_SIDES;  // Buy only / Sell only / Both
input Direction  InpDirection        = DIR_BUY;   // หน้าเทรด: Buy / Sell
input double     InpLots             = 0.01;      // Lot ต่อออเดอร์
input int        InpGridStepPoints   = 400;       // ระยะห่างกริด (จุด)
input int        InpProfitTargetPts  = 400;       // กำไรสะสม(จุด) เพื่อปิดทั้งชุด
input int        InpSlippage         = 20;        // Slippage (points)
input int        InpMaxOrders        = 0;         // จำกัดจำนวนออเดอร์ (0=ไม่จำกัด)
input long       InpMagic            = 660077;    // Magic number
input bool       InpCommentPriceLvl  = true;      // เขียนระดับราคาใน comment

// ความปลอดภัย: ป้องกันเปิดซ้ำระดับเดิม (เช็คช่วงกันชน 15% ของกริด)
input double     InpNoDupLevelRatio  = 0.0;      // 0.15*GridStep เป็นช่วงกันชน // 0 = ไม่ Block ช่วงราคา เข้าออเดอร์ได้เลย


input bool     InpUseCloseSignal  = true;        // ต้องการแท่งปิดยืนยันทิศ (bullish/bearish) หรือไม่
input double   InpMaxDistancePts  = 100.0;       // ระยะ "เข้าใกล้" EMA สั้น (หน่วย points)

//------------------------- State -----------------------------------
string Symb;
double PointV, TickSize;
double NoDupBand; // กันชนไม่ให้เปิดซ้ำระดับราคา
//--- Globals
//CTrade         trade;
int            hEMAfastTrend = INVALID_HANDLE;
int            hEMAslowTrend = INVALID_HANDLE;
int            hEMAfastEntry = INVALID_HANDLE;

bool GetBufferValue(int handle, int shift, double &val)
{
   double buf[];
   if(CopyBuffer(handle, 0, shift, 1, buf) < 1) return false;
   val = buf[0];
   return true;
}

// slope of EMA fast on trend TF (optional for robustness)
double SlopeFastTrend(int lookback=1)
{
   double a,b;
   if(!GetBufferValue(hEMAfastTrend, 0, a)) return 0.0;
   if(!GetBufferValue(hEMAfastTrend, lookback, b)) return 0.0;
   return (a-b);
}

// return trend: 1=uptrend, -1=downtrend, 0=sideway
int GetTrend()
{
   double emaF, emaS;
   if(!GetBufferValue(hEMAfastTrend, 0, emaF)) return 0;
   if(!GetBufferValue(hEMAslowTrend, 0, emaS)) return 0;

   if(emaF > emaS) return 1;
   if(emaF < emaS) return -1;
   return 0;
}

// Check if price pulled back near EMA fast (entry TF)
bool IsNearFastEMA(int dir, double &emaFastNow)
{
   if(!GetBufferValue(hEMAfastEntry, 0, emaFastNow)) return false;

   double price = (dir>0 ? SymbolInfoDouble(_Symbol, SYMBOL_BID)
                         : SymbolInfoDouble(_Symbol, SYMBOL_ASK));
   double distPts = MathAbs(price - emaFastNow)/_Point;

   if(distPts <= InpMaxDistancePts)
      return true;

   return false;
}

// Candle confirmation (simple): bullish for buy, bearish for sell
bool CloseConfirmation(int dir)
{
   if(!InpUseCloseSignal) return true;

   double open0 = iOpen(_Symbol, _Period, 1);
   double close0= iClose(_Symbol, _Period, 1);
   if(dir>0) return (close0 > open0);   // bullish bar
   else      return (close0 < open0);   // bearish bar
}

int CountOpenPositions(int dir=0) // 0=all, 1=buy, -1=sell
{
   int total=0;
   for(int i=0;i<PositionsTotal();i++)
   {
      if(PositionGetTicket(i))
      {
         string sym = PositionGetString(POSITION_SYMBOL);
         ulong  mg  = (ulong)PositionGetInteger(POSITION_MAGIC);
         int    tp  = (int)PositionGetInteger(POSITION_TYPE);
         if(sym==_Symbol && mg==InpMagic)
         {
            if(dir==0) total++;
            else if(dir==1 && tp==POSITION_TYPE_BUY) total++;
            else if(dir==-1 && tp==POSITION_TYPE_SELL) total++;
         }
      }
   }
   return total;
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
bool IsOurPosition(int index)
{
   if(!GetPositionByIndex_UsingTicket(index)) return false;
   if(PositionGetString(POSITION_SYMBOL) != Symb) return false;
   if(PositionGetInteger(POSITION_MAGIC) != InpMagic) return false;
   return true;
}

int CountOurPositions()
{
   int total=0;
   for(int i=0;i<PositionsTotal();i++)
      if(IsOurPosition(i)) total++;
   return total;
}

bool IsBuyPos(int index)
{
   if(!GetPositionByIndex_UsingTicket(index)) return false;
   return (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY;
}

// ราคาของออเดอร์ล่าสุด (ตามเวลาเปิดล่าสุด) ของชุดนี้
bool GetLastOpenPrice(double &price_out)
{
   datetime latest=0;
   double   p     = 0.0;
   bool     found = false;
   for(int i=0;i<PositionsTotal();i++)
   {
      if(!IsOurPosition(i)) continue;
      datetime t = (datetime)PositionGetInteger(POSITION_TIME);
      if(t>latest)
      {
         latest = t;
         p = PositionGetDouble(POSITION_PRICE_OPEN);
         found = true;
      }
   }
   if(found) price_out = p;
   return found;
}

// เช็คมีออเดอร์อยู่ใกล้ระดับ targetPrice ภายใน NoDupBand หรือไม่
bool HasOrderNear(double targetPrice)
{
   for(int i=0;i<PositionsTotal();i++)
   {
      if(!IsOurPosition(i)) continue;
      double po = PositionGetDouble(POSITION_PRICE_OPEN);
      if(MathAbs(po - targetPrice) <= NoDupBand*_Point) return true;
   }
   return false;
}

// ผลรวม "กำไรเป็นจุด" (สุทธิเป็นจุดของทุกออเดอร์)
double SumNetPoints()
{
   double sumPts=0.0;
   double bid = SymbolInfoDouble(Symb, SYMBOL_BID);
   double ask = SymbolInfoDouble(Symb, SYMBOL_ASK);
   for(int i=0;i<PositionsTotal();i++)
   {
      if(!IsOurPosition(i)) continue;
      bool isBuy = IsBuyPos(i);
      double open = PositionGetDouble(POSITION_PRICE_OPEN);
      double pts  = 0.0;
      if(isBuy)  pts = (bid - open)/_Point;  // ใช้ bid สำหรับปิด buy
      else       pts = (open - ask)/_Point;  // ใช้ ask สำหรับปิด sell
      sumPts += pts;
   }
   return sumPts;
}

bool CloseAll()
{
   bool ok=true;
   // ปิดให้หมดทั้งชุดของ Symbol+Magic
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      if(!IsOurPosition(i)) continue;
      ulong ticket = (ulong)PositionGetInteger(POSITION_TICKET);
      ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      double lots = PositionGetDouble(POSITION_VOLUME);
      if(type==POSITION_TYPE_BUY)
         ok &= Trade.PositionClose(ticket, InpSlippage);
      else
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
   if(dir==DIR_BUY) ok = Trade.Buy(InpLots, Symb, tk.ask, 0, 0, cmt);
   else             ok = Trade.Sell(InpLots, Symb, tk.bid, 0, 0, cmt);
   if(!ok) Print("OpenStarter failed. err=", _LastError);
   return ok;
}

// เปิดกริดถัดไป “เฉพาะทิศทางที่สวนทางราคา”
// - Buy: รอให้ราคาลงต่ำกว่า lastOpen - GridStep
// - Sell: รอให้ราคาขึ้นสูงกว่า lastOpen + GridStep
bool MaybeOpenNext(Direction dir)
{
   if(InpMaxOrders>0 && CountOurPositions() >= InpMaxOrders) return false;

   int trend = GetTrend();
   if(trend==0) return false; // sideway -> no trade
   
   // Pullback near EMA fast on entry TF
   double emaFastNow=0;
   if(!IsNearFastEMA(trend, emaFastNow) && CountOpenPositions(dir)==0) return false;

   double lastOpen;
   if(!GetLastOpenPrice(lastOpen)) return false;

   MqlTick tk; if(!SymbolInfoTick(Symb, tk)) return false;

   if(dir==DIR_BUY && trend==1)
   {
      double target = lastOpen - InpGridStepPoints*_Point;
      if(tk.ask <= target && !HasOrderNear(target))
      {
         Trade.SetExpertMagicNumber(InpMagic);
         string cmt = InpCommentPriceLvl ? StringFormat("Grid BUY @%.2f", tk.ask) : "";
         if(!Trade.Buy(InpLots, Symb, tk.ask, 0, 0, cmt))
            Print("Buy grid failed. err=", _LastError);
         else return true;
      }
   }
   else if(dir==DIR_SELL && trend==-1) // DIR_SELL
   {
      double target = lastOpen + InpGridStepPoints*_Point;
      if(tk.bid >= target && !HasOrderNear(target))
      {
         Trade.SetExpertMagicNumber(InpMagic);
         string cmt = InpCommentPriceLvl ? StringFormat("Grid SELL @%.2f", tk.bid) : "";
         if(!Trade.Sell(InpLots, Symb, tk.bid, 0, 0, cmt))
            Print("Sell grid failed. err=", _LastError);
         else return true;
      }
   }
   return false;
}

//------------------------- EA events --------------------------------
int OnInit()
{
   // EMA fast & slow on Trend TF
   hEMAfastTrend = iMA(_Symbol, InpTrendTF, InpFastEMA, 0, MODE_EMA, PRICE_CLOSE);
   hEMAslowTrend = iMA(_Symbol, InpTrendTF, InpSlowEMA, 0, MODE_EMA, PRICE_CLOSE);

   // EMA fast on Entry TF (current chart)
   hEMAfastEntry = iMA(_Symbol, _Period, InpFastEMA, 0, MODE_EMA, PRICE_CLOSE);

   if(hEMAfastTrend==INVALID_HANDLE || hEMAslowTrend==INVALID_HANDLE ||
      hEMAfastEntry==INVALID_HANDLE)
   {
      Print("Failed to create indicator handles.");
      return(INIT_FAILED);
   }
   
   Symb = _Symbol;
   PointV  = _Point;
   TickSize = SymbolInfoDouble(Symb, SYMBOL_TRADE_TICK_SIZE);
   NoDupBand = MathMax(1.0, InpNoDupLevelRatio * InpGridStepPoints); // หน่วย: points (ก่อนคูณ _Point)
   return(INIT_SUCCEEDED);
}

void OnTick()
{
   // 1) ถ้าไม่มีออเดอร์ -> เปิดเริ่มชุด
   if(CountOurPositions()==0)
   {
      OpenStarter(InpDirection);
      return;
   }

   // 2) เงื่อนไขกำไรสะสมถึงเป้า (เป็น “จุดสุทธิรวม”)
   double netPts = SumNetPoints();
   if(netPts >= InpProfitTargetPts)
   {
      // ปิดทั้งชุด แล้วเปิดตามทิศที่ตั้งไว้ (เริ่มชุดใหม่)
      if(CloseAll())
      {
         OpenStarter(InpDirection);
      }
      return; // รอบนี้จบ
   }

   // 3) เปิดกริดถัดไปเมื่อราคาเดินทางสวนมาจนถึงระยะ GridStep จาก "ออเดอร์ล่าสุด"
   MaybeOpenNext(InpDirection);
}

void OnDeinit(const int reason)
{
   if(hEMAfastTrend!=INVALID_HANDLE) IndicatorRelease(hEMAfastTrend);
   if(hEMAslowTrend!=INVALID_HANDLE) IndicatorRelease(hEMAslowTrend);
   if(hEMAfastEntry!=INVALID_HANDLE) IndicatorRelease(hEMAfastEntry);
}

// (ถ้าต้องการความเสถียรเพิ่มเติม อาจย้ายบาง logic ไป OnTimer พร้อมตั้ง EventSetTimer)
