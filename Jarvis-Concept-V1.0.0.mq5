//+------------------------------------------------------------------+
//|                                                GridAdoptFirst.mq5|
//|                              EA: Adopt first order and grid adds |
//+------------------------------------------------------------------+
#property strict

input long   InpMagic                = 20251017; // Magic number
input bool   AutoOpenFirst           = false;    // ให้ EA เปิดออเดอร์แรกเองหรือไม่
input ENUM_ORDER_TYPE InpFirstSide   = ORDER_TYPE_BUY;  // ทิศของออเดอร์แรก (ถ้า AutoOpenFirst=true)
input double InpFirstLot             = 0.10;     // ล็อตออเดอร์แรก (ถ้า AutoOpenFirst=true)

input int    TP_points               = 750;      // TP ของออเดอร์แรก (จุด)
input int    SL_points               = 2000;     // SL ของออเดอร์แรก (จุด)
input int    AddStep_points          = 500;      // ระยะเปิดออเดอร์เพิ่มเมื่อราคาวิ่งสวน (จุด)
input int    MaxAdds                 = 0;        // จำนวนออเดอร์เพิ่มสูงสุด (0=ไม่จำกัด)
input double LotMultiplier           = 1.2;      // ตัวคูณล็อตเมื่อเปิดเพิ่ม
input int    LotDecimals             = 2;        // ปัดตำแหน่งทศนิยมล็อต (เช่น 2 → 0.01)

input bool   IncludeForeignPositions = true;     // รวมออเดอร์ที่ไม่ได้ใช้ Magic นี้ (เช่น ออเดอร์มือเป็นออเดอร์แรก)
input bool   SameTP_SL_asFirst       = true;     // ออเดอร์เพิ่มตั้ง TP/SL ที่ “ราคาเดียวกัน” กับออเดอร์แรก

// เงื่อนไขเริ่ม Trailing เมื่อกำไรลอยรวม > 0 และราคาหนีจากราคาเฉลี่ย
input int    StartTrail_aboveAvg_points = 300;   // เริ่ม Trailing เมื่อราคา > ราคาเฉลี่ย +/- ค่านี้ (ขึ้นกับ Buy/Sell)
input int    TrailOffset_points         = 200;   // ระยะ SL ตามราคาปัจจุบัน (Buy: ต่ำกว่าราคา, Sell: สูงกว่าราคา)
input bool   TrailOnlyTighten           = true;  // ขยับ SL แค่เข้าหากำไร (ไม่ลดคุณภาพ SL)

input int    MinReopenSpacing_points    = 90;    // กันเปิดซ้ำซ้อนใกล้ราคาเดิม (จุด) บนฝั่งเดียวกัน

// -------------------------------------------------------------------
double pips(int pts){ return (double)pts * _Point; } // “points” ของ MT5
bool   IsBuy(ENUM_POSITION_TYPE t){ return (t==POSITION_TYPE_BUY); }
bool   IsSell(ENUM_POSITION_TYPE t){ return (t==POSITION_TYPE_SELL); }
bool   IsMySymbol(const string sym){ return (sym==_Symbol); }

struct PosInfo{
  ulong ticket;
  string sym;
  ENUM_POSITION_TYPE type;
  double lots, price, sl, tp;
  datetime time;
  long magic;
};

int OnInit(){ return(INIT_SUCCEEDED); }
void OnDeinit(const int){ }
void OnTick()
{
  // 1) ถ้าไม่มีออเดอร์บนสัญลักษณ์นี้เลย → option เปิดออเดอร์แรกอัตโนมัติ
  if(CountPositionsOnSymbol() == 0){
    if(AutoOpenFirst){
      OpenFirst();
    }
    return;
  }

  // 2) หา “ออเดอร์แรก” (ใบแรกสุดตามเวลา) ของสัญลักษณ์นี้ (รวมออเดอร์มือถ้าเลือก IncludeForeignPositions)
  PosInfo first;
  if(!FindFirstPosition(first)) return;

  // 2.1) ทำให้แน่ใจว่าออเดอร์แรกมี TP/SL ตามอินพุต ถ้ายังไม่มีจะใส่ให้
  EnsureFirstHasTPSL(first);

  // 3) พิจารณาเปิดออเดอร์เพิ่ม หากราคาไปสวนทิศทางออเดอร์แรกตาม step ที่กำหนด
  MaybeOpenAdd(first);

  // 4) ถ้ากำไรรวม (Equity > Balance) และราคา >/< ราคาเฉลี่ยตามเกณฑ์ → Trailing ปรับ SL ทุกใบตามกติกา
  MaybeTrailAll(first);

  // 5) ถ้าระบบปิดหมดเพราะชน TP/SL ตามธรรมชาติ เมื่อไม่มีออเดอร์เหลือ EA จะวนกลับไปข้อ 1 อัตโนมัติ
}

