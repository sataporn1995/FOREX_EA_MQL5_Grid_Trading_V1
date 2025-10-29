//+------------------------------------------------------------------+
//|                                        GridAdoptFirst_DualSide.mq5|
//|                   EA: Dual-side grid with separate profit tracking |
//+------------------------------------------------------------------+
#property strict

input long   InpMagic                = 2025102901; // Magic number
input bool   AutoOpenFirst           = false;    // ให้ EA เปิดออเดอร์แรกเองหรือไม่
input bool   AutoOpenBothSides       = false;    // เปิดทั้ง Buy และ Sell พร้อมกัน (ถ้า AutoOpenFirst=true)
input ENUM_ORDER_TYPE InpFirstSide   = ORDER_TYPE_BUY;  // ทิศของออเดอร์แรก (ถ้า AutoOpenBothSides=false)
input double InpFirstLot             = 0.01;     // ล็อตออเดอร์แรก

input int    TP_points               = 20000;      // TP ของออเดอร์แรก (จุด)
input int    SL_points               = 150000;     // SL ของออเดอร์แรก (จุด)
input int    AddStep_points          = 5000;      // ระยะเปิดออเดอร์เพิ่มเมื่อราคาวิ่งสวน (จุด)
input int    MaxAdds                 = 0;        // จำนวนออเดอร์เพิ่มสูงสุด (0=ไม่จำกัด)
input double LotMultiplier           = 1.1;      // ตัวคูณล็อตเมื่อเปิดเพิ่ม
input int    LotDecimals             = 2;        // ปัดตำแหน่งทศนิยมล็อต
input double MaxLot                  = 0.2;      // ล็อตสูงสุด
input int    Slippage                = 20;

input bool   IncludeForeignPositions = true;     // รวมออเดอร์ที่ไม่ได้ใช้ Magic นี้
input bool   SameTP_SL_asFirst       = true;     // ออเดอร์เพิ่มตั้ง TP/SL ที่ราคาเดียวกันกับออเดอร์แรก

// Trailing Stop parameters (แยกตาม Position Type)
input int    StartTrail_aboveAvg_points = 4000;   // เริ่ม Trailing เมื่อราคาหนีจากราคาเฉลี่ย
input int    TrailOffset_points         = 2000;   // ระยะ SL ตามราคาปัจจุบัน
input bool   TrailOnlyTighten           = true;  // ขยับ SL แค่เข้าหากำไร

input int    MinReopenSpacing_points    = 5000;    // กันเปิดซ้ำซ้อนใกล้ราคาเดิม (จุด)

// -------------------------------------------------------------------
double pips(int pts){ return (double)pts * _Point; }
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

struct ProfitInfo{
  double profit;
  double volume;
  int count;
};

int OnInit(){ 
  Print("EA Started - Dual Side Grid System");
  return(INIT_SUCCEEDED); 
}

void OnDeinit(const int){ }

void OnTick()
{
  // แสดงข้อมูล Profit แยกตาม Position Type
  DisplayProfitInfo();
  
  // ตรวจสอบว่ามีออเดอร์หรือไม่
  int buyCount = CountPositionsByType(POSITION_TYPE_BUY);
  int sellCount = CountPositionsByType(POSITION_TYPE_SELL);
  
  // 1) ถ้าไม่มีออเดอร์เลย → เปิดออเดอร์แรก
  if(buyCount == 0 && sellCount == 0){
    if(AutoOpenFirst){
      if(AutoOpenBothSides){
        OpenFirst(ORDER_TYPE_BUY);
        OpenFirst(ORDER_TYPE_SELL);
      } else {
        OpenFirst(InpFirstSide);
      }
    }
    return;
  }

  // 2) จัดการฝั่ง Buy (ถ้ามี)
  if(buyCount > 0){
    PosInfo firstBuy;
    if(FindFirstPositionByType(POSITION_TYPE_BUY, firstBuy)){
      EnsureFirstHasTPSL(firstBuy);
      MaybeOpenAdd(firstBuy);
      MaybeTrailAll(firstBuy);
    }
  }

  // 3) จัดการฝั่ง Sell (ถ้ามี)
  if(sellCount > 0){
    PosInfo firstSell;
    if(FindFirstPositionByType(POSITION_TYPE_SELL, firstSell)){
      EnsureFirstHasTPSL(firstSell);
      MaybeOpenAdd(firstSell);
      MaybeTrailAll(firstSell);
    }
  }
}

