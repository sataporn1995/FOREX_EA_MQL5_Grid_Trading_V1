//+------------------------------------------------------------------+
//|                                    EMA_Pullback_Stoch_EA.mq5      |
//|                                                                    |
//|                        EMA Pullback Strategy with Stochastic      |
//+------------------------------------------------------------------+
#property copyright "Pong Forex Trading System"
#property version   "1.00"
#property strict

//--- Input Parameters
//=== Trading Strategy Settings ===
input group "=== Stochastic Settings ==="
input int InpStochK = 14;                    // Stochastic %K Period
input int InpStochD = 3;                     // Stochastic %D Period
input int InpStochSlowing = 3;               // Stochastic Slowing
input double InpStochOversold = 30.0;        // Oversold Level
input double InpStochOverbought = 70.0;      // Overbought Level

input group "=== EMA Settings ==="
input int InpEMASignal = 50;                // EMA Signal
input int InpEMAPB = 100;                   // EMA Pullback
input int InpEMAPB_Structure = 200;         // EMA Pullback Structure

input group "=== TP/SL Settings ==="
input double InpTPMultiplier = 2.5;          // TP Multiplier (x SL Distance)

input group "=== Risk Management Mode ==="
enum ENUM_RISK_MODE
{
   RISK_DISABLED = 0,          // Disabled
   RISK_BREAK_EVEN = 1,        // Break Even Only
   RISK_TRAILING_STOP = 2,     // Trailing Stop Only
   RISK_BE_AND_TS = 3          // Break Even & Trailing Stop
};
input ENUM_RISK_MODE InpRiskMode = RISK_BREAK_EVEN;  // Risk Management Mode

input group "=== Break Even Settings ==="
input int InpBEActivationPoints = 500;       // BE Activation (Points)
input int InpBELockPoints = 50;              // BE Lock Profit (Points)

input group "=== Trailing Stop Settings ==="
input int InpTSTriggerPoints = 50;           // TS Trigger (Points)
input int InpTSDistancePoints = 30;          // TS Distance (Points)

input group "=== Lot Calculation ==="
enum ENUM_LOT_MODE
{
   LOT_FIXED = 0,              // Fixed Lot
   LOT_RISK_PERCENT = 1,       // % Risk per Trade
   LOT_RISK_MONEY = 2          // Fixed Money Risk
};
input ENUM_LOT_MODE InpLotMode = LOT_FIXED;  // Lot Calculation Mode
input double InpFixedLot = 0.01;             // Fixed Lot Size
input double InpRiskPercent = 1.0;           // Risk Percent (%)
input double InpRiskMoney = 10.0;            // Risk Money (USD)

input group "=== MM ===";
input bool   InpUseATR = true;           // Use ATR for SL
input int    InpARTPeriod = 14;              // ATR Period
input ENUM_TIMEFRAMES InpATRTF = PERIOD_M5; // TF for ATR
input double InpATRMultiplier = 2.0;          // ATR Multiplier
enum ENUM_SL_TYPES {
   SL_EMA_3, // EMA (3)
   SL_POINTS // SL Points
};
input ENUM_SL_TYPES InpSLType = SL_EMA_3; // SL Type
input int InpSLPoints = 5000; // SL Points

input group "=== Trading Time (Thai Time) ==="
input string InpStartTime = "06:00";         // Trading Start Time (HH:MM)
input string InpEndTime = "04:30";           // Trading End Time (HH:MM)
input int InpThaiTimeOffset = 0;             // Thai Time Offset from Broker (Hours)

input group "=== Spread Filter ==="
input int InpMaxSpreadPoints = 150;          // Max Spread (Points)

input group "=== General Settings ==="
input int InpMagicNumber = 123456;           // Magic Number
input string InpTradeComment = "EMA_Pullback"; // Trade Comment

//--- Global Variables
int handleStoch;
int handleEMASignal;
int handleEMAPB;
int handleEMAPB_Structure;
int handleATR;

