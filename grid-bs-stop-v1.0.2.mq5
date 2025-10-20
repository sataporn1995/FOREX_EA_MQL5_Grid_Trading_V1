//+------------------------------------------------------------------+
//|                                    EA_GridTrading_PendingStops   |
//| Grid Trading with BuyStop / SellStop pending orders              |
//| Rules: Buy only / Sell only / Both; GridStep, TP points, Max N   |
//| Rolling window grid that shifts with price, anti-duplicate guard |
//+------------------------------------------------------------------+
#property strict
#include <Trade/Trade.mqh>
CTrade trade;

//==================== Inputs =======================================
enum GridMode { MODE_BUY_ONLY=0, MODE_SELL_ONLY=1, MODE_BOTH=2 };
input GridMode InpMode             = MODE_BOTH;   // Trading side
input double   InpLots             = 0.01;        // Initial lot
input int      InpGridStepPoints   = 500;         // Grid step (points)
input int      InpTPPoints         = 400;         // TP distance (points), pending pre-set
input int      InpMaxPerSide       = 3;           // Max pending orders per side
input int      InpSlippagePoints   = 20;          // Max deviation
input ulong    InpMagic            = 20251020;    // Magic number
input bool     InpUseRollingWindow = true;        // Maintain rolling grid when price moves
input bool     InpAvoidSameGrid    = true;        // Avoid duplicates within ±GridStep

//==================== Globals ======================================
double  g_point, g_tick, g_step_price; // basic increments
int     g_digits;

//==================== Helpers ======================================
double TickSize()    { double v; return (SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE, v)? v : _Point); }
double PointSize()   { return _Point; }
int    DigitsCount() { return (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS); }

// normalize price to nearest valid tick
double NormPrice(double price)
{
   double ts = g_tick;
   if(ts<=0) ts = _Point;
   double k = MathRound(price/ts);
   return NormalizeDouble(k*ts, g_digits);
}

// Align price upward to next grid boundary of step_sz
double AlignUp(double price, double step_sz)
{
   double k = MathCeil(price/step_sz);
   return NormPrice(k*step_sz);
}

// Align price downward to previous grid boundary of step_sz
double AlignDown(double price, double step_sz)
{
   double k = MathFloor(price/step_sz);
   return NormPrice(k*step_sz);
}

