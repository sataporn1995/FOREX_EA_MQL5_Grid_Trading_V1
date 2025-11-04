//+------------------------------------------------------------------+
//|                                           EMA_Pullback_EA.mq5    |
//|                                  Copyright 2025, Your Name       |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025"
#property link      "https://www.mql5.com"
#property version   "1.00"
#property strict

// Input Parameters
input double   LotSize = 0.01;              // ขนาด Lot
input int      MagicNumber = 20251104;        // Magic Number
input string   TradeComment = "EMA_PB";     // คอมเมนต์ Order

// EMA Parameters
input int      EMA_H1_Period = 200;         // EMA H1 สำหรับ Trend Filter
input int      EMA_M5_Fast = 50;            // EMA 50 (M5)
input int      EMA_M5_Mid = 90;             // EMA 90 (M5)
input int      EMA_M5_Slow = 170;           // EMA 170 (M5)

input double   RR_Ratio = 2.5;              // Risk:Reward Ratio
input int      Slippage = 30;               // Slippage

// Global Variables
int handleEMA_H1;
int handleEMA_M5_Fast;
int handleEMA_M5_Mid;
int handleEMA_M5_Slow;

double ema_h1[];
double ema_m5_fast[];
double ema_m5_mid[];
double ema_m5_slow[];

// State tracking variables
bool waitingForPullback = false;
bool pullbackDetected = false;
bool deepPullbackDetected = false;
string currentDirection = "";

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   // สร้าง EMA Indicators
   handleEMA_H1 = iMA(_Symbol, PERIOD_H1, EMA_H1_Period, 0, MODE_EMA, PRICE_CLOSE);
   handleEMA_M5_Fast = iMA(_Symbol, PERIOD_M5, EMA_M5_Fast, 0, MODE_EMA, PRICE_CLOSE);
   handleEMA_M5_Mid = iMA(_Symbol, PERIOD_M5, EMA_M5_Mid, 0, MODE_EMA, PRICE_CLOSE);
   handleEMA_M5_Slow = iMA(_Symbol, PERIOD_M5, EMA_M5_Slow, 0, MODE_EMA, PRICE_CLOSE);
   
   if(handleEMA_H1 == INVALID_HANDLE || handleEMA_M5_Fast == INVALID_HANDLE || 
      handleEMA_M5_Mid == INVALID_HANDLE || handleEMA_M5_Slow == INVALID_HANDLE)
   {
      Print("Error creating EMA indicators");
      return(INIT_FAILED);
   }
   
   ArraySetAsSeries(ema_h1, true);
   ArraySetAsSeries(ema_m5_fast, true);
   ArraySetAsSeries(ema_m5_mid, true);
   ArraySetAsSeries(ema_m5_slow, true);
   
   Print("EA Initialized Successfully");
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   IndicatorRelease(handleEMA_H1);
   IndicatorRelease(handleEMA_M5_Fast);
   IndicatorRelease(handleEMA_M5_Mid);
   IndicatorRelease(handleEMA_M5_Slow);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // ตรวจสอบว่ามี Order เปิดอยู่หรือไม่
   if(PositionSelect(_Symbol))
   {
      return; // มี Position อยู่แล้ว ไม่เปิด Order ใหม่
   }
   
   // อัพเดทข้อมูล Indicators
   if(!UpdateIndicators())
      return;
   
   // ตรวจสอบเงื่อนไข BUY
   if(CheckBuyConditions())
   {
      OpenBuyOrder();
   }
   // ตรวจสอบเงื่อนไข SELL
   else if(CheckSellConditions())
   {
      OpenSellOrder();
   }
}

//+------------------------------------------------------------------+
//| Update Indicator Values                                          |
//+------------------------------------------------------------------+
bool UpdateIndicators()
{
   if(CopyBuffer(handleEMA_H1, 0, 0, 3, ema_h1) <= 0)
      return false;
   if(CopyBuffer(handleEMA_M5_Fast, 0, 0, 5, ema_m5_fast) <= 0)
      return false;
   if(CopyBuffer(handleEMA_M5_Mid, 0, 0, 5, ema_m5_mid) <= 0)
      return false;
   if(CopyBuffer(handleEMA_M5_Slow, 0, 0, 5, ema_m5_slow) <= 0)
      return false;
   
   return true;
}

