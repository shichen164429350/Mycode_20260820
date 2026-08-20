//+------------------------------------------------------------------+
//|                          XAU_RSI_VP_Integrated_Scalper_EA.mq5    |
//|      RSI divergence + volume profile scalping Expert Advisor      |
//+------------------------------------------------------------------+
#property strict
#property version   "1.10"
#property description "EA converted from the RSI divergence alert and volume profile indicator logic."

#include <Trade\Trade.mqh>

enum ENUM_LOT_MODE
  {
   LOT_FIXED = 0,
   LOT_RISK_PERCENT = 1
  };

enum ENUM_VOLUME_PROFILE_FILTER
  {
   VP_FILTER_OFF = 0,
   VP_FILTER_DISTANCE_ONLY = 1,
   VP_FILTER_TRADE_TOWARD_POC = 2,
   VP_FILTER_TRADE_WITH_POC_SIDE = 3
  };

enum ENUM_ENTRY_MODE
  {
   ENTRY_STRICT_ORIGINAL = 0,
   ENTRY_DIVERGENCE = 1,
   ENTRY_RSI_REVERSAL = 2
  };

input group "General"
input string  InpSymbol                 = "";       // Empty = chart symbol
input long    InpMagicNumber            = 20260820; // EA magic number
input bool    InpEnableTrading          = true;     // Enable order execution
input bool    InpShowChartStatus        = true;     // Show EA status on chart
input bool    InpDrawSignalObjects      = true;     // Draw signal arrows and key levels
input bool    InpUsePopupAlert          = false;    // Popup alert on signal/trade
input bool    InpUsePushNotification    = false;    // Mobile push notification

input group "Signal - RSI Divergence"
input ENUM_ENTRY_MODE InpEntryMode       = ENTRY_DIVERGENCE; // Strict, divergence, or active RSI reversal
input int     InpRsiPeriod              = 13;       // RSI period
input double  InpRsiBuyLevel            = 33.0;     // RSI buy threshold
input double  InpRsiSellLevel           = 67.0;     // RSI sell threshold
input int     InpPivotDepth             = 3;        // Pivot confirmation depth
input int     InpDivergenceWindow       = 12;       // Max bars between divergence pivots
input int     InpMinPriceGapPoints      = 20;       // Min price gap between pivots
input double  InpMinRsiGap              = 1.0;      // Min RSI gap between pivots
input int     InpHistoryBars            = 600;      // History bars to sample
input int     InpVolumePeriod           = 20;       // Average volume period
input double  InpVolumeSpikeMultiplier  = 1.5;      // Volume spike multiplier
input double  InpVolumeShrinkRatio      = 0.8;      // Pullback shrink-volume ratio
input int     InpClusterLookbackBars    = 240;      // Key-level cluster lookback
input int     InpClusterDistancePoints  = 80;       // Key-level cluster distance
input int     InpTouchBufferPoints      = 40;       // Support/resistance touch buffer
input int     InpBreakBufferPoints      = 10;       // Breakout buffer
input bool    InpUseM5Filter            = true;     // Use M5 RSI direction filter
input int     InpM5RsiBiasLevel         = 50;       // M5 RSI bias level

input group "Volume Profile"
input ENUM_VOLUME_PROFILE_FILTER InpVolumeProfileFilter = VP_FILTER_DISTANCE_ONLY; // Optional POC filter
input ENUM_TIMEFRAMES InpVpSourceTF     = PERIOD_M1;  // Source timeframe
input int     InpVpLookbackBars         = 720;        // Bars to scan
input double  InpVpRangeUsd             = 50.0;       // +/- price range around current price
input int     InpVpRows                 = 32;         // Price buckets in the range
input bool    InpVpUseRealVolume        = true;       // Prefer real volume when available
input int     InpVpMinPocDistancePoints = 0;          // Skip if too close to POC; 0 = off
input int     InpVpMaxPocDistancePoints = 0;          // Skip if too far from POC; 0 = off
input int     InpVpPocSideBufferPoints  = 80;         // Directional POC buffer
input bool    InpUsePocAsTakeProfit     = true;       // Use POC as closer target when valid

input group "Risk and Execution"
input ENUM_LOT_MODE InpLotMode          = LOT_FIXED; // Position sizing mode
input double  InpFixedLot               = 0.01;      // Fixed lot
input double  InpRiskPercent            = 0.50;      // Equity risk percent per trade
input int     InpMaxSpreadPoints        = 80;        // Max spread in points; 0 = off
input int     InpDeviationPoints        = 20;        // Max slippage/deviation in points
input int     InpMaxOpenPositions       = 1;         // Max open positions for this symbol/magic
input int     InpMaxTradesPerDay        = 3;         // Max entries per server day; 0 = off
input double  InpMaxDailyLossPercent    = 3.0;       // Stop entries after daily closed loss; 0 = off
input double  InpMaxDailyProfitPercent  = 0.0;       // Stop entries after daily closed profit; 0 = off
input bool    InpUseTradingHours        = false;     // Restrict entries by server hour
input int     InpTradeStartHour         = 0;         // Server start hour
input int     InpTradeEndHour           = 23;        // Server end hour
input bool    InpCloseOnOppositeSignal  = true;      // Close opposite EA positions before entry

input group "Stops and Position Management"
input bool    InpUseSwingStop           = true;      // Use divergence swing as stop anchor
input int     InpStopLossPoints         = 250;       // Fallback stop loss
input int     InpSwingStopBufferPoints  = 60;        // Swing stop buffer
input int     InpMinStopLossPoints      = 120;       // Min SL distance
input int     InpMaxStopLossPoints      = 700;       // Max SL distance; 0 = off
input bool    InpRejectIfStopTooWide    = true;      // Reject instead of clamping wide swing stops
input double  InpTakeProfitRr           = 1.50;      // TP = risk * RR
input int     InpMinTakeProfitPoints    = 120;       // Min TP distance
input bool    InpUseBreakEven           = true;      // Move SL to breakeven
input int     InpBreakEvenTriggerPoints = 180;       // Breakeven trigger
input int     InpBreakEvenLockPoints    = 20;        // Locked profit after breakeven
input bool    InpUseTrailingStop        = true;      // Trail SL after profit
input int     InpTrailingStartPoints    = 260;       // Start trailing after profit
input int     InpTrailingDistancePoints = 180;       // Trailing distance
input int     InpTrailingStepPoints     = 30;        // Min SL improvement

struct LevelCluster
  {
   double   price;
   int      touches;
   datetime last_time;
  };

struct VolumeProfileSnapshot
  {
   bool   ready;
   double poc_price;
   int    poc_index;
   double poc_volume;
   double total_volume;
   double current_volume;
   double current_ratio;
   double window_low;
   double bucket_step;
   int    bucket_count;
  };

struct TradeSignal
  {
   bool     valid;
   bool     is_buy;
   datetime bar_time;
   double   signal_price;
   double   swing_price;
   double   support;
   double   resistance;
   double   m1_rsi;
   double   m5_rsi;
   string   reason;
   string   detail;
   string   profile_note;
  };

CTrade  g_trade;
int     g_m1_rsi_handle = INVALID_HANDLE;
int     g_m5_rsi_handle = INVALID_HANDLE;
datetime g_last_m1_closed_bar = 0;
string  g_runtime_symbol = "";
string  g_status_name = "XAU_RSI_VP_EA_STATUS";
string  g_support_name = "XAU_RSI_VP_EA_SUPPORT";
string  g_resistance_name = "XAU_RSI_VP_EA_RESISTANCE";