// -------------------------------------------------------------------
// นับจำนวน Position บนสัญลักษณ์นี้ (รวม/ไม่รวม Magic ตามพารามิเตอร์)
int CountPositionsOnSymbol()
{
  int total = PositionsTotal();
  int count = 0;
  for(int i=0;i<total;i++){
    ulong ticket;
    if((ticket = PositionGetTicket(i))==0) continue;
    if(!PositionSelectByTicket(ticket)) continue;
    if(!IsMySymbol((string)PositionGetString(POSITION_SYMBOL))) continue;
    count++;
  }
  return count;
}

bool FindFirstPosition(PosInfo &outFirst)
{
  datetime tmin = LONG_MAX;
  bool found=false;
  int total = PositionsTotal();
  for(int i=0;i<total;i++){
    ulong ticket = PositionGetTicket(i);
    if(ticket==0) continue;
    if(!PositionSelectByTicket(ticket)) continue;
    string sym = (string)PositionGetString(POSITION_SYMBOL);
    if(!IsMySymbol(sym)) continue;

    long magic = (long)PositionGetInteger(POSITION_MAGIC);
    if(!IncludeForeignPositions && magic!=InpMagic) continue;

    datetime t   = (datetime)PositionGetInteger(POSITION_TIME);
    if(t < tmin){
      tmin = t;
      outFirst.ticket = ticket;
      outFirst.sym    = sym;
      outFirst.type   = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      outFirst.lots   = PositionGetDouble(POSITION_VOLUME);
      outFirst.price  = PositionGetDouble(POSITION_PRICE_OPEN);
      outFirst.sl     = PositionGetDouble(POSITION_SL);
      outFirst.tp     = PositionGetDouble(POSITION_TP);
      outFirst.time   = t;
      outFirst.magic  = magic;
      found = true;
    }
  }
  return found;
}

void EnsureFirstHasTPSL(PosInfo &first)
{
  double stepTP = pips(TP_points);
  double stepSL = pips(SL_points);

  double desiredTP = first.tp;
  double desiredSL = first.sl;

  if(IsBuy(first.type)){
    if(first.tp<=0) desiredTP = first.price + stepTP;
    if(first.sl<=0) desiredSL = first.price - stepSL;
  }else{
    if(first.tp<=0) desiredTP = first.price - stepTP;
    if(first.sl<=0) desiredSL = first.price + stepSL;
  }

  // แก้กรณีไม่มี SL/TP
  if(desiredTP!=first.tp || desiredSL!=first.sl){
    if(PositionSelectByTicket(first.ticket)){
      TradePositionModify(first.ticket, desiredSL, desiredTP);
      // refresh
      PositionSelectByTicket(first.ticket);
      first.tp = PositionGetDouble(POSITION_TP);
      first.sl = PositionGetDouble(POSITION_SL);
    }
  }
}

void MaybeOpenAdd(const PosInfo &first)
{
  // 1) ตรวจจำนวนออเดอร์ฝั่งเดียวกับใบแรก
  int sameSideCount = CountSameSide(first.type);
  int addsSoFar = sameSideCount - 1; // ไม่รวมใบแรก
  if(MaxAdds>0 && addsSoFar>=MaxAdds) return;

  // 2) ราคาเงื่อนไขเปิดเพิ่มเมื่อ “ไปสวนทาง” จากราคาเปิดใบแรก
  double price = (first.type==POSITION_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_BID)
                                                 : SymbolInfoDouble(_Symbol, SYMBOL_ASK);

  // ห้ามเปิดเพิ่ม “เลยเส้น SL ของออเดอร์แรก”
  if(first.sl>0){
    if(IsBuy(first.type) && price <= first.sl) return;
    if(IsSell(first.type) && price >= first.sl) return;
  }

  // ระยะที่ต้องเดินสวนเท่าใด: first.price ± k*AddStep_points
  // จะเปิดก็ต่อเมื่อผ่าน threshold รอบถัดไปและยังไม่มีออเดอร์ “ใกล้ๆ” ตรงนั้น
  // ตำแหน่ง add target ล่าสุดที่ควรเปิด = floor(ระยะสวน/step) * step
  int dir = IsBuy(first.type) ? -1 : +1; // Buy: ราคาลงเป็นลบ, Sell: ราคาขึ้นเป็นบวก
  double delta = (price - first.price) / _Point; // หน่วยจุด (points)
  double needed = (double)AddStep_points;

  if( (IsBuy(first.type) && delta <= -needed) || (IsSell(first.type) && delta >= needed) ){
    // ตรวจ anti-duplicate: ไม่มี order ราคาใกล้เกินไป
    if(!HasNearbyOrderSameSide(price, first.type, MinReopenSpacing_points)){
      // คำนวณล็อตของออเดอร์ถัดไป: lotFirst * (LotMultiplier)^(addsSoFar+1)
      double lotFirst = first.lots;
      double nextLot  = lotFirst * MathPow(LotMultiplier, (addsSoFar+1));
      nextLot = NormalizeLot(nextLot);

      // เปิดออเดอร์เพิ่ม และตั้ง SL/TP เหมือนใบแรก (หรือคำนวณใหม่ถ้าไม่ได้ใช้ SameTP_SL_asFirst)
      double sl, tp;
      CalcTP_SL_forAdd(first, sl, tp);

      OpenMarket(first.type==POSITION_TYPE_BUY ? ORDER_TYPE_BUY : ORDER_TYPE_SELL, nextLot, sl, tp);
    }
  }
}

