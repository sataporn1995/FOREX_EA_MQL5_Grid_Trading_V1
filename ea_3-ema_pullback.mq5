//+------------------------------------------------------------------+
//|                                            EMA_Pullback_EA.mq5   |
//|                                  Copyright 2025, Your Name       |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025"
#property link      "https://www.mql5.com"
#property version   "1.00"

#include <Trade\Trade.mqh>

//--- Input Parameters
input group "=== Trend Filter ==="
input ENUM_TIMEFRAMES InpTrendTF = PERIOD_H1;
input int InpEmaTrend = 200;        // EMA Period (For Trend Filter)

input group "=== EMA Settings ==="
input ENUM_TIMEFRAMES InpTradeTF = PERIOD_M5; // TF for Trade
input int InpEmaSignal = 50;          // EMA Signal (1)
input int InpEmaPullback = 90;          // EMA Pullback (2)
input int InpEmaPullbackStructure = 170;        // EMA Pullback Structure (3)

input group "=== Position Management ==="
enum ENUM_POSITION_MODE
{
   MODE_DISABLED,           // Disabled
   MODE_BREAK_EVEN,        // Break Even Only
   MODE_TRAILING_STOP,     // Trailing Stop Only
   MODE_BE_AND_TRAILING    // Break Even & Trailing Stop
};
input ENUM_POSITION_MODE InpPositionMode = MODE_BREAK_EVEN;  // Position Management Mode
input int InpBEActivationPoints = 500;    // Break Even Activation (points)
input int InpBEProfitPoints = 50;         // Break Even Profit Lock (points)
input int InpTrailActivation = 50;        // Trailing Stop Activation (points)
input int InpTrailStep = 30;              // Trailing Stop Step (points)

input group "=== Lot Calculation ==="
enum ENUM_LOT_MODE
{
   LOT_FIXED,           // Fixed Lot
   LOT_RISK_PERCENT,    // % Risk per Trade
   LOT_FIXED_MONEY      // Fixed Money Risk
};
input ENUM_LOT_MODE InpLotMode = LOT_FIXED;  // Lot Calculation Mode
input double InpFixedLot = 0.01;          // Fixed Lot Size
input double InpRiskPercent = 1.0;        // Risk Percent per Trade (%)
input double InpFixedMoney = 10.0;        // Fixed Money Risk

input group "=== Trading Time (Thai Time) ==="
input string InpStartTime = "06:00";      // Start Trading Time (HH:MM)
input string InpEndTime = "04:30";        // End Trading Time (HH:MM)

input group "=== EA Settings ==="
input int InpMagicNumber = 20251105;        // Magic Number
input string InpTradeComment = "EMA_PB";  // Trade Comment
input int InpMaxSpread = 250;             // Max Spread (points)

//--- Global Variables
CTrade trade;
int handleEMASignal_Trade, handleEMAPullback_Trade, handleEMAPullbackStructure_Trade;
int handleEMA_Trend;
double emaSignal_Trade[], emaPullback_Trade[], emaPullbackStructure_Trade[];
double emaFilter_Trend[];

// State tracking variables
enum ENUM_TRADE_STATE
{
   STATE_WAITING_PULLBACK,      // รอ Pullback
   STATE_IN_PULLBACK,           // อยู่ใน Pullback
   STATE_DEEP_PULLBACK,         // ทำ Deep Pullback แล้ว
   STATE_WAITING_SIGNAL         // รอสัญญาณเปิด Order
};

struct TradeState
{
   ENUM_TRADE_STATE buyState;
   ENUM_TRADE_STATE sellState;
   bool hasPullbackBuy;
   bool hasDeepPullbackBuy;
   bool hasPullbackSell;
   bool hasDeepPullbackSell;
   bool breakEvenDone;
};

TradeState tradeState;