double bufferStochMain[];
double bufferStochSignal[];
double bufferEMASignal[];
double bufferEMAPB[];
double bufferEMAPB_Structure[];
double bufferATRValue[]; 

bool previousStochBelowOS = false;   // Previous Stoch state for BUY
bool previousStochAboveOB = false;   // Previous Stoch state for SELL
bool pullbackBelowEMASignal = false;     // Pullback state for BUY
bool pullbackAboveEMASignal = false;     // Pullback state for SELL

// Break Even tracking
bool beActivated[];
double beLevel[];
int beTicketMap[];
int beArraySize = 0;

//+------------------------------------------------------------------+
//| Expert initialization function                                     |
//+------------------------------------------------------------------+
int OnInit()
{
   //--- Create indicators
   handleStoch = iStochastic(_Symbol, PERIOD_M5, InpStochK, InpStochD, InpStochSlowing, MODE_SMA, STO_LOWHIGH);
   handleEMASignal = iMA(_Symbol, PERIOD_M5, InpEMASignal, 0, MODE_EMA, PRICE_CLOSE);
   handleEMAPB = iMA(_Symbol, PERIOD_M5, InpEMAPB, 0, MODE_EMA, PRICE_CLOSE);
   handleEMAPB_Structure = iMA(_Symbol, PERIOD_M5, InpEMAPB_Structure, 0, MODE_EMA, PRICE_CLOSE);
   
   if(handleStoch == INVALID_HANDLE || handleEMASignal == INVALID_HANDLE || 
      handleEMAPB == INVALID_HANDLE || handleEMAPB_Structure == INVALID_HANDLE)
   {
      Print("Error creating indicators");
      return(INIT_FAILED);
   }
   
   //--- Set array as series
   ArraySetAsSeries(bufferStochMain, true);
   ArraySetAsSeries(bufferStochSignal, true);
   ArraySetAsSeries(bufferEMASignal, true);
   ArraySetAsSeries(bufferEMAPB, true);
   ArraySetAsSeries(bufferEMAPB_Structure, true);
   
   Print("EA Initialized Successfully");
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                   |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   //--- Release indicator handles
   IndicatorRelease(handleStoch);
   IndicatorRelease(handleEMASignal);
   IndicatorRelease(handleEMAPB);
   IndicatorRelease(handleEMAPB_Structure);
   
   ArrayFree(beActivated);
   ArrayFree(beLevel);
   ArrayFree(beTicketMap);
}

//+------------------------------------------------------------------+
//| Expert tick function                                               |
//+------------------------------------------------------------------+
void OnTick()
{
   //--- Check if new bar
   static datetime lastBarTime = 0;
   datetime currentBarTime = iTime(_Symbol, PERIOD_M5, 0);
   
   if(currentBarTime == lastBarTime)
   {
      // Not a new bar, only manage existing positions
      ManagePositions();
      return;
   }
   
   lastBarTime = currentBarTime;
   
   //--- Update indicator buffers
   if(!UpdateIndicators())
      return;
   
   //--- Check trading time
   if(!IsTradingTime())
   {
      ManagePositions();
      return;
   }
   
   //--- Check spread filter
   if(!CheckSpread())
   {
      ManagePositions();
      return;
   }
   
   //--- Check if we already have a position
   if(PositionSelect(_Symbol))
   {
      ManagePositions();
      return;
   }
   
   //--- Check trading signals
   CheckBuySignal();
   CheckSellSignal();
   
   //--- Manage existing positions
   ManagePositions();
}

//+------------------------------------------------------------------+
//| Update indicator buffers                                           |
//+------------------------------------------------------------------+
bool UpdateIndicators()
{
   if(CopyBuffer(handleStoch, 0, 0, 5, bufferStochMain) <= 0) return false;
   if(CopyBuffer(handleStoch, 1, 0, 5, bufferStochSignal) <= 0) return false;
   if(CopyBuffer(handleEMASignal, 0, 0, 5, bufferEMASignal) <= 0) return false;
   if(CopyBuffer(handleEMAPB, 0, 0, 5, bufferEMAPB) <= 0) return false;
   if(CopyBuffer(handleEMAPB_Structure, 0, 0, 5, bufferEMAPB_Structure) <= 0) return false;
   if(CopyBuffer(handleATR, 0, 0, 2, bufferATRValue) < 2) return false;
   
   return true;
}

