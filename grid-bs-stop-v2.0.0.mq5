//+------------------------------------------------------------------+
//|                                        GridTrading_BuyAndSellStop.mq5    |
//|                                  Grid Trading with Buy Stop Only  |
//+------------------------------------------------------------------+
#property copyright "Grid Trading System"
#property version   "1.00"
#property strict

// Custom Enum
enum ENUM_GRID_TYPE { 
   GRID_CLOSE_ALL, // Close All
   GRID_TP, // TP
   GRID_TSL // Trailing Stop
};

enum ENUM_NET_PROFIT { 
   NET_PROFIT_POINTS, // Net Profit Points
   NET_PROFIT_AMOUNT  // Net Profit Amount
};

//--- Input Parameters
input group "++++++++++ BUY GRID SETTINGS ++++++++++";
input bool     InpBuyEnable = true;              // [Buy] Enable Trading
input ENUM_GRID_TYPE InpBuyGridType = GRID_CLOSE_ALL; // [Buy] Grid Type
input int      InpBuyGridStep = 5000;             // [Buy] Grid Step (points)
input double   InpBuyGridStepMultiplier = 1.1;    // [Buy] Grid Step Multiplier
input int      InpBuyFollowDistance = 1500;       // [Buy] Follow Distance (points)
input int      InpBuyOrderDistance = 1000;        // [Buy] Order Distance (points)

input group "=== BUY PROFIT ==="; 
input ENUM_NET_PROFIT InpBuySumNetType = NET_PROFIT_POINTS; // [Buy] Net Profit (Points/Amount)
input int InpBuyNetProfitPoints = 3000; // [Buy] Net Profit Points (points)
input double InpBuyProfitTargetAmount = 10.0; // [Buy] TP (Amount)

input group "=== BUY TRAILING STOP ==="; 
input int InpBuyStartTrailAbroveAvgPoints = 500; // [Buy] Start Trailing Stop (points)
input int InpBuyTrailOffsetPoints = 300; // [Buy] Trailing Stop Offset (points)
input bool InpBuyTrailOnlyTighten = true; // [Buy] Move SL just to get profit

input group "=== BUY LOT SIZE ===";
input double InpBuyLotSize = 0.01; // [Buy] Start Lot
input double InpBuyMartingale = 1.1; // [Buy] Martingale Multiplier
input double InpBuyMaxLots = 0.05; // [Buy] Maximum Lot

input group "=== BUY ZONE FILTER ===";
input bool InpBuyEnablePriceZone = false; // [Buy] Enable/Disable Price Zone
input double InpBuyUpperPrice = 0.0; // [Buy] Upper Price (0 = No Limit)
input double InpBuyLowerPrice = 0.0; // [Buy] Lower Price (0 = No Limit)

input group "=== BUY FILTER ===";
input bool InpBuyEnableTrend = false; // [Buy] Enable/Disable Trend Filter by 2 EMA
input bool InpBuyEnableStoch = false; // [Buy] Enable/Disable Stoch Filter

input group "++++++++++ SELL GRID SETTINGS ++++++++++";
input bool     InpSellEnable = false;              // [Sell] Enable Trading
input ENUM_GRID_TYPE InpSellGridType = GRID_CLOSE_ALL; // [Sell] Grid Type
input int      InpSellGridStep = 5000;             // [Sell] Grid Step (points)
input double   InpSellGridStepMultiplier = 1.1;    // [Sell] Grid Step Multiplier
input int      InpSellFollowDistance = 1500;       // [Sell] Follow Distance (points)
input int      InpSellOrderDistance = 1000;        // [Sell] Order Distance (points)

input group "=== SELL PROFIT ==="; 
input ENUM_NET_PROFIT InpSellSumNetType = NET_PROFIT_POINTS; // [Sell] Net Profit (Points/Amount)
input int InpSellNetProfitPoints = 3000; // [Sell] Net Profit Points (points)
input double InpSellProfitTargetAmount = 10.0; // [Sell] TP (Amount)

