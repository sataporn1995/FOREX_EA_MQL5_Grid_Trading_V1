#property strict
#property copyright "PPongShared x ChatGPT"
#property version   "1.00"
#property description "Grid Trading with Pending BuyStop/SellStop, auto-shift and anti-duplicate"

#include <Trade/Trade.mqh>

enum GridMode
{
   MODE_BUY_ONLY = 0,
   MODE_SELL_ONLY = 1,
   MODE_BUY_SELL = 2
};

input GridMode InpMode                  = MODE_BUY_SELL;  // Trading Mode
input double   InpStartLot              = 0.01;           // Initial lot
input int      InpGridStepPoints        = 5000;            // GridStep (points)
input int      InpTPPoints              = 4000;            // TakeProfit (points)
input int      InpMaxPendingsPerSide    = 5;              // Max pendings per side
input ulong    InpMagic                 = 2025102001;       // Magic number
input int      InpMaxSlippagePoints     = 30;             // Slippage (market ops)
input bool     InpShowLevels            = true;           // Draw guide lines (debug)

CTrade trade;

// ---------- utilities ----------
double  g_point      = 0.0;
double  g_tick_size  = 0.0;
double  g_tick_value = 0.0;
int     g_digits     = 0;
long    g_stops_level= 0;

string  g_symbol;

double NormalizeToTick(double price)
{
   if(g_tick_size<=0.0) return price;
   double steps = MathRound(price / g_tick_size);
   return steps * g_tick_size;
}

double PointsToPrice(int pts){ return pts * g_point; }

bool RefreshSym()
{
   g_symbol = _Symbol;
   g_point  = SymbolInfoDouble(g_symbol, SYMBOL_POINT);
   g_tick_size = SymbolInfoDouble(g_symbol, SYMBOL_TRADE_TICK_SIZE);
   g_tick_value= SymbolInfoDouble(g_symbol, SYMBOL_TRADE_TICK_VALUE);
   g_digits = (int)SymbolInfoInteger(g_symbol, SYMBOL_DIGITS);
   g_stops_level = (long)SymbolInfoInteger(g_symbol, SYMBOL_TRADE_STOPS_LEVEL);
   return (g_point>0 && g_tick_size>0);
}

// quantize เป็น “ช่องกริด” ด้วยจำนวนจุดของ GridStep
long GridBucket(double price)
{
   double p_in_points = price / g_point;
   return (long)MathRound(p_in_points / (double)InpGridStepPoints);
}

bool PriceWithinSameGrid(double p1, double p2)
{
   // ถือว่า “ชนกัน” หากระยะห่าง < GridStep
   return (MathAbs(p1 - p2) < PointsToPrice(InpGridStepPoints));
}

bool IsMyOrder(const ulong ticket)
{
   if(!OrderSelect(ticket)) return false;
   if(OrderGetString(ORDER_SYMBOL)!=g_symbol) return false;
   if((ulong)OrderGetInteger(ORDER_MAGIC) != InpMagic) return false;
   return true;
}

bool IsMyPositionIdx(int idx)
{
   if(!PositionSelectByTicket(idx)) return false;
   if(PositionGetString(POSITION_SYMBOL)!=g_symbol) return false;
   if((ulong)PositionGetInteger(POSITION_MAGIC)!= InpMagic) return false;
   return true;
}

// collect orders (pendings only of our EA and symbol)
void CollectMyPendings(ENUM_ORDER_TYPE type_filter,
                       ulong &tickets[], double &prices[])
{
   ArrayResize(tickets,0);
   ArrayResize(prices,0);

   int total = (int)OrdersTotal();
   for(int i=0;i<total;i++)
   {
      ulong tk = OrderGetTicket(i);
      if(tk==0) continue;
      if(!OrderSelect(tk)) continue;

      if(OrderGetString(ORDER_SYMBOL)!=g_symbol) continue;
      if((ulong)OrderGetInteger(ORDER_MAGIC)!=InpMagic) continue;

      ENUM_ORDER_TYPE t = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
      if(t==type_filter)
      {
         double pr = OrderGetDouble(ORDER_PRICE_OPEN);
         int n = ArraySize(tickets);
         ArrayResize(tickets,n+1);
         ArrayResize(prices, n+1);
         tickets[n]=tk;
         prices[n]=pr;
      }
   }
}

