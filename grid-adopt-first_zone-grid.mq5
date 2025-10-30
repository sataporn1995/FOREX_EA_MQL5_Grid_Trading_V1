//+------------------------------------------------------------------+
//|                                        GridAdoptFirst_ZoneGrid.mq5|
//|                   EA: Dual-side grid with Zone Grid support      |
//+------------------------------------------------------------------+
#property strict

// Enum สำหรับเลือกโหมด Grid
enum ENUM_GRID_MODE
{
  GRID_NORMAL,    // Grid แบบปกติ (ระยะเท่ากันทุกออเดอร์)
  GRID_ZONE       // Grid แบบโซน (แบ่งเป็นโซน มีระยะต่างกันในแต่ละโซน)
};

input long   InpMagic                = 2025103001; // Magic number
//input bool   AutoOpenFirst           = false;    // ให้ EA เปิดออเดอร์แรกเองหรือไม่
//input bool   AutoOpenBothSides       = false;    // เปิดทั้ง Buy และ Sell พร้อมกัน
//input ENUM_ORDER_TYPE InpFirstSide   = ORDER_TYPE_BUY;  // ทิศของออเดอร์แรก
input double InpFirstLot             = 0.10;     // ล็อตออเดอร์แรก

input int    TP_points               = 2000;      // TP ของออเดอร์แรก (จุด)
input int    SL_points               = 15000;     // SL ของออเดอร์แรก (จุด)

//===== Grid Mode Selection =====
input ENUM_GRID_MODE GridMode        = GRID_NORMAL; // โหมดการเปิดออเดอร์

//===== Normal Grid Settings =====
input int    AddStep_points          = 500;      // ระยะเปิดออเดอร์เพิ่ม (GRID_NORMAL)
input int    MaxAdds                 = 0;        // จำนวนออเดอร์เพิ่มสูงสุด (0=ไม่จำกัด)

//===== Zone Grid Settings =====
input int    ZoneCount               = 3;        // จำนวนโซน (GRID_ZONE)
input string ZoneOrdersInput         = "3,5,7";  // จำนวนออเดอร์ในแต่ละโซน (คั่นด้วย ,)
input string ZoneSpacingInput        = "300,500,700"; // ระยะห่างในแต่ละโซน (จุด, คั่นด้วย ,)

input double LotMultiplier           = 1.1;      // ตัวคูณล็อตเมื่อเปิดเพิ่ม
input int    LotDecimals             = 2;        // ปัดตำแหน่งทศนิยมล็อต

input bool   IncludeForeignPositions = true;     // รวมออเดอร์ที่ไม่ได้ใช้ Magic นี้
input bool   SameTP_SL_asFirst       = true;     // ออเดอร์เพิ่มตั้ง TP/SL ที่ราคาเดียวกันกับออเดอร์แรก

// Trailing Stop parameters
input int    StartTrail_aboveAvg_points = 400;   // เริ่ม Trailing เมื่อราคาหนีจากราคาเฉลี่ย
input int    TrailOffset_points         = 290;   // ระยะ SL ตามราคาปัจจุบัน
input bool   TrailOnlyTighten           = true;  // ขยับ SL แค่เข้าหากำไร

input int    MinReopenSpacing_points    = 500;    // กันเปิดซ้ำซ้อนใกล้ราคาเดิม (จุด)

// -------------------------------------------------------------------
// โครงสร้างข้อมูลสำหรับ Zone Grid
struct ZoneConfig
{
  int zoneOrders[];      // จำนวนออเดอร์ในแต่ละโซน
  int zoneSpacing[];     // ระยะห่างในแต่ละโซน (จุด)
  int totalZones;        // จำนวนโซนทั้งหมด
  int maxOrders;         // จำนวนออเดอร์สูงสุดรวมทุกโซน
};

ZoneConfig g_ZoneConfig;

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