//+------------------------------------------------------------------+
//| Check if current time is within trading hours                     |
//+------------------------------------------------------------------+
bool IsTradingTime()
{
   MqlDateTime currentTime;
   TimeToStruct(TimeCurrent() + InpThaiTimeOffset * 3600, currentTime);
   
   int currentMinutes = currentTime.hour * 60 + currentTime.min;
   
   //--- Parse start time
   string startParts[];
   StringSplit(InpStartTime, ':', startParts);
   int startMinutes = (int)StringToInteger(startParts[0]) * 60 + (int)StringToInteger(startParts[1]);
   
   //--- Parse end time
   string endParts[];
   StringSplit(InpEndTime, ':', endParts);
   int endMinutes = (int)StringToInteger(endParts[0]) * 60 + (int)StringToInteger(endParts[1]);
   
   //--- Check if end time is next day
   if(endMinutes < startMinutes)
   {
      // Trading period spans midnight
      return (currentMinutes >= startMinutes || currentMinutes <= endMinutes);
   }
   else
   {
      // Trading period within same day
      return (currentMinutes >= startMinutes && currentMinutes <= endMinutes);
   }
}

//+------------------------------------------------------------------+
//| Check spread filter                                                |
//+------------------------------------------------------------------+
bool CheckSpread()
{
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double spread = ask - bid;
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   int spreadPoints = (int)(spread / point);
   
   return (spreadPoints <= InpMaxSpreadPoints);
}

//+------------------------------------------------------------------+
//| Check EMA alignment for BUY (50 > 100 > 200)                      |
//+------------------------------------------------------------------+
bool IsEMAAlignedForBuy()
{
   return (bufferEMASignal[1] > bufferEMAPB[1] && bufferEMAPB[1] > bufferEMAPB_Structure[1]);
}

//+------------------------------------------------------------------+
//| Check EMA alignment for SELL (200 > 100 > 50)                     |
//+------------------------------------------------------------------+
bool IsEMAAlignedForSell()
{
   return (bufferEMAPB_Structure[1] > bufferEMAPB[1] && bufferEMAPB[1] > bufferEMASignal[1]);
}

//+------------------------------------------------------------------+
//| Check BUY signal                                                   |
//+------------------------------------------------------------------+
void CheckBuySignal()
{
   double close1 = iClose(_Symbol, PERIOD_M5, 1);
   double close2 = iClose(_Symbol, PERIOD_M5, 2);
   
   //--- 1. Check Stochastic crossing above Oversold
   if(bufferStochMain[2] <= InpStochOversold && bufferStochMain[1] > InpStochOversold)
   {
      previousStochBelowOS = true;
      pullbackBelowEMASignal = false; // Reset pullback state
   }
   
   if(!previousStochBelowOS)
      return;
   
   //--- 2. Check EMA alignment (50 > 100 > 200)
   if(!IsEMAAlignedForBuy())
   {
      previousStochBelowOS = false;
      return;
   }
   
   //--- 3. Check pullback below EMA50
   if(close2 < bufferEMASignal[2])
   {
      pullbackBelowEMASignal = true;
   }
   
   if(!pullbackBelowEMASignal)
      return;
   
   //--- 4. Check deep pullback (below EMA50 or EMA100, but not close below EMA100)
   bool deepPullbackValid = false;
   for(int i = 2; i < 10; i++) // Check last 10 bars
   {
      double closeBar = iClose(_Symbol, PERIOD_M5, i);
      if(closeBar < bufferEMASignal[i] || closeBar < bufferEMAPB[i])
      {
         if(closeBar >= bufferEMAPB[i]) // Must not close below EMA100
         {
            deepPullbackValid = true;
            break;
         }
      }
   }
   
   if(!deepPullbackValid)
      return;
   
   //--- 5. Check if price closes above EMA50 or EMA100
   if(close1 > bufferEMASignal[1] || close1 > bufferEMAPB[1])
   {
      // Open BUY order
      OpenBuyOrder();
      
      // Reset states
      previousStochBelowOS = false;
      pullbackBelowEMASignal = false;
   }
}