input group "=== SELL TRAILING STOP ==="; 
input int InpSellStartTrailAbroveAvgPoints = 500; // [Sell] Start Trailing Stop (points)
input int InpSellTrailOffsetPoints = 300; // [Sell] Trailing Stop Offset (points)
input bool InpSellTrailOnlyTighten = true;  // [Sell] Move SL just to get profit

input group "=== SELL LOT SIZE ===";
input double InpSellLotSize = 0.01; // [Sell] Start Lot
input double InpSellMartingale = 1.1; // [Sell] Martingale Multiplier
input double InpSellMaxLots = 0.05; // [Sell] Maximum Lot

input group "=== SELL ZONE FILTER ===";
input bool InpSellEnablePriceZone = false; // [Sell] Enable/Disable Price Zone
input double InpSellUpperPrice = 0.0; // [Sell] Upper Price (0 = No Limit)
input double InpSellLowerPrice = 0.0; // [Sell] Lower Price (0 = No Limit)

input group "=== SELL FILTER ===";
input bool InpSellEnableTrend = false; // [Sell] Enable/Disable Trend Filter by 2 EMA
input bool InpSellEnableStoch = false; // [Sell] Enable/Disable Stoch Filter

//input group "++++++++++ INDICATOR FILTER ++++++++++";
input group "=== TREND ===";
input ENUM_TIMEFRAMES  InpTrendTF = PERIOD_H1; // [Buy] TF for Trend Filter
input int InpEmaFast = 50; // [Buy] EMA Fast
input int InpEmaSlow = 200; // [Buy] EMA Slow

input group "=== STOCH ===";
input ENUM_TIMEFRAMES InpStochTF = PERIOD_M5; // TF for Stoch Indicator
input int InpStochK = 14; // Stock K
input int InpStochD = 3; // Stock D
input int InpStochSlowing = 3; // Stoch Slowing
input ENUM_MA_METHOD InpStochMAMethod = MODE_SMA; // moving average method for stoch
input ENUM_STO_PRICE InpStochPrice = STO_LOWHIGH; // calculation method (Low/High or Close/Close)
input double InpStochOversold = 30.0; // Stoch Oversold
input double InpStochOverbought = 70.0; // Stoch Overbought

input group "++++++++++ OTHER ++++++++++";
input int      InpMagicNumber = 2025111201;        // Magic Number
input int      InpSlippage = 10; // Slippage (points)
input string   InpTradeComment = "Grid_BuySellStop"; // Comment

struct ProfitInfo{
  double profit;
  double volume;
  int count;
};

//--- Global Variables
double g_point_value;
int g_digits;

int handle_stoch = INVALID_HANDLE;
int handle_ema_fast = INVALID_HANDLE;
int handle_ema_slow = INVALID_HANDLE;

double buffer_stoch_main[];
double buffer_ema_fast[];
double buffer_ema_slow[];

