//+------------------------------------------------------------------+
//|                                    GridAdoptFirst_AutoTrend.mq5  |
//|                   EA: Zone Grid with Auto Trend Entry            |
//+------------------------------------------------------------------+
#property strict

// Enum สำหรับเลือกโหมด Grid
enum ENUM_GRID_MODE
{
  GRID_NORMAL,    // Grid แบบปกติ (ระยะเท่ากันทุกออเดอร์)
  GRID_ZONE       // Grid แบบโซน (แบ่งเป็นโซน มีระยะต่างกันในแต่ละโซน)
};

input long   InpMagic                = 2025103101; // Magic number

//===== First Order Mode =====
input bool   AutoOpenFirst           = false;    // เปิดออเดอร์แรกด้วยตนเอง
input bool   AutoOpenBothSides       = false;    // เปิดทั้ง Buy และ Sell พร้อมกัน (Manual)
input ENUM_ORDER_TYPE InpFirstSide   = ORDER_TYPE_BUY;  // ทิศของออเดอร์แรก (Manual)

//===== Auto Trend Entry Settings =====
input bool   AutoTrendEntry          = true;     // เปิดออเดอร์แรกแบบ Auto ตามเทรนด์
input ENUM_TIMEFRAMES TrendTimeframe = PERIOD_M5; // Timeframe สำหรับวิเคราะห์เทรนด์
input int    EMA_Fast                = 9;        // EMA เส้นเร็ว
input int    EMA_Medium              = 21;       // EMA เส้นกลาง
input int    EMA_Slow                = 50;       // EMA เส้นช้า
input int    RSI_Period              = 14;       // RSI Period
input double RSI_Oversold            = 30;       // RSI Oversold Level (สำหรับ Buy)
input double RSI_Overbought          = 70;       // RSI Overbought Level (สำหรับ Sell)
input int    Pullback_Bars           = 3;        // จำนวน Bars ที่ต้อง Pullback
input int    MinTrendBars            = 5;        // จำนวน Bars ขั้นต่ำที่ EMA เรียงตัว

input double InpFirstLot             = 0.01;     // ล็อตออเดอร์แรก

input int    TP_points               = 20000;      // TP ของออเดอร์แรก (จุด)
input int    SL_points               = 150000;     // SL ของออเดอร์แรก (จุด)

//===== Grid Mode Selection =====
input ENUM_GRID_MODE GridMode        = GRID_NORMAL; // โหมดการเปิดออเดอร์

//===== Normal Grid Settings =====
input int    AddStep_points          = 5000;      // ระยะเปิดออเดอร์เพิ่ม (GRID_NORMAL)
input int    MaxAdds                 = 0;        // จำนวนออเดอร์เพิ่มสูงสุด (0=ไม่จำกัด)

//===== Zone Grid Settings =====
input int    ZoneCount               = 3;        // จำนวนโซน (GRID_ZONE)
input string ZoneOrdersInput         = "3,5,7";  // จำนวนออเดอร์ในแต่ละโซน (คั่นด้วย ,)
input string ZoneSpacingInput        = "3000,5000,7000"; // ระยะห่างในแต่ละโซน (จุด, คั่นด้วย ,)
input string ZoneGapInput            = "2000,3000"; // ระยะห่างระหว่างโซน (จุด, คั่นด้วย ,)

input double LotMultiplier           = 1.1;      // ตัวคูณล็อตเมื่อเปิดเพิ่ม
input int    LotDecimals             = 2;        // ปัดตำแหน่งทศนิยมล็อต
input double BlockedMaxLot           = 0.8;       // ล็อตสูงสุด

input bool   InpIncludeForeignPositions_ = true;     // รวมออเดอร์ที่ไม่ได้ใช้ Magic นี้
input bool   SameTP_SL_asFirst       = true;     // ออเดอร์เพิ่มตั้ง TP/SL ที่ราคาเดียวกันกับออเดอร์แรก

// Trailing Stop parameters
input int    StartTrail_aboveAvg_points = 2000;   // เริ่ม Trailing เมื่อราคาหนีจากราคาเฉลี่ย
input int    TrailOffset_points         = 2000;   // ระยะ SL ตามราคาปัจจุบัน
input bool   TrailOnlyTighten           = true;  // ขยับ SL แค่เข้าหากำไร