//+------------------------------------------------------------------+
//| Basic helpers                                                    |
//+------------------------------------------------------------------+
int ClampInt(const int value, const int low, const int high)
  {
   if(value < low)
      return low;
   if(value > high)
      return high;
   return value;
  }

double ClampDouble(const double value, const double low, const double high)
  {
   if(value < low)
      return low;
   if(value > high)
      return high;
   return value;
  }

double SymbolPoint()
  {
   double point = 0.0;
   if(!SymbolInfoDouble(g_runtime_symbol, SYMBOL_POINT, point) || point <= 0.0)
      point = _Point;
   return point;
  }

int SymbolDigits()
  {
   long digits = 0;
   if(!SymbolInfoInteger(g_runtime_symbol, SYMBOL_DIGITS, digits))
      digits = (long)_Digits;
   return (int)digits;
  }

double NormalizeSymbolPrice(const double price)
  {
   return NormalizeDouble(price, SymbolDigits());
  }

string PriceText(const double price)
  {
   return DoubleToString(NormalizeSymbolPrice(price), SymbolDigits());
  }

bool GetBidAsk(double &bid, double &ask)
  {
   bid = 0.0;
   ask = 0.0;
   if(!SymbolInfoDouble(g_runtime_symbol, SYMBOL_BID, bid))
      return false;
   if(!SymbolInfoDouble(g_runtime_symbol, SYMBOL_ASK, ask))
      return false;
   return (bid > 0.0 && ask > 0.0 && ask >= bid);
  }

int MinStopDistancePoints()
  {
   long stops_level = 0;
   if(!SymbolInfoInteger(g_runtime_symbol, SYMBOL_TRADE_STOPS_LEVEL, stops_level))
      stops_level = 0;
   return (int)MathMax((double)stops_level, 0.0);
  }

datetime DayStart(const datetime t)
  {
   MqlDateTime dt;
   TimeToStruct(t, dt);
   dt.hour = 0;
   dt.min = 0;
   dt.sec = 0;
   return StructToTime(dt);
  }

void EnsureStatusLabel()
  {
   if(!InpShowChartStatus)
      return;

   if(ObjectFind(0, g_status_name) >= 0)
      return;

   if(!ObjectCreate(0, g_status_name, OBJ_LABEL, 0, 0, 0))
      return;

   ObjectSetInteger(0, g_status_name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, g_status_name, OBJPROP_XDISTANCE, 10);
   ObjectSetInteger(0, g_status_name, OBJPROP_YDISTANCE, 12);
   ObjectSetInteger(0, g_status_name, OBJPROP_FONTSIZE, 9);
   ObjectSetString(0, g_status_name, OBJPROP_FONT, "Arial");
   ObjectSetInteger(0, g_status_name, OBJPROP_COLOR, clrWhite);
   ObjectSetInteger(0, g_status_name, OBJPROP_BACK, false);
   ObjectSetInteger(0, g_status_name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, g_status_name, OBJPROP_HIDDEN, true);
  }

void SetStatusText(const string text)
  {
   Comment(text);
   if(InpShowChartStatus)
     {
      EnsureStatusLabel();
      ObjectSetString(0, g_status_name, OBJPROP_TEXT, text);
     }
  }

void DrawOrUpdateHLine(const string name, const double price, const color clr)
  {
   if(!InpDrawSignalObjects)
      return;

   if(price <= 0.0)
     {
      if(ObjectFind(0, name) >= 0)
         ObjectDelete(0, name);
      return;
     }

   if(ObjectFind(0, name) < 0)
     {
      if(!ObjectCreate(0, name, OBJ_HLINE, 0, 0, price))
         return;
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_BACK, true);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
     }

   ObjectSetDouble(0, name, OBJPROP_PRICE, NormalizeSymbolPrice(price));
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_SOLID);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
  }

void DrawSignalArrow(const TradeSignal &signal)
  {
   if(!InpDrawSignalObjects || !signal.valid)
      return;

   const double point = SymbolPoint();
   const double price = signal.is_buy ? signal.signal_price - 12.0 * point : signal.signal_price + 12.0 * point;
   string name = StringFormat("XAU_RSI_VP_EA_%s_%I64d",
                              signal.is_buy ? "BUY" : "SELL",
                              (long)signal.bar_time);
   if(ObjectFind(0, name) >= 0)
      return;

   if(!ObjectCreate(0, name, OBJ_ARROW, 0, signal.bar_time, NormalizeSymbolPrice(price)))
      return;

   ObjectSetInteger(0, name, OBJPROP_ARROWCODE, signal.is_buy ? 233 : 234);
   ObjectSetInteger(0, name, OBJPROP_COLOR, signal.is_buy ? clrLimeGreen : clrTomato);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);

   string text_name = name + "_TEXT";
   if(ObjectCreate(0, text_name, OBJ_TEXT, 0, signal.bar_time, NormalizeSymbolPrice(price)))
     {
      ObjectSetString(0, text_name, OBJPROP_TEXT, signal.is_buy ? "BUY" : "SELL");
      ObjectSetString(0, text_name, OBJPROP_FONT, "Arial");
      ObjectSetInteger(0, text_name, OBJPROP_FONTSIZE, 8);
      ObjectSetInteger(0, text_name, OBJPROP_COLOR, signal.is_buy ? clrLimeGreen : clrTomato);
      ObjectSetInteger(0, text_name, OBJPROP_ANCHOR, ANCHOR_LEFT_UPPER);
      ObjectSetInteger(0, text_name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, text_name, OBJPROP_HIDDEN, true);
     }
  }

void Notify(const string message)
  {
   Print(message);
   if(InpUsePopupAlert)
      Alert(message);
   if(InpUsePushNotification)
      SendNotification(message);
  }

//+------------------------------------------------------------------+
//| Data loading and signal helpers                                  |
//+------------------------------------------------------------------+
bool CopyRatesSeries(const string symbol, const ENUM_TIMEFRAMES tf, const int bars, MqlRates &rates[])
  {
   ArraySetAsSeries(rates, true);
   int copied = CopyRates(symbol, tf, 0, bars, rates);
   return (copied > InpPivotDepth + 5);
  }

bool CopyRsiSeries(const int handle, const int bars, double &values[])
  {
   ArraySetAsSeries(values, true);
   int copied = CopyBuffer(handle, 0, 0, bars, values);
   return (copied > InpPivotDepth + 5);
  }

bool IsPivotLow(const MqlRates &rates[], const int index, const int depth)
  {
   double value = rates[index].low;
   for(int i = 1; i <= depth; i++)
     {
      if(index - i < 0 || index + i >= ArraySize(rates))
         return false;
      if(value > rates[index - i].low)
         return false;
      if(value >= rates[index + i].low)
         return false;
     }
   return true;
  }

bool IsPivotHigh(const MqlRates &rates[], const int index, const int depth)
  {
   double value = rates[index].high;
   for(int i = 1; i <= depth; i++)
     {
      if(index - i < 0 || index + i >= ArraySize(rates))
         return false;
      if(value < rates[index - i].high)
         return false;
      if(value <= rates[index + i].high)
         return false;
     }
   return true;
  }