//+------------------------------------------------------------------+
//| Expert initialization function                                    |
//+------------------------------------------------------------------+
int OnInit()
{
   //--- Get symbol properties
   g_point_value = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   g_digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   
   //--- Check parameters
   if(InpBuyGridStep <= 0 || InpBuyFollowDistance <= 0 || InpBuyOrderDistance <= 0
   || InpSellGridStep <= 0 || InpSellFollowDistance <= 0 || InpSellOrderDistance <= 0)
   {
      Print("Error: Invalid input parameters!");
      return(INIT_PARAMETERS_INCORRECT);
   }
   
   handle_stoch = iStochastic(_Symbol, InpStochTF, InpStochK, InpStochD, InpStochSlowing, InpStochMAMethod, InpStochPrice);
   handle_ema_fast = iMA(_Symbol, InpTrendTF, InpEmaFast, 0, MODE_EMA, PRICE_CLOSE);
   handle_ema_slow = iMA(_Symbol, InpTrendTF, InpEmaSlow, 0, MODE_EMA, PRICE_CLOSE);
   
   if(handle_stoch == INVALID_HANDLE || handle_ema_fast == INVALID_HANDLE || handle_ema_slow == INVALID_HANDLE)
   {
      Print("Error creating indicators");
      return(INIT_FAILED);
   }
   
   //--- Set array as series
   ArraySetAsSeries(buffer_stoch_main, true);
   ArraySetAsSeries(buffer_ema_fast, true);
   ArraySetAsSeries(buffer_ema_slow, true);
   
   Print("Grid Trading EA initialized successfully");
   //Print("Grid Step: ", InpBuyGridStep, " points");
   //Print("Follow Distance: ", InpBuyFollowDistance, " points");
   //Print("Order Distance: ", InpBuyOrderDistance, " points");
   //Print("Net Profit Points: ", InpBuyNetProfitPoints, " points");
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                  |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   IndicatorRelease(handle_stoch);
   IndicatorRelease(handle_ema_fast);
   IndicatorRelease(handle_ema_slow);
   
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
   
   if(!UpdateIndicators()) return;
   
   if (InpBuyEnable) BuyManagement(ask);
   if (InpSellEnable) SellManagement(bid);
}

double pips(int pts){ return (double)pts * _Point; }
bool   IsBuy(ENUM_POSITION_TYPE t){ return (t==POSITION_TYPE_BUY); }
bool   IsSell(ENUM_POSITION_TYPE t){ return (t==POSITION_TYPE_SELL); }
bool   IsMySymbol(const string sym){ return (sym==_Symbol); }

//+------------------------------------------------------------------+
//| Update indicator buffers                                           |
//+------------------------------------------------------------------+
bool UpdateIndicators()
{
   if(CopyBuffer(handle_stoch, 0, 0, 5, buffer_stoch_main) <= 0) return false;
   if(CopyBuffer(handle_ema_fast, 0, 0, 5, buffer_ema_fast) <= 0) return false;
   if(CopyBuffer(handle_ema_slow, 0, 0, 5, buffer_ema_slow) <= 0) return false;
   
   return true;
}

bool CheckBuySignal () {
   if (InpBuyEnableTrend && buffer_ema_fast[1] < buffer_ema_slow[1]) return false;
   if (InpBuyEnableStoch) {
      bool is_cross_up = buffer_stoch_main[2] <= InpStochOversold && buffer_stoch_main[1] > InpStochOversold;
      if (!is_cross_up) return false;
   }

   return true;
}

bool CheckSellSignal () {
   if (InpSellEnableTrend && buffer_ema_fast[1] > buffer_ema_slow[1]) return false;
   if (InpSellEnableStoch) {
      bool is_cross_down = buffer_stoch_main[2] >= InpStochOverbought && buffer_stoch_main[1] < InpStochOverbought;
      if (!is_cross_down) return false;
   }

   return true;
}

