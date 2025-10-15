//+------------------------------------------------------------------+
//|                                                EngulfingTrend.mq5|
//|                        by PPong + ChatGPT (MQL5)                 |
//+------------------------------------------------------------------+
#property copyright "PPong + ChatGPT"
#property version   "1.00"
#property strict

#include <Trade/Trade.mqh>
CTrade Trade;

//------------------------- Inputs -----------------------------------
input ulong   InpMagic              = 20251015;        // Magic number
input double  InpLot                = 0.01;            // Fixed lot size
input ENUM_TIMEFRAMES InpSignalTF   = PERIOD_M15;      // Timeframe for signals
input int     InpEMAFast            = 50;              // Fast EMA
input int     InpEMASlow            = 200;             // Slow EMA
input int     InpSwingBackBars      = 2;               // Swing lookback (1-2 bars)
input double  InpRR                 = 1.0;             // Risk:Reward (e.g., 1, 2, 5)
input bool    InpUseATRFilter       = true;            // Use ATR filter for body size
input int     InpATRPeriod          = 14;              // ATR Period
input double  InpMinBodyATR         = 0.2;             // Min body >= 0.2 * ATR
input int     InpSlippagePoints     = 5;               // Slippage (points)
input int     InpMaxSpreadPoints    = 200;             // Max spread (points)
input bool    InpOnlyOnePosition    = true;            // Allow only one position per symbol

//------------------------- Globals ----------------------------------
datetime      g_last_bar_time = 0;

//------------------------- Helpers ----------------------------------
bool IsNewBar(ENUM_TIMEFRAMES tf)
{
   MqlRates r[];
   if(CopyRates(_Symbol, tf, 0, 2, r) != 2) return false;
   if(g_last_bar_time != r[0].time)
   {
      g_last_bar_time = r[0].time;
      return true;
   }
   return false;
}

int CountOpenPositions(string sym, ulong magic)
{
   int cnt = 0;
   for(int i=0;i<PositionsTotal();i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) == sym &&
         PositionGetInteger(POSITION_MAGIC)  == (long)magic)
         cnt++;
   }
   return cnt;
}

double iEMA_(ENUM_TIMEFRAMES tf, int period, int shift)
{
   return iMA(_Symbol, tf, period, shift, MODE_EMA, PRICE_CLOSE);
}
/*double iEMA_(ENUM_TIMEFRAMES tf, int period)
{
   return iMA(_Symbol, tf, period, 0, MODE_EMA, PRICE_CLOSE);
}*/

bool TrendIsUp(ENUM_TIMEFRAMES tf)
{
   double f = iEMA_(tf, InpEMAFast, 0);
   double s = iEMA_(tf, InpEMASlow, 0);
   //double f = iEMA_(tf, InpEMAFast);
   //double s = iEMA_(tf, InpEMASlow);
   return (f > s);
}

bool TrendIsDown(ENUM_TIMEFRAMES tf)
{
   double f = iEMA_(tf, InpEMAFast, 0);
   double s = iEMA_(tf, InpEMASlow, 0);
   //double f = iEMA_(tf, InpEMAFast);
   //double s = iEMA_(tf, InpEMASlow);
   return (f < s);
}

