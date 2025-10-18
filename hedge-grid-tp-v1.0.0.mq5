#property strict
#property description "Hedge Grid Trade: เปิด Buy/Sell พร้อมกัน เติมกริด และปิดรีเซ็ตเฉพาะฝั่งที่ได้กำไร"

input double   InpLots                = 0.01;     // ขนาด Lot ต่อออเดอร์
input int      InpGridStepPoints      = 400;      // ระยะกริด (จุด)
input int      InpTargetPointsPerSide = 400;      // เป้ากำไรรวมต่อฝั่ง (จุด)
input int      InpSlippagePoints      = 20;       // สลิปเพจ (จุด)
input long     InpMagic               = 20251014; // Magic number
input int      InpMaxPositionsPerSide = 50;       // จำนวนออเดอร์สูงสุดต่อฝั่ง
input bool     InpAllowHedgeBothSides = true;     // เปิดทั้งสองฝั่ง (ควรเป็น true ตามสเป็ค)

input bool     InputEnableTP  = true;    // Enable TP: true = Enable & false = Disable
input int      InpGridTPPoints   = 400;  // ระยะTP (จุด

string Sym;
double _PointP;   // point จริงของสัญลักษณ์
int    _DigitsP;

enum Side { SIDE_BUY=0, SIDE_SELL=1 };