void BuyManagement(double ask) {
//--- Count positions and orders
   int buy_positions = CountPositions(POSITION_TYPE_BUY);
   int buy_stop_orders = CountPendingOrders(ORDER_TYPE_BUY_STOP);
   
   //--- Check if we should close all positions (Profit Target)
   if(buy_positions > 0)
   {
      bool chkNetProfit = CheckNetProfit(POSITION_TYPE_BUY);
      if(chkNetProfit && InpBuyGridType == GRID_CLOSE_ALL)
      {
         CloseAllPositions(POSITION_TYPE_BUY);
         DeleteAllStopOrders(ORDER_TYPE_BUY_STOP);
         return;
      }
      
      if(chkNetProfit && InpBuyGridType == GRID_TSL)
      {
         MaybeTrailAll(POSITION_TYPE_BUY);
         return;
      }
   }
   
   //--- Get lowest buy position price
   double lowest_buy_price = GetLowestBuyPrice();
   
   //--- Condition 1: No Buy Position - Place Buy Stop
   if(buy_positions == 0 && buy_stop_orders == 0)
   {
      if (!CheckBuySignal()) return;
      double buy_stop_price = NormalizeDouble(ask + InpBuyOrderDistance * g_point_value, g_digits);
      PlaceBuyStop(buy_stop_price);
      return;
   }
   
   //--- Condition 2: Follow price down (adjust Buy Stop)
   if(buy_positions == 0 && buy_stop_orders > 0)
   {
      double current_buy_stop_price = GetCurrentStopPrice(ORDER_TYPE_BUY_STOP);
      if(current_buy_stop_price > 0)
      {
         double distance = (current_buy_stop_price - ask) / g_point_value;
         
         // ถ้าระยะห่างมากกว่าหรือเท่ากับ Follow Distance
         if(distance >= InpBuyFollowDistance)
         {
            DeleteAllStopOrders(ORDER_TYPE_BUY_STOP);
            double new_buy_stop_price = NormalizeDouble(ask + InpBuyOrderDistance * g_point_value, g_digits);
            PlaceBuyStop(new_buy_stop_price);
         }
      }
      return;
   }
   
   //--- Condition 3 & 4: Has Buy Position - Manage Buy Stop
   if(buy_positions > 0)
   {
      int grid_step_result = MathRound(InpBuyGridStep * pow(InpBuyGridStepMultiplier, CountPositions(POSITION_TYPE_BUY) - 1));
      double threshold_price = lowest_buy_price - (grid_step_result + InpBuyFollowDistance) * g_point_value;
      
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
      if(buy_stop_orders > 0)
      {
         double current_buy_stop_price = GetCurrentStopPrice(ORDER_TYPE_BUY_STOP);
         double new_buy_stop_price = NormalizeDouble(ask + InpBuyOrderDistance * g_point_value, g_digits);
         if(current_buy_stop_price >= lowest_buy_price)
         {
            DeleteAllStopOrders(ORDER_TYPE_BUY_STOP);
         }
         if(ask <= threshold_price && current_buy_stop_price > ask + InpBuyFollowDistance * g_point_value)
         {
            DeleteAllStopOrders(ORDER_TYPE_BUY_STOP);
            PlaceBuyStop(new_buy_stop_price);
         }
      }
   }
}