bool FindRecentPivots(const MqlRates &rates[],
                      const bool search_lows,
                      const int depth,
                      const int lookback,
                      int &newer_index,
                      int &older_index)
  {
   newer_index = -1;
   older_index = -1;

   int limit = MathMin(ArraySize(rates) - depth - 1, lookback);
   for(int i = depth + 1; i <= limit; i++)
     {
      bool ok = search_lows ? IsPivotLow(rates, i, depth) : IsPivotHigh(rates, i, depth);
      if(!ok)
         continue;

      if(newer_index < 0)
         newer_index = i;
      else
        {
         older_index = i;
         return true;
        }
     }
   return false;
  }

void AddCluster(LevelCluster &clusters[], const double price, const datetime t, const double max_distance)
  {
   int total = ArraySize(clusters);
   for(int i = 0; i < total; i++)
     {
      if(MathAbs(clusters[i].price - price) <= max_distance)
        {
         clusters[i].price = (clusters[i].price * clusters[i].touches + price) / (clusters[i].touches + 1);
         clusters[i].touches++;
         if(t > clusters[i].last_time)
            clusters[i].last_time = t;
         return;
        }
     }

   ArrayResize(clusters, total + 1);
   clusters[total].price = price;
   clusters[total].touches = 1;
   clusters[total].last_time = t;
  }

bool BuildKeyLevels(const MqlRates &rates[], double &support, double &resistance)
  {
   support = 0.0;
   resistance = 0.0;

   LevelCluster support_clusters[];
   LevelCluster resistance_clusters[];
   ArrayResize(support_clusters, 0);
   ArrayResize(resistance_clusters, 0);

   double max_distance = InpClusterDistancePoints * SymbolPoint();
   int limit = MathMin(ArraySize(rates) - InpPivotDepth - 1, InpClusterLookbackBars);
   for(int i = InpPivotDepth + 1; i <= limit; i++)
     {
      if(IsPivotLow(rates, i, InpPivotDepth))
         AddCluster(support_clusters, rates[i].low, rates[i].time, max_distance);
      if(IsPivotHigh(rates, i, InpPivotDepth))
         AddCluster(resistance_clusters, rates[i].high, rates[i].time, max_distance);
     }

   double current = rates[1].close;
   double best_support_distance = DBL_MAX;
   double best_resistance_distance = DBL_MAX;

   for(int i = 0; i < ArraySize(support_clusters); i++)
     {
      if(support_clusters[i].price < current)
        {
         double d = current - support_clusters[i].price;
         if(d < best_support_distance)
           {
            best_support_distance = d;
            support = support_clusters[i].price;
           }
        }
     }

   for(int i = 0; i < ArraySize(resistance_clusters); i++)
     {
      if(resistance_clusters[i].price > current)
        {
         double d = resistance_clusters[i].price - current;
         if(d < best_resistance_distance)
           {
            best_resistance_distance = d;
            resistance = resistance_clusters[i].price;
           }
        }
     }

   return (support > 0.0 || resistance > 0.0);
  }

double AverageTickVolume(const MqlRates &rates[], const int from_shift, const int period)
  {
   if(ArraySize(rates) <= from_shift + period)
      return 0.0;

   long sum = 0;
   int count = 0;
   for(int i = from_shift + 1; i <= from_shift + period; i++)
     {
      sum += rates[i].tick_volume;
      count++;
     }

   return (count > 0 ? (double)sum / count : 0.0);
  }

bool M5BullishFilter(const double &m5_rsi[])
  {
   return (ArraySize(m5_rsi) >= 3 && m5_rsi[1] >= InpM5RsiBiasLevel && m5_rsi[1] >= m5_rsi[2]);
  }

bool M5BearishFilter(const double &m5_rsi[])
  {
   return (ArraySize(m5_rsi) >= 3 && m5_rsi[1] <= InpM5RsiBiasLevel && m5_rsi[1] <= m5_rsi[2]);
  }

bool BullishDivergence(const MqlRates &rates[], const double &rsi[], int &newer_index, int &older_index)
  {
   if(!FindRecentPivots(rates, true, InpPivotDepth, InpClusterLookbackBars, newer_index, older_index))
      return false;
   if(older_index - newer_index > InpDivergenceWindow)
      return false;

   double min_price_gap = InpMinPriceGapPoints * SymbolPoint();
   if(!(rates[newer_index].low < rates[older_index].low - min_price_gap))
      return false;
   if(!(rsi[newer_index] > rsi[older_index] + InpMinRsiGap))
      return false;
   return true;
  }

bool BearishDivergence(const MqlRates &rates[], const double &rsi[], int &newer_index, int &older_index)
  {
   if(!FindRecentPivots(rates, false, InpPivotDepth, InpClusterLookbackBars, newer_index, older_index))
      return false;
   if(older_index - newer_index > InpDivergenceWindow)
      return false;

   double min_price_gap = InpMinPriceGapPoints * SymbolPoint();
   if(!(rates[newer_index].high > rates[older_index].high + min_price_gap))
      return false;
   if(!(rsi[newer_index] < rsi[older_index] - InpMinRsiGap))
      return false;
   return true;
  }

bool BullishContext(const MqlRates &rates[], const double support, const double resistance, string &reason)
  {
   reason = "";

   double avg = AverageTickVolume(rates, 1, InpVolumePeriod);
   if(avg <= 0.0)
      return false;

   double close1 = rates[1].close;
   double open1 = rates[1].open;
   double low1 = rates[1].low;
   double vol1 = (double)rates[1].tick_volume;
   double point = SymbolPoint();

   bool breakout_up = (resistance > 0.0 &&
                       close1 > resistance + InpBreakBufferPoints * point &&
                       vol1 >= avg * InpVolumeSpikeMultiplier);
   bool pullback_rebound = (support > 0.0 &&
                            low1 <= support + InpTouchBufferPoints * point &&
                            close1 > open1 &&
                            vol1 <= avg * InpVolumeShrinkRatio &&
                            close1 > support);

   if(breakout_up)
     {
      reason = "volume breakout";
      return true;
     }
   if(pullback_rebound)
     {
      reason = "low-volume pullback";
      return true;
     }
   return false;
  }

bool BearishContext(const MqlRates &rates[], const double support, const double resistance, string &reason)
  {
   reason = "";

   double avg = AverageTickVolume(rates, 1, InpVolumePeriod);
   if(avg <= 0.0)
      return false;

   double close1 = rates[1].close;
   double open1 = rates[1].open;
   double high1 = rates[1].high;
   double vol1 = (double)rates[1].tick_volume;
   double point = SymbolPoint();

   bool breakout_down = (support > 0.0 &&
                         close1 < support - InpBreakBufferPoints * point &&
                         vol1 >= avg * InpVolumeSpikeMultiplier);
   bool pullback_reject = (resistance > 0.0 &&
                           high1 >= resistance - InpTouchBufferPoints * point &&
                           close1 < open1 &&
                           vol1 <= avg * InpVolumeShrinkRatio &&
                           close1 < resistance);

   if(breakout_down)
     {
      reason = "volume breakout";
      return true;
     }
   if(pullback_reject)
     {
      reason = "low-volume pullback";
      return true;
     }
   return false;
  }

//+------------------------------------------------------------------+
//| Volume profile logic                                             |
//+------------------------------------------------------------------+
double RateVolume(const MqlRates &rate)
  {
   double volume = 0.0;
   if(InpVpUseRealVolume)
      volume = (double)rate.real_volume;
   if(volume <= 0.0)
      volume = (double)rate.tick_volume;
   if(volume <= 0.0)
      volume = 1.0;
   return volume;
  }

