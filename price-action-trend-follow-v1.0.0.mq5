//+------------------------------------------------------------------+
//|                                                    PriceActionEA |
//|               Trend-follow + Break Swing + RR 1:1 + Spread Buff  |
//+------------------------------------------------------------------+
#property strict

//---- Inputs
input ENUM_TIMEFRAMES InpTF            = PERIOD_M15;    // Timeframe ทำงานของสัญญาณ
input int             FastEMA          = 50;            // EMA เร็ว (เช็คเทรนด์)
input int             SlowEMA          = 200;           // EMA ช้า (เช็คเทรนด์)
input int             PivotLeftRight   = 3;             // จำนวนแท่งซ้าย/ขวา เพื่อยืนยัน Swing (pivot)
input int             LookbackBars     = 200;           // ย้อนหลังสูงสุดเพื่อค้นหา Swing
input double          ExtraBufferPts   = 10;            // เผื่อ SL เพิ่ม (points) นอกเหนือจากสเปรด
input bool            UseRiskPercent   = true;          // ใช้คำนวณ Lot ตามความเสี่ยง?
input double          RiskPercent      = 1.0;           // % ความเสี่ยงต่อดีล (ถ้า UseRiskPercent=true)
input double          FixedLot         = 0.10;          // Fixed lot (ถ้า UseRiskPercent=false)
input int             SlippagePts      = 20;            // Slippage (points)
input int             Magic            = 20251010;      // Magic number
input bool            AllowBuy         = true;          // อนุญาตฝั่ง Buy
input bool            AllowSell        = true;          // อนุญาตฝั่ง Sell
input bool            OneTradePerBar   = true;          // ป้องกันเข้าออเดอร์ซ้ำในแท่งเดียวกัน

//---- Globals
datetime g_lastBarTime = 0;

//---- Utilities
bool IsNewBar()
{
   datetime t = iTime(_Symbol, InpTF, 0);
   if(t != g_lastBarTime)
   {
      g_lastBarTime = t;
      return true;
   }
   return false;
}

double GetSpreadPoints()
{
   long spread_points=0;
   if(SymbolInfoInteger(_Symbol, SYMBOL_SPREAD, spread_points))
      return (double)spread_points;
   // fallback: calc from Bid/Ask
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   return (ask - bid) / _Point;
}

bool HasOpenPosition(int magic, int direction/*1=Buy,-1=Sell,0=any*/)
{
   for(int i=0;i<PositionsTotal();i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
      {
         if((int)PositionGetInteger(POSITION_MAGIC) != magic) continue;
         if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
         long type = PositionGetInteger(POSITION_TYPE);
         if(direction== 1 && type==POSITION_TYPE_BUY)  return true;
         if(direction==-1 && type==POSITION_TYPE_SELL) return true;
         if(direction== 0) return true;
      }
   }
   // also prevent duplicated pending orders with same magic
   for(int i=0;i<OrdersTotal();i++)
   {
      ulong ot = OrderGetTicket(i);
      if(OrderSelect(ot))
      {
         if((int)OrderGetInteger(ORDER_MAGIC) != magic) continue;
         if(OrderGetString(ORDER_SYMBOL) != _Symbol)    continue;
         return true;
      }
   }
   return false;
}

//---- Swing pivot finder: return last confirmed swing high/low price & index
bool FindLastSwingHigh(int lr, int lookback, double &price, int &barIndex)
{
   // pivot high: High[i] > High[i-1..i-lr] AND High[i] >= High[i+1..i+lr]
   for(int i=lr+1; i< MathMin(lookback, 10000); i++)
   {
      bool isHigh=true;
      double H = iHigh(_Symbol, InpTF, i);
      for(int l=1; l<=lr; l++)
      {
         if(H <= iHigh(_Symbol, InpTF, i-l)) { isHigh=false; break; }
         if(H <  iHigh(_Symbol, InpTF, i+l)) { isHigh=false; break; }
      }
      if(isHigh)
      {
         price = H;
         barIndex = i;
         return true;
      }
   }
   return false;
}

bool FindLastSwingLow(int lr, int lookback, double &price, int &barIndex)
{
   for(int i=lr+1; i< MathMin(lookback, 10000); i++)
   {
      bool isLow=true;
      double L = iLow(_Symbol, InpTF, i);
      for(int l=1; l<=lr; l++)
      {
         if(L >= iLow(_Symbol, InpTF, i-l)) { isLow=false; break; }
         if(L >  iLow(_Symbol, InpTF, i+l)) { isLow=false; break; }
      }
      if(isLow)
      {
         price = L;
         barIndex = i;
         return true;
      }
   }
   return false;
}

//---- Trend by EMA cross: Fast > Slow => uptrend
int GetTrend()
{
   double fast = iMA(_Symbol, InpTF, FastEMA, 0, MODE_EMA, PRICE_CLOSE);
   double slow = iMA(_Symbol, InpTF, SlowEMA, 0, MODE_EMA, PRICE_CLOSE);
   if(fast > slow) return 1;
   if(fast < slow) return -1;
   return 0;
}

