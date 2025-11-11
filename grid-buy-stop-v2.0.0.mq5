//+------------------------------------------------------------------+
//|                                        GridTrading_BuyStop.mq5    |
//|                                  Grid Trading with Buy Stop Only  |
//+------------------------------------------------------------------+
#property copyright "Grid Trading System"
#property version   "1.00"
#property strict

//--- Input Parameters
input group "=== GRID SETTINGS ===";
enum ENUM_GRID_TYPE { 
   GRID_CLOSE_ALL, // Close All
   GRID_TP, // TP
   GRID_TSL // Trailing Stop
};
input ENUM_GRID_TYPE InpGridType = GRID_CLOSE_ALL; // Grid Type
input int      InpGridStep = 5000;             // Grid Step (points)
input double   InpGridStepMultiplier = 1.1;    // Grid Step Multiplier
input int      InpFollowDistance = 1500;       // Follow Distance (points)
input int      InpOrderDistance = 1000;        // Order Distance (points)

input group "=== PROFIT ==="; 
enum ENUM_NET_PROFIT { 
   NET_PROFIT_POINTS, // Net Profit Points
   NET_PROFIT_AMOUNT  // Net Profit Amount
};
input ENUM_NET_PROFIT InpSumNetType = NET_PROFIT_POINTS; // Net Profit (Points/Amount)
input int InpNetProfitPoints = 3000; // Net Profit Points (points)
input double InpProfitTargetAmount = 10.0; // TP (Amount)

input group "=== TRAILING STOP ==="; 
input int InpStartTrailAbroveAvgPoints = 500; // Start Trailing Stop (points)
input int InpTrailOffsetPoints = 300; // Trailing Stop Offset (points)
input bool InpTrailOnlyTighten = true;  // Move SL just to get profit

input group "=== LOT SIZE ===";
input double InpLotSize = 0.01; // Start Lot
input double InpMartingale = 1.1; // Martingale Multiplier
input double InpMaxLots = 0.05; // Maximum Lot

input group "=== ZONE FILTER ===";
input bool InpEnablePriceZone = false; // Enable/Disable Price Zone
input double InpUpperPrice = 0.0; // Upper Price (0 = No Limit)
input double InpLowerPrice = 0.0; // Lower Price (0 = No Limit)

input group "=== OTHER ===";
input int      InpMagicNumber = 2025111101;        // Magic Number
input int      InpSlippage = 10; // Slippage (points)
input string   InpTradeComment = "Grid_BuyStop"; // Comment

struct ProfitInfo{
  double profit;
  double volume;
  int count;
};

//--- Global Variables
double g_point_value;
int g_digits;

//+------------------------------------------------------------------+
//| Expert initialization function                                    |
//+------------------------------------------------------------------+
int OnInit()
{
   //--- Get symbol properties
   g_point_value = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   g_digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   
   //--- Check parameters
   if(InpGridStep <= 0 || InpFollowDistance <= 0 || InpOrderDistance <= 0)
   {
      Print("Error: Invalid input parameters!");
      return(INIT_PARAMETERS_INCORRECT);
   }
   
   Print("Grid Trading EA initialized successfully");
   Print("Grid Step: ", InpGridStep, " points");
   Print("Follow Distance: ", InpFollowDistance, " points");
   Print("Order Distance: ", InpOrderDistance, " points");
   Print("Net Profit Points: ", InpNetProfitPoints, " points");
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                  |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   Print("EA deinitialized. Reason: ", reason);
}