//+------------------------------------------------------------------+
//| Check H1 Trend Filter for BUY                                    |
//+------------------------------------------------------------------+
bool CheckH1TrendBuy()
{
   MqlRates h1_rates[];
   ArraySetAsSeries(h1_rates, true);
   
   if(CopyRates(_Symbol, PERIOD_H1, 0, 2, h1_rates) <= 0)
      return false;
   
   // ราคาปิดแท่งเทียนล่าสุด H1 > EMA(200)
   return (h1_rates[1].close > ema_h1[1]);
}

//+------------------------------------------------------------------+
//| Check H1 Trend Filter for SELL                                   |
//+------------------------------------------------------------------+
bool CheckH1TrendSell()
{
   MqlRates h1_rates[];
   ArraySetAsSeries(h1_rates, true);
   
   if(CopyRates(_Symbol, PERIOD_H1, 0, 2, h1_rates) <= 0)
      return false;
   
   // ราคาปิดแท่งเทียนล่าสุด H1 < EMA(200)
   return (h1_rates[1].close < ema_h1[1]);
}

//+------------------------------------------------------------------+
//| Check EMA Alignment for BUY (50 > 90 > 170)                     |
//+------------------------------------------------------------------+
bool CheckEMAAlignmentBuy()
{
   // เรียงจากด้านบน: EMA50 > EMA90 > EMA170
   return (ema_m5_fast[1] > ema_m5_mid[1] && ema_m5_mid[1] > ema_m5_slow[1]);
}

//+------------------------------------------------------------------+
//| Check EMA Alignment for SELL (170 > 90 > 50)                    |
//+------------------------------------------------------------------+
bool CheckEMAAlignmentSell()
{
   // เรียงจากด้านบน: EMA170 > EMA90 > EMA50
   return (ema_m5_slow[1] > ema_m5_mid[1] && ema_m5_mid[1] > ema_m5_fast[1]);
}