//+------------------------------------------------------------------+
//| Expert initialization function                                     |
//+------------------------------------------------------------------+
int OnInit()
{
   // Initialize trade object
   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(10);
   trade.SetTypeFilling(ORDER_FILLING_FOK);
   
   // Create indicator handles
   handleEMASignal_Trade = iMA(_Symbol, InpTradeTF, InpEmaSignal, 0, MODE_EMA, PRICE_CLOSE);
   handleEMAPullback_Trade = iMA(_Symbol, InpTradeTF, InpEmaPullback, 0, MODE_EMA, PRICE_CLOSE);
   handleEMAPullbackStructure_Trade = iMA(_Symbol, InpTradeTF, InpEmaPullbackStructure, 0, MODE_EMA, PRICE_CLOSE);
   handleEMA_Trend = iMA(_Symbol, InpTrendTF, InpEmaTrend, 0, MODE_EMA, PRICE_CLOSE);
   
   if(handleEMASignal_Trade == INVALID_HANDLE || handleEMAPullback_Trade == INVALID_HANDLE || 
      handleEMAPullbackStructure_Trade == INVALID_HANDLE || handleEMA_Trend == INVALID_HANDLE)
   {
      Print("Error creating indicator handles");
      return(INIT_FAILED);
   }
   
   // Set array as series
   ArraySetAsSeries(emaSignal_Trade, true);
   ArraySetAsSeries(emaPullback_Trade, true);
   ArraySetAsSeries(emaPullbackStructure_Trade, true);
   ArraySetAsSeries(emaFilter_Trend, true);
   
   // Initialize trade state
   tradeState.buyState = STATE_WAITING_PULLBACK;
   tradeState.sellState = STATE_WAITING_PULLBACK;
   tradeState.hasPullbackBuy = false;
   tradeState.hasDeepPullbackBuy = false;
   tradeState.hasPullbackSell = false;
   tradeState.hasDeepPullbackSell = false;
   tradeState.breakEvenDone = false;
   
   Print("EA Initialized Successfully");
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   // Release indicator handles
   IndicatorRelease(handleEMASignal_Trade);
   IndicatorRelease(handleEMAPullback_Trade);
   IndicatorRelease(handleEMAPullbackStructure_Trade);
   IndicatorRelease(handleEMA_Trend);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // Check if it's a new bar on M5
   static datetime lastBarTime = 0;
   datetime currentBarTime = iTime(_Symbol, InpTradeTF, 0);
   
   bool isNewBar = (currentBarTime != lastBarTime);
   if(isNewBar)
   {
      lastBarTime = currentBarTime;
   }
   
   // Update indicators
   if(!UpdateIndicators())
      return;
   
   // Manage open positions
   ManagePositions();
   
   // Check trading time
   if(!IsTradingTime())
      return;
   
   // Check if we already have an open position
   if(PositionSelect(_Symbol))
      return;
   
   // Only check for new signals on new bar
   if(!isNewBar)
      return;
   
   // Check for trading signals
   CheckBuySignal();
   CheckSellSignal();
}

//+------------------------------------------------------------------+
//| Update indicator values                                          |
//+------------------------------------------------------------------+
bool UpdateIndicators()
{
   if(CopyBuffer(handleEMASignal_Trade, 0, 0, 3, emaSignal_Trade) <= 0) return false;
   if(CopyBuffer(handleEMAPullback_Trade, 0, 0, 3, emaPullback_Trade) <= 0) return false;
   if(CopyBuffer(handleEMAPullbackStructure_Trade, 0, 0, 3, emaPullbackStructure_Trade) <= 0) return false;
   if(CopyBuffer(handleEMA_Trend, 0, 0, 2, emaFilter_Trend) <= 0) return false;
   
   return true;
}

//+------------------------------------------------------------------+
//| Check if current time is within trading hours                    |
//+------------------------------------------------------------------+
bool IsTradingTime()
{
   MqlDateTime timeNow;
   TimeToStruct(TimeCurrent(), timeNow);
   
   // Parse start time
   string startParts[];
   int startCount = StringSplit(InpStartTime, ':', startParts);
   if(startCount != 2) return false;
   int startHour = (int)StringToInteger(startParts[0]);
   int startMin = (int)StringToInteger(startParts[1]);
   
   // Parse end time
   string endParts[];
   int endCount = StringSplit(InpEndTime, ':', endParts);
   if(endCount != 2) return false;
   int endHour = (int)StringToInteger(endParts[0]);
   int endMin = (int)StringToInteger(endParts[1]);
   
   int currentMinutes = timeNow.hour * 60 + timeNow.min;
   int startMinutes = startHour * 60 + startMin;
   int endMinutes = endHour * 60 + endMin;
   
   if(endMinutes < startMinutes) // Crosses midnight
   {
      return (currentMinutes >= startMinutes || currentMinutes <= endMinutes);
   }
   else
   {
      return (currentMinutes >= startMinutes && currentMinutes <= endMinutes);
   }
}