//+------------------------------------------------------------------+
//| Check SELL signal                                                  |
//+------------------------------------------------------------------+
void CheckSellSignal()
{
   double close1 = iClose(_Symbol, PERIOD_M5, 1);
   double close2 = iClose(_Symbol, PERIOD_M5, 2);
   
   //--- 1. Check Stochastic crossing below Overbought
   if(bufferStochMain[2] >= InpStochOverbought && bufferStochMain[1] < InpStochOverbought)
   {
      previousStochAboveOB = true;
      pullbackAboveEMASignal = false; // Reset pullback state
   }
   
   if(!previousStochAboveOB)
      return;
   
   //--- 2. Check EMA alignment (200 > 100 > 50)
   if(!IsEMAAlignedForSell())
   {
      previousStochAboveOB = false;
      return;
   }
   
   //--- 3. Check pullback above EMA50
   if(close2 > bufferEMASignal[2])
   {
      pullbackAboveEMASignal = true;
   }
   
   if(!pullbackAboveEMASignal)
      return;
   
   //--- 4. Check deep pullback (above EMA50 or EMA100, but not close above EMA100)
   bool deepPullbackValid = false;
   for(int i = 2; i < 10; i++) // Check last 10 bars
   {
      double closeBar = iClose(_Symbol, PERIOD_M5, i);
      if(closeBar > bufferEMASignal[i] || closeBar > bufferEMAPB[i])
      {
         if(closeBar <= bufferEMAPB[i]) // Must not close above EMA100
         {
            deepPullbackValid = true;
            break;
         }
      }
   }
   
   if(!deepPullbackValid)
      return;
   
   //--- 5. Check if price closes below EMA50 or EMA100
   if(close1 < bufferEMASignal[1] || close1 < bufferEMAPB[1])
   {
      // Open SELL order
      OpenSellOrder();
      
      // Reset states
      previousStochAboveOB = false;
      pullbackAboveEMASignal = false;
   }
}

//+------------------------------------------------------------------+
//| Open BUY order                                                     |
//+------------------------------------------------------------------+
void OpenBuyOrder()
{
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double sl = bufferEMAPB[1]; // SL at EMA100 of entry bar
   double slDistance = ask - sl;
   double tp = ask + (slDistance * InpTPMultiplier);
   
   //--- Calculate lot size
   double lotSize = CalculateLotSize(slDistance);
   
   if(lotSize < SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN))
   {
      Print("Lot size too small: ", lotSize);
      return;
   }
   
   //--- Normalize values
   sl = NormalizeDouble(sl, _Digits);
   tp = NormalizeDouble(tp, _Digits);
   lotSize = NormalizeDouble(lotSize, 2);
   
   //--- Send order
   MqlTradeRequest request = {};
   MqlTradeResult result = {};
   
   request.action = TRADE_ACTION_DEAL;
   request.symbol = _Symbol;
   request.volume = lotSize;
   request.type = ORDER_TYPE_BUY;
   request.price = ask;
   request.sl = sl;
   request.tp = tp;
   request.deviation = 10;
   request.magic = InpMagicNumber;
   request.comment = InpTradeComment;
   
   if(OrderSend(request, result))
   {
      if(result.retcode == TRADE_RETCODE_DONE)
      {
         Print("BUY order opened successfully. Ticket: ", result.order, " Price: ", ask, " SL: ", sl, " TP: ", tp);
         
         // Initialize Break Even tracking if needed
         if(InpRiskMode == RISK_BREAK_EVEN || InpRiskMode == RISK_BE_AND_TS)
         {
            AddBETracking(result.order, false, 0.0);
         }
      }
      else
      {
         Print("BUY order failed. Error: ", result.retcode, " - ", result.comment);
      }
   }
   else
   {
      Print("OrderSend failed. Error: ", GetLastError());
   }
}