//+------------------------------------------------------------------+
//| Expert tick function                                              |
//+------------------------------------------------------------------+
void OnTick()
{
   //--- Get current prices
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   
   //--- Count positions and orders
   int buy_positions = CountPositions(POSITION_TYPE_BUY);
   int buy_stop_orders = CountPendingOrders(ORDER_TYPE_BUY_STOP);
   
   //--- Check if we should close all positions (Profit Target)
   if(buy_positions > 0)
   {
      if(CheckNetProfit() && InpGridType == GRID_CLOSE_ALL)
      {
         CloseAllBuyPositions();
         DeleteAllBuyStopOrders();
         return;
      }
      
      if(CheckNetProfit() && InpGridType == GRID_TSL)
      {
         MaybeTrailAll(POSITION_TYPE_BUY);
         //DeleteAllBuyStopOrders();
         return;
      }
   }
   
   //--- Get lowest buy position price
   double lowest_buy_price = GetLowestBuyPrice();
   
   //--- Condition 1: No Buy Position - Place Buy Stop
   if(buy_positions == 0 && buy_stop_orders == 0)
   {
      double buy_stop_price = NormalizeDouble(ask + InpOrderDistance * g_point_value, g_digits);
      PlaceBuyStop(buy_stop_price);
      return;
   }
   
   //--- Condition 2: Follow price down (adjust Buy Stop)
   if(buy_positions == 0 && buy_stop_orders > 0)
   {
      double current_buy_stop_price = GetBuyStopPrice();
      if(current_buy_stop_price > 0)
      {
         double distance = (current_buy_stop_price - ask) / g_point_value;
         
         // ถ้าระยะห่างมากกว่าหรือเท่ากับ Follow Distance
         if(distance >= InpFollowDistance)
         {
            DeleteAllBuyStopOrders();
            double new_buy_stop_price = NormalizeDouble(ask + InpOrderDistance * g_point_value, g_digits);
            PlaceBuyStop(new_buy_stop_price);
         }
      }
      return;
   }
   
   
   
   //--- Condition 3 & 4: Has Buy Position - Manage Buy Stop
   if(buy_positions > 0)
   {
      int grid_step_result = (int)(InpGridStep * pow(InpGridStepMultiplier, CountPositions(POSITION_TYPE_BUY) - 1));
      double threshold_price = lowest_buy_price - (grid_step_result + InpFollowDistance) * g_point_value;
      
      // ถ้าไม่มี Buy Stop และราคา Ask ต่ำกว่า threshold
      if(buy_stop_orders == 0 && ask < threshold_price)
      {
         // ตั้ง Buy Stop ที่ต่ำกว่า lowest position ตาม Grid Step
         double new_buy_stop_price = NormalizeDouble(lowest_buy_price - grid_step_result * g_point_value, g_digits);
         
         // ตรวจสอบว่าไม่เหนือ lowest position
         if(new_buy_stop_price < lowest_buy_price)
         {
            PlaceBuyStop(new_buy_stop_price);
         }
      }
      
      // ถ้ามี Buy Stop อยู่แล้ว ตรวจสอบว่าไม่เหนือ lowest position
      if(buy_stop_orders > 0 || ask <= threshold_price)
      {
         double current_buy_stop_price = GetBuyStopPrice();
         double new_buy_stop_price = NormalizeDouble(ask + InpOrderDistance * g_point_value, g_digits);
         if(current_buy_stop_price >= lowest_buy_price || current_buy_stop_price >= ask + (grid_step_result + InpFollowDistance) * g_point_value)
         {
            DeleteAllBuyStopOrders();
            PlaceBuyStop(new_buy_stop_price);
         }
      }
   }
}

double pips(int pts){ return (double)pts * _Point; }
bool   IsBuy(ENUM_POSITION_TYPE t){ return (t==POSITION_TYPE_BUY); }
bool   IsSell(ENUM_POSITION_TYPE t){ return (t==POSITION_TYPE_SELL); }
bool   IsMySymbol(const string sym){ return (sym==_Symbol); }

bool ValidateZone() {
   double price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if (price >= InpUpperPrice && InpUpperPrice != 0.0) return false;
   else if (price <= InpLowerPrice && InpLowerPrice != 0.0) return false;
   
   return true;
}

//+------------------------------------------------------------------+
//| Count positions by type                                           |
//+------------------------------------------------------------------+
int CountPositions(ENUM_POSITION_TYPE pos_type)
{
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
      {
         if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
            PositionGetInteger(POSITION_MAGIC) == InpMagicNumber &&
            PositionGetInteger(POSITION_TYPE) == pos_type)
         {
            count++;
         }
      }
   }
   return count;
}

//+------------------------------------------------------------------+
//| Count pending orders by type                                      |
//+------------------------------------------------------------------+
int CountPendingOrders(ENUM_ORDER_TYPE order_type)
{
   int count = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(OrderSelect(ticket))
      {
         if(OrderGetString(ORDER_SYMBOL) == _Symbol &&
            OrderGetInteger(ORDER_MAGIC) == InpMagicNumber &&
            OrderGetInteger(ORDER_TYPE) == order_type)
         {
            count++;
         }
      }
   }
   return count;
}