int CountSameSide(ENUM_POSITION_TYPE side)
{
  int total=PositionsTotal(), cnt=0;
  for(int i=0;i<total;i++){
    ulong ticket=PositionGetTicket(i);
    if(ticket==0) continue;
    if(!PositionSelectByTicket(ticket)) continue;
    if(!IsMySymbol((string)PositionGetString(POSITION_SYMBOL))) continue;

    if(!IncludeForeignPositions && (long)PositionGetInteger(POSITION_MAGIC)!=InpMagic) continue;

    if((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE)==side) cnt++;
  }
  return cnt;
}

bool HasNearbyOrderSameSide(double refPrice, ENUM_POSITION_TYPE side, int nearPts)
{
  int total=PositionsTotal();
  double thresh = pips(nearPts);
  for(int i=0;i<total;i++){
    ulong ticket=PositionGetTicket(i);
    if(ticket==0) continue;
    if(!PositionSelectByTicket(ticket)) continue;
    if(!IsMySymbol((string)PositionGetString(POSITION_SYMBOL))) continue;
    if(!IncludeForeignPositions && (long)PositionGetInteger(POSITION_MAGIC)!=InpMagic) continue;

    if((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE)!=side) continue;
    double p = PositionGetDouble(POSITION_PRICE_OPEN);
    if(MathAbs(p - refPrice) <= thresh) return true;
  }
  return false;
}

double NormalizeLot(double lot)
{
  // ปัดตาม LotDecimals และตาม symbol step/min/max
  double minLot, maxLot, lotStep;
  SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN, minLot);
  SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX, maxLot);
  SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP, lotStep);

  double byDecimals = NormalizeDouble(lot, LotDecimals);
  // บังคับให้ลง step
  double steps = MathFloor(byDecimals/lotStep) * lotStep;
  double finalLot = MathMax(minLot, MathMin(maxLot, steps));
  // เผื่อกรณีปัดแล้วได้ 0 ให้ดันเป็น minLot
  if(finalLot < minLot) finalLot = minLot;
  return finalLot;
}

void CalcTP_SL_forAdd(const PosInfo &first, double &outSL, double &outTP)
{
  if(SameTP_SL_asFirst && first.tp>0 && first.sl>0){
    outTP = first.tp;
    outSL = first.sl;
    return;
  }
  // else: คำนวณเทียบจากราคาเปิดของ "ใบที่จะเปิด" → เราไม่รู้ราคา fill ล่วงหน้า
  // จึงคำนวณแบบ dynamic หลังเปิดก็ได้, แต่เพื่อความง่าย ให้ตั้งโดยอิง Bid/Ask ปัจจุบัน
  double nowB = SymbolInfoDouble(_Symbol, SYMBOL_BID);
  double nowA = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
  double stepTP = pips(TP_points), stepSL = pips(SL_points);

  if(IsBuy(first.type)){
    outTP = nowA + stepTP;
    outSL = nowB - stepSL;
  }else{
    outTP = nowB - stepTP;
    outSL = nowA + stepSL;
  }
}