//+------------------------------------------------------------------+
//| Open SELL order                                                    |
//+------------------------------------------------------------------+
void OpenSellOrder()
{
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double sl = bufferEMAPB[1]; // SL at EMA100 of entry bar
   double slDistance = sl - bid;
   double tp = bid - (slDistance * InpTPMultiplier);
   
   //--- Calculate lot size
   double lotSize = CalculateLotSize(slDistance);
   
   if(lotSize < SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN))
   {
      Print("Lot size too small: ", lotSize);
      return;
   }
   
   //--- Normalize values
   sl = NormalizeDouble(sl, _Digits);
   tp = NormalizeDouble(tp, _Digits);
   lotSize = NormalizeDouble(lotSize, 2);
   
   //--- Send order
   MqlTradeRequest request = {};
   MqlTradeResult result = {};
   
   request.action = TRADE_ACTION_DEAL;
   request.symbol = _Symbol;
   request.volume = lotSize;
   request.type = ORDER_TYPE_SELL;
   request.price = bid;
   request.sl = sl;
   request.tp = tp;
   request.deviation = 10;
   request.magic = InpMagicNumber;
   request.comment = InpTradeComment;
   
   if(OrderSend(request, result))
   {
      if(result.retcode == TRADE_RETCODE_DONE)
      {
         Print("SELL order opened successfully. Ticket: ", result.order, " Price: ", bid, " SL: ", sl, " TP: ", tp);
         
         // Initialize Break Even tracking if needed
         if(InpRiskMode == RISK_BREAK_EVEN || InpRiskMode == RISK_BE_AND_TS)
         {
            AddBETracking(result.order, false, 0.0);
         }
      }
      else
      {
         Print("SELL order failed. Error: ", result.retcode, " - ", result.comment);
      }
   }
   else
   {
      Print("OrderSend failed. Error: ", GetLastError());
   }
}

//+------------------------------------------------------------------+
//| Calculate lot size based on risk mode                             |
//+------------------------------------------------------------------+
double CalculateLotSize(double slDistance)
{
   double lotSize = InpFixedLot;
   
   if(InpLotMode == LOT_FIXED)
   {
      return InpFixedLot;
   }
   
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   
   double slInTicks = slDistance / tickSize;
   double riskMoney = 0.0;
   
   if(InpLotMode == LOT_RISK_PERCENT)
   {
      double equity = AccountInfoDouble(ACCOUNT_EQUITY);
      riskMoney = equity * InpRiskPercent / 100.0;
   }
   else if(InpLotMode == LOT_RISK_MONEY)
   {
      riskMoney = InpRiskMoney;
   }
   
   if(riskMoney > 0 && slInTicks > 0 && tickValue > 0)
   {
      lotSize = riskMoney / (slInTicks * tickValue);
   }
   
   //--- Normalize lot size
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   
   lotSize = MathFloor(lotSize / lotStep) * lotStep;
   lotSize = MathMax(minLot, MathMin(maxLot, lotSize));
   
   return lotSize;
}