/*double iATR_(ENUM_TIMEFRAMES tf, int period, int shift)
{
   return iATR(_Symbol, tf, period, shift);
}*/
/*double iATR_(ENUM_TIMEFRAMES tf, int period)
{
   return iATR(_Symbol, tf, period);
}*/
//+------------------------------------------------------------------+
//| Function to get ATR value for a specific shift                   |
//+------------------------------------------------------------------+
double GetATRValue(
    const string symbol,          // Symbol name (e.g., _Symbol or NULL)
    const ENUM_TIMEFRAMES period, // Timeframe (e.g., PERIOD_H1 or 0)
    const int atr_period,         // Averaging period (e.g., 14)
    const int shift               // Bar index (0 for current, 1 for previous, etc.)
    )
{
    // 1. Get the indicator handle
    int atr_handle = iATR(symbol, period, atr_period);

    // 2. Check for an invalid handle
    if (atr_handle == INVALID_HANDLE)
    {
        // Print error and return 0.0 or a custom error value
        Print("Error creating ATR handle for ", symbol, ": ", GetLastError());
        return 0.0; 
    }
    
    // 3. Prepare the array to receive the value(s)
    double atr_array[1]; 
    // Set the array as a time series so index 0 is the most recent data
    ArraySetAsSeries(atr_array, true); 

    // 4. Copy the data from the indicator buffer
    //    - Buffer 0: The ATR indicator's single data buffer
    //    - shift:    The starting position (the bar index you want)
    //    - 1:        The number of elements to copy
    int copied = CopyBuffer(atr_handle, 0, shift, 1, atr_array);

    // 5. Check if the copy operation was successful
    if (copied > 0)
    {
        // The requested value is the first element of the small array
        return atr_array[0];
    }
    else
    {
        // Print error if data could not be copied
        Print("Error copying ATR buffer for shift ", shift, ": ", GetLastError());
        return 0.0;
    }
}
//+------------------------------------------------------------------+

struct Candle { double open, close, high, low; };
bool GetCandle(ENUM_TIMEFRAMES tf, int shift, Candle &c)
{
   double O[],C[],H[],L[];
   if(CopyOpen (_Symbol, tf, shift, 1, O) != 1) return false;
   if(CopyClose(_Symbol, tf, shift, 1, C) != 1) return false;
   if(CopyHigh (_Symbol, tf, shift, 1, H) != 1) return false;
   if(CopyLow  (_Symbol, tf, shift, 1, L) != 1) return false;
   c.open=O[0]; c.close=C[0]; c.high=H[0]; c.low=L[0];
   return true;
}

// Engulfing (body-to-body)
bool IsBullishEngulfing(ENUM_TIMEFRAMES tf)
{
   Candle c1, c2; // c1 = previous closed bar [1], c2 = bar [2]
   if(!GetCandle(tf,1,c1) || !GetCandle(tf,2,c2)) return false;
   bool prevBear = (c2.close < c2.open);
   bool nowBull  = (c1.close > c1.open);
   if(!(prevBear && nowBull)) return false;

   double body1 = MathAbs(c1.close - c1.open);
   double body2 = MathAbs(c2.close - c2.open);

   bool engulf = (c1.open <= c2.close && c1.close >= c2.open); // body engulf
   if(!engulf) return false;

   if(InpUseATRFilter)
   {
      //double atr = iATR_(tf, InpATRPeriod, 1);
      //double atr = iATR_(tf, InpATRPeriod);
      double atr = GetATRValue(_Symbol, tf, InpATRPeriod, 1);
      if(atr <= 0) return false;
      if(body1 < InpMinBodyATR * atr) return false;
   }
   return true;
}

bool IsBearishEngulfing(ENUM_TIMEFRAMES tf)
{
   Candle c1, c2;
   if(!GetCandle(tf,1,c1) || !GetCandle(tf,2,c2)) return false;
   bool prevBull = (c2.close > c2.open);
   bool nowBear  = (c1.close < c1.open);
   if(!(prevBull && nowBear)) return false;

   double body1 = MathAbs(c1.close - c1.open);
   if(InpUseATRFilter)
   {
      //double atr = iATR_(tf, InpATRPeriod, 1);
      //double atr = iATR_(tf, InpATRPeriod);
      double atr = GetATRValue(_Symbol, tf, InpATRPeriod, 1);
      if(atr <= 0) return false;
      if(body1 < InpMinBodyATR * atr) return false;
   }

   bool engulf = (c1.open >= c2.close && c1.close <= c2.open);
   return engulf;
}