void SellManagement(double bid) {
//--- Count positions and orders
   int sell_positions = CountPositions(POSITION_TYPE_SELL);
   int sell_stop_orders = CountPendingOrders(ORDER_TYPE_SELL_STOP);
   
   //--- Check if we should close all positions (Profit Target)
   if(sell_positions > 0)
   {
      bool chkNetProfit = CheckNetProfit(POSITION_TYPE_SELL);
      if(chkNetProfit && InpSellGridType == GRID_CLOSE_ALL)
      {
         CloseAllPositions(POSITION_TYPE_SELL);
         DeleteAllStopOrders(ORDER_TYPE_SELL_STOP);
         return;
      }
      
      if(chkNetProfit && InpSellGridType == GRID_TSL)
      {
         MaybeTrailAll(POSITION_TYPE_SELL);
         return;
      }
   }
   
   //--- Get highest sell position price
   double highest_sell_price = GetHighestSellPrice();
   
   //--- Condition 1: No Sell Position - Place Sell Stop
   if(sell_positions == 0 && sell_stop_orders == 0)
   {
      if (!CheckSellSignal()) return;
      double sell_stop_price = NormalizeDouble(bid - InpSellOrderDistance * g_point_value, g_digits);
      PlaceSellStop(sell_stop_price);
      return;
   }
   
   //--- Condition 2: Follow price up (adjust Sell Stop)
   if(sell_positions == 0 && sell_stop_orders > 0)
   {
      double current_sell_stop_price = GetCurrentStopPrice(ORDER_TYPE_SELL_STOP);
      if(current_sell_stop_price > 0)
      {
         double distance = (bid - current_sell_stop_price) / g_point_value;
         
         // ถ้าระยะห่างมากกว่าหรือเท่ากับ Follow Distance
         if(distance >= InpSellFollowDistance)
         {
            DeleteAllStopOrders(ORDER_TYPE_SELL_STOP);
            double new_sell_stop_price = NormalizeDouble(bid - InpSellOrderDistance * g_point_value, g_digits);
            PlaceSellStop(new_sell_stop_price);
         }
      }
      return;
   }
   
   //--- Condition 3 & 4: Has Sell Position - Manage Sell Stop
   if(sell_positions > 0)
   {
      int grid_step_result = MathRound(InpSellGridStep * pow(InpSellGridStepMultiplier, CountPositions(POSITION_TYPE_SELL) - 1));
      double threshold_price = highest_sell_price + (grid_step_result + InpSellFollowDistance) * g_point_value;
      
      // If has not Sell Stop & Bid > threshold_price
      if(sell_stop_orders == 0 && bid > threshold_price)
      {
         // ตั้ง Buy Stop ที่ต่ำกว่า lowest position ตาม Grid Step
         double new_sell_stop_price = NormalizeDouble(highest_sell_price + grid_step_result * g_point_value, g_digits);
         
         // ตรวจสอบว่าไม่เหนือ lowest position
         if(new_sell_stop_price > highest_sell_price)
         {
            PlaceSellStop(new_sell_stop_price);
         }
      }
      
      // ถ้ามี Buy Stop อยู่แล้ว ตรวจสอบว่าไม่เหนือ lowest position
      if(sell_stop_orders > 0)
      {
         double current_sell_stop_price = GetCurrentStopPrice(ORDER_TYPE_SELL_STOP);
         double new_sell_stop_price = NormalizeDouble(bid - InpSellOrderDistance * g_point_value, g_digits);
         if(current_sell_stop_price <= highest_sell_price)
         {
            DeleteAllStopOrders(ORDER_TYPE_SELL_STOP);
         }
         if(bid >= threshold_price && current_sell_stop_price < bid - InpSellFollowDistance * g_point_value)
         {
            DeleteAllStopOrders(ORDER_TYPE_SELL_STOP);
            PlaceSellStop(new_sell_stop_price);
         }
      }
   }
}

bool ValidateZone(ENUM_POSITION_TYPE pos_type) {
   double price = SymbolInfoDouble(_Symbol, pos_type == POSITION_TYPE_BUY ? SYMBOL_BID : SYMBOL_ASK);
   double upper_price = pos_type == POSITION_TYPE_BUY ? InpBuyUpperPrice: InpSellUpperPrice;
   double lower_price = pos_type == POSITION_TYPE_BUY ? InpBuyLowerPrice: InpSellLowerPrice;
   if (price >= upper_price && upper_price != 0.0) return false;
   else if (price <= lower_price && lower_price != 0.0) return false;
   
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
//| Get lowest buy position price                                     |
//+------------------------------------------------------------------+
double GetHighestSellPrice()
{
   double highest = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
      {
         if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
            PositionGetInteger(POSITION_MAGIC) == InpMagicNumber &&
            PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL)
         {
            double price = PositionGetDouble(POSITION_PRICE_OPEN);
            if(highest == 0 || price > highest)
            {
               highest = price;
            }
         }
      }
   }
   return highest;
}