//+------------------------------------------------------------------+
//| Check H1 trend filter for BUY                                    |
//+------------------------------------------------------------------+
bool CheckH1TrendFilterBuy()
{
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   if(CopyRates(_Symbol, InpTrendTF, 0, 2, rates) <= 0) return false;
   
   return (rates[1].close > emaFilter_Trend[0]);
}

//+------------------------------------------------------------------+
//| Check H1 trend filter for SELL                                   |
//+------------------------------------------------------------------+
bool CheckH1TrendFilterSell()
{
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   if(CopyRates(_Symbol, InpTrendTF, 0, 2, rates) <= 0) return false;
   
   return (rates[1].close < emaFilter_Trend[0]);
}

//+------------------------------------------------------------------+
//| Check if EMAs are aligned for BUY (50 > 90 > 170)               |
//+------------------------------------------------------------------+
bool CheckEMAAlignmentBuy()
{
   return (emaSignal_Trade[0] > emaPullback_Trade[0] && emaPullback_Trade[0] > emaPullbackStructure_Trade[0]);
}

//+------------------------------------------------------------------+
//| Check if EMAs are aligned for SELL (170 > 90 > 50)              |
//+------------------------------------------------------------------+
bool CheckEMAAlignmentSell()
{
   return (emaPullbackStructure_Trade[0] > emaPullback_Trade[0] && emaPullback_Trade[0] > emaSignal_Trade[0]);
}