bool PriceOccupied(double p, ENUM_ORDER_TYPE type, double tol_points)
{
   string sym=_Symbol; ulong mg=InpMagic;
   double tol = tol_points * g_point;
   // Active positions (avoid placing at same grid span)
   for(int i=0;i<PositionsTotal();++i){
      ulong tk=PositionGetTicket(i);
      if(PositionSelectByTicket(tk)){
         if(PositionGetString(POSITION_SYMBOL)==sym && PositionGetInteger(POSITION_MAGIC)==(long)mg){
            double op=PositionGetDouble(POSITION_PRICE_OPEN);
            if(MathAbs(op-p) <= tol) return true;
         }
      }
   }
   // Pending orders
   for(int j=0;j<OrdersTotal();++j){
      if(OrderSelect(j)){
         if(OrderGetString(ORDER_SYMBOL)==sym && (ulong)OrderGetInteger(ORDER_MAGIC)==mg){
            ENUM_ORDER_TYPE t=(ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
            if(t==type){
               double op=OrderGetDouble(ORDER_PRICE_OPEN);
               if(MathAbs(op-p) <= tol) return true;
            }
         }
      }
   }
   return false;
}

int CountSidePending(ENUM_ORDER_TYPE type, double &min_p, double &max_p)
{
   int cnt=0; string sym=_Symbol; ulong mg=InpMagic;
   min_p=DBL_MAX; max_p=-DBL_MAX;
   for(int j=0;j<OrdersTotal();++j){
      if(OrderSelect(j)){
         if(OrderGetString(ORDER_SYMBOL)==sym && (ulong)OrderGetInteger(ORDER_MAGIC)==mg){
            ENUM_ORDER_TYPE t=(ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
            if(t==type){
               cnt++; double op=OrderGetDouble(ORDER_PRICE_OPEN);
               if(op<min_p) min_p=op; if(op>max_p) max_p=op;
            }
         }
      }
   }
   if(cnt==0){min_p=0; max_p=0;}
   return cnt;
}

// Collect tickets for this side, sorted by price asc
void CollectSideTickets(ENUM_ORDER_TYPE type, ulong &tickets[] , double &prices[])
{
   ArrayResize(tickets,0); ArrayResize(prices,0);
   struct Item { double p; ulong tk; };
   Item arr[]; int n=0;
   for(int j=0;j<OrdersTotal();++j){
      if(OrderSelect(j)){
         if(OrderGetString(ORDER_SYMBOL)==_Symbol && (ulong)OrderGetInteger(ORDER_MAGIC)==InpMagic){
            if((ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE)==type){
               Item it; it.p=OrderGetDouble(ORDER_PRICE_OPEN); it.tk=OrderGetInteger(ORDER_TICKET);
               ArrayResize(arr, n+1); arr[n++]=it;
            }
         }
      }
   }
   // sort asc
   for(int i=0;i<n-1;i++) for(int k=i+1;k<n;k++) if(arr[i].p>arr[k].p){ Item t=arr[i]; arr[i]=arr[k]; arr[k]=t; }
   ArrayResize(tickets,n); ArrayResize(prices,n);
   for(int i=0;i<n;i++){ tickets[i]=arr[i].tk; prices[i]=arr[i].p; }
}

bool PlacePending(ENUM_ORDER_TYPE type, double price)
{
   price = NormPrice(price);
   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(InpSlippagePoints);
   double tp=0, sl=0; // only TP per spec
   double step_tp = InpTPPoints * g_point;
   if(type==ORDER_TYPE_BUY_STOP){ tp = NormPrice(price + step_tp); }
   else if(type==ORDER_TYPE_SELL_STOP){ tp = NormPrice(price - step_tp); }

   MqlTradeResult res;
   bool ok=false;
   if(type==ORDER_TYPE_BUY_STOP)
      ok = trade.BuyStop(InpLots, price, _Symbol, sl, tp);
   else if(type==ORDER_TYPE_SELL_STOP)
      ok = trade.SellStop(InpLots, price, _Symbol, sl, tp);

   if(!ok) Print("[ERR] PlacePending failed type=",(int)type," price=",DoubleToString(price,g_digits)," err=",GetLastError());
   return ok;
}

bool DeleteOrder(ulong ticket)
{
   trade.SetExpertMagicNumber(InpMagic);
   bool ok = trade.OrderDelete(ticket);
   if(!ok) Print("[ERR] Delete order ",ticket," failed err=",GetLastError());
   return ok;
}

// Build desired grid levels for a side and reconcile with market
void MaintainSide(ENUM_ORDER_TYPE type)
{
   if(InpMaxPerSide<=0) return;
   double step_sz = InpGridStepPoints * g_point;
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   // Base anchor aligned to grid from current price
   double base;
   if(type==ORDER_TYPE_BUY_STOP) base = AlignUp(ask + 1e-8, step_sz); // strictly above Ask
   else                          base = AlignDown(bid - 1e-8, step_sz); // strictly below Bid

   // Desired grid set
   double desired[]; ArrayResize(desired, InpMaxPerSide);
   if(type==ORDER_TYPE_BUY_STOP){
      for(int i=0;i<InpMaxPerSide;i++) desired[i] = base + i*step_sz;
   } else {
      for(int i=0;i<InpMaxPerSide;i++) desired[i] = base - i*step_sz;
   }

   // Collect existing
   ulong tickets[]; double prices[]; CollectSideTickets(type, tickets, prices);

   // Delete orders not on desired grid (or too close) to keep strict spacing
   for(int i=0;i<ArraySize(tickets);++i){
      bool keep=false;
      for(int d=0; d<ArraySize(desired); ++d){
         if(MathAbs(prices[i]-desired[d]) <= 0.25*step_sz) { keep=true; break; }
      }
      if(!keep) DeleteOrder(tickets[i]);
   }

   // Re-collect after deletions
   CollectSideTickets(type, tickets, prices);

   // Add missing desired levels
   for(int d=0; d<ArraySize(desired); ++d){
      bool found=false;
      for(int i=0;i<ArraySize(prices);++i){ if(MathAbs(prices[i]-desired[d]) <= 0.25*step_sz) { found=true; break; } }
      if(!found){
         if(!InpAvoidSameGrid || !PriceOccupied(desired[d], type, InpGridStepPoints))
            PlacePending(type, desired[d]);
      }
   }

   // Rolling window behavior is naturally satisfied by the dynamic base recompute.
}

//==================== Lifecycle ====================================
int OnInit()
{
   g_point  = PointSize();
   g_tick   = TickSize();
   g_digits = DigitsCount();
   g_step_price = InpGridStepPoints * g_point;
   return(INIT_SUCCEEDED);
}

void OnTick()
{
   if(InpMode==MODE_BUY_ONLY || InpMode==MODE_BOTH)
      MaintainSide(ORDER_TYPE_BUY_STOP);
   if(InpMode==MODE_SELL_ONLY || InpMode==MODE_BOTH)
      MaintainSide(ORDER_TYPE_SELL_STOP);
}

// Replenish quickly when TP closes positions
void OnTradeTransaction(const MqlTradeTransaction &trans,const MqlTradeRequest &req,const MqlTradeResult &res)
{
   if(trans.type==TRADE_TRANSACTION_DEAL_ADD){
      long   deal_entry = (long)HistoryDealGetInteger(trans.deal, DEAL_ENTRY);
      long   reason     = (long)HistoryDealGetInteger(trans.deal, DEAL_REASON);
      string sym        = HistoryDealGetString(trans.deal, DEAL_SYMBOL);
      ulong  magic      = (ulong)HistoryDealGetInteger(trans.deal, DEAL_MAGIC);
      if(sym==_Symbol && magic==InpMagic && deal_entry==DEAL_ENTRY_OUT && reason==DEAL_REASON_TP){
         // A TP just happened: rebuild grids immediately
         if(InpMode==MODE_BUY_ONLY || InpMode==MODE_BOTH)
            MaintainSide(ORDER_TYPE_BUY_STOP);
         if(InpMode==MODE_SELL_ONLY || InpMode==MODE_BOTH)
            MaintainSide(ORDER_TYPE_SELL_STOP);
      }
   }
}

//==================== Notes ========================================
// • Pending grid keeps exactly InpMaxPerSide orders per allowed side at
//   distances of InpGridStepPoints. Prices are aligned to valid tick size.
// • BuyStop levels: starting just above current Ask, then +step, +2*step, ...
//   SellStop levels: starting just below current Bid, then -step, -2*step, ...
// • TP is preset on the pending orders: BuyStop TP = +TPPoints; SellStop TP = -TPPoints.
// • Anti-duplicate: before placing, EA checks no positions or pendings exist
//   within ±GridStep around the target price (same side & magic & symbol).
// • Rolling window: as price drifts by ≥ one grid, the desired set shifts and the
//   EA deletes off-grid orders and adds new ones beyond the extreme.
// • If you need SL, trailing, or martingale sizing, they can be added easily.
//+------------------------------------------------------------------+
