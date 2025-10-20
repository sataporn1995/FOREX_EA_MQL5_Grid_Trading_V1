//+------------------------------------------------------------------+
//| GridTrading_BS_SS.mq5  (Fixed: undeclared identifier issues)     |
//+------------------------------------------------------------------+
#property strict
#property description "Grid Trading (Buy Stop / Sell Stop) with TP, sliding window, non-duplicating levels."
#property version   "1.01"

#include <Trade/Trade.mqh>
CTrade Trade;

//-------------------- Inputs --------------------
enum GridMode { MODE_BUY_ONLY=0, MODE_SELL_ONLY=1, MODE_BUY_SELL=2 };
input GridMode   InpMode                = MODE_BUY_SELL;
input double     InpLot                 = 0.01;
input int        InpGridStepPoints      = 500;
input int        InpTPPoints            = 400;
input int        InpMaxPendingsPerSide  = 3;
input long       InpMagic               = 555555;
input bool       InpAutoSeedOnStart     = true;
input int        InpSlippagePoints      = 20;
input bool       InpShowHUD             = true;
input bool       InpAllowECN            = true;
input bool       InpStartEnabled        = true;

//-------------------- Vars --------------------
string  Sym;
double  Pt, Pip;
int     Digits_;
bool    g_enabled;
long    chart_id;
//datetime g_lastSlideCheck=0;
ulong g_lastSlideCheck=0;
int      g_slideEveryMs=500;
//volatile int g_lastTPDir = 0; // +1 buy, -1 sell
int g_lastTPDir = 0; // +1 buy, -1 sell

//-------------------- Utils --------------------
double NormalizeVolume(double vol){
   double step  = SymbolInfoDouble(Sym, SYMBOL_VOLUME_STEP);
   double minv  = SymbolInfoDouble(Sym, SYMBOL_VOLUME_MIN);
   double maxv  = SymbolInfoDouble(Sym, SYMBOL_VOLUME_MAX);
   if(step<=0) step=0.01;
   double v = MathMax(minv, MathMin(maxv, MathFloor(vol/step+1e-9)*step));
   return v;
}
double NormalizePrice(double price){ return NormalizeDouble(price,(int)SymbolInfoInteger(Sym,SYMBOL_DIGITS)); }
double PointsToPrice(int points){ return points * Pt; }

// ตรวจสอบ Position ของเรา
bool IsOurPositionByIndex(int index){
   //if(!PositionSelectByIndex(index)) return false;
   if(!PositionSelectByTicket(index)) return false;
   if(PositionGetString(POSITION_SYMBOL)!=Sym) return false;
   if((long)PositionGetInteger(POSITION_MAGIC)!=InpMagic) return false;
   return true;
}