//---- Risk-based lot calculation
double CalcLotsByRisk(double stop_distance_points)
{
   // Value per point for 1 lot:
   double tick_value   = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tick_size    = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double point_value_per_lot = (tick_value / tick_size) * _Point; // conservative

   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double risk_money = balance * (RiskPercent/100.0);
   if(stop_distance_points <= 0) return 0.0;

   // money per lot for that stop distance:
   double money_per_lot = (stop_distance_points * point_value_per_lot);
   if(money_per_lot<=0) return 0.0;

   double lots = risk_money / money_per_lot;

   // clamp to broker min/max/step
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double step   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   lots = MathMax(minLot, MathMin(lots, maxLot));
   // round to step
   lots = MathFloor(lots/step)*step;
   return NormalizeDouble(lots, 2);
}

bool RespectStopsLevel(double &sl, double &tp, int type)
{
   // Ensure SL/TP not violating stop level or freeze level
   int stops_level = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   int freeze      = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL);
   int req_dist    = MathMax(stops_level, freeze);
   if(req_dist<=0) return true;

   double price = (type==ORDER_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_BID)
                                         : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   if(type==ORDER_TYPE_BUY)
   {
      if((price - sl)/_Point < req_dist) sl = price - req_dist*_Point;
      if((tp - price)/_Point < req_dist) tp = price + req_dist*_Point;
   }
   else
   {
      if((sl - price)/_Point < req_dist) sl = price + req_dist*_Point;
      if((price - tp)/_Point < req_dist) tp = price - req_dist*_Point;
   }
   return true;
}

bool SendOrder(int order_type, double lots, double sl, double tp)
{
   MqlTradeRequest  req;
   MqlTradeResult   res;
   ZeroMemory(req); ZeroMemory(res);

   double price = (order_type==ORDER_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                                               : SymbolInfoDouble(_Symbol, SYMBOL_BID);

   req.action      = TRADE_ACTION_DEAL;
   req.symbol      = _Symbol;
   req.magic       = Magic;
   req.type        = (ENUM_ORDER_TYPE)order_type;
   req.volume      = lots;
   req.price       = price;
   req.sl          = sl;
   req.tp          = tp;
   req.deviation   = SlippagePts;
   req.type_filling= ORDER_FILLING_FOK;

   bool sent = OrderSend(req, res);
   if(!sent || res.retcode != TRADE_RETCODE_DONE)
   {
      PrintFormat("OrderSend failed. retcode=%d, comment=%s", res.retcode, res.comment);
      return false;
   }
   return true;
}

//+------------------------------------------------------------------+
//| Expert init/deinit                                               |
//+------------------------------------------------------------------+
int OnInit()
{
   g_lastBarTime = iTime(_Symbol, InpTF, 0);
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert tick                                                      |
//+------------------------------------------------------------------+
void OnTick()
{
   // ทำงานเฉพาะเมื่อเกิดแท่งใหม่ (ลดสัญญาณซ้ำ/รีเพนท์จาก pivot)
   if(OneTradePerBar && !IsNewBar()) return;

   // หลีกเลี่ยงเปิดซ้ำถ้ามีออเดอร์เดิม
   if(HasOpenPosition(Magic, 0)) return;

   int trend = GetTrend();
   if(trend==0) return;

   // ค้นหา Swing ล่าสุด
   double swingHigh; int shIndex;
   double swingLow;  int slIndex;
   bool okH = FindLastSwingHigh(PivotLeftRight, LookbackBars, swingHigh, shIndex);
   bool okL = FindLastSwingLow (PivotLeftRight, LookbackBars, swingLow,  slIndex);
   if(!okH || !okL) return;

   // ราคาและสเปรด
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double close0 = iClose(_Symbol, InpTF, 1); // ใช้แท่งที่เพิ่งปิด (bar index 1)
   double spreadPts = GetSpreadPoints();
   double bufferPts = spreadPts + ExtraBufferPts;

   // เงื่อนไขเข้าเทรดแบบ Break Swing + Trend
   if(trend>0 && AllowBuy)
   {
      // ปิดแท่งทะลุ Swing High
      if(close0 > swingHigh)
      {
         // SL ต่ำกว่า Swing Low - buffer
         double sl_price = swingLow - bufferPts*_Point;
         // RR 1:1
         double entry    = ask;
         double riskPts  = (entry - sl_price)/_Point;
         if(riskPts <= 0) return;

         double lots = UseRiskPercent ? CalcLotsByRisk(riskPts) : FixedLot;
         if(lots <= 0) return;

         double tp_price = entry + riskPts*_Point;

         RespectStopsLevel(sl_price, tp_price, ORDER_TYPE_BUY);
         SendOrder(ORDER_TYPE_BUY, lots, sl_price, tp_price);
      }
   }
   else if(trend<0 && AllowSell)
   {
      // ปิดแท่งหลุด Swing Low
      if(close0 < swingLow)
      {
         // SL สูงกว่า Swing High + buffer
         double sl_price = swingHigh + bufferPts*_Point;
         // RR 1:1
         double entry    = bid;
         double riskPts  = (sl_price - entry)/_Point;
         if(riskPts <= 0) return;

         double lots = UseRiskPercent ? CalcLotsByRisk(riskPts) : FixedLot;
         if(lots <= 0) return;

         double tp_price = entry - riskPts*_Point;

         RespectStopsLevel(sl_price, tp_price, ORDER_TYPE_SELL);
         SendOrder(ORDER_TYPE_SELL, lots, sl_price, tp_price);
      }
   }
}
//+------------------------------------------------------------------+