bool BuildVolumeProfileSnapshot(const double current_price, VolumeProfileSnapshot &profile)
  {
   profile.ready = false;
   profile.poc_price = 0.0;
   profile.poc_index = -1;
   profile.poc_volume = 0.0;
   profile.total_volume = 0.0;
   profile.current_volume = 0.0;
   profile.current_ratio = 0.0;
   profile.window_low = 0.0;
   profile.bucket_step = 0.0;
   profile.bucket_count = 0;

   const ENUM_TIMEFRAMES tf = (InpVpSourceTF == PERIOD_CURRENT ? (ENUM_TIMEFRAMES)Period() : InpVpSourceTF);
   const int bars_to_copy = MathMax(50, InpVpLookbackBars);

   MqlRates rates[];
   ArraySetAsSeries(rates, false);
   int copied = CopyRates(g_runtime_symbol, tf, 0, bars_to_copy, rates);
   if(copied <= 0 || current_price <= 0.0)
      return false;

   const double point = SymbolPoint();
   const double half_range = MathMax(InpVpRangeUsd, point * 100.0);
   const double window_low = current_price - half_range;
   const double window_high = current_price + half_range;
   const int bucket_count = ClampInt(InpVpRows, 8, 64);
   const double bucket_step = MathMax((window_high - window_low) / (double)bucket_count, point);

   double bucket_volumes[];
   ArrayResize(bucket_volumes, bucket_count);
   ArrayInitialize(bucket_volumes, 0.0);

   for(int i = 0; i < copied; ++i)
     {
      const double vol = RateVolume(rates[i]);
      double bar_low = rates[i].low;
      double bar_high = rates[i].high;
      if(bar_low > bar_high)
        {
         const double tmp = bar_low;
         bar_low = bar_high;
         bar_high = tmp;
        }
      if(bar_high < window_low || bar_low > window_high)
         continue;

      const double bar_range = bar_high - bar_low;
      if(bar_range <= point * 0.1)
        {
         const double mid = (bar_low + bar_high) * 0.5;
         int index = (int)MathFloor((mid - window_low) / bucket_step);
         index = ClampInt(index, 0, bucket_count - 1);
         bucket_volumes[index] += vol;
         continue;
        }

      int first = (int)MathFloor((MathMax(bar_low, window_low) - window_low) / bucket_step);
      int last = (int)MathFloor((MathMin(bar_high, window_high) - window_low) / bucket_step);
      first = ClampInt(first, 0, bucket_count - 1);
      last = ClampInt(last, 0, bucket_count - 1);
      if(last < first)
        {
         const int swap = first;
         first = last;
         last = swap;
        }

      for(int b = first; b <= last; ++b)
        {
         const double row_low = window_low + (double)b * bucket_step;
         const double row_high = row_low + bucket_step;
         const double overlap = MathMax(0.0, MathMin(bar_high, row_high) - MathMax(bar_low, row_low));
         if(overlap <= 0.0)
            continue;
         bucket_volumes[b] += vol * (overlap / bar_range);
        }
     }

   int poc_index = 0;
   double max_volume = bucket_volumes[0];
   double total_volume = bucket_volumes[0];
   for(int i = 1; i < bucket_count; ++i)
     {
      total_volume += bucket_volumes[i];
      if(bucket_volumes[i] > max_volume)
        {
         max_volume = bucket_volumes[i];
         poc_index = i;
        }
     }

   int current_index = (int)MathFloor((current_price - window_low) / bucket_step);
   current_index = ClampInt(current_index, 0, bucket_count - 1);

   profile.ready = (max_volume > 0.0);
   profile.poc_price = NormalizeSymbolPrice(window_low + ((double)poc_index + 0.5) * bucket_step);
   profile.poc_index = poc_index;
   profile.poc_volume = max_volume;
   profile.total_volume = total_volume;
   profile.current_volume = bucket_volumes[current_index];
   profile.current_ratio = (max_volume > 0.0 ? bucket_volumes[current_index] / max_volume : 0.0);
   profile.window_low = window_low;
   profile.bucket_step = bucket_step;
   profile.bucket_count = bucket_count;
   return profile.ready;
  }

bool VolumeProfileAllows(const bool is_buy,
                         const double price,
                         const VolumeProfileSnapshot &profile,
                         string &note)
  {
   note = "";
   if(InpVolumeProfileFilter == VP_FILTER_OFF)
     {
      note = "VP filter off";
      return true;
     }

   if(!profile.ready)
     {
      note = "VP not ready";
      return false;
     }

   const double point = SymbolPoint();
   double distance_points = MathAbs(price - profile.poc_price) / point;

   if(InpVpMinPocDistancePoints > 0 && distance_points < InpVpMinPocDistancePoints)
     {
      note = StringFormat("near POC %.0fpt", distance_points);
      return false;
     }
   if(InpVpMaxPocDistancePoints > 0 && distance_points > InpVpMaxPocDistancePoints)
     {
      note = StringFormat("far from POC %.0fpt", distance_points);
      return false;
     }

   const double buffer = InpVpPocSideBufferPoints * point;
   if(InpVolumeProfileFilter == VP_FILTER_TRADE_TOWARD_POC)
     {
      if(is_buy && price > profile.poc_price + buffer)
        {
         note = "buy is above POC";
         return false;
        }
      if(!is_buy && price < profile.poc_price - buffer)
        {
         note = "sell is below POC";
         return false;
        }
     }
   else if(InpVolumeProfileFilter == VP_FILTER_TRADE_WITH_POC_SIDE)
     {
      if(is_buy && price < profile.poc_price - buffer)
        {
         note = "buy is below POC";
         return false;
        }
      if(!is_buy && price > profile.poc_price + buffer)
        {
         note = "sell is above POC";
         return false;
        }
     }

   note = StringFormat("POC=%s dist=%.0fpt curVol=%.0f%%",
                       PriceText(profile.poc_price),
                       distance_points,
                       profile.current_ratio * 100.0);
   return true;
  }

//+------------------------------------------------------------------+
//| Trading guards and money management                              |
//+------------------------------------------------------------------+
bool IsWithinTradingHours()
  {
   if(!InpUseTradingHours)
      return true;

   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   int start_hour = ClampInt(InpTradeStartHour, 0, 23);
   int end_hour = ClampInt(InpTradeEndHour, 0, 23);

   if(start_hour == end_hour)
      return dt.hour == start_hour;
   if(start_hour < end_hour)
      return (dt.hour >= start_hour && dt.hour <= end_hour);
   return (dt.hour >= start_hour || dt.hour <= end_hour);
  }

bool SpreadAllows(string &reason)
  {
   reason = "";
   if(InpMaxSpreadPoints <= 0)
      return true;

   double bid = 0.0;
   double ask = 0.0;
   if(!GetBidAsk(bid, ask))
     {
      reason = "bid/ask unavailable";
      return false;
     }

   double spread_points = (ask - bid) / SymbolPoint();
   if(spread_points > InpMaxSpreadPoints)
     {
      reason = StringFormat("spread %.0fpt > %dpt", spread_points, InpMaxSpreadPoints);
      return false;
     }
   return true;
  }

int CountOpenPositions(const int type_filter = -1)
  {
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; --i)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;
      if(PositionGetString(POSITION_SYMBOL) != g_runtime_symbol)
         continue;
      if((long)PositionGetInteger(POSITION_MAGIC) != InpMagicNumber)
         continue;

      int type = (int)PositionGetInteger(POSITION_TYPE);
      if(type_filter >= 0 && type != type_filter)
         continue;
      count++;
     }
   return count;
  }