//+------------------------------------------------------------------+
//| Get lowest buy position price                                     |
//+------------------------------------------------------------------+
double GetLowestBuyPrice()
{
   double lowest = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
      {
         if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
            PositionGetInteger(POSITION_MAGIC) == InpMagicNumber &&
            PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
         {
            double price = PositionGetDouble(POSITION_PRICE_OPEN);
            if(lowest == 0 || price < lowest)
            {
               lowest = price;
            }
         }
      }
   }
   return lowest;
}

//+------------------------------------------------------------------+
//| Get current Buy Stop price                                        |
//+------------------------------------------------------------------+
double GetBuyStopPrice()
{
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(OrderSelect(ticket))
      {
         if(OrderGetString(ORDER_SYMBOL) == _Symbol &&
            OrderGetInteger(ORDER_MAGIC) == InpMagicNumber &&
            OrderGetInteger(ORDER_TYPE) == ORDER_TYPE_BUY_STOP)
         {
            return OrderGetDouble(ORDER_PRICE_OPEN);
         }
      }
   }
   return 0;
}

double CalTagetPrice(ENUM_POSITION_TYPE pos_type) // Buy -> ask, Sell -> bid
{
   // คำนวณการเปลี่ยนแปลงของราคา
   double price_change = InpNetProfitPoints * g_point_value;
   
   double current_price = SymbolInfoDouble(_Symbol, pos_type == POSITION_TYPE_BUY ? SYMBOL_ASK: SYMBOL_BID);
   
   // คำนวณราคาเป้าหมาย
   double target_price = current_price + (pos_type == POSITION_TYPE_BUY ? price_change : -price_change);
   
   // หากต้องการให้ราคาอยู่ในรูปที่ถูกต้องตาม Tick Size (แนะนำ)
   // ควรใช้ฟังก์ชัน NormailzeDouble() เพื่อปรับทศนิยมให้ถูกต้องตาม Symbol
   return NormalizeDouble(target_price, g_digits);
}

//+------------------------------------------------------------------+
//| Place Buy Stop order                                              |
//+------------------------------------------------------------------+
bool PlaceBuyStop(double price)
{
   bool isTradeZone = ValidateZone();
   if (InpEnablePriceZone && !isTradeZone) return false;
   
   MqlTradeRequest request = {};
   MqlTradeResult result = {};
   
   double next_lots = NormalizeDouble(InpLotSize * pow(InpMartingale, CountPositions(POSITION_TYPE_BUY)), 2);
   if (next_lots > InpMaxLots) next_lots = InpMaxLots;
   
   double tp_price = 0;
   if (InpGridType == GRID_TP) {
      //if(dir==DIR_BUY) tpPrice = CalTagetPrice(tk.ask, InpProfitTargetPts);
      //else tpPrice = CalTagetPrice(tk.bid, InpProfitTargetPts); 
      tp_price = CalTagetPrice(POSITION_TYPE_BUY);
   }
   
   request.action = TRADE_ACTION_PENDING;
   request.symbol = _Symbol;
   request.volume = next_lots;
   request.type = ORDER_TYPE_BUY_STOP;
   request.price = price;
   request.sl = 0;
   request.tp = tp_price;
   request.deviation = InpSlippage;
   request.magic = InpMagicNumber;
   request.comment = InpTradeComment;
   request.type_filling = ORDER_FILLING_IOC;
   
   if(!OrderSend(request, result))
   {
      Print("Error placing Buy Stop: ", GetLastError(), " - ", result.comment);
      return false;
   }
   
   Print("Buy Stop placed at ", price, " | Ticket: ", result.order);
   return true;
}

