//+------------------------------------------------------------------+
//|                                           Trend Scalping EA.mq5 |
//|                                  Copyright 2024, Your Name       |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024"
#property link      "https://www.mql5.com"
#property version   "1.00"

#include <Trade\Trade.mqh>

//--- Input Parameters
input group "=== Trend Detection (EMA) ==="
input ENUM_TIMEFRAMES TrendTimeframe = PERIOD_H1;        // Timeframe สำหรับตรวจสอบเทรนด์
input int FastEMA = 8;                                    // EMA เร็ว
input int MiddleEMA = 21;                                 // EMA กลาง
input int SlowEMA = 50;                                   // EMA ช้า

input group "=== Entry Signals ==="
input ENUM_TIMEFRAMES SignalTimeframe = PERIOD_M5;       // Timeframe สำหรับสัญญาณเข้า
input int StochK = 5;                                     // Stochastic %K Period
input int StochD = 3;                                     // Stochastic %D Period
input int StochSlowing = 3;                               // Stochastic Slowing
input int RSI_Period = 14;                                // RSI Period
input double StochOversold = 30.0;                        // Stochastic Oversold Level
input double StochOverbought = 70.0;                      // Stochastic Overbought Level
input double RSI_Oversold = 30.0;                         // RSI Oversold Level
input double RSI_Overbought = 70.0;                       // RSI Overbought Level

input group "=== Stop Loss & Take Profit ==="
input ENUM_TIMEFRAMES SL_Timeframe = PERIOD_M5;          // Timeframe สำหรับคำนวณ SL
input int SwingLookback = 10;                             // จำนวนแท่งย้อนหลังสำหรับหา Swing High/Low
input int ATR_Period = 14;                                // ATR Period
input double ATR_Multiplier = 1.5;                        // ATR Multiplier สำหรับ SL
input double TP_Ratio = 2.0;                              // Risk:Reward Ratio (1, 2, 3, etc.)

input group "=== Money Management ==="
input double LotSize = 0.01;                              // Lot Size
input double RiskPercent = 1.0;                           // % Risk ต่อเทรด (0 = ใช้ Fixed Lot)
input int MaxSpread = 30;                                 // Spread สูงสุดที่อนุญาต (points)

input group "=== Trading Hours ==="
input bool UseTimeFilter = false;                         // ใช้ฟิลเตอร์เวลา
input int StartHour = 0;                                  // เวลาเริ่มเทรด (ชั่วโมง)
input int EndHour = 23;                                   // เวลาหยุดเทรด (ชั่วโมง)

input group "=== General Settings ==="
input int MagicNumber = 123456;                           // Magic Number
input string TradeComment = "Trend Scalping";             // Comment