// -------------------------------------------------------------------
int OnInit()
{ 
  Print("=== EA Started - Zone Grid System ===");
  Print("Grid Mode: ", EnumToString(GridMode));
  
  // Parse และตรวจสอบ Zone Configuration
  if(GridMode == GRID_ZONE)
  {
    if(!ParseZoneConfig())
    {
      Print("ERROR: Invalid Zone Configuration!");
      return(INIT_PARAMETERS_INCORRECT);
    }
    PrintZoneConfig();
  }
  else
  {
    Print("Normal Grid - AddStep: ", AddStep_points, " points, MaxAdds: ", MaxAdds);
  }
  
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
    /*if(AutoOpenFirst){
      if(AutoOpenBothSides){
        OpenFirst(ORDER_TYPE_BUY);
        OpenFirst(ORDER_TYPE_SELL);
      } else {
        OpenFirst(InpFirstSide);
      }
    }*/
    return;
  }

  // 2) จัดการฝั่ง Buy
  if(buyCount > 0){
    PosInfo firstBuy;
    if(FindFirstPositionByType(POSITION_TYPE_BUY, firstBuy)){
      EnsureFirstHasTPSL(firstBuy);
      MaybeOpenAdd(firstBuy);
      MaybeTrailAll(firstBuy);
    }
  }

  // 3) จัดการฝั่ง Sell
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
// ฟังก์ชันสำหรับ Parse Zone Configuration
bool ParseZoneConfig()
{
  ArrayResize(g_ZoneConfig.zoneOrders, 0);
  ArrayResize(g_ZoneConfig.zoneSpacing, 0);
  
  // Parse จำนวนออเดอร์ในแต่ละโซน
  string ordersArr[];
  int ordersCount = StringSplit(ZoneOrdersInput, ',', ordersArr);
  if(ordersCount != ZoneCount)
  {
    Print("ERROR: จำนวนโซนไม่ตรงกับข้อมูล ZoneOrdersInput");
    return false;
  }
  
  // Parse ระยะห่างในแต่ละโซน
  string spacingArr[];
  int spacingCount = StringSplit(ZoneSpacingInput, ',', spacingArr);
  if(spacingCount != ZoneCount)
  {
    Print("ERROR: จำนวนโซนไม่ตรงกับข้อมูล ZoneSpacingInput");
    return false;
  }
  
  ArrayResize(g_ZoneConfig.zoneOrders, ZoneCount);
  ArrayResize(g_ZoneConfig.zoneSpacing, ZoneCount);
  
  g_ZoneConfig.totalZones = ZoneCount;
  g_ZoneConfig.maxOrders = 0;
  
  for(int i=0; i<ZoneCount; i++)
  {
    StringTrimLeft(ordersArr[i]);
    StringTrimRight(ordersArr[i]);
    StringTrimLeft(spacingArr[i]);
    StringTrimRight(spacingArr[i]);
    
    g_ZoneConfig.zoneOrders[i] = (int)StringToInteger(ordersArr[i]);
    g_ZoneConfig.zoneSpacing[i] = (int)StringToInteger(spacingArr[i]);
    
    if(g_ZoneConfig.zoneOrders[i] <= 0 || g_ZoneConfig.zoneSpacing[i] <= 0)
    {
      Print("ERROR: ค่า Zone Orders หรือ Zone Spacing ไม่ถูกต้องในโซนที่ ", i+1);
      return false;
    }
    
    g_ZoneConfig.maxOrders += g_ZoneConfig.zoneOrders[i];
  }
  
  return true;
}

void PrintZoneConfig()
{
  Print("=== Zone Grid Configuration ===");
  Print("Total Zones: ", g_ZoneConfig.totalZones);
  Print("Max Orders: ", g_ZoneConfig.maxOrders);
  
  for(int i=0; i<g_ZoneConfig.totalZones; i++)
  {
    Print(StringFormat("Zone %d: %d orders, %d points spacing", 
          i+1, g_ZoneConfig.zoneOrders[i], g_ZoneConfig.zoneSpacing[i]));
  }
  Print("================================");
}

// -------------------------------------------------------------------
// คำนวณว่าควรเปิดออเดอร์ที่ระดับไหน (สำหรับ Zone Grid)
bool ShouldOpenAtZone(const PosInfo &first, int currentOrderCount, double currentPrice, int &outZone, double &outTargetPrice)
{
  // currentOrderCount = จำนวนออเดอร์ที่มีอยู่แล้ว (ไม่นับใบแรก)
  int totalNeeded = 0;
  
  for(int z=0; z<g_ZoneConfig.totalZones; z++)
  {
    totalNeeded += g_ZoneConfig.zoneOrders[z];
    
    // ถ้าจำนวนออเดอร์ปัจจุบันน้อยกว่าจำนวนที่ควรมีในโซนนี้
    if(currentOrderCount < totalNeeded)
    {
      // คำนวณระยะห่างจากออเดอร์แรก
      int orderInZone = currentOrderCount - (totalNeeded - g_ZoneConfig.zoneOrders[z]);
      
      // คำนวณราคาเป้าหมาย
      double distancePoints = 0;
      for(int prevZ=0; prevZ<z; prevZ++)
      {
        distancePoints += g_ZoneConfig.zoneOrders[prevZ] * g_ZoneConfig.zoneSpacing[prevZ];
      }
      distancePoints += (orderInZone + 1) * g_ZoneConfig.zoneSpacing[z];
      
      if(IsBuy(first.type))
      {
        outTargetPrice = first.price - pips((int)distancePoints);
        if(currentPrice <= outTargetPrice)
        {
          outZone = z;
          return true;
        }
      }
      else // Sell
      {
        outTargetPrice = first.price + pips((int)distancePoints);
        if(currentPrice >= outTargetPrice)
        {
          outZone = z;
          return true;
        }
      }
      
      return false; // ยังไม่ถึงราคาเป้าหมาย
    }
  }
  
  return false; // ครบจำนวนออเดอร์ทุกโซนแล้ว
}