// -------------------------------------------------------------------
// แสดงข้อมูล Profit แยกตาม Symbol และ Position Type
void DisplayProfitInfo()
{
  ProfitInfo buyInfo = CalculateProfit(POSITION_TYPE_BUY);
  ProfitInfo sellInfo = CalculateProfit(POSITION_TYPE_SELL);
  
  static datetime lastDisplay = 0;
  if(TimeCurrent() - lastDisplay < 1) return; // แสดงทุก 1 วินาที
  lastDisplay = TimeCurrent();
  
  string info = StringFormat("\n=== Profit Info [%s] ===\n", _Symbol);
  info += StringFormat("BUY  → Profit: %.2f | Positions: %d | Volume: %.2f\n", 
                       buyInfo.profit, buyInfo.count, buyInfo.volume);
  info += StringFormat("SELL → Profit: %.2f | Positions: %d | Volume: %.2f\n", 
                       sellInfo.profit, sellInfo.count, sellInfo.volume);
  info += StringFormat("NET  → Profit: %.2f\n", buyInfo.profit + sellInfo.profit);
  info += "========================\n";
  
  Comment(info);
}

// คำนวณ Profit แยกตาม Position Type
ProfitInfo CalculateProfit(ENUM_POSITION_TYPE type)
{
  ProfitInfo info;
  info.profit = 0;
  info.volume = 0;
  info.count = 0;
  
  int total = PositionsTotal();
  for(int i=0; i<total; i++){
    ulong ticket = PositionGetTicket(i);
    if(ticket == 0) continue;
    if(!PositionSelectByTicket(ticket)) continue;
    if(!IsMySymbol((string)PositionGetString(POSITION_SYMBOL))) continue;
    
    if(!IncludeForeignPositions && (long)PositionGetInteger(POSITION_MAGIC) != InpMagic) 
      continue;
    
    if((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) == type){
      info.profit += PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
      info.volume += PositionGetDouble(POSITION_VOLUME);
      info.count++;
    }
  }
  
  return info;
}

// นับจำนวน Position ตาม Type
int CountPositionsByType(ENUM_POSITION_TYPE type)
{
  int total = PositionsTotal();
  int count = 0;
  for(int i=0; i<total; i++){
    ulong ticket = PositionGetTicket(i);
    if(ticket==0) continue;
    if(!PositionSelectByTicket(ticket)) continue;
    if(!IsMySymbol((string)PositionGetString(POSITION_SYMBOL))) continue;
    
    if(!IncludeForeignPositions && (long)PositionGetInteger(POSITION_MAGIC)!=InpMagic) 
      continue;
    
    if((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) == type) 
      count++;
  }
  return count;
}