bool ClosePositionsByType(const int type_filter)
  {
   bool ok = true;
   for(int i = PositionsTotal() - 1; i >= 0; --i)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;
      if(PositionGetString(POSITION_SYMBOL) != g_runtime_symbol)
         continue;
      if((long)PositionGetInteger(POSITION_MAGIC) != InpMagicNumber)
         continue;
      if((int)PositionGetInteger(POSITION_TYPE) != type_filter)
         continue;

      if(!g_trade.PositionClose(ticket))
        {
         ok = false;
         PrintFormat("Close failed ticket=%I64u retcode=%u %s",
                     ticket,
                     g_trade.ResultRetcode(),
                     g_trade.ResultRetcodeDescription());
        }
     }
   return ok;
  }

double ClosedProfitSince(const datetime from_time)
  {
   if(!HistorySelect(from_time, TimeCurrent()))
      return 0.0;

   double profit = 0.0;
   int total = HistoryDealsTotal();
   for(int i = 0; i < total; i++)
     {
      ulong ticket = HistoryDealGetTicket(i);
      if(ticket == 0)
         continue;
      if(HistoryDealGetString(ticket, DEAL_SYMBOL) != g_runtime_symbol)
         continue;
      if((long)HistoryDealGetInteger(ticket, DEAL_MAGIC) != InpMagicNumber)
         continue;

      int type = (int)HistoryDealGetInteger(ticket, DEAL_TYPE);
      if(type != DEAL_TYPE_BUY && type != DEAL_TYPE_SELL)
         continue;

      profit += HistoryDealGetDouble(ticket, DEAL_PROFIT);
      profit += HistoryDealGetDouble(ticket, DEAL_SWAP);
      profit += HistoryDealGetDouble(ticket, DEAL_COMMISSION);
     }
   return profit;
  }

int EntryDealsSince(const datetime from_time)
  {
   if(!HistorySelect(from_time, TimeCurrent()))
      return 0;

   int count = 0;
   int total = HistoryDealsTotal();
   for(int i = 0; i < total; i++)
     {
      ulong ticket = HistoryDealGetTicket(i);
      if(ticket == 0)
         continue;
      if(HistoryDealGetString(ticket, DEAL_SYMBOL) != g_runtime_symbol)
         continue;
      if((long)HistoryDealGetInteger(ticket, DEAL_MAGIC) != InpMagicNumber)
         continue;
      if((int)HistoryDealGetInteger(ticket, DEAL_ENTRY) == DEAL_ENTRY_IN)
         count++;
     }
   return count;
  }

bool DailyRiskAllows(string &reason)
  {
   reason = "";
   datetime start = DayStart(TimeCurrent());

   if(InpMaxTradesPerDay > 0)
     {
      int entries = EntryDealsSince(start);
      if(entries >= InpMaxTradesPerDay)
        {
         reason = StringFormat("daily trade limit %d reached", InpMaxTradesPerDay);
         return false;
        }
     }

   double day_profit = ClosedProfitSince(start);
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   if(InpMaxDailyLossPercent > 0.0 && day_profit <= -balance * InpMaxDailyLossPercent / 100.0)
     {
      reason = StringFormat("daily loss guard %.2f reached", day_profit);
      return false;
     }
   if(InpMaxDailyProfitPercent > 0.0 && day_profit >= balance * InpMaxDailyProfitPercent / 100.0)
     {
      reason = StringFormat("daily profit guard %.2f reached", day_profit);
      return false;
     }
   return true;
  }

bool TradingAllowedForDirection(const bool is_buy, string &reason)
  {
   reason = "";

   if(!InpEnableTrading)
     {
      reason = "trading disabled by input";
      return false;
     }
   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED))
     {
      reason = "terminal auto-trading disabled";
      return false;
     }
   if(!MQLInfoInteger(MQL_TRADE_ALLOWED))
     {
      reason = "EA trading permission disabled";
      return false;
     }

   long trade_mode = SYMBOL_TRADE_MODE_DISABLED;
   if(!SymbolInfoInteger(g_runtime_symbol, SYMBOL_TRADE_MODE, trade_mode))
     {
      reason = "symbol trade mode unavailable";
      return false;
     }
   if(trade_mode == SYMBOL_TRADE_MODE_DISABLED || trade_mode == SYMBOL_TRADE_MODE_CLOSEONLY)
     {
      reason = "symbol trading disabled/close-only";
      return false;
     }
   if(is_buy && trade_mode == SYMBOL_TRADE_MODE_SHORTONLY)
     {
      reason = "symbol is short-only";
      return false;
     }
   if(!is_buy && trade_mode == SYMBOL_TRADE_MODE_LONGONLY)
     {
      reason = "symbol is long-only";
      return false;
     }
   if(!IsWithinTradingHours())
     {
      reason = "outside trading hours";
      return false;
     }
   if(!SpreadAllows(reason))
      return false;
   if(!DailyRiskAllows(reason))
      return false;

   return true;
  }

double NormalizeVolume(const double raw_lots)
  {
   double min_lot = 0.0;
   double max_lot = 0.0;
   double step = 0.0;
   if(!SymbolInfoDouble(g_runtime_symbol, SYMBOL_VOLUME_MIN, min_lot) || min_lot <= 0.0)
      min_lot = 0.01;
   if(!SymbolInfoDouble(g_runtime_symbol, SYMBOL_VOLUME_MAX, max_lot) || max_lot <= 0.0)
      max_lot = 100.0;
   if(!SymbolInfoDouble(g_runtime_symbol, SYMBOL_VOLUME_STEP, step) || step <= 0.0)
      step = min_lot;

   double lots = ClampDouble(raw_lots, min_lot, max_lot);
   lots = MathFloor(lots / step) * step;
   if(lots < min_lot)
      lots = min_lot;
   return NormalizeDouble(lots, 8);
  }

double CalculateLots(const double entry, const double stop_loss)
  {
   if(InpLotMode == LOT_FIXED || InpRiskPercent <= 0.0)
      return NormalizeVolume(InpFixedLot);

   double tick_size = 0.0;
   double tick_value = 0.0;
   if(!SymbolInfoDouble(g_runtime_symbol, SYMBOL_TRADE_TICK_SIZE, tick_size) || tick_size <= 0.0)
      return NormalizeVolume(InpFixedLot);
   if(!SymbolInfoDouble(g_runtime_symbol, SYMBOL_TRADE_TICK_VALUE, tick_value) || tick_value <= 0.0)
      return NormalizeVolume(InpFixedLot);

   double risk_money = AccountInfoDouble(ACCOUNT_EQUITY) * InpRiskPercent / 100.0;
   double price_risk = MathAbs(entry - stop_loss);
   double money_per_lot = price_risk / tick_size * tick_value;
   if(risk_money <= 0.0 || money_per_lot <= 0.0)
      return NormalizeVolume(InpFixedLot);

   return NormalizeVolume(risk_money / money_per_lot);
  }