input int    MinReopenSpacing_points    = 5000;    // กันเปิดซ้ำซ้อนใกล้ราคาเดิม (จุด)

// -------------------------------------------------------------------
// โครงสร้างข้อมูลสำหรับ Zone Grid
struct ZoneConfig
{
  int zoneOrders[];      // จำนวนออเดอร์ในแต่ละโซน
  int zoneSpacing[];     // ระยะห่างในแต่ละโซน (จุด)
  int zoneGaps[];        // ระยะห่างระหว่างโซน (จุด)
  int totalZones;        // จำนวนโซนทั้งหมด
  int maxOrders;         // จำนวนออเดอร์สูงสุดรวมทุกโซน
};

ZoneConfig g_ZoneConfig;

// Handles สำหรับ Indicators
int h_EMA_Fast, h_EMA_Medium, h_EMA_Slow, h_RSI;

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

enum TREND_STATE
{
  TREND_NONE,      // ไม่มีเทรนด์ชัดเจน (Sideway)
  TREND_UP,        // Uptrend
  TREND_DOWN       // Downtrend
};

// -------------------------------------------------------------------
int OnInit()
{ 
  Print("=== EA Started - Auto Trend Entry System ===");
  Print("Grid Mode: ", EnumToString(GridMode));
  Print("Auto Trend Entry: ", AutoTrendEntry);
  
  // สร้าง Indicator Handles
  if(AutoTrendEntry)
  {
    h_EMA_Fast   = iMA(_Symbol, TrendTimeframe, EMA_Fast, 0, MODE_EMA, PRICE_CLOSE);
    h_EMA_Medium = iMA(_Symbol, TrendTimeframe, EMA_Medium, 0, MODE_EMA, PRICE_CLOSE);
    h_EMA_Slow   = iMA(_Symbol, TrendTimeframe, EMA_Slow, 0, MODE_EMA, PRICE_CLOSE);
    h_RSI        = iRSI(_Symbol, TrendTimeframe, RSI_Period, PRICE_CLOSE);
    
    if(h_EMA_Fast == INVALID_HANDLE || h_EMA_Medium == INVALID_HANDLE || 
       h_EMA_Slow == INVALID_HANDLE || h_RSI == INVALID_HANDLE)
    {
      Print("ERROR: Cannot create indicator handles!");
      return(INIT_FAILED);
    }
    
    Print("Trend Analysis: EMA(", EMA_Fast, ",", EMA_Medium, ",", EMA_Slow, ") + RSI(", RSI_Period, ")");
    Print("RSI Levels: Oversold=", RSI_Oversold, " Overbought=", RSI_Overbought);
  }
  
  // Parse Zone Configuration
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

void OnDeinit(const int reason)
{ 
  // ปล่อย Indicator Handles
  if(h_EMA_Fast != INVALID_HANDLE) IndicatorRelease(h_EMA_Fast);
  if(h_EMA_Medium != INVALID_HANDLE) IndicatorRelease(h_EMA_Medium);
  if(h_EMA_Slow != INVALID_HANDLE) IndicatorRelease(h_EMA_Slow);
  if(h_RSI != INVALID_HANDLE) IndicatorRelease(h_RSI);
}

void OnTick()
{
  // แสดงข้อมูล Profit แยกตาม Position Type
  DisplayProfitInfo();
  
  // ตรวจสอบว่ามีออเดอร์หรือไม่
  int buyCount = CountPositionsByType(POSITION_TYPE_BUY);
  int sellCount = CountPositionsByType(POSITION_TYPE_SELL);
  
  // 1) ถ้าไม่มีออเดอร์เลย → เปิดออเดอร์แรก
  if(buyCount == 0 && sellCount == 0)
  {
    if(AutoTrendEntry)
    {
      // เปิดออเดอร์แรกแบบ Auto ตามเทรนด์
      CheckAndOpenAutoTrend();
    }
    else if(AutoOpenFirst)
    {
      // เปิดออเดอร์แรกแบบ Manual
      if(AutoOpenBothSides){
        OpenFirst(ORDER_TYPE_BUY);
        OpenFirst(ORDER_TYPE_SELL);
      } else {
        OpenFirst(InpFirstSide);
      }
    }
    return;
  }

  // 2) ถ้ามีออเดอร์ Buy แล้ว และ AutoTrendEntry เปิด → ตรวจสอบว่าจะเปิด Sell เพิ่มได้ไหม
  if(AutoTrendEntry && buyCount > 0 && sellCount == 0)
  {
    CheckAndOpenAutoTrend();
  }
  
  // 3) ถ้ามีออเดอร์ Sell แล้ว และ AutoTrendEntry เปิด → ตรวจสอบว่าจะเปิด Buy เพิ่มได้ไหม
  if(AutoTrendEntry && sellCount > 0 && buyCount == 0)
  {
    CheckAndOpenAutoTrend();
  }

  // 4) จัดการฝั่ง Buy
  if(buyCount > 0){
    PosInfo firstBuy;
    if(FindFirstPositionByType(POSITION_TYPE_BUY, firstBuy)){
      EnsureFirstHasTPSL(firstBuy);
      MaybeOpenAdd(firstBuy);
      MaybeTrailAll(firstBuy);
    }
  }

  // 5) จัดการฝั่ง Sell
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
// ตรวจสอบและเปิดออเดอร์แรกตามเทรนด์
void CheckAndOpenAutoTrend()
{
  // ตรวจสอบว่ามีออเดอร์อะไรอยู่บ้าง
  int buyCount = CountPositionsByType(POSITION_TYPE_BUY);
  int sellCount = CountPositionsByType(POSITION_TYPE_SELL);
  
  // วิเคราะห์เทรนด์
  TREND_STATE trend = AnalyzeTrend();
  
  if(trend == TREND_NONE)
  {
    // Sideway - ไม่เปิดออเดอร์
    return;
  }
  
  // ตรวจสอบ Pullback
  bool hasPullback = CheckPullback(trend);
  if(!hasPullback) return;
  
  // ตรวจสอบ RSI
  double rsi = GetRSI(0);
  
  // Uptrend + Pullback + RSI Oversold → พิจารณาเปิด Buy
  if(trend == TREND_UP && buyCount == 0)
  {
    if(rsi <= RSI_Oversold)
    {
      Print("Auto Entry Signal: BUY - Uptrend + Pullback + RSI=", DoubleToString(rsi, 2));
      OpenFirst(ORDER_TYPE_BUY);
    }
  }
  
  // Downtrend + Pullback + RSI Overbought → พิจารณาเปิด Sell
  if(trend == TREND_DOWN && sellCount == 0)
  {
    if(rsi >= RSI_Overbought)
    {
      Print("Auto Entry Signal: SELL - Downtrend + Pullback + RSI=", DoubleToString(rsi, 2));
      OpenFirst(ORDER_TYPE_SELL);
    }
  }
}

// วิเคราะห์เทรนด์จาก EMA 3 เส้น
TREND_STATE AnalyzeTrend()
{
  double emaFast[], emaMedium[], emaSlow[];
  ArraySetAsSeries(emaFast, true);
  ArraySetAsSeries(emaMedium, true);
  ArraySetAsSeries(emaSlow, true);
  
  if(CopyBuffer(h_EMA_Fast, 0, 0, MinTrendBars + 1, emaFast) <= 0) return TREND_NONE;
  if(CopyBuffer(h_EMA_Medium, 0, 0, MinTrendBars + 1, emaMedium) <= 0) return TREND_NONE;
  if(CopyBuffer(h_EMA_Slow, 0, 0, MinTrendBars + 1, emaSlow) <= 0) return TREND_NONE;
  
  // ตรวจสอบว่า EMA เรียงตัวต่อเนื่องกี่ Bar
  int uptrendBars = 0;
  int downtrendBars = 0;
  
  for(int i=0; i<MinTrendBars; i++)
  {
    // Uptrend: Fast > Medium > Slow
    if(emaFast[i] > emaMedium[i] && emaMedium[i] > emaSlow[i])
      uptrendBars++;
    
    // Downtrend: Fast < Medium < Slow
    if(emaFast[i] < emaMedium[i] && emaMedium[i] < emaSlow[i])
      downtrendBars++;
  }
  
  // ต้องเรียงตัวครบตามจำนวน MinTrendBars
  if(uptrendBars >= MinTrendBars)
    return TREND_UP;
  
  if(downtrendBars >= MinTrendBars)
    return TREND_DOWN;
  
  return TREND_NONE; // Sideway
}

// ตรวจสอบ Pullback
bool CheckPullback(TREND_STATE trend)
{
  MqlRates rates[];
  ArraySetAsSeries(rates, true);
  
  if(CopyRates(_Symbol, TrendTimeframe, 0, Pullback_Bars + 1, rates) <= 0)
    return false;
  
  if(trend == TREND_UP)
  {
    // ตรวจสอบว่ามี Pullback (ราคาปรับลง) ใน Pullback_Bars ที่ผ่านมา
    int downBars = 0;
    for(int i=1; i<=Pullback_Bars; i++)
    {
      if(rates[i].close < rates[i].open) // Bearish candle
        downBars++;
    }
    
    // ต้องมี Pullback อย่างน้อย 1 bar และ bar ปัจจุบันเริ่มกลับตัวขึ้น
    if(downBars >= 1 && rates[0].close > rates[0].open)
      return true;
  }
  else if(trend == TREND_DOWN)
  {
    // ตรวจสอบว่ามี Pullback (ราคาปรับขึ้น)
    int upBars = 0;
    for(int i=1; i<=Pullback_Bars; i++)
    {
      if(rates[i].close > rates[i].open) // Bullish candle
        upBars++;
    }
    
    // ต้องมี Pullback อย่างน้อย 1 bar และ bar ปัจจุบันเริ่มกลับตัวลง
    if(upBars >= 1 && rates[0].close < rates[0].open)
      return true;
  }
  
  return false;
}

// อ่านค่า RSI
double GetRSI(int shift)
{
  double rsi[];
  ArraySetAsSeries(rsi, true);
  
  if(CopyBuffer(h_RSI, 0, shift, 1, rsi) <= 0)
    return -1;
  
  return rsi[0];
}

// -------------------------------------------------------------------
// ฟังก์ชันสำหรับ Parse Zone Configuration
bool ParseZoneConfig()
{
  ArrayResize(g_ZoneConfig.zoneOrders, 0);
  ArrayResize(g_ZoneConfig.zoneSpacing, 0);
  ArrayResize(g_ZoneConfig.zoneGaps, 0);
  
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
  
  // Parse ระยะห่างระหว่างโซน (จำนวนต้องน้อยกว่า ZoneCount 1)
  string gapArr[];
  int gapCount = StringSplit(ZoneGapInput, ',', gapArr);
  if(gapCount != ZoneCount - 1 && ZoneCount > 1)
  {
    Print("ERROR: ระยะห่างระหว่างโซนต้องมี ", ZoneCount-1, " ค่า");
    return false;
  }
  
  ArrayResize(g_ZoneConfig.zoneOrders, ZoneCount);
  ArrayResize(g_ZoneConfig.zoneSpacing, ZoneCount);
  ArrayResize(g_ZoneConfig.zoneGaps, ZoneCount - 1);
  
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
  
  // Parse ระยะห่างระหว่างโซน
  for(int i=0; i<ZoneCount-1; i++)
  {
    StringTrimLeft(gapArr[i]);
    StringTrimRight(gapArr[i]);
    g_ZoneConfig.zoneGaps[i] = (int)StringToInteger(gapArr[i]);
    
    if(g_ZoneConfig.zoneGaps[i] < 0)
    {
      Print("ERROR: ระยะห่างระหว่างโซนต้องเป็นค่าบวก");
      return false;
    }
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
    
    if(i < g_ZoneConfig.totalZones - 1)
    {
      Print(StringFormat("  → Gap to Zone %d: %d points", i+2, g_ZoneConfig.zoneGaps[i]));
    }
  }
  Print("================================");
}

// -------------------------------------------------------------------
// คำนวณว่าควรเปิดออเดอร์ที่ระดับไหน (สำหรับ Zone Grid พร้อมระยะห่างระหว่างโซน)
bool ShouldOpenAtZone(const PosInfo &first, int currentOrderCount, double currentPrice, int &outZone, double &outTargetPrice)
{
  int totalNeeded = 0;
  
  for(int z=0; z<g_ZoneConfig.totalZones; z++)
  {
    totalNeeded += g_ZoneConfig.zoneOrders[z];
    
    if(currentOrderCount < totalNeeded)
    {
      int orderInZone = currentOrderCount - (totalNeeded - g_ZoneConfig.zoneOrders[z]);
      
      // คำนวณระยะห่างรวมจากออเดอร์แรก (รวมระยะห่างระหว่างโซน)
      double distancePoints = 0;
      
      // ระยะห่างจากโซนก่อนหน้า
      for(int prevZ=0; prevZ<z; prevZ++)
      {
        distancePoints += g_ZoneConfig.zoneOrders[prevZ] * g_ZoneConfig.zoneSpacing[prevZ];
        
        // เพิ่มระยะห่างระหว่างโซน
        if(prevZ < g_ZoneConfig.totalZones - 1)
        {
          distancePoints += g_ZoneConfig.zoneGaps[prevZ];
        }
      }
      
      // ระยะห่างภายในโซนปัจจุบัน
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
      
      return false;
    }
  }
  
  return false;
}

// -------------------------------------------------------------------
void DisplayProfitInfo()
{
  ProfitInfo buyInfo = CalculateProfit(POSITION_TYPE_BUY);
  ProfitInfo sellInfo = CalculateProfit(POSITION_TYPE_SELL);
  
  static datetime lastDisplay = 0;
  if(TimeCurrent() - lastDisplay < 1) return;
  lastDisplay = TimeCurrent();
  
  string info = StringFormat("\n=== %s [%s] ===\n", _Symbol, EnumToString(GridMode));
  
  if(AutoTrendEntry)
  {
    TREND_STATE trend = AnalyzeTrend();
    double rsi = GetRSI(0);
    info += StringFormat("Trend: %s | RSI: %.1f\n", 
                         trend==TREND_UP?"UP":trend==TREND_DOWN?"DOWN":"SIDEWAY", rsi);
  }
  
  info += StringFormat("BUY  → P/L: $%.2f | Pos: %d | Vol: %.2f\n", 
                       buyInfo.profit, buyInfo.count, buyInfo.volume);
  info += StringFormat("SELL → P/L: $%.2f | Pos: %d | Vol: %.2f\n", 
                       sellInfo.profit, sellInfo.count, sellInfo.volume);
  info += StringFormat("NET  → P/L: $%.2f\n", buyInfo.profit + sellInfo.profit);
  info += "=============================\n";
  
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
    
    if(!InpIncludeForeignPositions_ && (long)PositionGetInteger(POSITION_MAGIC) != InpMagic) 
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
    
    if(!InpIncludeForeignPositions_ && (long)PositionGetInteger(POSITION_MAGIC)!=InpMagic) 
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
    if(!InpIncludeForeignPositions_ && magic!=InpMagic) continue;

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
  
  double price = (first.type==POSITION_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_BID)
                                                 : SymbolInfoDouble(_Symbol, SYMBOL_ASK);

  if(first.sl>0){
    if(IsBuy(first.type) && price <= first.sl) return;
    if(IsSell(first.type) && price >= first.sl) return;
  }
  
  if(GridMode == GRID_NORMAL)
  {
    MaybeOpenAdd_Normal(first, addsSoFar, price);
  }
  else
  {
    MaybeOpenAdd_Zone(first, addsSoFar, price);
  }
}

void MaybeOpenAdd_Normal(const PosInfo &first, int addsSoFar, double price)
{
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

void MaybeOpenAdd_Zone(const PosInfo &first, int addsSoFar, double price)
{
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

int CountSameSide(ENUM_POSITION_TYPE side)
{
  int total=PositionsTotal(), cnt=0;
  for(int i=0;i<total;i++){
    ulong ticket=PositionGetTicket(i);
    if(ticket==0) continue;
    if(!PositionSelectByTicket(ticket)) continue;
    if(!IsMySymbol((string)PositionGetString(POSITION_SYMBOL))) continue;

    if(!InpIncludeForeignPositions_ && (long)PositionGetInteger(POSITION_MAGIC)!=InpMagic) continue;

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
    if(!InpIncludeForeignPositions_ && (long)PositionGetInteger(POSITION_MAGIC)!=InpMagic) continue;

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
    if(!InpIncludeForeignPositions_ && (long)PositionGetInteger(POSITION_MAGIC)!=InpMagic) continue;
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
    if(!InpIncludeForeignPositions_ && (long)PositionGetInteger(POSITION_MAGIC)!=InpMagic) continue;
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
  
  double blockedLot = lot > BlockedMaxLot ? NormalizeLot(BlockedMaxLot): lot;
  req.action   = TRADE_ACTION_DEAL;
  req.symbol   = _Symbol;
  req.volume   = blockedLot;
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