//--- Global Variables
CTrade trade;
int handleEMA_Fast, handleEMA_Middle, handleEMA_Slow;
int handleStoch, handleRSI, handleATR;
double emaFast[], emaMiddle[], emaSlow[];
double stochMain[], stochSignal[];
double rsiBuffer[];
double atrBuffer[];

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   //--- Set trade parameters
   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(10);
   trade.SetTypeFilling(ORDER_FILLING_FOK);
   
   //--- Create indicators for trend detection
   handleEMA_Fast = iMA(_Symbol, TrendTimeframe, FastEMA, 0, MODE_EMA, PRICE_CLOSE);
   handleEMA_Middle = iMA(_Symbol, TrendTimeframe, MiddleEMA, 0, MODE_EMA, PRICE_CLOSE);
   handleEMA_Slow = iMA(_Symbol, TrendTimeframe, SlowEMA, 0, MODE_EMA, PRICE_CLOSE);
   
   //--- Create indicators for entry signals
   handleStoch = iStochastic(_Symbol, SignalTimeframe, StochK, StochD, StochSlowing, MODE_SMA, STO_LOWHIGH);
   handleRSI = iRSI(_Symbol, SignalTimeframe, RSI_Period, PRICE_CLOSE);
   
   //--- Create ATR for SL calculation
   handleATR = iATR(_Symbol, SL_Timeframe, ATR_Period);
   
   //--- Check if indicators are created successfully
   if(handleEMA_Fast == INVALID_HANDLE || handleEMA_Middle == INVALID_HANDLE || 
      handleEMA_Slow == INVALID_HANDLE || handleStoch == INVALID_HANDLE || 
      handleRSI == INVALID_HANDLE || handleATR == INVALID_HANDLE)
   {
      Print("Error creating indicators!");
      return(INIT_FAILED);
   }
   
   //--- Set array as series
   ArraySetAsSeries(emaFast, true);
   ArraySetAsSeries(emaMiddle, true);
   ArraySetAsSeries(emaSlow, true);
   ArraySetAsSeries(stochMain, true);
   ArraySetAsSeries(stochSignal, true);
   ArraySetAsSeries(rsiBuffer, true);
   ArraySetAsSeries(atrBuffer, true);
   
   Print("Trend Scalping EA initialized successfully!");
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   //--- Release indicator handles
   IndicatorRelease(handleEMA_Fast);
   IndicatorRelease(handleEMA_Middle);
   IndicatorRelease(handleEMA_Slow);
   IndicatorRelease(handleStoch);
   IndicatorRelease(handleRSI);
   IndicatorRelease(handleATR);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   //--- Check if new bar
   static datetime lastBarTime = 0;
   datetime currentBarTime = iTime(_Symbol, SignalTimeframe, 0);
   
   if(currentBarTime == lastBarTime)
      return;
   
   lastBarTime = currentBarTime;
   
   //--- Check trading time
   if(UseTimeFilter && !IsWithinTradingHours())
      return;
   
   //--- Check spread
   long spread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   if(spread > MaxSpread)
   {
      Print("Spread too high: ", spread, " points");
      return;
   }
   
   //--- Check if already have position
   if(PositionSelect(_Symbol))
      return;
   
   //--- Copy indicator buffers
   if(!CopyIndicatorData())
      return;
   
   //--- Determine trend
   int trend = GetTrend();
   
   if(trend == 0) // Sideways - ไม่เทรด
      return;
   
   //--- Check for entry signals
   if(trend == 1) // Uptrend
   {
      if(CheckBuySignal())
         OpenBuy();
   }
   else if(trend == -1) // Downtrend
   {
      if(CheckSellSignal())
         OpenSell();
   }
}

//+------------------------------------------------------------------+
//| Copy indicator data                                              |
//+------------------------------------------------------------------+
bool CopyIndicatorData()
{
   if(CopyBuffer(handleEMA_Fast, 0, 0, 3, emaFast) <= 0)
      return false;
   if(CopyBuffer(handleEMA_Middle, 0, 0, 3, emaMiddle) <= 0)
      return false;
   if(CopyBuffer(handleEMA_Slow, 0, 0, 3, emaSlow) <= 0)
      return false;
   if(CopyBuffer(handleStoch, MAIN_LINE, 0, 3, stochMain) <= 0)
      return false;
   if(CopyBuffer(handleStoch, SIGNAL_LINE, 0, 3, stochSignal) <= 0)
      return false;
   if(CopyBuffer(handleRSI, 0, 0, 3, rsiBuffer) <= 0)
      return false;
   if(CopyBuffer(handleATR, 0, 0, 3, atrBuffer) <= 0)
      return false;
   
   return true;
}

//+------------------------------------------------------------------+
//| Determine trend using 3 EMAs                                     |
//+------------------------------------------------------------------+
int GetTrend()
{
   // Uptrend: Fast EMA > Middle EMA > Slow EMA
   if(emaFast[0] > emaMiddle[0] && emaMiddle[0] > emaSlow[0])
      return 1;
   
   // Downtrend: Fast EMA < Middle EMA < Slow EMA
   if(emaFast[0] < emaMiddle[0] && emaMiddle[0] < emaSlow[0])
      return -1;
   
   // Sideways
   return 0;
}

//+------------------------------------------------------------------+
//| Check buy signal                                                 |
//+------------------------------------------------------------------+
bool CheckBuySignal()
{
   // Stochastic: %K ตัดขึ้นเหนือ %D จากโซน Oversold
   bool stochCross = (stochMain[1] <= stochSignal[1] && stochMain[0] > stochSignal[0]);
   bool stochOversold = (stochMain[1] < StochOversold || stochSignal[1] < StochOversold);
   
   // RSI: ตัดขึ้นเหนือจากโซน Oversold
   bool rsiSignal = (rsiBuffer[1] < RSI_Oversold && rsiBuffer[0] > RSI_Oversold);
   
   return (stochCross && stochOversold && rsiSignal);
}

//+------------------------------------------------------------------+
//| Check sell signal                                                |
//+------------------------------------------------------------------+
bool CheckSellSignal()
{
   // Stochastic: %K ตัดลงใต้ %D จากโซน Overbought
   bool stochCross = (stochMain[1] >= stochSignal[1] && stochMain[0] < stochSignal[0]);
   bool stochOverbought = (stochMain[1] > StochOverbought || stochSignal[1] > StochOverbought);
   
   // RSI: ตัดลงใต้จากโซน Overbought
   bool rsiSignal = (rsiBuffer[1] > RSI_Overbought && rsiBuffer[0] < RSI_Overbought);
   
   return (stochCross && stochOverbought && rsiSignal);
}