//+------------------------------------------------------------------+
//| Get current Buy/Sell Stop price                                        |
//+------------------------------------------------------------------+
double GetCurrentStopPrice(ENUM_ORDER_TYPE order_type)
{
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(OrderSelect(ticket))
      {
         if(OrderGetString(ORDER_SYMBOL) == _Symbol &&
            OrderGetInteger(ORDER_MAGIC) == InpMagicNumber &&
            OrderGetInteger(ORDER_TYPE) == order_type)
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
   double price_change = (pos_type == POSITION_TYPE_BUY ? InpBuyNetProfitPoints: InpSellNetProfitPoints) * g_point_value;
   
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
   bool isTradeZone = ValidateZone(POSITION_TYPE_BUY);
   if (InpBuyEnablePriceZone && !isTradeZone) return false;
   
   MqlTradeRequest request = {};
   MqlTradeResult result = {};
   
   double next_lots = NormalizeDouble(InpBuyLotSize * pow(InpBuyMartingale, CountPositions(POSITION_TYPE_BUY)), 2);
   if (next_lots > InpBuyMaxLots) next_lots = InpBuyMaxLots;
   
   double tp_price = 0;
   if (InpBuyGridType == GRID_TP) {
      //if(dir==DIR_BUY) tpPrice = CalTagetPrice(tk.ask, InpProfitTargetPts);
      //else tpPrice = CalTagetPrice(tk.bid, InpProfitTargetPts); 
      //tp_price = CalTagetPrice(POSITION_TYPE_BUY);
      int buy_positions = CountPositions(POSITION_TYPE_BUY);
      int next_grid_step = buy_positions == 0 ? InpBuyGridStep: MathRound(InpBuyGridStep * pow(InpBuyGridStepMultiplier, buy_positions - 1));
      tp_price = price + next_grid_step * g_point_value;
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
   //request.type_filling = ORDER_FILLING_RETURN;
   
   if(!OrderSend(request, result))
   {
      Print("Error placing Buy Stop: ", GetLastError(), " - ", result.comment);
      return false;
   }
   
   Print("Buy Stop placed at ", price, " | Ticket: ", result.order);
   return true;
}

//+------------------------------------------------------------------+
//| Place Sell Stop order                                              |
//+------------------------------------------------------------------+
bool PlaceSellStop(double price)
{
   bool isTradeZone = ValidateZone(POSITION_TYPE_SELL);
   if (InpSellEnablePriceZone && !isTradeZone) return false;
   
   MqlTradeRequest request = {};
   MqlTradeResult result = {};
   
   double next_lots = NormalizeDouble(InpSellLotSize * pow(InpSellMartingale, CountPositions(POSITION_TYPE_SELL)), 2);
   if (next_lots > InpSellMaxLots) next_lots = InpSellMaxLots;
   
   double tp_price = 0;
   if (InpSellGridType == GRID_TP) {
      //if(dir==DIR_BUY) tpPrice = CalTagetPrice(tk.ask, InpProfitTargetPts);
      //else tpPrice = CalTagetPrice(tk.bid, InpProfitTargetPts); 
      //tp_price = CalTagetPrice(POSITION_TYPE_SELL);
      int sell_positions = CountPositions(POSITION_TYPE_SELL);
      int next_grid_step = sell_positions == 0 ? InpSellGridStep: MathRound(InpSellGridStep * pow(InpSellGridStepMultiplier, sell_positions - 1));
      tp_price = price - next_grid_step * g_point_value;
   }
   
   request.action = TRADE_ACTION_PENDING;
   request.symbol = _Symbol;
   request.volume = next_lots;
   request.type = ORDER_TYPE_SELL_STOP;
   request.price = price;
   request.sl = 0;
   request.tp = tp_price;
   request.deviation = InpSlippage;
   request.magic = InpMagicNumber;
   request.comment = InpTradeComment;
   request.type_filling = ORDER_FILLING_IOC;
   //request.type_filling = ORDER_FILLING_RETURN;
   
   if(!OrderSend(request, result))
   {
      Print("Error placing Sell Stop: ", GetLastError(), " - ", result.comment);
      return false;
   }
   
   Print("Sell Stop placed at ", price, " | Ticket: ", result.order);
   return true;
}

//+------------------------------------------------------------------+
//| Delete all Buy/Sell Stop orders                                        |
//+------------------------------------------------------------------+
void DeleteAllStopOrders(ENUM_ORDER_TYPE order_type)
{
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(OrderSelect(ticket))
      {
         if(OrderGetString(ORDER_SYMBOL) == _Symbol &&
            OrderGetInteger(ORDER_MAGIC) == InpMagicNumber &&
            OrderGetInteger(ORDER_TYPE) == order_type)
         {
            MqlTradeRequest request = {};
            MqlTradeResult result = {};
            
            request.action = TRADE_ACTION_REMOVE;
            request.order = ticket;
            
            if(OrderSend(request, result))
            {
               Print("Order Stop deleted: ", ticket);
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Check net profit of all buy/sell positions                             |
//+------------------------------------------------------------------+
bool CheckNetProfit(ENUM_POSITION_TYPE pos_type)
{
   double total_profit_points = 0;
   double total_volume = 0;
   double weighted_price = 0;
   
   double current_price = SymbolInfoDouble(_Symbol, pos_type == POSITION_TYPE_BUY ? SYMBOL_BID: SYMBOL_ASK);
   
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
      {
         if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
            PositionGetInteger(POSITION_MAGIC) == InpMagicNumber &&
            PositionGetInteger(POSITION_TYPE) == pos_type)
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
      //total_profit_points = (current_bid - average_price) / g_point_value;
      if(pos_type == POSITION_TYPE_BUY)
      {
         total_profit_points = (current_price - average_price) / g_point_value;
      }
      else  // SELL
      {
         total_profit_points = (average_price - current_price) / g_point_value; 
      }
      
      Print("Average Price: ", average_price, " | Current Price: ", current_price, 
            " | Profit Points: ", total_profit_points);
      
      int net_profit_points = pos_type == POSITION_TYPE_BUY ? InpBuyNetProfitPoints: InpSellNetProfitPoints;
      if(total_profit_points >= net_profit_points)
      {
         Print("Net profit target reached! Closing all buy positions...");
         return true;
      }
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| Close all buy/sell positions                                           |
//+------------------------------------------------------------------+
void CloseAllPositions(ENUM_POSITION_TYPE pos_type)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
      {
         if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
            PositionGetInteger(POSITION_MAGIC) == InpMagicNumber &&
            PositionGetInteger(POSITION_TYPE) == pos_type)
         {
            MqlTradeRequest request = {};
            MqlTradeResult result = {};
            
            request.action = TRADE_ACTION_DEAL;
            request.symbol = _Symbol;
            request.volume = PositionGetDouble(POSITION_VOLUME);
            request.type = pos_type == POSITION_TYPE_BUY ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
            request.position = ticket;
            request.price = SymbolInfoDouble(_Symbol, pos_type == POSITION_TYPE_BUY ? SYMBOL_BID: SYMBOL_ASK);
            request.deviation = InpSlippage;
            request.magic = InpMagicNumber;
            request.type_filling = ORDER_FILLING_IOC;
            //request.type_filling = ORDER_FILLING_RETURN;
            
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
                                                
  double price = SymbolInfoDouble(_Symbol, pos_type == POSITION_TYPE_BUY ? SYMBOL_BID : SYMBOL_ASK);                                                

  double need = pips(pos_type == POSITION_TYPE_BUY ? InpBuyStartTrailAbroveAvgPoints: InpSellStartTrailAbroveAvgPoints);
  bool ok=false;
  if(IsBuy(pos_type)){
    ok = (price >= (avgPrice + need));
  }else{
    ok = (price <= (avgPrice - need));
  }
  if(!ok) return;

  double trail = pips(pos_type == POSITION_TYPE_BUY ? InpBuyTrailOffsetPoints: InpSellTrailOffsetPoints);
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
      if(InpBuyTrailOnlyTighten) newSL = (curSL<=0) ? targetSL : MathMax(curSL, targetSL);
      else newSL = targetSL;
    }else{
      double targetSL = price + trail;
      if(InpSellTrailOnlyTighten) newSL = (curSL<=0) ? targetSL : MathMin(curSL, targetSL);
      else newSL = targetSL;
    }

    if(newSL != curSL){
      TradePositionModify(ticket, newSL, curTP);
    }
  }
}

//+------------------------------------------------------------------+