bool BuildStopsAndTargets(const TradeSignal &signal,
                          const VolumeProfileSnapshot &profile,
                          const double entry,
                          double &sl,
                          double &tp,
                          string &reject_reason)
  {
   reject_reason = "";
   const double point = SymbolPoint();
   const int stop_level = MinStopDistancePoints();
   const int min_sl_points = MathMax(InpMinStopLossPoints, stop_level + 2);
   const int min_tp_points = MathMax(InpMinTakeProfitPoints, stop_level + 2);

   if(signal.is_buy)
     {
      sl = entry - InpStopLossPoints * point;
      if(InpUseSwingStop && signal.swing_price > 0.0)
         sl = signal.swing_price - InpSwingStopBufferPoints * point;

      if(entry - sl < min_sl_points * point)
         sl = entry - min_sl_points * point;

      double sl_points = (entry - sl) / point;
      if(InpMaxStopLossPoints > 0 && sl_points > InpMaxStopLossPoints)
        {
         if(InpRejectIfStopTooWide)
           {
            reject_reason = StringFormat("SL %.0fpt > max %dpt", sl_points, InpMaxStopLossPoints);
            return false;
           }
         sl = entry - InpMaxStopLossPoints * point;
        }

      double risk_price = entry - sl;
      tp = entry + MathMax(risk_price * InpTakeProfitRr, min_tp_points * point);
      if(InpUsePocAsTakeProfit && profile.ready && profile.poc_price > entry + min_tp_points * point)
         tp = MathMin(tp, profile.poc_price);

      if(tp - entry < min_tp_points * point)
         tp = entry + min_tp_points * point;
     }
   else
     {
      sl = entry + InpStopLossPoints * point;
      if(InpUseSwingStop && signal.swing_price > 0.0)
         sl = signal.swing_price + InpSwingStopBufferPoints * point;

      if(sl - entry < min_sl_points * point)
         sl = entry + min_sl_points * point;

      double sl_points = (sl - entry) / point;
      if(InpMaxStopLossPoints > 0 && sl_points > InpMaxStopLossPoints)
        {
         if(InpRejectIfStopTooWide)
           {
            reject_reason = StringFormat("SL %.0fpt > max %dpt", sl_points, InpMaxStopLossPoints);
            return false;
           }
         sl = entry + InpMaxStopLossPoints * point;
        }

      double risk_price = sl - entry;
      tp = entry - MathMax(risk_price * InpTakeProfitRr, min_tp_points * point);
      if(InpUsePocAsTakeProfit && profile.ready && profile.poc_price < entry - min_tp_points * point)
         tp = MathMax(tp, profile.poc_price);

      if(entry - tp < min_tp_points * point)
         tp = entry - min_tp_points * point;
     }

   sl = NormalizeSymbolPrice(sl);
   tp = NormalizeSymbolPrice(tp);

   if(signal.is_buy && !(sl < entry && tp > entry))
     {
      reject_reason = "invalid buy SL/TP";
      return false;
     }
   if(!signal.is_buy && !(sl > entry && tp < entry))
     {
      reject_reason = "invalid sell SL/TP";
      return false;
     }
   return true;
  }

//+------------------------------------------------------------------+
//| Signal evaluation                                                |
//+------------------------------------------------------------------+
void ResetSignal(TradeSignal &signal)
  {
   signal.valid = false;
   signal.is_buy = false;
   signal.bar_time = 0;
   signal.signal_price = 0.0;
   signal.swing_price = 0.0;
   signal.support = 0.0;
   signal.resistance = 0.0;
   signal.m1_rsi = 0.0;
   signal.m5_rsi = 0.0;
   signal.reason = "";
   signal.detail = "";
   signal.profile_note = "";
  }

bool LoadMarketData(MqlRates &m1_rates[], MqlRates &m5_rates[], double &m1_rsi[], double &m5_rsi[], string &error)
  {
   error = "";
   int m1_need = MathMax(InpHistoryBars, InpClusterLookbackBars + InpPivotDepth * 4 + InpVolumePeriod + 50);
   int m5_need = MathMax(200, InpClusterLookbackBars / 2 + 50);

   if(!CopyRatesSeries(g_runtime_symbol, PERIOD_M1, m1_need, m1_rates))
     {
      error = "failed to read M1 rates";
      return false;
     }
   if(!CopyRatesSeries(g_runtime_symbol, PERIOD_M5, m5_need, m5_rates))
     {
      error = "failed to read M5 rates";
      return false;
     }
   if(!CopyRsiSeries(g_m1_rsi_handle, ArraySize(m1_rates), m1_rsi))
     {
      error = "failed to read M1 RSI";
      return false;
     }
   if(!CopyRsiSeries(g_m5_rsi_handle, ArraySize(m5_rates), m5_rsi))
     {
      error = "failed to read M5 RSI";
      return false;
     }
   if(ArraySize(m1_rates) < 50 || ArraySize(m1_rsi) < 50 || ArraySize(m5_rsi) < 10)
     {
      error = "not enough market data";
      return false;
     }
   return true;
  }

string BoolText(const bool value)
  {
   return value ? "Y" : "N";
  }

string EntryModeText()
  {
   if(InpEntryMode == ENTRY_STRICT_ORIGINAL)
      return "strict";
   if(InpEntryMode == ENTRY_RSI_REVERSAL)
      return "rsi-reversal";
   return "divergence";
  }