// swing from last N(=1..2) closed bars
double GetSwingLow(ENUM_TIMEFRAMES tf, int backBars)
{
   int n = MathMax(1, MathMin(2, backBars));
   double minL = DBL_MAX;
   for(int i=1; i<=n; i++)
   {
      double L[];
      if(CopyLow(_Symbol, tf, i, 1, L) != 1) return 0.0;
      if(L[0] < minL) minL = L[0];
   }
   return minL;
}

double GetSwingHigh(ENUM_TIMEFRAMES tf, int backBars)
{
   int n = MathMax(1, MathMin(2, backBars));
   double maxH = -DBL_MAX;
   for(int i=1; i<=n; i++)
   {
      double H[];
      if(CopyHigh(_Symbol, tf, i, 1, H) != 1) return 0.0;
      if(H[0] > maxH) maxH = H[0];
   }
   return maxH;
}

bool SpreadOK()
{
   double spr = (SymbolInfoInteger(_Symbol, SYMBOL_SPREAD)); // in points
   return (spr <= InpMaxSpreadPoints);
}

void NormalizeSLTP(double &sl, double &tp)
{
   int stoplevel = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL); // points
   double step   = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   if(stoplevel > 0 && step > 0)
   {
      double minDist = stoplevel * step;
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

      // push SL/TP if too close
      if(sl != 0.0)
      {
         if(sl < bid && (bid - sl) < minDist) sl = bid - minDist;
         if(sl > ask && (sl - ask) < minDist) sl = ask + minDist;
      }
      if(tp != 0.0)
      {
         if(tp > ask && (tp - ask) < minDist) tp = ask + minDist;
         if(tp < bid && (bid - tp) < minDist) tp = bid - minDist;
      }
   }
   sl = NormalizeDouble(sl, _Digits);
   tp = NormalizeDouble(tp, _Digits);
}

//------------------------- Entry Logic ------------------------------
void TryOpenBuy()
{
   if(!SpreadOK()) return;

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double sl  = GetSwingLow(InpSignalTF, InpSwingBackBars);
   if(sl <= 0 || sl >= ask) return;

   double riskDist = ask - sl;
   double tp  = ask + InpRR * riskDist;

   NormalizeSLTP(sl, tp);

   Trade.SetExpertMagicNumber(InpMagic);
   Trade.SetDeviationInPoints(InpSlippagePoints);

   Trade.Buy(InpLot, NULL, ask, sl, tp, "Bullish Engulfing");
}

void TryOpenSell()
{
   if(!SpreadOK()) return;

   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double sl  = GetSwingHigh(InpSignalTF, InpSwingBackBars);
   if(sl <= 0 || sl <= bid) return;

   double riskDist = sl - bid;
   double tp  = bid - InpRR * riskDist;

   NormalizeSLTP(sl, tp);

   Trade.SetExpertMagicNumber(InpMagic);
   Trade.SetDeviationInPoints(InpSlippagePoints);

   Trade.Sell(InpLot, NULL, bid, sl, tp, "Bearish Engulfing");
}

//------------------------- OnTick -----------------------------------
int OnInit()
{
   if(InpSwingBackBars < 1 || InpSwingBackBars > 2)
   {
      Print("InpSwingBackBars must be 1 or 2. Adjusting to 2.");
      //InpSwingBackBars = 2;
   }
   return(INIT_SUCCEEDED);
}

void OnTick()
{
   // Signal runs once per new bar on the selected timeframe
   if(!IsNewBar(InpSignalTF)) return;

   // Optional: only one position per symbol (with our magic)
   if(InpOnlyOnePosition && CountOpenPositions(_Symbol, InpMagic) > 0) return;

   // BUY setup: Uptrend + Bullish Engulfing( [1] over [2] )
   if(TrendIsUp(InpSignalTF) && IsBullishEngulfing(InpSignalTF))
      TryOpenBuy();

   // SELL setup: Downtrend + Bearish Engulfing
   if(TrendIsDown(InpSignalTF) && IsBearishEngulfing(InpSignalTF))
      TryOpenSell();
}
//+------------------------------------------------------------------+