// ----------------- Utilities -----------------
bool IsMyPosition(int index)
{
   if(!GetPositionByIndex_UsingTicket(index)) return false;
   string s = PositionGetString(POSITION_SYMBOL);
   long   m = (long)PositionGetInteger(POSITION_MAGIC);
   return (s==Sym && m==InpMagic);
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

int CountSide(Side sd)
{
   int total=0;
   for(int i=0;i<PositionsTotal();++i)
   {
      if(!GetPositionByIndex_UsingTicket(i)) continue;
      if(PositionGetString(POSITION_SYMBOL)!=Sym) continue;
      if((long)PositionGetInteger(POSITION_MAGIC)!=InpMagic) continue;
      long type = PositionGetInteger(POSITION_TYPE);
      if( (sd==SIDE_BUY && type==POSITION_TYPE_BUY) ||
          (sd==SIDE_SELL&& type==POSITION_TYPE_SELL) ) total++;
   }
   return total;
}

double CalTagetPrice(double current_price, int points, Side side) // Buy -> ask, Sell -> bid
{
   // ดึงค่า Point Size ของ Symbol ปัจจุบัน
   double point_size = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   
   // คำนวณการเปลี่ยนแปลงของราคา
   double price_change = InpGridTPPoints * point_size;
   
   //double current_price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   
   // คำนวณราคาเป้าหมาย
   double target_price = current_price + (side == SIDE_BUY ? price_change : -price_change);
   
   // หากต้องการให้ราคาอยู่ในรูปที่ถูกต้องตาม Tick Size (แนะนำ)
   // ควรใช้ฟังก์ชัน NormailzeDouble() เพื่อปรับทศนิยมให้ถูกต้องตาม Symbol's Digits
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   return NormalizeDouble(target_price, digits);
}

bool GetLastPrice(Side sd, double &last_price)
{
   // สำหรับ Buy: หา "ราคาล่าสุดของฝั่งนั้นที่เปิดล่าสุด" (ตามเวลาเปิด)
   // เราเก็บเป็นเวลาล่าสุด
   datetime last_time = 0;
   bool found=false;
   for(int i=0;i<PositionsTotal();++i)
   {
      if(!GetPositionByIndex_UsingTicket(i)) continue;
      if(PositionGetString(POSITION_SYMBOL)!=Sym) continue;
      if((long)PositionGetInteger(POSITION_MAGIC)!=InpMagic) continue;
      long   type  = PositionGetInteger(POSITION_TYPE);
      if( (sd==SIDE_BUY && type!=POSITION_TYPE_BUY) ||
          (sd==SIDE_SELL&& type!=POSITION_TYPE_SELL) ) continue;

      datetime t    = (datetime)PositionGetInteger(POSITION_TIME);
      double   prc  = PositionGetDouble(POSITION_PRICE_OPEN);

      if(!found || t>last_time) { last_time=t; last_price=prc; found=true; }
   }
   return found;
}

bool HasPositionNearLevel(Side sd, double level, double tolerance_points)
{
   double tol = tolerance_points * _PointP;
   for(int i=0;i<PositionsTotal();++i)
   {
      if(!GetPositionByIndex_UsingTicket(i)) continue;
      if(PositionGetString(POSITION_SYMBOL)!=Sym) continue;
      if((long)PositionGetInteger(POSITION_MAGIC)!=InpMagic) continue;
      long type = PositionGetInteger(POSITION_TYPE);

      if( (sd==SIDE_BUY && type!=POSITION_TYPE_BUY) ||
          (sd==SIDE_SELL&& type!=POSITION_TYPE_SELL) ) continue;

      double po = PositionGetDouble(POSITION_PRICE_OPEN);
      if(MathAbs(po - level) <= tol) return true;
   }
   return false;
}

double SumSideProfitMoney(Side sd)
{
   double sum=0.0;
   for(int i=0;i<PositionsTotal();++i)
   {
      if(!GetPositionByIndex_UsingTicket(i)) continue;
      if(PositionGetString(POSITION_SYMBOL)!=Sym) continue;
      if((long)PositionGetInteger(POSITION_MAGIC)!=InpMagic) continue;
      long type = PositionGetInteger(POSITION_TYPE);

      if( (sd==SIDE_BUY && type!=POSITION_TYPE_BUY) ||
          (sd==SIDE_SELL&& type!=POSITION_TYPE_SELL) ) continue;

      sum += PositionGetDouble(POSITION_PROFIT); // รวมทั้ง floating + swap + commission
   }
   return sum;
}

// "จำนวนจุดรวม" ของฝั่งนั้น (ถ่วงตาม lot)
double SumSidePoints(Side sd)
{
   double points_sum = 0.0;
   double price_now_bid = SymbolInfoDouble(Sym, SYMBOL_BID);
   double price_now_ask = SymbolInfoDouble(Sym, SYMBOL_ASK);

   for(int i=0;i<PositionsTotal();++i)
   {
      if(!GetPositionByIndex_UsingTicket(i)) continue;
      if(PositionGetString(POSITION_SYMBOL)!=Sym) continue;
      if((long)PositionGetInteger(POSITION_MAGIC)!=InpMagic) continue;
      long type   = PositionGetInteger(POSITION_TYPE);
      double vol  = PositionGetDouble(POSITION_VOLUME);
      double open = PositionGetDouble(POSITION_PRICE_OPEN);

      if(sd==SIDE_BUY && type==POSITION_TYPE_BUY)
      {
         double p = (price_now_bid - open)/_PointP; // จุดกำไร(ขาดทุน)
         points_sum += p * (vol / InpLots); // นอร์มัลไลซ์ด้วยล็อตตั้งต้นให้ scale ใกล้เคียงสเป็ค
      }
      else
      if(sd==SIDE_SELL && type==POSITION_TYPE_SELL)
      {
         double p = (open - price_now_ask)/_PointP;
         points_sum += p * (vol / InpLots);
      }
   }
   return points_sum;
}

bool OpenMarket(Side sd, double lots)
{
   MqlTradeRequest  req;
   MqlTradeResult   res;
   ZeroMemory(req); ZeroMemory(res);
   
   double tpPrice = 0;
   if (InputEnableTP) {
      if (sd == SIDE_BUY) tpPrice = CalTagetPrice(SYMBOL_ASK, InpGridTPPoints, SIDE_BUY);
      else tpPrice = CalTagetPrice(SYMBOL_BID, InpGridTPPoints, SIDE_SELL);
   }

   req.action   = TRADE_ACTION_DEAL;
   req.symbol   = Sym;
   req.magic    = InpMagic;
   req.deviation= InpSlippagePoints;

   if(sd==SIDE_BUY)
   {
      req.type   = ORDER_TYPE_BUY;
      req.price  = SymbolInfoDouble(Sym, SYMBOL_ASK);
   }
   else
   {
      req.type   = ORDER_TYPE_SELL;
      req.price  = SymbolInfoDouble(Sym, SYMBOL_BID);
   }
   req.volume  = lots;
   req.tp      = tpPrice;

   bool ok = OrderSend(req, res);
   if(!ok || res.retcode!=10009 /*TRADE_RETCODE_DONE*/)
   {
      PrintFormat("OrderSend failed side=%s ret=%d comment=%s",
                  (sd==SIDE_BUY?"BUY":"SELL"), res.retcode, res.comment);
      return false;
   }
   return true;
}

bool CloseAllSide(Side sd)
{
   bool all_ok=true;
   // ปิดทีละโพสิชันของฝั่งนั้น
   for(int i=PositionsTotal()-1;i>=0;--i)
   {
      if(!GetPositionByIndex_UsingTicket(i)) continue;
      if(PositionGetString(POSITION_SYMBOL)!=Sym) continue;
      if((long)PositionGetInteger(POSITION_MAGIC)!=InpMagic) continue;

      long type = PositionGetInteger(POSITION_TYPE);
      if( (sd==SIDE_BUY && type!=POSITION_TYPE_BUY) ||
          (sd==SIDE_SELL&& type!=POSITION_TYPE_SELL) ) continue;

      ulong ticket = (ulong)PositionGetInteger(POSITION_TICKET);
      double vol   = PositionGetDouble(POSITION_VOLUME);

      MqlTradeRequest  rq; MqlTradeResult rs;
      ZeroMemory(rq); ZeroMemory(rs);
      rq.action   = TRADE_ACTION_DEAL;
      rq.symbol   = Sym;
      rq.magic    = InpMagic;
      rq.deviation= InpSlippagePoints;
      rq.volume   = vol;

      if(type==POSITION_TYPE_BUY)
      {
         rq.type  = ORDER_TYPE_SELL; // close buy == sell
         rq.price = SymbolInfoDouble(Sym, SYMBOL_BID);
      }
      else
      {
         rq.type  = ORDER_TYPE_BUY;  // close sell == buy
         rq.price = SymbolInfoDouble(Sym, SYMBOL_ASK);
      }
      rq.position = ticket;

      bool ok = OrderSend(rq, rs);
      if(!ok || rs.retcode!=10009)
      {
         all_ok=false;
         PrintFormat("Close failed ticket=%I64u ret=%d comment=%s",
                     ticket, rs.retcode, rs.comment);
      }
   }
   return all_ok;
}

// ----------------- Core Logic -----------------
void EnsureInitialBothSides()
{
   if(!InpAllowHedgeBothSides) return;

   int buys = CountSide(SIDE_BUY);
   int sells= CountSide(SIDE_SELL);

   if(buys==0) OpenMarket(SIDE_BUY, InpLots);
   if(sells==0) OpenMarket(SIDE_SELL, InpLots);
}

void TryOpenNextGrid(Side sd)
{
   int cur = CountSide(sd);
   if(cur<=0) return; // ต้องมีอย่างน้อย 1 ไม้ก่อน
   if(cur>=InpMaxPositionsPerSide) return;

   double last_price;
   if(!GetLastPrice(sd, last_price)) return;

   double bid = SymbolInfoDouble(Sym, SYMBOL_BID);
   double ask = SymbolInfoDouble(Sym, SYMBOL_ASK);
   double step = InpGridStepPoints * _PointP;

   if(sd==SIDE_BUY)
   {
      // เปิด Buy ใหม่เมื่อราคา <= last_buy - step
      double trigger = last_price - step;
      if(bid <= trigger)
      {
         // กันซ้ำระดับเดิม
         if(!HasPositionNearLevel(SIDE_BUY, trigger, InpGridStepPoints/2.0))
            OpenMarket(SIDE_BUY, InpLots);
      }
   }
   else // SELL
   {
      // เปิด Sell ใหม่เมื่อราคา >= last_sell + step
      double trigger = last_price + step;
      if(ask >= trigger)
      {
         if(!HasPositionNearLevel(SIDE_SELL, trigger, InpGridStepPoints/2.0))
            OpenMarket(SIDE_SELL, InpLots);
      }
   }
}

void TryTakeProfitAndReset(Side sd)
{
   // เงื่อนไขปิดกำไรฝั่งเดียว:
   //  (1) คะแนนจุดรวม >= TargetPointsPerSide  และ  (2) กำไรรวมเป็นบวก
   double pts = SumSidePoints(sd);
   double money = SumSideProfitMoney(sd);

   if(pts >= InpTargetPointsPerSide && money > 0.0)
   {
      bool ok = CloseAllSide(sd);
      if(ok)
      {
         // เปิดไม้แรกใหม่ของฝั่งนั้นตามสเป็ค
         OpenMarket(sd, InpLots);
      }
   }
}

// ----------------- MQL5 Events -----------------
int OnInit()
{
   Sym     = _Symbol;
   _PointP = SymbolInfoDouble(Sym, SYMBOL_POINT);
   _DigitsP= (int)SymbolInfoInteger(Sym, SYMBOL_DIGITS);

   if(_PointP<=0)
   {
      Print("Symbol point invalid.");
      return(INIT_FAILED);
   }
   return(INIT_SUCCEEDED);
}

void OnTick()
{
   // 1) ให้มี Buy/Sell ไม้แรกเสมอ (ตามสเป็คเปิดทั้งคู่)
   EnsureInitialBothSides();

   // 2) เติมกริดฝั่งละทิศที่กำหนด (Buy ต่ำกว่า / Sell สูงกว่า)
   TryOpenNextGrid(SIDE_BUY);
   TryOpenNextGrid(SIDE_SELL);

   // 3) เช็คเป้ากำไรต่อฝั่ง แล้วปิดเฉพาะฝั่งที่ถึงเป้า จากนั้นเปิดฝั่งนั้นใหม่
   if (!InputEnableTP)
   {
      TryTakeProfitAndReset(SIDE_BUY);
      TryTakeProfitAndReset(SIDE_SELL);
   }
}

void OnDeinit(const int reason){}