bool EvaluateClosedBarSignal(const MqlRates &m1_rates[],
                             const double &m1_rsi[],
                             const double &m5_rsi[],
                             const VolumeProfileSnapshot &profile,
                             TradeSignal &signal,
                             string &status_line)
  {
   ResetSignal(signal);
   status_line = "";

   double support = 0.0;
   double resistance = 0.0;
   BuildKeyLevels(m1_rates, support, resistance);
   DrawOrUpdateHLine(g_support_name, support, clrSeaGreen);
   DrawOrUpdateHLine(g_resistance_name, resistance, clrIndianRed);

   int bull_newer = -1;
   int bull_older = -1;
   int bear_newer = -1;
   int bear_older = -1;
   bool bullish_div = BullishDivergence(m1_rates, m1_rsi, bull_newer, bull_older);
   bool bearish_div = BearishDivergence(m1_rates, m1_rsi, bear_newer, bear_older);

   bool m5_buy_ok = (!InpUseM5Filter || M5BullishFilter(m5_rsi));
   bool m5_sell_ok = (!InpUseM5Filter || M5BearishFilter(m5_rsi));

   string buy_reason = "";
   string sell_reason = "";
   bool buy_context = BullishContext(m1_rates, support, resistance, buy_reason);
   bool sell_context = BearishContext(m1_rates, support, resistance, sell_reason);

   double close_price = m1_rates[1].close;
   string vp_note = "";

   bool buy_rsi_ok = (bullish_div && bull_newer >= 0 && m1_rsi[bull_newer] <= InpRsiBuyLevel);
   bool sell_rsi_ok = (bearish_div && bear_newer >= 0 && m1_rsi[bear_newer] >= InpRsiSellLevel);
   bool buy_reversal = (m1_rsi[1] <= InpRsiBuyLevel &&
                        m1_rsi[1] > m1_rsi[2] &&
                        m1_rates[1].close > m1_rates[1].open);
   bool sell_reversal = (m1_rsi[1] >= InpRsiSellLevel &&
                         m1_rsi[1] < m1_rsi[2] &&
                         m1_rates[1].close < m1_rates[1].open);

   bool buy_setup = false;
   bool sell_setup = false;
   string buy_detail = "";
   string sell_detail = "";

   if(InpEntryMode == ENTRY_STRICT_ORIGINAL)
     {
      buy_setup = (bullish_div && buy_rsi_ok && m5_buy_ok && buy_context);
      sell_setup = (bearish_div && sell_rsi_ok && m5_sell_ok && sell_context);
      buy_detail = "strict bullish divergence";
      sell_detail = "strict bearish divergence";
     }
   else if(InpEntryMode == ENTRY_RSI_REVERSAL)
     {
      buy_setup = ((buy_reversal || buy_rsi_ok) && m5_buy_ok);
      sell_setup = ((sell_reversal || sell_rsi_ok) && m5_sell_ok);
      buy_detail = buy_reversal ? "RSI reversal scalp" : "RSI bullish divergence";
      sell_detail = sell_reversal ? "RSI reversal scalp" : "RSI bearish divergence";
      if(buy_context && buy_reason != "")
         buy_detail += " + " + buy_reason;
      if(sell_context && sell_reason != "")
         sell_detail += " + " + sell_reason;
     }
   else
     {
      buy_setup = (bullish_div && buy_rsi_ok && m5_buy_ok);
      sell_setup = (bearish_div && sell_rsi_ok && m5_sell_ok);
      buy_detail = buy_context && buy_reason != "" ? "bullish divergence + " + buy_reason : "bullish divergence";
      sell_detail = sell_context && sell_reason != "" ? "bearish divergence + " + sell_reason : "bearish divergence";
     }

   if(buy_setup)
     {
      if(!VolumeProfileAllows(true, close_price, profile, vp_note))
        {
         status_line = "BUY signal blocked by VP: " + vp_note;
         return false;
        }

      signal.valid = true;
      signal.is_buy = true;
      signal.bar_time = m1_rates[1].time;
      signal.signal_price = m1_rates[1].low;
      signal.swing_price = (bull_newer >= 0 ? m1_rates[bull_newer].low : m1_rates[1].low);
      signal.support = support;
      signal.resistance = resistance;
      signal.m1_rsi = m1_rsi[1];
      signal.m5_rsi = m5_rsi[1];
      signal.reason = buy_detail;
      signal.detail = bullish_div ? StringFormat("bullish divergence p%d/p%d", bull_newer, bull_older) : "RSI reversal";
      signal.profile_note = vp_note;
      status_line = "BUY signal ready";
      return true;
     }

   if(sell_setup)
     {
      if(!VolumeProfileAllows(false, close_price, profile, vp_note))
        {
         status_line = "SELL signal blocked by VP: " + vp_note;
         return false;
        }

      signal.valid = true;
      signal.is_buy = false;
      signal.bar_time = m1_rates[1].time;
      signal.signal_price = m1_rates[1].high;
      signal.swing_price = (bear_newer >= 0 ? m1_rates[bear_newer].high : m1_rates[1].high);
      signal.support = support;
      signal.resistance = resistance;
      signal.m1_rsi = m1_rsi[1];
      signal.m5_rsi = m5_rsi[1];
      signal.reason = sell_detail;
      signal.detail = bearish_div ? StringFormat("bearish divergence p%d/p%d", bear_newer, bear_older) : "RSI reversal";
      signal.profile_note = vp_note;
      status_line = "SELL signal ready";
      return true;
     }

   if((bullish_div || buy_reversal) && !m5_buy_ok)
      status_line = "bullish divergence exists, M5 rejected";
   else if((bearish_div || sell_reversal) && !m5_sell_ok)
      status_line = "bearish divergence exists, M5 rejected";
   else if(bullish_div || bearish_div)
      status_line = "divergence exists, context/RSI not aligned";
   else
      status_line = StringFormat("no signal | mode=%s bullDiv=%s bearDiv=%s buyRev=%s sellRev=%s",
                                 EntryModeText(),
                                 BoolText(bullish_div),
                                 BoolText(bearish_div),
                                 BoolText(buy_reversal),
                                 BoolText(sell_reversal));

   return false;
  }

//+------------------------------------------------------------------+
//| Trade execution and management                                   |
//+------------------------------------------------------------------+
bool OpenSignalTrade(const TradeSignal &signal, const VolumeProfileSnapshot &profile)
  {
   if(!signal.valid)
      return false;

   string guard_reason = "";
   if(!TradingAllowedForDirection(signal.is_buy, guard_reason))
     {
      Notify(StringFormat("%s signal on %s, not traded: %s",
                          signal.is_buy ? "BUY" : "SELL",
                          g_runtime_symbol,
                          guard_reason));
      return false;
     }

   if(InpCloseOnOppositeSignal)
     {
      int opposite_type = signal.is_buy ? POSITION_TYPE_SELL : POSITION_TYPE_BUY;
      ClosePositionsByType(opposite_type);
     }

   if(InpMaxOpenPositions > 0 && CountOpenPositions() >= InpMaxOpenPositions)
     {
      Notify(StringFormat("%s signal skipped: max open positions reached",
                          signal.is_buy ? "BUY" : "SELL"));
      return false;
     }

   double bid = 0.0;
   double ask = 0.0;
   if(!GetBidAsk(bid, ask))
     {
      Notify("Signal skipped: bid/ask unavailable");
      return false;
     }

   double entry = signal.is_buy ? ask : bid;
   double sl = 0.0;
   double tp = 0.0;
   string reject_reason = "";
   if(!BuildStopsAndTargets(signal, profile, entry, sl, tp, reject_reason))
     {
      Notify(StringFormat("%s signal skipped: %s",
                          signal.is_buy ? "BUY" : "SELL",
                          reject_reason));
      return false;
     }

   double lots = CalculateLots(entry, sl);
   if(lots <= 0.0)
     {
      Notify("Signal skipped: calculated lot <= 0");
      return false;
     }

   string comment = StringFormat("RSI_VP_%s_%s",
                                 signal.is_buy ? "BUY" : "SELL",
                                 signal.reason);

   bool sent = false;
   if(signal.is_buy)
      sent = g_trade.Buy(lots, g_runtime_symbol, 0.0, sl, tp, comment);
   else
      sent = g_trade.Sell(lots, g_runtime_symbol, 0.0, sl, tp, comment);

   if(sent)
     {
      Notify(StringFormat("%s opened %s lots=%.2f SL=%s TP=%s | %s | %s",
                          g_runtime_symbol,
                          signal.is_buy ? "BUY" : "SELL",
                          lots,
                          PriceText(sl),
                          PriceText(tp),
                          signal.reason,
                          signal.profile_note));
      return true;
     }

   Notify(StringFormat("%s order failed retcode=%u %s",
                       signal.is_buy ? "BUY" : "SELL",
                       g_trade.ResultRetcode(),
                       g_trade.ResultRetcodeDescription()));
   return false;
  }

bool ImproveStop(const int type, const double old_sl, const double candidate_sl, const double step_points)
  {
   const double point = SymbolPoint();
   if(old_sl <= 0.0)
      return true;
   if(type == POSITION_TYPE_BUY)
      return candidate_sl > old_sl + step_points * point;
   return candidate_sl < old_sl - step_points * point;
  }

bool StopDistanceAllows(const int type, const double candidate_sl)
  {
   double bid = 0.0;
   double ask = 0.0;
   if(!GetBidAsk(bid, ask))
      return false;

   const double point = SymbolPoint();
   const int min_points = MinStopDistancePoints() + 2;
   if(type == POSITION_TYPE_BUY)
      return (bid - candidate_sl) >= min_points * point;
   return (candidate_sl - ask) >= min_points * point;
  }