//+------------------------------------------------------------------+
//| Delete all Buy Stop orders                                        |
//+------------------------------------------------------------------+
void DeleteAllBuyStopOrders()
{
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(OrderSelect(ticket))
      {
         if(OrderGetString(ORDER_SYMBOL) == _Symbol &&
            OrderGetInteger(ORDER_MAGIC) == InpMagicNumber &&
            OrderGetInteger(ORDER_TYPE) == ORDER_TYPE_BUY_STOP)
         {
            MqlTradeRequest request = {};
            MqlTradeResult result = {};
            
            request.action = TRADE_ACTION_REMOVE;
            request.order = ticket;
            
            if(OrderSend(request, result))
            {
               Print("Buy Stop deleted: ", ticket);
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Check net profit of all buy positions                             |
//+------------------------------------------------------------------+
bool CheckNetProfit()
{
   double total_profit_points = 0;
   double total_volume = 0;
   double weighted_price = 0;
   
   double current_bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
      {
         if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
            PositionGetInteger(POSITION_MAGIC) == InpMagicNumber &&
            PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
         {
            double open_price = PositionGetDouble(POSITION_PRICE_OPEN);
            double volume = PositionGetDouble(POSITION_VOLUME);
            
            weighted_price += open_price * volume;
            total_volume += volume;
         }
      }
   }
   
   if(total_volume > 0)
   {
      double average_price = weighted_price / total_volume;
      total_profit_points = (current_bid - average_price) / g_point_value;
      
      Print("Average Price: ", average_price, " | Current Bid: ", current_bid, 
            " | Profit Points: ", total_profit_points);
      
      if(total_profit_points >= InpNetProfitPoints)
      {
         Print("Net profit target reached! Closing all buy positions...");
         return true;
      }
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| Close all buy positions                                           |
//+------------------------------------------------------------------+
void CloseAllBuyPositions()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
      {
         if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
            PositionGetInteger(POSITION_MAGIC) == InpMagicNumber &&
            PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
         {
            MqlTradeRequest request = {};
            MqlTradeResult result = {};
            
            request.action = TRADE_ACTION_DEAL;
            request.symbol = _Symbol;
            request.volume = PositionGetDouble(POSITION_VOLUME);
            request.type = ORDER_TYPE_SELL;
            request.position = ticket;
            request.price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
            request.deviation = InpSlippage;
            request.magic = InpMagicNumber;
            request.type_filling = ORDER_FILLING_IOC;
            
            if(OrderSend(request, result))
            {
               Print("Position closed: ", ticket, " | Profit: ", PositionGetDouble(POSITION_PROFIT));
            }
            else
            {
               Print("Error closing position: ", GetLastError());
            }
         }
      }
   }
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
    
    if((long)PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) 
      continue;
    
    if((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) == type){
      info.profit += PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
      info.volume += PositionGetDouble(POSITION_VOLUME);
      info.count++;
    }
  }
  
  return info;
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
    if((long)PositionGetInteger(POSITION_MAGIC)!=InpMagicNumber) continue;
    if((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE)!=side) continue;

    double lot = PositionGetDouble(POSITION_VOLUME);
    double prc = PositionGetDouble(POSITION_PRICE_OPEN);
    v   += lot;
    pxv += lot*prc;
  }
  if(v<=0) return 0.0;
  return pxv/v;
}

void MaybeTrailAll(ENUM_POSITION_TYPE pos_type)
{
  // คำนวณ Profit เฉพาะฝั่งนี้
  ProfitInfo info = CalculateProfit(pos_type);
  if(info.profit <= 0) return; // ต้องกำไรลอยเท่านั้น

  double avgPrice = VWAP(pos_type);
  if(avgPrice <= 0) return;

  /*double price = (first.type==POSITION_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_BID)
                                                 : SymbolInfoDouble(_Symbol, SYMBOL_ASK);*/
                                                
  double price = true ? SymbolInfoDouble(_Symbol, SYMBOL_BID): SymbolInfoDouble(_Symbol, SYMBOL_ASK);                                                

  double need = pips(InpStartTrailAbroveAvgPoints);
  bool ok=false;
  if(IsBuy(pos_type)){
    ok = (price >= (avgPrice + need));
  }else{
    ok = (price <= (avgPrice - need));
  }
  if(!ok) return;

  double trail = pips(InpTrailOffsetPoints);
  int total=PositionsTotal();
  for(int i=0;i<total;i++){
    ulong ticket=PositionGetTicket(i);
    if(ticket==0) continue;
    if(!PositionSelectByTicket(ticket)) continue;
    if(!IsMySymbol((string)PositionGetString(POSITION_SYMBOL))) continue;
    if((long)PositionGetInteger(POSITION_MAGIC)!=InpMagicNumber) continue;
    if((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE)!=pos_type) continue;

    double curSL = PositionGetDouble(POSITION_SL);
    double curTP = PositionGetDouble(POSITION_TP);
    double newSL = curSL;

    if(IsBuy(pos_type)){
      double targetSL = price - trail;
      if(InpTrailOnlyTighten) newSL = (curSL<=0) ? targetSL : MathMax(curSL, targetSL);
      else newSL = targetSL;
    }else{
      double targetSL = price + trail;
      if(InpTrailOnlyTighten) newSL = (curSL<=0) ? targetSL : MathMin(curSL, targetSL);
      else newSL = targetSL;
    }

    if(newSL != curSL){
      TradePositionModify(ticket, newSL, curTP);
    }
  }
}

//+------------------------------------------------------------------+