//+------------------------------------------------------------------+
//| Manage existing positions                                          |
//+------------------------------------------------------------------+
void ManagePositions()
{
   if(InpRiskMode == RISK_DISABLED)
      return;
   
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket <= 0) continue;
      
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;
      
      long posType = PositionGetInteger(POSITION_TYPE);
      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double currentSL = PositionGetDouble(POSITION_SL);
      double currentTP = PositionGetDouble(POSITION_TP);
      
      double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      
      bool needUpdate = false;
      double newSL = currentSL;
      
      if(posType == POSITION_TYPE_BUY)
      {
         if(InpRiskMode == RISK_BREAK_EVEN)
         {
            needUpdate = ManageBreakEvenBuy(ticket, openPrice, currentSL, bid, point, newSL);
         }
         else if(InpRiskMode == RISK_TRAILING_STOP)
         {
            needUpdate = ManageTrailingStopBuy(ticket, openPrice, currentSL, bid, point, newSL);
         }
         else if(InpRiskMode == RISK_BE_AND_TS)
         {
            needUpdate = ManageBEAndTSBuy(ticket, openPrice, currentSL, bid, point, newSL);
         }
      }
      else if(posType == POSITION_TYPE_SELL)
      {
         if(InpRiskMode == RISK_BREAK_EVEN)
         {
            needUpdate = ManageBreakEvenSell(ticket, openPrice, currentSL, ask, point, newSL);
         }
         else if(InpRiskMode == RISK_TRAILING_STOP)
         {
            needUpdate = ManageTrailingStopSell(ticket, openPrice, currentSL, ask, point, newSL);
         }
         else if(InpRiskMode == RISK_BE_AND_TS)
         {
            needUpdate = ManageBEAndTSSell(ticket, openPrice, currentSL, ask, point, newSL);
         }
      }
      
      if(needUpdate)
      {
         ModifyPosition(ticket, newSL, currentTP);
      }
   }
}