//+------------------------------------------------------------------+
//| Check if current spread is acceptable                            |
//+------------------------------------------------------------------+
bool CheckSpread()
{
   long spread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   
   if(spread > InpMaxSpread)
   {
      Print("Spread too high: ", spread, " points (Max: ", InpMaxSpread, " points)");
      return false;
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| Check for BUY signal                                             |
//+------------------------------------------------------------------+
void CheckBuySignal()
{
   // 1. Check H1 trend filter
   if(!CheckH1TrendFilterBuy()) 
   {
      tradeState.buyState = STATE_WAITING_PULLBACK;
      tradeState.hasPullbackBuy = false;
      tradeState.hasDeepPullbackBuy = false;
      return;
   }
   
   // 2. Check EMA alignment
   if(!CheckEMAAlignmentBuy()) 
   {
      tradeState.buyState = STATE_WAITING_PULLBACK;
      tradeState.hasPullbackBuy = false;
      tradeState.hasDeepPullbackBuy = false;
      return;
   }
   
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   if(CopyRates(_Symbol, InpTradeTF, 0, 3, rates) <= 0) return;
   
   double close1 = rates[1].close;
   double close2 = rates[2].close;
   
   // 3. Check for pullback below EMA 50
   if(close1 < emaSignal_Trade[1])
   {
      tradeState.hasPullbackBuy = true;
      tradeState.buyState = STATE_IN_PULLBACK;
   }
   
   // 4. Check for deep pullback
   if(tradeState.hasPullbackBuy && (close1 < emaPullback_Trade[1] || close1 < emaPullbackStructure_Trade[1]))
   {
      if(close1 >= emaPullbackStructure_Trade[1]) // Must not close below EMA 170
      {
         tradeState.hasDeepPullbackBuy = true;
         tradeState.buyState = STATE_DEEP_PULLBACK;
      }
   }
   
   // 5. Check for entry signal
   if(tradeState.hasDeepPullbackBuy && close1 > emaSignal_Trade[1] && close2 <= emaSignal_Trade[2])
   {
      // Check spread before opening order
      if(!CheckSpread())
      {
         Print("BUY Order cancelled due to high spread");
         // Reset state
         tradeState.buyState = STATE_WAITING_PULLBACK;
         tradeState.hasPullbackBuy = false;
         tradeState.hasDeepPullbackBuy = false;
         return;
      }
      
      double sl = emaPullbackStructure_Trade[1];
      double entryPrice = rates[1].close;
      double slDistance = entryPrice - sl;
      double tp = entryPrice + (slDistance * 2.5);
      
      double lotSize = CalculateLotSize(slDistance);
      
      if(lotSize >= SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN))
      {
         if(trade.Buy(lotSize, _Symbol, 0, sl, tp, InpTradeComment))
         {
            Print("BUY Order Opened: Lot=", lotSize, " SL=", sl, " TP=", tp);
            tradeState.breakEvenDone = false;
         }
      }
      
      // Reset state
      tradeState.buyState = STATE_WAITING_PULLBACK;
      tradeState.hasPullbackBuy = false;
      tradeState.hasDeepPullbackBuy = false;
   }
}

//+------------------------------------------------------------------+
//| Check for SELL signal                                            |
//+------------------------------------------------------------------+
void CheckSellSignal()
{
   // 1. Check H1 trend filter
   if(!CheckH1TrendFilterSell()) 
   {
      tradeState.sellState = STATE_WAITING_PULLBACK;
      tradeState.hasPullbackSell = false;
      tradeState.hasDeepPullbackSell = false;
      return;
   }
   
   // 2. Check EMA alignment
   if(!CheckEMAAlignmentSell()) 
   {
      tradeState.sellState = STATE_WAITING_PULLBACK;
      tradeState.hasPullbackSell = false;
      tradeState.hasDeepPullbackSell = false;
      return;
   }
   
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   if(CopyRates(_Symbol, InpTradeTF, 0, 3, rates) <= 0) return;
   
   double close1 = rates[1].close;
   double close2 = rates[2].close;
   
   // 3. Check for pullback above EMA 50
   if(close1 > emaSignal_Trade[1])
   {
      tradeState.hasPullbackSell = true;
      tradeState.sellState = STATE_IN_PULLBACK;
   }
   
   // 4. Check for deep pullback
   if(tradeState.hasPullbackSell && (close1 > emaPullback_Trade[1] || close1 > emaPullbackStructure_Trade[1]))
   {
      if(close1 <= emaPullbackStructure_Trade[1]) // Must not close above EMA 170
      {
         tradeState.hasDeepPullbackSell = true;
         tradeState.sellState = STATE_DEEP_PULLBACK;
      }
   }
   
   // 5. Check for entry signal
   if(tradeState.hasDeepPullbackSell && close1 < emaSignal_Trade[1] && close2 >= emaSignal_Trade[2])
   {
      // Check spread before opening order
      if(!CheckSpread())
      {
         Print("SELL Order cancelled due to high spread");
         // Reset state
         tradeState.sellState = STATE_WAITING_PULLBACK;
         tradeState.hasPullbackSell = false;
         tradeState.hasDeepPullbackSell = false;
         return;
      }
      
      double sl = emaPullbackStructure_Trade[1];
      double entryPrice = rates[1].close;
      double slDistance = sl - entryPrice;
      double tp = entryPrice - (slDistance * 2.5);
      
      double lotSize = CalculateLotSize(slDistance);
      
      if(lotSize >= SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN))
      {
         if(trade.Sell(lotSize, _Symbol, 0, sl, tp, InpTradeComment))
         {
            Print("SELL Order Opened: Lot=", lotSize, " SL=", sl, " TP=", tp);
            tradeState.breakEvenDone = false;
         }
      }
      
      // Reset state
      tradeState.sellState = STATE_WAITING_PULLBACK;
      tradeState.hasPullbackSell = false;
      tradeState.hasDeepPullbackSell = false;
   }
}