//+------------------------------------------------------------------+
//| Check BUY Conditions                                             |
//+------------------------------------------------------------------+
bool CheckBuyConditions()
{
   // 1. ตรวจสอบ Trend Filter H1
   if(!CheckH1TrendBuy())
      return false;
   
   // 2. ตรวจสอบการเรียงตัวของ EMA
   if(!CheckEMAAlignmentBuy())
      return false;
   
   MqlRates m5_rates[];
   ArraySetAsSeries(m5_rates, true);
   
   if(CopyRates(_Symbol, PERIOD_M5, 0, 5, m5_rates) <= 0)
      return false;
   
   // 3. ตรวจสอบ Pullback: กราฟปิดต่ำกว่า EMA(50)
   bool pullbackBelowEMA50 = false;
   for(int i = 1; i <= 3; i++)
   {
      if(m5_rates[i].close < ema_m5_fast[i])
      {
         pullbackBelowEMA50 = true;
         break;
      }
   }
   
   if(!pullbackBelowEMA50)
      return false;
   
   // 4. ตรวจสอบ Deep Pullback: ต่ำกว่า EMA(90) หรือ EMA(170) แต่ไม่ปิดต่ำกว่า EMA(170)
   bool deepPullback = false;
   for(int i = 1; i <= 3; i++)
   {
      // ต้องทำ Deep Pullback (ต่ำกว่า EMA90 หรือ EMA170)
      if(m5_rates[i].low < ema_m5_mid[i] || m5_rates[i].low < ema_m5_slow[i])
      {
         // แต่ราคาปิดต้องไม่ต่ำกว่า EMA(170)
         if(m5_rates[i].close >= ema_m5_slow[i])
         {
            deepPullback = true;
            break;
         }
      }
   }
   
   if(!deepPullback)
      return false;
   
   // 5. รอให้กราฟกลับไปปิดเหนือ EMA(50)
   if(m5_rates[1].close > ema_m5_fast[1] && m5_rates[2].close <= ema_m5_fast[2])
   {
      return true;
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| Check SELL Conditions                                            |
//+------------------------------------------------------------------+
bool CheckSellConditions()
{
   // 1. ตรวจสอบ Trend Filter H1
   if(!CheckH1TrendSell())
      return false;
   
   // 2. ตรวจสอบการเรียงตัวของ EMA
   if(!CheckEMAAlignmentSell())
      return false;
   
   MqlRates m5_rates[];
   ArraySetAsSeries(m5_rates, true);
   
   if(CopyRates(_Symbol, PERIOD_M5, 0, 5, m5_rates) <= 0)
      return false;
   
   // 3. ตรวจสอบ Pullback: กราฟปิดสูงกว่า EMA(50)
   bool pullbackAboveEMA50 = false;
   for(int i = 1; i <= 3; i++)
   {
      if(m5_rates[i].close > ema_m5_fast[i])
      {
         pullbackAboveEMA50 = true;
         break;
      }
   }
   
   if(!pullbackAboveEMA50)
      return false;
   
   // 4. ตรวจสอบ Deep Pullback: สูงกว่า EMA(90) หรือ EMA(170) แต่ไม่ปิดสูงกว่า EMA(170)
   bool deepPullback = false;
   for(int i = 1; i <= 3; i++)
   {
      // ต้องทำ Deep Pullback (สูงกว่า EMA90 หรือ EMA170)
      if(m5_rates[i].high > ema_m5_mid[i] || m5_rates[i].high > ema_m5_slow[i])
      {
         // แต่ราคาปิดต้องไม่สูงกว่า EMA(170)
         if(m5_rates[i].close <= ema_m5_slow[i])
         {
            deepPullback = true;
            break;
         }
      }
   }
   
   if(!deepPullback)
      return false;
   
   // 5. รอให้กราฟกลับลงไปปิดต่ำกว่า EMA(50)
   if(m5_rates[1].close < ema_m5_fast[1] && m5_rates[2].close >= ema_m5_fast[2])
   {
      return true;
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| Open BUY Order                                                   |
//+------------------------------------------------------------------+
void OpenBuyOrder()
{
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double sl = ema_m5_slow[1];  // SL ที่ EMA(170)
   double slDistance = ask - sl;
   double tp = ask + (slDistance * RR_Ratio);  // TP = 2.5 เท่าของ SL
   
   // Normalize prices
   sl = NormalizeDouble(sl, _Digits);
   tp = NormalizeDouble(tp, _Digits);
   
   MqlTradeRequest request = {};
   MqlTradeResult result = {};
   
   request.action = TRADE_ACTION_DEAL;
   request.symbol = _Symbol;
   request.volume = LotSize;
   request.type = ORDER_TYPE_BUY;
   request.price = ask;
   request.sl = sl;
   request.tp = tp;
   request.deviation = Slippage;
   request.magic = MagicNumber;
   request.comment = TradeComment;
   
   if(OrderSend(request, result))
   {
      Print("BUY Order opened successfully. Ticket: ", result.order);
   }
   else
   {
      Print("Error opening BUY order: ", GetLastError());
   }
}

//+------------------------------------------------------------------+
//| Open SELL Order                                                  |
//+------------------------------------------------------------------+
void OpenSellOrder()
{
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double sl = ema_m5_slow[1];  // SL ที่ EMA(170)
   double slDistance = sl - bid;
   double tp = bid - (slDistance * RR_Ratio);  // TP = 2.5 เท่าของ SL
   
   // Normalize prices
   sl = NormalizeDouble(sl, _Digits);
   tp = NormalizeDouble(tp, _Digits);
   
   MqlTradeRequest request = {};
   MqlTradeResult result = {};
   
   request.action = TRADE_ACTION_DEAL;
   request.symbol = _Symbol;
   request.volume = LotSize;
   request.type = ORDER_TYPE_SELL;
   request.price = bid;
   request.sl = sl;
   request.tp = tp;
   request.deviation = Slippage;
   request.magic = MagicNumber;
   request.comment = TradeComment;
   
   if(OrderSend(request, result))
   {
      Print("SELL Order opened successfully. Ticket: ", result.order);
   }
   else
   {
      Print("Error opening SELL order: ", GetLastError());
   }
}
//+------------------------------------------------------------------+