// หาออเดอร์แรกของ Position Type ที่ระบุ
bool FindFirstPositionByType(ENUM_POSITION_TYPE type, PosInfo &outFirst)
{
  datetime tmin = LONG_MAX;
  bool found = false;
  int total = PositionsTotal();
  
  for(int i=0; i<total; i++){
    ulong ticket = PositionGetTicket(i);
    if(ticket==0) continue;
    if(!PositionSelectByTicket(ticket)) continue;
    
    string sym = (string)PositionGetString(POSITION_SYMBOL);
    if(!IsMySymbol(sym)) continue;

    long magic = (long)PositionGetInteger(POSITION_MAGIC);
    if(!IncludeForeignPositions && magic!=InpMagic) continue;

    ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
    if(posType != type) continue;

    datetime t = (datetime)PositionGetInteger(POSITION_TIME);
    if(t < tmin){
      tmin = t;
      outFirst.ticket = ticket;
      outFirst.sym    = sym;
      outFirst.type   = posType;
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

  if(desiredTP!=first.tp || desiredSL!=first.sl){
    if(PositionSelectByTicket(first.ticket)){
      TradePositionModify(first.ticket, desiredSL, desiredTP);
      PositionSelectByTicket(first.ticket);
      first.tp = PositionGetDouble(POSITION_TP);
      first.sl = PositionGetDouble(POSITION_SL);
    }
  }
}

void MaybeOpenAdd(const PosInfo &first)
{
  int sameSideCount = CountSameSide(first.type);
  int addsSoFar = sameSideCount - 1;
  if(MaxAdds>0 && addsSoFar>=MaxAdds) return;

  double price = (first.type==POSITION_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_BID)
                                                 : SymbolInfoDouble(_Symbol, SYMBOL_ASK);

  if(first.sl>0){
    if(IsBuy(first.type) && price <= first.sl) return;
    if(IsSell(first.type) && price >= first.sl) return;
  }

  double delta = (price - first.price) / _Point;
  double needed = (double)AddStep_points;

  if((IsBuy(first.type) && delta <= -needed) || (IsSell(first.type) && delta >= needed)){
    if(!HasNearbyOrderSameSide(price, first.type, MinReopenSpacing_points)){
      double lotFirst = first.lots;
      double nextLot  = lotFirst * MathPow(LotMultiplier, (addsSoFar+1));
      nextLot = NormalizeLot(nextLot);

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
  double minLot, maxLot, lotStep;
  SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN, minLot);
  SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX, maxLot);
  SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP, lotStep);

  double byDecimals = NormalizeDouble(lot, LotDecimals);
  double steps = MathFloor(byDecimals/lotStep) * lotStep;
  double finalLot = MathMax(minLot, MathMin(maxLot, steps));
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
  // คำนวณ Profit เฉพาะฝั่งนี้
  ProfitInfo info = CalculateProfit(first.type);
  if(info.profit <= 0) return; // ต้องกำไรลอยเท่านั้น

  double avgPrice = VWAP(first.type);
  if(avgPrice <= 0) return;

  double price = (first.type==POSITION_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_BID)
                                                 : SymbolInfoDouble(_Symbol, SYMBOL_ASK);

  double need = pips(StartTrail_aboveAvg_points);
  bool ok=false;
  if(IsBuy(first.type)){
    ok = (price >= (avgPrice + need));
  }else{
    ok = (price <= (avgPrice - need));
  }
  if(!ok) return;

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

bool OpenFirst(ENUM_ORDER_TYPE orderType)
{
  double lot = NormalizeLot(InpFirstLot);
  double sl, tp;
  double stepTP = pips(TP_points), stepSL = pips(SL_points);

  if(orderType == ORDER_TYPE_BUY){
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
  double blockedLot = lot > MaxLot ? NormalizeLot(MaxLot): lot;
  req.action   = TRADE_ACTION_DEAL;
  req.symbol   = _Symbol;
  req.volume   = lot;
  req.magic    = InpMagic;
  req.type     = type;
  req.deviation= Slippage;
  if(type==ORDER_TYPE_BUY){
    req.price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
  }else{
    req.price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
  }
  req.sl = sl;
  req.tp = tp;

  MqlTradeResult res;
  if(!OrderSend(req, res)){
    Print("OrderSend failed: ", GetLastError());
    return false;
  }
  
  Print(StringFormat("Opened %s position: Ticket=%d, Lot=%.2f, Price=%.5f", 
        EnumToString(type), res.order, lot, req.price));
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
    Print("Modify failed: ", GetLastError());
    return false;
  }
  return true;
}
//+------------------------------------------------------------------+