//+------------------------------------------------------------------+
//| Calculate lot size based on risk                                 |
//+------------------------------------------------------------------+
double CalculateLotSize(double slDistance)
{
   double lotSize = InpFixedLot;
   
   if(InpLotMode == LOT_RISK_PERCENT)
   {
      double equity = AccountInfoDouble(ACCOUNT_EQUITY);
      double riskMoney = equity * InpRiskPercent / 100.0;
      
      double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
      double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
      double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
      
      double slDistanceInTicks = slDistance / tickSize;
      lotSize = riskMoney / (slDistanceInTicks * tickValue);
   }
   else if(InpLotMode == LOT_FIXED_MONEY)
   {
      double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
      double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
      
      double slDistanceInTicks = slDistance / tickSize;
      lotSize = InpFixedMoney / (slDistanceInTicks * tickValue);
   }
   
   // Round to allowed lot step
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   lotSize = MathFloor(lotSize / lotStep) * lotStep;
   
   // Check min/max lot
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   
   if(lotSize < minLot) lotSize = 0;
   if(lotSize > maxLot) lotSize = maxLot;
   
   return lotSize;
}

//+------------------------------------------------------------------+
//| Manage open positions                                            |
//+------------------------------------------------------------------+
void ManagePositions()
{
   if(InpPositionMode == MODE_DISABLED)
      return;
   
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket <= 0) continue;
      
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;
      
      double positionOpenPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double positionSL = PositionGetDouble(POSITION_SL);
      double positionTP = PositionGetDouble(POSITION_TP);
      long positionType = PositionGetInteger(POSITION_TYPE);
      
      double currentPrice = (positionType == POSITION_TYPE_BUY) ? 
                           SymbolInfoDouble(_Symbol, SYMBOL_BID) : 
                           SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      
      double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
      double newSL = positionSL;
      bool modifySL = false;
      
      if(positionType == POSITION_TYPE_BUY)
      {
         double profit = currentPrice - positionOpenPrice;
         
         // Break Even
         if((InpPositionMode == MODE_BREAK_EVEN || InpPositionMode == MODE_BE_AND_TRAILING) && 
            !tradeState.breakEvenDone)
         {
            if(profit >= InpBEActivationPoints * point)
            {
               newSL = positionOpenPrice + InpBEProfitPoints * point;
               if(newSL > positionSL)
               {
                  modifySL = true;
                  tradeState.breakEvenDone = true;
                  Print("Break Even activated for BUY");
               }
            }
         }
         
         // Trailing Stop
         if((InpPositionMode == MODE_TRAILING_STOP || 
            (InpPositionMode == MODE_BE_AND_TRAILING && tradeState.breakEvenDone)))
         {
            if(profit >= InpTrailActivation * point)
            {
               double trailSL = currentPrice - InpTrailStep * point;
               if(trailSL > positionSL && trailSL > newSL)
               {
                  newSL = trailSL;
                  modifySL = true;
               }
            }
         }
      }
      else // SELL
      {
         double profit = positionOpenPrice - currentPrice;
         
         // Break Even
         if((InpPositionMode == MODE_BREAK_EVEN || InpPositionMode == MODE_BE_AND_TRAILING) && 
            !tradeState.breakEvenDone)
         {
            if(profit >= InpBEActivationPoints * point)
            {
               newSL = positionOpenPrice - InpBEProfitPoints * point;
               if(newSL < positionSL || positionSL == 0)
               {
                  modifySL = true;
                  tradeState.breakEvenDone = true;
                  Print("Break Even activated for SELL");
               }
            }
         }
         
         // Trailing Stop
         if((InpPositionMode == MODE_TRAILING_STOP || 
            (InpPositionMode == MODE_BE_AND_TRAILING && tradeState.breakEvenDone)))
         {
            if(profit >= InpTrailActivation * point)
            {
               double trailSL = currentPrice + InpTrailStep * point;
               if((trailSL < positionSL || positionSL == 0) && trailSL < newSL)
               {
                  newSL = trailSL;
                  modifySL = true;
               }
            }
         }
      }
      
      if(modifySL)
      {
         trade.PositionModify(ticket, newSL, positionTP);
      }
   }
}
//+------------------------------------------------------------------+