// เก็บราคาของ Pending Orders ฝั่งที่ระบุ (isBuy=true=BUY_STOP)
int CollectOurPendingPrices(bool isBuy, double &prices[]){
   ArrayResize(prices,0);
   int total=(int)OrdersTotal();
   for(int i=0;i<total;i++){
      //if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(!OrderGetTicket(i)) continue;
      if(OrderGetString(ORDER_SYMBOL)!=Sym) continue;
      if((long)OrderGetInteger(ORDER_MAGIC)!=InpMagic) continue;
      ENUM_ORDER_TYPE t=(ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
      if(isBuy && t!=ORDER_TYPE_BUY_STOP)  continue;
      if(!isBuy && t!=ORDER_TYPE_SELL_STOP) continue;
      double p=OrderGetDouble(ORDER_PRICE_OPEN);
      int sz=ArraySize(prices); ArrayResize(prices,sz+1); prices[sz]=p;
   }
   if(ArraySize(prices)>1) ArraySort(prices); // ASC
   return ArraySize(prices);
}

// เก็บราคาของ Positions ฝั่งที่ระบุ
int CollectOurPositionPrices(bool isBuy, double &prices[]){
   ArrayResize(prices,0);
   int total=(int)PositionsTotal();
   for(int i=0;i<total;i++){
      if(!IsOurPositionByIndex(i)) continue;
      long type=PositionGetInteger(POSITION_TYPE);
      if(isBuy && type!=POSITION_TYPE_BUY) continue;
      if(!isBuy && type!=POSITION_TYPE_SELL) continue;
      double p=PositionGetDouble(POSITION_PRICE_OPEN);
      int sz=ArraySize(prices); ArrayResize(prices,sz+1); prices[sz]=p;
   }
   if(ArraySize(prices)>1) ArraySort(prices);
   return ArraySize(prices);
}

// ห้ามซ้ำระดับ (±GridStep)
bool IsLevelFree(double level){
   double tol=PointsToPrice(InpGridStepPoints) - 1e-10;
   // ตรวจ Pending
   int ot=(int)OrdersTotal();
   for(int i=0;i<ot;i++){
      //if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(!OrderGetTicket(i)) continue;
      if(OrderGetString(ORDER_SYMBOL)!=Sym) continue;
      if((long)OrderGetInteger(ORDER_MAGIC)!=InpMagic) continue;
      double p=OrderGetDouble(ORDER_PRICE_OPEN);
      if(MathAbs(p-level) <= tol) return false;
   }
   // ตรวจ Positions
   int pt=(int)PositionsTotal();
   for(int i=0;i<pt;i++){
      if(!IsOurPositionByIndex(i)) continue;
      double p=PositionGetDouble(POSITION_PRICE_OPEN);
      if(MathAbs(p-level) <= tol) return false;
   }
   return true;
}

// วาง Pending พร้อม TP (กรณี ECN จะ Modify ทีหลัง)
bool PlacePending(bool isBuy, double level){
   if(!IsLevelFree(level)) return false;

   MqlTradeRequest req; MqlTradeResult res; MqlTradeCheckResult  check_result;
   ZeroMemory(req); ZeroMemory(res); ZeroMemory(check_result);

   req.action   = TRADE_ACTION_PENDING;
   req.symbol   = Sym;
   req.magic    = InpMagic;
   req.deviation= InpSlippagePoints;
   req.volume   = NormalizeVolume(InpLot);
   req.type     = isBuy ? ORDER_TYPE_BUY_STOP : ORDER_TYPE_SELL_STOP;
   req.price    = NormalizePrice(level);

   double tp_dist  = PointsToPrice(InpTPPoints);
   double tp_price = isBuy ? NormalizePrice(level + tp_dist)
                           : NormalizePrice(level - tp_dist);

   req.tp = InpAllowECN ? 0.0 : tp_price;

   if(!OrderCheck(req,check_result) || !Trade.OrderSend(req,res)){
      PrintFormat("PlacePending failed: %s / retcode=%d price=%.*f",
                  res.comment, (int)res.retcode, Digits_, level);
      return false;
   }

   // Modify TP สำหรับ ECN
   if(InpAllowECN){
      ulong ticket = res.order;
      if(ticket>0){
         MqlTradeRequest mod; MqlTradeResult mr;
         ZeroMemory(mod); ZeroMemory(mr);
         mod.action = TRADE_ACTION_MODIFY;
         mod.order  = ticket;
         mod.symbol = Sym;
         mod.price  = NormalizePrice(level);
         mod.tp     = tp_price;
         if(!Trade.OrderSend(mod,mr)){
            Print("Modify-after-create failed: ", mr.comment);
         }
      }
   }
   return true;
}

// ลบ Pending ที่ราคาที่กำหนด (แบบตรงเป๊ะ)
bool DeletePendingAtPrice(bool isBuy, double level){
   int total=(int)OrdersTotal();
   for(int i=0;i<total;i++){
      //if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(!OrderGetTicket(i)) continue;
      if(OrderGetString(ORDER_SYMBOL)!=Sym) continue;
      if((long)OrderGetInteger(ORDER_MAGIC)!=InpMagic) continue;
      ENUM_ORDER_TYPE t=(ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
      if(isBuy && t!=ORDER_TYPE_BUY_STOP)  continue;
      if(!isBuy && t!=ORDER_TYPE_SELL_STOP) continue;
      double p=OrderGetDouble(ORDER_PRICE_OPEN);
      if(MathAbs(p-level) <= 0.5*Pt){
         ulong ticket=(ulong)OrderGetInteger(ORDER_TICKET);
         if(ticket==0) return false;
         if(!Trade.OrderDelete(ticket)){
            Print("DeletePending failed ticket=",ticket," err=",GetLastError());
            return false;
         }
         return true;
      }
   }
   return false;
}

//-------------------- Grid Seeding --------------------
void SeedSide(bool isBuy){
   double ask = SymbolInfoDouble(Sym, SYMBOL_ASK);
   double bid = SymbolInfoDouble(Sym, SYMBOL_BID);
   double step = PointsToPrice(InpGridStepPoints);

   double start = isBuy
      ? NormalizePrice( MathCeil(ask/Pt)*Pt )   // BuyStop เริ่มเหนือ Ask เล็กน้อย
      : NormalizePrice( MathFloor(bid/Pt)*Pt ); // SellStop เริ่มใต้ Bid เล็กน้อย

   for(int k=0;k<InpMaxPendingsPerSide;k++){
      double lvl = isBuy ? (start + k*step) : (start - k*step);
      if(IsLevelFree(lvl)) PlacePending(isBuy,lvl);
   }
}

// เติมกริดเมื่อฝั่งนั้นไป TP
void ReplenishAfterTP(bool isBuy){
   double arr[]; int n=CollectOurPendingPrices(isBuy,arr);
   double step=PointsToPrice(InpGridStepPoints);
   if(n==0){ SeedSide(isBuy); return; }
   if(n>=InpMaxPendingsPerSide) return;

   double newLevel = isBuy ? NormalizePrice(arr[n-1] + step)
                           : NormalizePrice(arr[0]   - step);
   if(IsLevelFree(newLevel)) PlacePending(isBuy,newLevel);
}

//-------------------- Sliding Window --------------------
void SlideIfNeeded(){
   //datetime g_lastSlideCheck = 0;
   //if((ulong)(GetMicrosecondCount()/1000) - (ulong)g_lastSlideCheck < (ulong)g_slideEveryMs) return;
   ulong current_ms = GetMicrosecondCount() / 1000; // เป็น millisecond
   if(current_ms - (ulong)g_lastSlideCheck < (ulong)g_slideEveryMs) return;
   g_lastSlideCheck=GetMicrosecondCount()/1000;

   double ask = SymbolInfoDouble(Sym, SYMBOL_ASK);
   double bid = SymbolInfoDouble(Sym, SYMBOL_BID);
   double step= PointsToPrice(InpGridStepPoints);

   // BUY: ถ้า bid < lowest-buystop - step  -> เติมด้านล่าง ลบด้านบน
   if(InpMode!=MODE_SELL_ONLY){
      double bs[]; int nb=CollectOurPendingPrices(true,bs);
      if(nb>0){
         double lowest=bs[0];
         if(bid < lowest - step){
            double newLow = NormalizePrice(lowest - step);
            if(nb>=InpMaxPendingsPerSide){
               double highest=bs[nb-1];
               DeletePendingAtPrice(true, highest);
            }
            if(IsLevelFree(newLow)) PlacePending(true,newLow);
         }
      }
   }

   // SELL: ถ้า ask > highest-sellstop + step -> เติมด้านบน ลบด้านล่าง
   if(InpMode!=MODE_BUY_ONLY){
      double ss[]; int ns=CollectOurPendingPrices(false,ss);
      if(ns>0){
         double highest=ss[ns-1];
         if(ask > highest + step){
            double newHigh = NormalizePrice(highest + step);
            if(ns>=InpMaxPendingsPerSide){
               double lowest=ss[0];
               DeletePendingAtPrice(false, lowest);
            }
            if(IsLevelFree(newHigh)) PlacePending(false,newHigh);
         }
      }
   }
}

//-------------------- HUD --------------------
string btn_name="EA_TOGGLE";
void DrawHUD(){
   if(!InpShowHUD) return;

   string lbl="GRID_HUD";
   ObjectDelete(chart_id,lbl);

   double buyPend[], sellPend[];
   CollectOurPendingPrices(true, buyPend);
   CollectOurPendingPrices(false, sellPend);

   int posTot=PositionsTotal();
   int myBuyPos=0,mySellPos=0; double netProfit=0.0;
   for(int i=0;i<posTot;i++){
      if(!IsOurPositionByIndex(i)) continue;
      long t=PositionGetInteger(POSITION_TYPE);
      if(t==POSITION_TYPE_BUY)  myBuyPos++;
      if(t==POSITION_TYPE_SELL) mySellPos++;
      netProfit += PositionGetDouble(POSITION_PROFIT);
   }

   string status = g_enabled?"ENABLED":"DISABLED";
   string txt=StringFormat("Grid %s\nBuyPend: %d  SellPend: %d\nBuyPos: %d  SellPos: %d\nNet PnL: %.2f",
                           status, ArraySize(buyPend), ArraySize(sellPend),
                           myBuyPos, mySellPos, netProfit);

   ObjectCreate(chart_id,lbl,OBJ_LABEL,0,0,0);
   ObjectSetInteger(chart_id,lbl,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetInteger(chart_id,lbl,OBJPROP_XDISTANCE,12);
   ObjectSetInteger(chart_id,lbl,OBJPROP_YDISTANCE,24);
   ObjectSetInteger(chart_id,lbl,OBJPROP_FONTSIZE,10);
   ObjectSetString (chart_id,lbl,OBJPROP_TEXT,txt);

   // Button (ใช้ ObjectFind(chart_id, ...) คืนค่า <0 = ไม่พบ)
   if(ObjectFind(chart_id,btn_name) < 0){
      ObjectCreate(chart_id,btn_name,OBJ_BUTTON,0,0,0);
      ObjectSetInteger(chart_id,btn_name,OBJPROP_CORNER,CORNER_LEFT_UPPER);
      ObjectSetInteger(chart_id,btn_name,OBJPROP_XDISTANCE,12);
      ObjectSetInteger(chart_id,btn_name,OBJPROP_YDISTANCE,2);
      ObjectSetInteger(chart_id,btn_name,OBJPROP_FONTSIZE,9);
      ObjectSetInteger(chart_id,btn_name,OBJPROP_BGCOLOR,clrAliceBlue);
      ObjectSetInteger(chart_id,btn_name,OBJPROP_COLOR,clrBlack);
      ObjectSetString (chart_id,btn_name,OBJPROP_TEXT,g_enabled?"⏸ Disable":"▶ Enable");
      ObjectSetInteger(chart_id,btn_name,OBJPROP_STATE,false);
   }else{
      ObjectSetString(chart_id,btn_name,OBJPROP_TEXT,g_enabled?"⏸ Disable":"▶ Enable");
   }
}

//-------------------- Lifecycle --------------------
int OnInit(){
   Sym     = _Symbol;
   Pt      = SymbolInfoDouble(Sym, SYMBOL_POINT);
   Digits_ = (int)SymbolInfoInteger(Sym, SYMBOL_DIGITS);
   Pip     = Pt * ((Digits_%2==0)?10.0:1.0);
   chart_id= ChartID();
   g_enabled= InpStartEnabled;

   if(InpAutoSeedOnStart && g_enabled){
      if(InpMode!=MODE_SELL_ONLY) SeedSide(true);
      if(InpMode!=MODE_BUY_ONLY)  SeedSide(false);
   }
   EventSetTimer(1);
   return(INIT_SUCCEEDED);
}
void OnDeinit(const int reason){ EventKillTimer(); }
void OnTimer(){ if(InpShowHUD) DrawHUD(); }

void MaintainSide(bool isBuy){
   if( (isBuy && InpMode==MODE_SELL_ONLY) || (!isBuy && InpMode==MODE_BUY_ONLY) ) return;

   double arr[]; int n = CollectOurPendingPrices(isBuy,arr);
   double step=PointsToPrice(InpGridStepPoints);
   double ask=SymbolInfoDouble(Sym, SYMBOL_ASK);
   double bid=SymbolInfoDouble(Sym, SYMBOL_BID);

   if(n==0){
      if(isBuy){
         double base = NormalizePrice(MathCeil(ask/Pt)*Pt);
         for(int k=0;k<InpMaxPendingsPerSide;k++){
            double lvl = base + k*step;
            if(IsLevelFree(lvl)) PlacePending(true,lvl);
         }
      }else{
         double base = NormalizePrice(MathFloor(bid/Pt)*Pt);
         for(int k=0;k<InpMaxPendingsPerSide;k++){
            double lvl = base - k*step;
            if(IsLevelFree(lvl)) PlacePending(false,lvl);
         }
      }
      return;
   }

   if(n>InpMaxPendingsPerSide){
      int excess = n - InpMaxPendingsPerSide;
      for(int i=0;i<excess;i++){
         if(isBuy) DeletePendingAtPrice(true,  arr[n-1-i]); // ตัดบนก่อน
         else      DeletePendingAtPrice(false, arr[0+i]);   // ตัดล่างก่อน
      }
   }

   n = CollectOurPendingPrices(isBuy,arr);
   while(n<InpMaxPendingsPerSide){
      double newLevel = isBuy ? NormalizePrice(arr[n-1] + step)
                              : NormalizePrice(arr[0]   - step);
      if(PlacePending(isBuy,newLevel)) n++;
      else break;
   }
}

void OnTick(){
   if(!g_enabled){ if(InpShowHUD) DrawHUD(); return; }
   SlideIfNeeded();
   MaintainSide(true);
   MaintainSide(false);
   if(InpShowHUD) DrawHUD();
}

//-------------------- Trade Events --------------------
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
{
   if(trans.type==TRADE_TRANSACTION_DEAL_ADD){
      ulong deal_id = trans.deal;
      if(!HistorySelect(TimeCurrent()-86400*5, TimeCurrent())) return;
      if(!HistoryDealSelect(deal_id)) return;

      if((string)HistoryDealGetString(deal_id, DEAL_SYMBOL)!=Sym) return;
      if((long)HistoryDealGetInteger(deal_id, DEAL_MAGIC)!=InpMagic) return;

      long reason=(long)HistoryDealGetInteger(deal_id, DEAL_REASON);
      long entry =(long)HistoryDealGetInteger(deal_id, DEAL_ENTRY);
      long type  =(long)HistoryDealGetInteger(deal_id, DEAL_TYPE);

      if(entry==DEAL_ENTRY_OUT && reason==DEAL_REASON_TP){
         if(type==DEAL_TYPE_SELL) g_lastTPDir=-1;
         else if(type==DEAL_TYPE_BUY) g_lastTPDir=+1;

         if(g_lastTPDir==+1 && InpMode!=MODE_SELL_ONLY) ReplenishAfterTP(true);
         if(g_lastTPDir==-1 && InpMode!=MODE_BUY_ONLY)  ReplenishAfterTP(false);
         g_lastTPDir=0;
      }
   }
}

//-------------------- Chart Events --------------------
void OnChartEvent(const int id,const long &lparam,const double &dparam,const string &sparam)
{
   if(id==CHARTEVENT_OBJECT_CLICK && sparam==btn_name){
      g_enabled = !g_enabled;
      DrawHUD();
   }
}