void MaybeTrailAll(const PosInfo &first)
{
  // เงื่อนไขเริ่ม: Equity > Balance และราคา หนีจาก “ราคาเฉลี่ยถ่วงน้ำหนักด้วยล็อต” ตามที่กำหนด
  double equity  = AccountInfoDouble(ACCOUNT_EQUITY);
  double balance = AccountInfoDouble(ACCOUNT_BALANCE);
  if(!(equity > balance)) return;

  // ราคาเฉลี่ยฝั่งเดียวกับ first
  double avgPrice = VWAP(first.type);
  if(avgPrice <= 0) return;

  double price = (first.type==POSITION_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_BID)
                                                 : SymbolInfoDouble(_Symbol, SYMBOL_ASK);

  double need   = pips(StartTrail_aboveAvg_points);
  bool ok=false;
  if(IsBuy(first.type)){
    ok = (price >= (avgPrice + need));
  }else{
    ok = (price <= (avgPrice - need));
  }
  if(!ok) return;

  // ปรับ SL ทุกใบฝั่งเดียวกันให้เลื่อนตามราคา (Buy: ต่ำกว่าราคา X จุด, Sell: สูงกว่าราคา X จุด)
  double trail = pips(TrailOffset_points);
  int total=PositionsTotal();
  for(int i=0;i<total;i++){
    ulong ticket=PositionGetTicket(i);
    if(ticket==0) continue;
    if(!PositionSelectByTicket(ticket)) continue;
    if(!IsMySymbol((string)PositionGetString(POSITION_SYMBOL))) continue;
    if(!IncludeForeignPositions && (long)PositionGetInteger(POSITION_MAGIC)!=InpMagic) continue;
    if((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE)!=first.type) continue;

    double curSL = PositionGetDouble(POSITION_SL);
    double curTP = PositionGetDouble(POSITION_TP);
    double newSL = curSL;

    if(IsBuy(first.type)){
      double targetSL = price - trail;
      if(TrailOnlyTighten) newSL = (curSL<=0) ? targetSL : MathMax(curSL, targetSL);
      else newSL = targetSL;
    }else{
      double targetSL = price + trail;
      if(TrailOnlyTighten) newSL = (curSL<=0) ? targetSL : MathMin(curSL, targetSL);
      else newSL = targetSL;
    }

    if(newSL != curSL){
      TradePositionModify(ticket, newSL, curTP);
    }
  }
}

double VWAP(ENUM_POSITION_TYPE side)
{
  int total=PositionsTotal();
  double v=0, pxv=0;
  for(int i=0;i<total;i++){
    ulong ticket=PositionGetTicket(i);
    if(ticket==0) continue;
    if(!PositionSelectByTicket(ticket)) continue;
    if(!IsMySymbol((string)PositionGetString(POSITION_SYMBOL))) continue;
    if(!IncludeForeignPositions && (long)PositionGetInteger(POSITION_MAGIC)!=InpMagic) continue;
    if((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE)!=side) continue;

    double lot = PositionGetDouble(POSITION_VOLUME);
    double prc = PositionGetDouble(POSITION_PRICE_OPEN);
    v   += lot;
    pxv += lot*prc;
  }
  if(v<=0) return 0.0;
  return pxv/v;
}

bool OpenFirst()
{
  double lot = NormalizeLot(InpFirstLot);
  double sl, tp;
  double stepTP = pips(TP_points), stepSL = pips(SL_points);

  if(InpFirstSide == ORDER_TYPE_BUY){
    double a = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    tp = a + stepTP;
    sl = a - stepSL;
    return OpenMarket(ORDER_TYPE_BUY, lot, sl, tp);
  }else{
    double b = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    tp = b - stepTP;
    sl = b + stepSL;
    return OpenMarket(ORDER_TYPE_SELL, lot, sl, tp);
  }
}

bool OpenMarket(ENUM_ORDER_TYPE type, double lot, double sl, double tp)
{
  MqlTradeRequest req;
  ZeroMemory(req);
  req.action   = TRADE_ACTION_DEAL;
  req.symbol   = _Symbol;
  req.volume   = lot;
  req.magic    = InpMagic;
  req.type     = type;
  req.deviation= 20; // ปรับได้
  if(type==ORDER_TYPE_BUY){
    req.price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
  }else{
    req.price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
  }
  req.sl = sl;
  req.tp = tp;

  MqlTradeResult res;
  if(!OrderSend(req, res)){
    Print("OrderSend failed: ", _LastError);
    return false;
  }
  return true;
}

bool TradePositionModify(ulong ticket, double sl, double tp)
{
  MqlTradeRequest req;
  ZeroMemory(req);
  req.action  = TRADE_ACTION_SLTP;
  req.position= ticket;
  req.symbol  = _Symbol;
  req.sl      = sl;
  req.tp      = tp;

  MqlTradeResult res;
  if(!OrderSend(req, res)){
    Print("Modify failed: ", _LastError);
    return false;
  }
  return true;
}
//+------------------------------------------------------------------+