//+------------------------------------------------------------------+
//| Manage Break Even for BUY                                          |
//+------------------------------------------------------------------+
bool ManageBreakEvenBuy(ulong ticket, double openPrice, double currentSL, double currentPrice, double point, double &newSL)
{
   int beIndex = FindBEIndex(ticket);
   if(beIndex < 0) return false;
   
   if(beActivated[beIndex]) return false; // Already activated
   
   double profitPoints = (currentPrice - openPrice) / point;
   
   if(profitPoints >= InpBEActivationPoints)
   {
      newSL = openPrice + (InpBELockPoints * point);
      newSL = NormalizeDouble(newSL, _Digits);
      
      if(newSL > currentSL)
      {
         beActivated[beIndex] = true;
         beLevel[beIndex] = newSL;
         return true;
      }
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| Manage Break Even for SELL                                         |
//+------------------------------------------------------------------+
bool ManageBreakEvenSell(ulong ticket, double openPrice, double currentSL, double currentPrice, double point, double &newSL)
{
   int beIndex = FindBEIndex(ticket);
   if(beIndex < 0) return false;
   
   if(beActivated[beIndex]) return false; // Already activated
   
   double profitPoints = (openPrice - currentPrice) / point;
   
   if(profitPoints >= InpBEActivationPoints)
   {
      newSL = openPrice - (InpBELockPoints * point);
      newSL = NormalizeDouble(newSL, _Digits);
      
      if(newSL < currentSL || currentSL == 0)
      {
         beActivated[beIndex] = true;
         beLevel[beIndex] = newSL;
         return true;
      }
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| Manage Trailing Stop for BUY                                       |
//+------------------------------------------------------------------+
bool ManageTrailingStopBuy(ulong ticket, double openPrice, double currentSL, double currentPrice, double point, double &newSL)
{
   double profitPoints = (currentPrice - openPrice) / point;
   
   if(profitPoints >= InpTSTriggerPoints)
   {
      newSL = currentPrice - (InpTSDistancePoints * point);
      newSL = NormalizeDouble(newSL, _Digits);
      
      if(newSL > currentSL)
      {
         return true;
      }
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| Manage Trailing Stop for SELL                                      |
//+------------------------------------------------------------------+
bool ManageTrailingStopSell(ulong ticket, double openPrice, double currentSL, double currentPrice, double point, double &newSL)
{
   double profitPoints = (openPrice - currentPrice) / point;
   
   if(profitPoints >= InpTSTriggerPoints)
   {
      newSL = currentPrice + (InpTSDistancePoints * point);
      newSL = NormalizeDouble(newSL, _Digits);
      
      if(newSL < currentSL || currentSL == 0)
      {
         return true;
      }
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| Manage Break Even & Trailing Stop for BUY                          |
//+------------------------------------------------------------------+
bool ManageBEAndTSBuy(ulong ticket, double openPrice, double currentSL, double currentPrice, double point, double &newSL)
{
   int beIndex = FindBEIndex(ticket);
   if(beIndex < 0) return false;
   
   double profitPoints = (currentPrice - openPrice) / point;
   
   // First, check Break Even
   if(!beActivated[beIndex])
   {
      if(profitPoints >= InpBEActivationPoints)
      {
         newSL = openPrice + (InpBELockPoints * point);
         newSL = NormalizeDouble(newSL, _Digits);
         
         if(newSL > currentSL)
         {
            beActivated[beIndex] = true;
            beLevel[beIndex] = newSL;
            return true;
         }
      }
      return false;
   }
   
   // After Break Even is activated, do Trailing Stop
   if(profitPoints >= InpTSTriggerPoints)
   {
      newSL = currentPrice - (InpTSDistancePoints * point);
      newSL = NormalizeDouble(newSL, _Digits);
      
      if(newSL > currentSL)
      {
         beLevel[beIndex] = newSL;
         return true;
      }
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| Manage Break Even & Trailing Stop for SELL                         |
//+------------------------------------------------------------------+
bool ManageBEAndTSSell(ulong ticket, double openPrice, double currentSL, double currentPrice, double point, double &newSL)
{
   int beIndex = FindBEIndex(ticket);
   if(beIndex < 0) return false;
   
   double profitPoints = (openPrice - currentPrice) / point;
   
   // First, check Break Even
   if(!beActivated[beIndex])
   {
      if(profitPoints >= InpBEActivationPoints)
      {
         newSL = openPrice - (InpBELockPoints * point);
         newSL = NormalizeDouble(newSL, _Digits);
         
         if(newSL < currentSL || currentSL == 0)
         {
            beActivated[beIndex] = true;
            beLevel[beIndex] = newSL;
            return true;
         }
      }
      return false;
   }
   
   // After Break Even is activated, do Trailing Stop
   if(profitPoints >= InpTSTriggerPoints)
   {
      newSL = currentPrice + (InpTSDistancePoints * point);
      newSL = NormalizeDouble(newSL, _Digits);
      
      if(newSL < currentSL || currentSL == 0)
      {
         beLevel[beIndex] = newSL;
         return true;
      }
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| Modify position                                                    |
//+------------------------------------------------------------------+
void ModifyPosition(ulong ticket, double sl, double tp)
{
   MqlTradeRequest request = {};
   MqlTradeResult result = {};
   
   request.action = TRADE_ACTION_SLTP;
   request.position = ticket;
   request.sl = NormalizeDouble(sl, _Digits);
   request.tp = NormalizeDouble(tp, _Digits);
   
   if(OrderSend(request, result))
   {
      if(result.retcode == TRADE_RETCODE_DONE)
      {
         Print("Position ", ticket, " modified. New SL: ", sl);
      }
   }
}

//+------------------------------------------------------------------+
//| Add Break Even tracking for position                               |
//+------------------------------------------------------------------+
void AddBETracking(ulong ticket, bool activated, double level)
{
   beArraySize++;
   ArrayResize(beActivated, beArraySize);
   ArrayResize(beLevel, beArraySize);
   ArrayResize(beTicketMap, beArraySize);
   
   beTicketMap[beArraySize - 1] = (int)ticket;
   beActivated[beArraySize - 1] = activated;
   beLevel[beArraySize - 1] = level;
}

//+------------------------------------------------------------------+
//| Find Break Even index by ticket                                    |
//+------------------------------------------------------------------+
int FindBEIndex(ulong ticket)
{
   for(int i = 0; i < beArraySize; i++)
   {
      if(beTicketMap[i] == (int)ticket)
         return i;
   }
   return -1;
}

//+------------------------------------------------------------------+