// -------------------------------------------------------------------
void DisplayProfitInfo()
{
  ProfitInfo buyInfo = CalculateProfit(POSITION_TYPE_BUY);
  ProfitInfo sellInfo = CalculateProfit(POSITION_TYPE_SELL);
  
  static datetime lastDisplay = 0;
  if(TimeCurrent() - lastDisplay < 1) return;
  lastDisplay = TimeCurrent();
  
  string info = StringFormat("\n=== Profit Info [%s] ===\n", _Symbol);
  info += StringFormat("Mode: %s\n", EnumToString(GridMode));
  info += StringFormat("BUY  → P/L: $%.2f | Pos: %d | Vol: %.2f\n", 
                       buyInfo.profit, buyInfo.count, buyInfo.volume);
  info += StringFormat("SELL → P/L: $%.2f | Pos: %d | Vol: %.2f\n", 
                       sellInfo.profit, sellInfo.count, sellInfo.volume);
  info += StringFormat("NET  → P/L: $%.2f\n", buyInfo.profit + sellInfo.profit);
  info += "==========================\n";
  
  Comment(info);
}

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

// -------------------------------------------------------------------
// ฟังก์ชันหลักในการตัดสินใจเปิดออเดอร์เพิ่ม
void MaybeOpenAdd(const PosInfo &first)
{
  int sameSideCount = CountSameSide(first.type);
  int addsSoFar = sameSideCount - 1; // ไม่นับใบแรก
  
  double price = (first.type==POSITION_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_BID)
                                                 : SymbolInfoDouble(_Symbol, SYMBOL_ASK);

  // ห้ามเปิดเพิ่มเลย SL ของออเดอร์แรก
  if(first.sl>0){
    if(IsBuy(first.type) && price <= first.sl) return;
    if(IsSell(first.type) && price >= first.sl) return;
  }
  
  // เลือกโหมด Grid
  if(GridMode == GRID_NORMAL)
  {
    MaybeOpenAdd_Normal(first, addsSoFar, price);
  }
  else // GRID_ZONE
  {
    MaybeOpenAdd_Zone(first, addsSoFar, price);
  }
}

// Grid แบบปกติ
void MaybeOpenAdd_Normal(const PosInfo &first, int addsSoFar, double price)
{
  // ตรวจสอบจำนวนสูงสุด
  if(MaxAdds>0 && addsSoFar>=MaxAdds) return;

  double delta = (price - first.price) / _Point;
  double needed = (double)AddStep_points;

  if((IsBuy(first.type) && delta <= -needed) || (IsSell(first.type) && delta >= needed))
  {
    if(!HasNearbyOrderSameSide(price, first.type, MinReopenSpacing_points))
    {
      double lotFirst = first.lots;
      double nextLot  = lotFirst * MathPow(LotMultiplier, (addsSoFar+1));
      nextLot = NormalizeLot(nextLot);

      double sl, tp;
      CalcTP_SL_forAdd(first, sl, tp);

      OpenMarket(first.type==POSITION_TYPE_BUY ? ORDER_TYPE_BUY : ORDER_TYPE_SELL, nextLot, sl, tp);
    }
  }
}

// Grid แบบโซน
void MaybeOpenAdd_Zone(const PosInfo &first, int addsSoFar, double price)
{
  // ตรวจสอบจำนวนสูงสุด
  if(addsSoFar >= g_ZoneConfig.maxOrders) return;
  
  int targetZone;
  double targetPrice;
  
  if(ShouldOpenAtZone(first, addsSoFar, price, targetZone, targetPrice))
  {
    if(!HasNearbyOrderSameSide(price, first.type, MinReopenSpacing_points))
    {
      double lotFirst = first.lots;
      double nextLot  = lotFirst * MathPow(LotMultiplier, (addsSoFar+1));
      nextLot = NormalizeLot(nextLot);

      double sl, tp;
      CalcTP_SL_forAdd(first, sl, tp);

      Print(StringFormat("Opening Zone %d order #%d at price %.5f", 
            targetZone+1, addsSoFar+1, price));
      
      OpenMarket(first.type==POSITION_TYPE_BUY ? ORDER_TYPE_BUY : ORDER_TYPE_SELL, nextLot, sl, tp);
    }
  }
}

// -------------------------------------------------------------------
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
  ProfitInfo info = CalculateProfit(first.type);
  if(info.profit <= 0) return;

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
  req.action   = TRADE_ACTION_DEAL;
  req.symbol   = _Symbol;
  req.volume   = lot;
  req.magic    = InpMagic;
  req.type     = type;
  req.deviation= 20;
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
  
  Print(StringFormat("Opened %s: Ticket=%d, Lot=%.2f, Price=%.5f", 
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