//+------------------------------------------------------------------+
//| Open buy position                                                |
//+------------------------------------------------------------------+
void OpenBuy()
{
   double sl = CalculateStopLoss(true);
   double tp = CalculateTakeProfit(true, sl);
   double lotSize = CalculateLotSize(sl);
   
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   
   if(trade.Buy(lotSize, _Symbol, ask, sl, tp, TradeComment))
   {
      Print("Buy order opened: Lot=", lotSize, " SL=", sl, " TP=", tp);
   }
   else
   {
      Print("Error opening buy order: ", GetLastError());
   }
}

//+------------------------------------------------------------------+
//| Open sell position                                               |
//+------------------------------------------------------------------+
void OpenSell()
{
   double sl = CalculateStopLoss(false);
   double tp = CalculateTakeProfit(false, sl);
   double lotSize = CalculateLotSize(sl);
   
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   
   if(trade.Sell(lotSize, _Symbol, bid, sl, tp, TradeComment))
   {
      Print("Sell order opened: Lot=", lotSize, " SL=", sl, " TP=", tp);
   }
   else
   {
      Print("Error opening sell order: ", GetLastError());
   }
}

//+------------------------------------------------------------------+
//| Calculate Stop Loss based on Swing High/Low and ATR             |
//+------------------------------------------------------------------+
double CalculateStopLoss(bool isBuy)
{
   double swingLevel = FindSwingLevel(!isBuy);
   double atr = atrBuffer[0];
   double atrDistance = atr * ATR_Multiplier;
   
   double price = isBuy ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double sl;
   
   if(isBuy)
   {
      sl = MathMin(swingLevel, price - atrDistance);
   }
   else
   {
      sl = MathMax(swingLevel, price + atrDistance);
   }
   
   return NormalizeDouble(sl, _Digits);
}

//+------------------------------------------------------------------+
//| Find Swing High/Low                                             |
//+------------------------------------------------------------------+
double FindSwingLevel(bool findHigh)
{
   double level = findHigh ? 0 : DBL_MAX;
   
   for(int i = 1; i <= SwingLookback; i++)
   {
      if(findHigh)
      {
         double high = iHigh(_Symbol, SL_Timeframe, i);
         if(high > level)
            level = high;
      }
      else
      {
         double low = iLow(_Symbol, SL_Timeframe, i);
         if(low < level)
            level = low;
      }
   }
   
   return level;
}

//+------------------------------------------------------------------+
//| Calculate Take Profit based on Risk:Reward ratio                |
//+------------------------------------------------------------------+
double CalculateTakeProfit(bool isBuy, double sl)
{
   double price = isBuy ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double slDistance = MathAbs(price - sl);
   double tpDistance = slDistance * TP_Ratio;
   
   double tp = isBuy ? price + tpDistance : price - tpDistance;
   
   return NormalizeDouble(tp, _Digits);
}

//+------------------------------------------------------------------+
//| Calculate lot size based on risk percentage                     |
//+------------------------------------------------------------------+
double CalculateLotSize(double sl)
{
   if(RiskPercent <= 0)
      return LotSize;
   
   double price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double slDistance = MathAbs(price - sl);
   
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   
   double accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskMoney = accountBalance * RiskPercent / 100.0;
   
   double moneyPerLot = (slDistance / tickSize) * tickValue;
   double lots = riskMoney / moneyPerLot;
   
   //--- Normalize lot size
   lots = MathFloor(lots / lotStep) * lotStep;
   
   //--- Check min/max lot
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   
   if(lots < minLot)
      lots = minLot;
   if(lots > maxLot)
      lots = maxLot;
   
   return NormalizeDouble(lots, 2);
}

//+------------------------------------------------------------------+
//| Check if within trading hours                                    |
//+------------------------------------------------------------------+
bool IsWithinTradingHours()
{
   MqlDateTime time;
   TimeToStruct(TimeCurrent(), time);
   
   if(StartHour <= EndHour)
   {
      return (time.hour >= StartHour && time.hour < EndHour);
   }
   else // Overnight trading
   {
      return (time.hour >= StartHour || time.hour < EndHour);
   }
}
//+------------------------------------------------------------------+
