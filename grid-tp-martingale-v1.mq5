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

input Direction  InpDirection        = DIR_BUY;   // หน้าเทรด: Buy / Sell
input double     InpLots             = 0.01;      // Lot ต่อออเดอร์
input int        InpGridStepPoints   = 5000;       // ระยะห่างกริด (จุด)
input int        InpProfitTargetPts  = 3000;       // กำไรสะสม(จุด) เพื่อปิดทั้งชุด
input int        InpSlippage         = 20;        // Slippage (points)
input int        InpMaxOrders        = 0;         // จำกัดจำนวนออเดอร์ (0=ไม่จำกัด)
input long       InpMagic            = 660077;    // Magic number
input bool       InpCommentPriceLvl  = true;      // เขียนระดับราคาใน comment

// ความปลอดภัย: ป้องกันเปิดซ้ำระดับเดิม (เช็คช่วงกันชน 15% ของกริด)
input double     InpNoDupLevelRatio  = 0.0;      // 0.15*GridStep เป็นช่วงกันชน // 0 = ไม่ Block ช่วงราคา เข้าออเดอร์ได้เลย

input double   InpMartingaleMultiply = 1.1;

input bool     InputEnableTP  = true;    // Enable TP: true = Enable & false = Disable
input int      InpGridTPPoints   = 5000;  // ระยะTP (จุด)

//------------------------- State -----------------------------------
string Symb;
double PointV, TickSize;
double NoDupBand; // กันชนไม่ให้เปิดซ้ำระดับราคา

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

double CalTagetPrice(double current_price, int points) // Buy -> ask, Sell -> bid
{
   // ดึงค่า Point Size ของ Symbol ปัจจุบัน
   double point_size = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   
   // คำนวณการเปลี่ยนแปลงของราคา
   double price_change = InpGridTPPoints * point_size;
   
   //double current_price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   
   // คำนวณราคาเป้าหมาย
   double target_price = current_price + (InpDirection == DIR_BUY ? price_change : -price_change);
   
   // หากต้องการให้ราคาอยู่ในรูปที่ถูกต้องตาม Tick Size (แนะนำ)
   // ควรใช้ฟังก์ชัน NormailzeDouble() เพื่อปรับทศนิยมให้ถูกต้องตาม Symbol's Digits
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   return NormalizeDouble(target_price, digits);
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
   
   double tpPrice = 0;
   if (InputEnableTP) {
      if(dir==DIR_BUY) tpPrice = CalTagetPrice(tk.ask, InpGridTPPoints);
      else tpPrice = CalTagetPrice(tk.bid, InpGridTPPoints);
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
   if (InputEnableTP) {
      if(dir==DIR_BUY) tpPrice = CalTagetPrice(tk.ask, InpGridTPPoints);
      else tpPrice = CalTagetPrice(tk.bid, InpGridTPPoints);
   }
   
   double nextLots = NormalizeDouble(InpLots * pow(InpMartingaleMultiply, CountOurPositions()), 2);

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

//------------------------- EA events --------------------------------
int OnInit()
{
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
   if (!InputEnableTP) {
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
   }

   // 3) เปิดกริดถัดไปเมื่อราคาเดินทางสวนมาจนถึงระยะ GridStep จาก "ออเดอร์ล่าสุด"
   MaybeOpenNext(InpDirection);
   
   //Comment("Orders:" + CountOurPositions());
}

// (ถ้าต้องการความเสถียรเพิ่มเติม อาจย้ายบาง logic ไป OnTimer พร้อมตั้ง EventSetTimer)