void ManageOpenPositions()
  {
   const double point = SymbolPoint();
   double bid = 0.0;
   double ask = 0.0;
   if(!GetBidAsk(bid, ask))
      return;

   for(int i = PositionsTotal() - 1; i >= 0; --i)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;
      if(PositionGetString(POSITION_SYMBOL) != g_runtime_symbol)
         continue;
      if((long)PositionGetInteger(POSITION_MAGIC) != InpMagicNumber)
         continue;

      int type = (int)PositionGetInteger(POSITION_TYPE);
      double open_price = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl = PositionGetDouble(POSITION_SL);
      double tp = PositionGetDouble(POSITION_TP);
      double current = (type == POSITION_TYPE_BUY ? bid : ask);
      double profit_points = (type == POSITION_TYPE_BUY ? current - open_price : open_price - current) / point;

      double candidate_sl = sl;
      bool should_modify = false;

      if(InpUseBreakEven && profit_points >= InpBreakEvenTriggerPoints)
        {
         double be_sl = (type == POSITION_TYPE_BUY ?
                         open_price + InpBreakEvenLockPoints * point :
                         open_price - InpBreakEvenLockPoints * point);
         be_sl = NormalizeSymbolPrice(be_sl);
         if(ImproveStop(type, sl, be_sl, 0.0) && StopDistanceAllows(type, be_sl))
           {
            candidate_sl = be_sl;
            should_modify = true;
           }
        }

      if(InpUseTrailingStop && profit_points >= InpTrailingStartPoints)
        {
         double trail_sl = (type == POSITION_TYPE_BUY ?
                            current - InpTrailingDistancePoints * point :
                            current + InpTrailingDistancePoints * point);
         trail_sl = NormalizeSymbolPrice(trail_sl);
         if(ImproveStop(type, candidate_sl, trail_sl, InpTrailingStepPoints) &&
            StopDistanceAllows(type, trail_sl))
           {
            candidate_sl = trail_sl;
            should_modify = true;
           }
        }

      if(should_modify && candidate_sl > 0.0)
        {
         if(!g_trade.PositionModify(ticket, candidate_sl, tp))
            PrintFormat("PositionModify failed ticket=%I64u retcode=%u %s",
                        ticket,
                        g_trade.ResultRetcode(),
                        g_trade.ResultRetcodeDescription());
        }
     }
  }

//+------------------------------------------------------------------+
//| EA lifecycle                                                     |
//+------------------------------------------------------------------+
int OnInit()
  {
   if(InpRsiPeriod < 2 || InpPivotDepth < 1)
      return INIT_PARAMETERS_INCORRECT;

   g_runtime_symbol = InpSymbol;
   if(g_runtime_symbol == "")
      g_runtime_symbol = _Symbol;
   if(!SymbolSelect(g_runtime_symbol, true))
      g_runtime_symbol = _Symbol;

   if(!SymbolSelect(g_runtime_symbol, true))
     {
      Print("Failed to select symbol: ", g_runtime_symbol);
      return INIT_FAILED;
     }

   g_m1_rsi_handle = iRSI(g_runtime_symbol, PERIOD_M1, InpRsiPeriod, PRICE_CLOSE);
   g_m5_rsi_handle = iRSI(g_runtime_symbol, PERIOD_M5, InpRsiPeriod, PRICE_CLOSE);
   if(g_m1_rsi_handle == INVALID_HANDLE || g_m5_rsi_handle == INVALID_HANDLE)
     {
      Print("Failed to create RSI handles.");
      return INIT_FAILED;
     }

   g_trade.SetExpertMagicNumber(InpMagicNumber);
   g_trade.SetDeviationInPoints(InpDeviationPoints);
   g_trade.SetTypeFillingBySymbol(g_runtime_symbol);

   EnsureStatusLabel();
   SetStatusText(StringFormat("RSI VP Scalper EA loaded on %s\nTrading=%s; waiting for next closed M1 bar",
                              g_runtime_symbol,
                              InpEnableTrading ? "ON" : "OFF"));
   Print("XAU_RSI_VolumeProfile_Scalper_EA loaded on ", g_runtime_symbol);
   return INIT_SUCCEEDED;
  }

void OnDeinit(const int reason)
  {
   if(g_m1_rsi_handle != INVALID_HANDLE)
      IndicatorRelease(g_m1_rsi_handle);
   if(g_m5_rsi_handle != INVALID_HANDLE)
      IndicatorRelease(g_m5_rsi_handle);

   ObjectDelete(0, g_status_name);
   ObjectDelete(0, g_support_name);
   ObjectDelete(0, g_resistance_name);
   Comment("");
  }

void OnTick()
  {
   ManageOpenPositions();

   MqlRates m1_rates[];
   MqlRates m5_rates[];
   double m1_rsi[];
   double m5_rsi[];
   string load_error = "";

   if(!LoadMarketData(m1_rates, m5_rates, m1_rsi, m5_rsi, load_error))
     {
      SetStatusText("RSI VP Scalper EA\n" + load_error);
      return;
     }

   datetime closed_bar_time = m1_rates[1].time;
   double bid = 0.0;
   double ask = 0.0;
   GetBidAsk(bid, ask);

   VolumeProfileSnapshot profile;
   BuildVolumeProfileSnapshot(bid > 0.0 ? bid : m1_rates[1].close, profile);

   if(g_last_m1_closed_bar == 0)
     {
      g_last_m1_closed_bar = closed_bar_time;
      SetStatusText(StringFormat("RSI VP Scalper EA %s\nTrading=%s; initialized on M1 close %s\nPOC=%s",
                                 g_runtime_symbol,
                                 InpEnableTrading ? "ON" : "OFF",
                                 TimeToString(closed_bar_time, TIME_DATE | TIME_MINUTES),
                                 profile.ready ? PriceText(profile.poc_price) : "n/a"));
      return;
     }

   if(closed_bar_time == g_last_m1_closed_bar)
     {
      SetStatusText(StringFormat("RSI VP Scalper EA %s\nTrading=%s; waiting next M1 close\nM1 RSI=%.1f M5 RSI=%.1f POC=%s Open=%d",
                                 g_runtime_symbol,
                                 InpEnableTrading ? "ON" : "OFF",
                                 m1_rsi[1],
                                 m5_rsi[1],
                                 profile.ready ? PriceText(profile.poc_price) : "n/a",
                                 CountOpenPositions()));
      return;
     }

   g_last_m1_closed_bar = closed_bar_time;

   TradeSignal signal;
   string signal_status = "";
   bool has_signal = EvaluateClosedBarSignal(m1_rates, m1_rsi, m5_rsi, profile, signal, signal_status);

   if(has_signal)
     {
      DrawSignalArrow(signal);
      Notify(StringFormat("%s %s signal | %s | M1 RSI=%.1f M5 RSI=%.1f | %s",
                          g_runtime_symbol,
                          signal.is_buy ? "BUY" : "SELL",
                          signal.reason,
                          signal.m1_rsi,
                          signal.m5_rsi,
                          signal.profile_note));
      OpenSignalTrade(signal, profile);
     }

   SetStatusText(StringFormat("RSI VP Scalper EA %s\nTrading=%s; %s\nM1 RSI=%.1f M5 RSI=%.1f POC=%s Open=%d",
                              g_runtime_symbol,
                              InpEnableTrading ? "ON" : "OFF",
                              signal_status,
                              m1_rsi[1],
                              m5_rsi[1],
                              profile.ready ? PriceText(profile.poc_price) : "n/a",
                              CountOpenPositions()));
  }
//+------------------------------------------------------------------+