// collect my open positions (market)
void CollectMyPositions(ENUM_POSITION_TYPE pos_filter,
                        double &prices[])
{
   ArrayResize(prices,0);
   int total = (int)PositionsTotal();
   for(int i=0;i<total;i++)
   {
      if(!IsMyPositionIdx(i)) continue;
      ENUM_POSITION_TYPE pt=(ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      if(pt==pos_filter)
      {
         double pr = PositionGetDouble(POSITION_PRICE_OPEN);
         int n = ArraySize(prices);
         ArrayResize(prices, n+1);
         prices[n]=pr;
      }
   }
}

// ป้องกันซ้ำ: มี pending/position อยู่ในช่องกริดเดียวกันหรือใกล้กว่า GridStep ไหม
bool OccupiedAround(double level_price,
                    const double &pend_prices[], const double &pos_prices[])
{
   for(int i=0;i<ArraySize(pend_prices);++i)
      if(PriceWithinSameGrid(level_price, pend_prices[i])) return true;
   for(int j=0;j<ArraySize(pos_prices);++j)
      if(PriceWithinSameGrid(level_price, pos_prices[j])) return true;
   return false;
}

// ---------- placement & cancel ----------
bool PlacePending(ENUM_ORDER_TYPE type, double price_level, double lots, double tp_points)
{
   MqlTradeRequest  req;
   MqlTradeResult   res;
   ZeroMemory(req); ZeroMemory(res);

   req.action = TRADE_ACTION_PENDING;
   req.symbol = g_symbol;
   req.magic  = (long)InpMagic;
   req.volume = lots;
   req.deviation = InpMaxSlippagePoints;

   price_level = NormalizeToTick(price_level);

   if(type==ORDER_TYPE_BUY_STOP)
   {
      req.type  = ORDER_TYPE_BUY_STOP;
      req.price = price_level;

      double tp = price_level + PointsToPrice((int)tp_points);
      req.tp = NormalizeDouble(tp, g_digits);
   }
   else if(type==ORDER_TYPE_SELL_STOP)
   {
      req.type  = ORDER_TYPE_SELL_STOP;
      req.price = price_level;

      double tp = price_level - PointsToPrice((int)tp_points);
      req.tp = NormalizeDouble(tp, g_digits);
   }
   else
      return false;

   // ระยะห้ามวางใกล้ตลาดเกิน stop level
   double ask = SymbolInfoDouble(g_symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(g_symbol, SYMBOL_BID);
   double min_dist = g_stops_level * g_point;

   if(type==ORDER_TYPE_BUY_STOP && (req.price - ask) < min_dist)
      req.price = NormalizeToTick(ask + min_dist);
   if(type==ORDER_TYPE_SELL_STOP && (bid - req.price) < min_dist)
      req.price = NormalizeToTick(bid - min_dist);

   bool ok = OrderSend(req, res);
   return ok && (res.retcode==TRADE_RETCODE_DONE || res.retcode==TRADE_RETCODE_PLACED);
}

bool CancelOrder(ulong ticket)
{
   if(!OrderSelect(ticket)) return false;
   return trade.OrderDelete(ticket);
}

// ---------- compute target grids ----------
/*
   Buy Stop: วาง “เหนือ” ราคา Ask:
   - เริ่มจาก level ล่างสุด = ceil((Ask)/step)*step
   - ต่อเนื่องขึ้นไปทีละ GridStep
*/
void ComputeBuyStopLevels(double ask, double &levels[])
{
   ArrayResize(levels, 0);
   double step = PointsToPrice(InpGridStepPoints);
   double start = MathCeil(ask / step) * step;

   for(int i=0;i<InpMaxPendingsPerSide;i++)
   {
      int n = ArraySize(levels);
      ArrayResize(levels, n+1);
      levels[n] = NormalizeToTick(start + step*i);
   }
}

/*
   Sell Stop: วาง “ต่ำกว่า” ราคา Bid:
   - เริ่มจาก level บนสุด = floor((Bid)/step)*step
   - ไล่ลงทีละ GridStep
*/
void ComputeSellStopLevels(double bid, double &levels[])
{
   ArrayResize(levels, 0);
   double step = PointsToPrice(InpGridStepPoints);
   double start = MathFloor(bid / step) * step;

   for(int i=0;i<InpMaxPendingsPerSide;i++)
   {
      int n = ArraySize(levels);
      ArrayResize(levels, n+1);
      levels[n] = NormalizeToTick(start - step*i);
   }
}

// ปรับหน้าต่าง (auto-shift): หากราคาเลยขอบกริดมากกว่า 1*GridStep ให้ “ขยับหน้าต่าง” อิงราคาปัจจุบัน
void AutoShiftBuyLevels(double ask, double &levels[])
{
   if(ArraySize(levels)==0) return;
   double step = PointsToPrice(InpGridStepPoints);

   // ถ้าราคาลงต่ำกว่า “BuyStop ล่างสุด” มากกว่า 1 step ⇒ คำนวณชุดใหม่จากราคา
   double lowest = levels[0];
   if(ask + step < lowest)
      ComputeBuyStopLevels(ask, levels);
}

void AutoShiftSellLevels(double bid, double &levels[])
{
   if(ArraySize(levels)==0) return;
   double step = PointsToPrice(InpGridStepPoints);

   // ถ้าราคาขึ้นสูงกว่า “SellStop บนสุด” มากกว่า 1 step ⇒ คำนวณชุดใหม่จากราคา
   double highest = levels[0];
   if(bid - step > highest)
      ComputeSellStopLevels(bid, levels);
}

// สร้าง/ซิงค์ pending orders ให้ตรงกับ levels เป้าหมาย + ลบส่วนเกิน + ป้องกันชนกริด
void SyncSide(ENUM_ORDER_TYPE side_type,
              const double &target_levels[],
              const double &pend_prices[], const ulong &pend_tickets[],
              const double &pos_prices[])
{
   // 1) ยกเลิกคำสั่งที่ “ไม่อยู่” ใน target levels (ถือว่าเลื่อนหน้าต่างแล้ว)
   for(int i=0;i<ArraySize(pend_tickets);++i)
   {
      bool found=false;
      for(int j=0;j<ArraySize(target_levels);++j)
      {
         if(MathAbs(pend_prices[i]-target_levels[j]) < (g_tick_size/2.0))
         { found=true; break; }
      }
      if(!found)
         CancelOrder(pend_tickets[i]);
   }

   // 2) เติมที่ขาด โดยเลี่ยงชนกริดกับ pending/position ปัจจุบัน
   // เก็บราคาที่เหลือหลังยกเลิก (รีเฟรชสั้นๆ)
   ulong tk2[]; double pr2[];
   CollectMyPendings(side_type, tk2, pr2);

   for(int j=0;j<ArraySize(target_levels);++j)
   {
      bool already=false;
      for(int i=0;i<ArraySize(pr2);++i)
         if(MathAbs(pr2[i]-target_levels[j]) < (g_tick_size/2.0)) { already=true; break; }

      if(already) continue;

      // anti-duplicate: ห้ามมี pending/position ใน ±GridStep
      if(OccupiedAround(target_levels[j], pr2, pos_prices)) continue;

      PlacePending(side_type, target_levels[j], InpStartLot, InpTPPoints);

      // อัปเดตรายการชั่วคราว
      int n=ArraySize(pr2);
      ArrayResize(pr2, n+1);
      pr2[n]=target_levels[j];
   }
}

// ---------- drawing (optional) ----------
void DrawGuideLines(const string name_prefix, const double &levels[], color clr)
{
   if(!InpShowLevels) return;
   for(int i=0;i<ArraySize(levels);++i)
   {
      string nm = name_prefix + IntegerToString(i);
      if(ObjectFind(0, nm)==-1)
      {
         ObjectCreate(0, nm, OBJ_HLINE, 0, 0, levels[i]);
         ObjectSetInteger(0, nm, OBJPROP_COLOR, clr);
         ObjectSetInteger(0, nm, OBJPROP_STYLE, STYLE_DOT);
      }
      ObjectSetDouble(0, nm, OBJPROP_PRICE, levels[i]);
   }
}

// ---------- EA lifecycle ----------
int OnInit()
{
   if(!RefreshSym())
   {
      Print("Failed to load symbol info");
      return(INIT_FAILED);
   }
   trade.SetExpertMagicNumber((int)InpMagic);
   return(INIT_SUCCEEDED);
}

void OnTick()
{
   if(!RefreshSym()) return;

   const double ask = SymbolInfoDouble(g_symbol, SYMBOL_ASK);
   const double bid = SymbolInfoDouble(g_symbol, SYMBOL_BID);

   // --- เตรียมข้อมูลฝั่ง Buy (Buy Stop) ---
   double buy_target_levels[];
   if(InpMode==MODE_BUY_ONLY || InpMode==MODE_BUY_SELL)
      ComputeBuyStopLevels(ask, buy_target_levels);

   // --- เตรียมข้อมูลฝั่ง Sell (Sell Stop) ---
   double sell_target_levels[];
   if(InpMode==MODE_SELL_ONLY || InpMode==MODE_BUY_SELL)
      ComputeSellStopLevels(bid, sell_target_levels);

   // auto-shift ตามข้อ 6.x
   if(ArraySize(buy_target_levels)>0)  AutoShiftBuyLevels(ask, buy_target_levels);
   if(ArraySize(sell_target_levels)>0) AutoShiftSellLevels(bid, sell_target_levels);

   // เก็บสถานะปัจจุบัน
   ulong  buy_tk[];  double buy_pr[];
   ulong  sell_tk[]; double sell_pr[];
   double pos_buy_pr[];  double pos_sell_pr[];

   if(InpMode==MODE_BUY_ONLY || InpMode==MODE_BUY_SELL)
   {
      CollectMyPendings(ORDER_TYPE_BUY_STOP, buy_tk, buy_pr);
      CollectMyPositions(POSITION_TYPE_BUY, pos_buy_pr);
   }
   if(InpMode==MODE_SELL_ONLY || InpMode==MODE_BUY_SELL)
   {
      CollectMyPendings(ORDER_TYPE_SELL_STOP, sell_tk, sell_pr);
      CollectMyPositions(POSITION_TYPE_SELL, pos_sell_pr);
   }

   // ซิงค์ให้เท่ากับ target levels + ป้องกันซ้ำในกริดเดียวกัน
   if(ArraySize(buy_target_levels)>0)
      SyncSide(ORDER_TYPE_BUY_STOP,  buy_target_levels, buy_pr, buy_tk, pos_buy_pr);

   if(ArraySize(sell_target_levels)>0)
      SyncSide(ORDER_TYPE_SELL_STOP, sell_target_levels, sell_pr, sell_tk, pos_sell_pr);

   // วาดเส้นไกด์ (optional)
   if(InpShowLevels)
   {
      if(ArraySize(buy_target_levels)>0)
         DrawGuideLines("BUY_LEVEL_",  buy_target_levels,  clrLime);
      if(ArraySize(sell_target_levels)>0)
         DrawGuideLines("SELL_LEVEL_", sell_target_levels, clrTomato);
   }
}
