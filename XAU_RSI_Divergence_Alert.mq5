//+------------------------------------------------------------------+
//|                                        XAU_RSI_Divergence_Alert.mq5
//|                         MT5 黄金短线 RSI 背离量能预警指标
//+------------------------------------------------------------------+
#property strict
#property version   "1.00"
#property description "XAUUSD M1+M5 RSI divergence, volume and key-level alert indicator"
#property indicator_chart_window
#property indicator_plots 0

input string  InpSymbol                = "XAUUSD"; // 品种
input int     InpRsiPeriod             = 13;       // RSI周期
input double  InpRsiBuyLevel           = 33.0;     // RSI买入阈值
input double  InpRsiSellLevel          = 67.0;     // RSI卖出阈值
input int     InpPivotDepth            = 3;        // 背离确认深度
input int     InpDivergenceWindow      = 12;       // 背离有效窗口（M1根数）
input int     InpMinPriceGapPoints     = 20;       // 两个拐点最小价差（点）
input double  InpMinRsiGap             = 1.0;      // 两个拐点最小RSI差
input int     InpHistoryBars           = 600;      // 历史取样K线
input int     InpVolumePeriod          = 20;       // 均量周期
input double  InpVolumeSpikeMultiplier = 1.5;      // 放量倍数
input double  InpVolumeShrinkRatio     = 0.8;      // 缩量比例
input int     InpClusterLookbackBars   = 240;      // 关键位聚类回看
input int     InpClusterDistancePoints = 80;       // 关键位聚类距离（点）
input int     InpTouchBufferPoints     = 40;       // 触碰缓冲（点）
input int     InpBreakBufferPoints     = 10;       // 突破缓冲（点）
input int     InpM5RsiBiasLevel        = 50;       // M5方向过滤阈值
input bool    InpUseM5Filter           = true;     // 开启M5过滤
input bool    InpUsePushNotification    = true;     // 手机推送
input bool    InpUsePopupAlert          = true;     // 弹窗提醒
input bool    InpShowChartLabel         = true;     // 图上状态条
input color   InpBuyArrowColor         = clrLimeGreen;
input color   InpSellArrowColor        = clrTomato;
input color   InpSupportColor          = clrSeaGreen;
input color   InpResistanceColor       = clrIndianRed;
input int     InpArrowCodeBuy          = 233;      // 上箭头
input int     InpArrowCodeSell         = 234;      // 下箭头

struct LevelCluster
  {
   double   price;
   int      touches;
   datetime last_time;
  };

int      g_m1_rsi_handle = INVALID_HANDLE;
int      g_m5_rsi_handle = INVALID_HANDLE;
datetime g_last_m1_closed_bar = 0;
bool     g_ready = false;
bool     g_history_drawn = false;
string   g_runtime_symbol = "";
string   g_status_name = "XAU_RSI_DIV_STATUS";
string   g_support_name = "XAU_RSI_DIV_SUPPORT";
string   g_resistance_name = "XAU_RSI_DIV_RESISTANCE";

//+------------------------------------------------------------------+
//| Basic helpers                                                    |
//+------------------------------------------------------------------+
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

void EnsureStatusLabel()
  {
   if(!InpShowChartLabel)
      return;

   if(ObjectFind(0, g_status_name) >= 0)
      return;

   if(!ObjectCreate(0, g_status_name, OBJ_LABEL, 0, 0, 0))
      return;

   ObjectSetInteger(0, g_status_name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, g_status_name, OBJPROP_XDISTANCE, 10);
   ObjectSetInteger(0, g_status_name, OBJPROP_YDISTANCE, 12);
   ObjectSetInteger(0, g_status_name, OBJPROP_FONTSIZE, 10);
   ObjectSetString(0, g_status_name, OBJPROP_FONT, "Microsoft YaHei");
   ObjectSetInteger(0, g_status_name, OBJPROP_COLOR, clrWhite);
   ObjectSetInteger(0, g_status_name, OBJPROP_BACK, false);
   ObjectSetInteger(0, g_status_name, OBJPROP_SELECTABLE, false);
  }

void SetStatusText(const string text)
  {
   if(InpShowChartLabel)
     {
      EnsureStatusLabel();
      ObjectSetString(0, g_status_name, OBJPROP_TEXT, text);
     }
   Comment(text);
   ChartRedraw(0);
  }

string TimeframeName(const ENUM_TIMEFRAMES tf)
  {
   switch(tf)
     {
      case PERIOD_M1:  return "M1";
      case PERIOD_M5:  return "M5";
      case PERIOD_M15: return "M15";
      case PERIOD_M30: return "M30";
      case PERIOD_H1:  return "H1";
      default:         return IntegerToString((int)tf);
     }
  }

void DrawOrUpdateHLine(const string name, const double price, const color clr)
  {
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
     }

   ObjectSetDouble(0, name, OBJPROP_PRICE, price);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_SOLID);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
  }

void DrawSignalArrow(const datetime bar_time,
                     const double price,
                     const bool is_buy,
                     const string text)
  {
   string name = StringFormat("XAU_RSI_DIV_%s_%I64d", is_buy ? "BUY" : "SELL", (long)bar_time);
   if(ObjectFind(0, name) >= 0)
      return;

   if(!ObjectCreate(0, name, OBJ_ARROW, 0, bar_time, price))
      return;

   ObjectSetInteger(0, name, OBJPROP_ARROWCODE, is_buy ? InpArrowCodeBuy : InpArrowCodeSell);
   ObjectSetInteger(0, name, OBJPROP_COLOR, is_buy ? InpBuyArrowColor : InpSellArrowColor);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);

   string text_name = name + "_TEXT";
   if(ObjectCreate(0, text_name, OBJ_TEXT, 0, bar_time, price))
     {
      ObjectSetString(0, text_name, OBJPROP_TEXT, text);
      ObjectSetString(0, text_name, OBJPROP_FONT, "Microsoft YaHei");
      ObjectSetInteger(0, text_name, OBJPROP_FONTSIZE, 9);
      ObjectSetInteger(0, text_name, OBJPROP_COLOR, is_buy ? InpBuyArrowColor : InpSellArrowColor);
      ObjectSetInteger(0, text_name, OBJPROP_ANCHOR, ANCHOR_LEFT_UPPER);
      ObjectSetInteger(0, text_name, OBJPROP_SELECTABLE, false);
     }
  }

//+------------------------------------------------------------------+
//| Data loading                                                     |
//+------------------------------------------------------------------+
bool CopyRatesSeries(const string symbol, const ENUM_TIMEFRAMES tf, const int bars, MqlRates &rates[])
  {
   ArraySetAsSeries(rates, true);
   int copied = CopyRates(symbol, tf, 0, bars, rates);
   return(copied > InpPivotDepth + 5);
  }

bool CopyRsiSeries(const int handle, const int bars, double &values[])
  {
   ArraySetAsSeries(values, true);
   int copied = CopyBuffer(handle, 0, 0, bars, values);
   return(copied > InpPivotDepth + 5);
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

   return(support > 0.0 || resistance > 0.0);
  }

bool BuildKeyLevelsAtShift(const MqlRates &rates[], const int current_shift, double &support, double &resistance)
  {
   support = 0.0;
   resistance = 0.0;

   LevelCluster support_clusters[];
   LevelCluster resistance_clusters[];
   ArrayResize(support_clusters, 0);
   ArrayResize(resistance_clusters, 0);

   double max_distance = InpClusterDistancePoints * SymbolPoint();
   int start = current_shift + InpPivotDepth + 1;
   int limit = MathMin(ArraySize(rates) - InpPivotDepth - 1, current_shift + InpClusterLookbackBars);
   for(int i = start; i <= limit; i++)
     {
      if(IsPivotLow(rates, i, InpPivotDepth))
         AddCluster(support_clusters, rates[i].low, rates[i].time, max_distance);
      if(IsPivotHigh(rates, i, InpPivotDepth))
         AddCluster(resistance_clusters, rates[i].high, rates[i].time, max_distance);
     }

   double current = rates[current_shift].close;
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

   return(support > 0.0 || resistance > 0.0);
  }

bool FindRecentPivotsAt(const MqlRates &rates[],
                        const int current_shift,
                        const bool search_lows,
                        const int depth,
                        const int lookback,
                        int &newer_index,
                        int &older_index)
  {
   newer_index = -1;
   older_index = -1;

   int start = current_shift + depth + 1;
   int limit = MathMin(ArraySize(rates) - depth - 1, current_shift + lookback);
   for(int i = start; i <= limit; i++)
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

   return(count > 0 ? (double)sum / count : 0.0);
  }

bool M5BullishFilter(const double &m5_rsi[])
  {
   return(ArraySize(m5_rsi) >= 3 && m5_rsi[1] >= InpM5RsiBiasLevel && m5_rsi[1] >= m5_rsi[2]);
  }

bool M5BearishFilter(const double &m5_rsi[])
  {
   return(ArraySize(m5_rsi) >= 3 && m5_rsi[1] <= InpM5RsiBiasLevel && m5_rsi[1] <= m5_rsi[2]);
  }

bool GetM5RsiByTime(const datetime bar_time, double &value)
  {
   int shift = iBarShift(g_runtime_symbol, PERIOD_M5, bar_time, true);
   if(shift < 0)
      return false;

   double tmp[];
   ArraySetAsSeries(tmp, true);
   if(CopyBuffer(g_m5_rsi_handle, 0, shift, 1, tmp) != 1)
      return false;

   value = tmp[0];
   return true;
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
   double open1  = rates[1].open;
   double low1   = rates[1].low;
   double vol1   = (double)rates[1].tick_volume;
   double point  = SymbolPoint();

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
      reason = "放量突破";
      return true;
     }
   if(pullback_rebound)
     {
      reason = "缩量回踩";
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
   double open1  = rates[1].open;
   double high1  = rates[1].high;
   double vol1   = (double)rates[1].tick_volume;
   double point  = SymbolPoint();

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
      reason = "放量突破";
      return true;
     }
   if(pullback_reject)
     {
      reason = "缩量回踩";
      return true;
     }
   return false;
  }

bool BullishContextAtShift(const MqlRates &rates[], const int current_shift, const double support, const double resistance, string &reason)
  {
   reason = "";

   double avg = AverageTickVolume(rates, current_shift, InpVolumePeriod);
   if(avg <= 0.0)
      return false;

   double close1 = rates[current_shift].close;
   double open1  = rates[current_shift].open;
   double low1   = rates[current_shift].low;
   double vol1   = (double)rates[current_shift].tick_volume;
   double point  = SymbolPoint();

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
      reason = "放量突破";
      return true;
     }
   if(pullback_rebound)
     {
      reason = "缩量回踩";
      return true;
     }
   return false;
  }

bool BearishContextAtShift(const MqlRates &rates[], const int current_shift, const double support, const double resistance, string &reason)
  {
   reason = "";

   double avg = AverageTickVolume(rates, current_shift, InpVolumePeriod);
   if(avg <= 0.0)
      return false;

   double close1 = rates[current_shift].close;
   double open1  = rates[current_shift].open;
   double high1  = rates[current_shift].high;
   double vol1   = (double)rates[current_shift].tick_volume;
   double point  = SymbolPoint();

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
      reason = "放量突破";
      return true;
     }
   if(pullback_reject)
     {
      reason = "缩量回踩";
      return true;
     }
   return false;
  }

bool EvaluateHistoricalSignalAtShift(const MqlRates &m1_rates[],
                                     const double &m1_rsi[],
                                     const int current_shift,
                                     const double m5_rsi_value,
                                     const bool use_m5_filter,
                                     bool &is_buy,
                                     string &reason,
                                     double &signal_price)
  {
   is_buy = false;
   reason = "";
   signal_price = 0.0;

   if(current_shift <= InpPivotDepth + 1)
      return false;
   if(current_shift + InpPivotDepth + 1 >= ArraySize(m1_rates))
      return false;

   int bull_newer = -1;
   int bull_older = -1;
   int bear_newer = -1;
   int bear_older = -1;
   bool bullish_div = FindRecentPivotsAt(m1_rates, current_shift, true, InpPivotDepth, InpClusterLookbackBars, bull_newer, bull_older);
   bool bearish_div = FindRecentPivotsAt(m1_rates, current_shift, false, InpPivotDepth, InpClusterLookbackBars, bear_newer, bear_older);

   double support = 0.0;
   double resistance = 0.0;
   BuildKeyLevelsAtShift(m1_rates, current_shift, support, resistance);

   string buy_reason = "";
   string sell_reason = "";
   bool buy_context = BullishContextAtShift(m1_rates, current_shift, support, resistance, buy_reason);
   bool sell_context = BearishContextAtShift(m1_rates, current_shift, support, resistance, sell_reason);

   bool m5_buy_ok = true;
   bool m5_sell_ok = true;
   if(use_m5_filter)
     {
      m5_buy_ok = (m5_rsi_value >= InpM5RsiBiasLevel);
      m5_sell_ok = (m5_rsi_value <= InpM5RsiBiasLevel);
     }

   if(bullish_div && m1_rsi[bull_newer] <= InpRsiBuyLevel && m5_buy_ok && buy_context)
     {
      is_buy = true;
      reason = buy_reason;
      signal_price = m1_rates[current_shift].low - 12 * SymbolPoint();
      return true;
     }

   if(bearish_div && m1_rsi[bear_newer] >= InpRsiSellLevel && m5_sell_ok && sell_context)
     {
      is_buy = false;
      reason = sell_reason;
      signal_price = m1_rates[current_shift].high + 12 * SymbolPoint();
      return true;
     }

   return false;
  }

void BackfillHistorySignals(const MqlRates &m1_rates[], const double &m1_rsi[])
  {
   int max_shift = MathMin(ArraySize(m1_rates) - InpPivotDepth - 2, InpClusterLookbackBars);
   int min_shift = InpPivotDepth + 2;
   int drawn = 0;

   for(int shift = max_shift; shift >= min_shift; shift--)
     {
      double m5_value = 50.0;
      if(!GetM5RsiByTime(m1_rates[shift].time, m5_value))
         continue;

      bool is_buy = false;
      string reason = "";
      double price = 0.0;
      if(EvaluateHistoricalSignalAtShift(m1_rates, m1_rsi, shift, m5_value, InpUseM5Filter, is_buy, reason, price))
        {
         DrawSignalArrow(m1_rates[shift].time, price, is_buy, is_buy ? "买入预警" : "卖出预警");
         drawn++;
        }
     }

   if(drawn > 0)
      SetStatusText(StringFormat("历史回放已绘制 %d 个信号，实时等待下一根 M1 收盘", drawn));
   else
      SetStatusText("历史区间未找到信号，实时等待下一根 M1 收盘");
  }

//+------------------------------------------------------------------+
//| UI / alerts                                                      |
//+------------------------------------------------------------------+
void UpdateStatus(const string mode_text,
                  const string signal_text,
                  const double support,
                  const double resistance,
                  const double m1_rsi,
                  const double m5_rsi,
                  const string detail)
  {
   string text = StringFormat(
      "当前模式：%s\n"
      "M1 RSI(%d)：%s\n"
      "M5 RSI(%d)：%s\n"
      "支撑：%s\n"
      "阻力：%s\n"
      "推送：%s  弹窗：%s\n"
      "%s%s",
      mode_text,
      InpRsiPeriod,
      DoubleToString(m1_rsi, 1),
      InpRsiPeriod,
      DoubleToString(m5_rsi, 1),
      support > 0.0 ? DoubleToString(NormalizeSymbolPrice(support), SymbolDigits()) : "无",
      resistance > 0.0 ? DoubleToString(NormalizeSymbolPrice(resistance), SymbolDigits()) : "无",
      InpUsePushNotification ? "开启" : "关闭",
      InpUsePopupAlert ? "开启" : "关闭",
      signal_text,
      detail != "" ? "\n" + detail : "");
   SetStatusText(text);
  }

void NotifySignal(const bool is_buy,
                  const datetime bar_time,
                  const double price,
                  const double m1_rsi,
                  const double m5_rsi,
                  const string reason)
  {
   string dir = is_buy ? "买入" : "卖出";
   double p = NormalizeSymbolPrice(price);
   string message = StringFormat("%s %s预警 | %s | RSI(M1)=%.1f RSI(M5)=%.1f | 价格=%s",
                                 InpSymbol,
                                 dir,
                                 reason,
                                 m1_rsi,
                                 m5_rsi,
                                 DoubleToString(p, SymbolDigits()));

   DrawSignalArrow(bar_time, p, is_buy, dir + "预警");

   if(InpUsePopupAlert)
      Alert(message);
   if(InpUsePushNotification)
      SendNotification(message);

   Print(message);
  }

//+------------------------------------------------------------------+
//| Indicator lifecycle                                              |
//+------------------------------------------------------------------+
int OnInit()
  {
   if(InpRsiPeriod < 2)
      return INIT_PARAMETERS_INCORRECT;

   g_runtime_symbol = InpSymbol;
   if(!SymbolSelect(g_runtime_symbol, true) || !SymbolInfoInteger(g_runtime_symbol, SYMBOL_DIGITS))
      g_runtime_symbol = _Symbol;
   if(!SymbolSelect(g_runtime_symbol, true))
      g_runtime_symbol = _Symbol;

   EnsureStatusLabel();
   SetStatusText("指标已加载，等待首个 M1 收盘...");
   Print("XAU_RSI_Divergence_Alert loaded on ", g_runtime_symbol);

   g_m1_rsi_handle = iRSI(g_runtime_symbol, PERIOD_M1, InpRsiPeriod, PRICE_CLOSE);
   g_m5_rsi_handle = iRSI(g_runtime_symbol, PERIOD_M5, InpRsiPeriod, PRICE_CLOSE);
   if(g_m1_rsi_handle == INVALID_HANDLE || g_m5_rsi_handle == INVALID_HANDLE)
     {
      Print("Failed to create RSI handles.");
      SetStatusText("RSI句柄创建失败，请检查品种名称是否正确");
      return INIT_FAILED;
     }

   IndicatorSetString(INDICATOR_SHORTNAME, "XAU RSI Divergence Alert");
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

//+------------------------------------------------------------------+
//| Main calculation                                                 |
//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
  {
   MqlRates m1_rates[];
   MqlRates m5_rates[];
   double   m1_rsi[];
   double   m5_rsi[];

   int m1_need = MathMax(InpHistoryBars, InpClusterLookbackBars + InpPivotDepth * 4 + InpVolumePeriod + 50);
   int m5_need = MathMax(200, InpClusterLookbackBars / 2 + 50);

   if(!CopyRatesSeries(g_runtime_symbol, PERIOD_M1, m1_need, m1_rates))
     {
      SetStatusText("未能读取 M1 数据，请检查品种名称/图表品种是否匹配");
      return rates_total;
     }
   if(!CopyRatesSeries(g_runtime_symbol, PERIOD_M5, m5_need, m5_rates))
     {
      SetStatusText("未能读取 M5 数据，请检查品种名称/历史数据是否完整");
      return rates_total;
     }
   if(!CopyRsiSeries(g_m1_rsi_handle, ArraySize(m1_rates), m1_rsi))
     {
      SetStatusText("未能读取 M1 RSI 数据");
      return rates_total;
     }
   if(!CopyRsiSeries(g_m5_rsi_handle, ArraySize(m5_rates), m5_rsi))
     {
      SetStatusText("未能读取 M5 RSI 数据");
      return rates_total;
     }

   if(ArraySize(m1_rates) < 50 || ArraySize(m1_rsi) < 50 || ArraySize(m5_rsi) < 10)
      return rates_total;

   double support = 0.0;
   double resistance = 0.0;
   BuildKeyLevels(m1_rates, support, resistance);
   DrawOrUpdateHLine(g_support_name, support, InpSupportColor);
   DrawOrUpdateHLine(g_resistance_name, resistance, InpResistanceColor);

   datetime closed_bar_time = m1_rates[1].time;
   string mode_text = TimeframeName(PERIOD_M1) + " + " + TimeframeName(PERIOD_M5) + " / " + g_runtime_symbol;

   if(!g_ready)
     {
      g_last_m1_closed_bar = closed_bar_time;
      g_ready = true;
      if(!g_history_drawn)
        {
         BackfillHistorySignals(m1_rates, m1_rsi);
         g_history_drawn = true;
        }
      UpdateStatus(mode_text,
                   "历史回放已就绪，实时等待下一根 M1 收盘",
                   support,
                   resistance,
                   m1_rsi[1],
                   m5_rsi[1],
                   "");
      return rates_total;
     }

   if(closed_bar_time == g_last_m1_closed_bar)
     {
      UpdateStatus(mode_text,
                   "等待下一根 M1 收盘",
                   support,
                   resistance,
                   m1_rsi[1],
                   m5_rsi[1],
                   "");
      return rates_total;
     }

   g_last_m1_closed_bar = closed_bar_time;

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

   string signal_text = "暂无信号";
   string detail = "";

   if(bullish_div && m1_rsi[bull_newer] <= InpRsiBuyLevel && m5_buy_ok && buy_context)
     {
      signal_text = "买入预警";
      detail = "普通看涨背离 / " + buy_reason;
      NotifySignal(true, closed_bar_time, m1_rates[1].low - 12 * SymbolPoint(), m1_rsi[1], m5_rsi[1], buy_reason);
      UpdateStatus(mode_text, signal_text, support, resistance, m1_rsi[1], m5_rsi[1], detail);
      return rates_total;
     }

   if(bearish_div && m1_rsi[bear_newer] >= InpRsiSellLevel && m5_sell_ok && sell_context)
     {
      signal_text = "卖出预警";
      detail = "普通看跌背离 / " + sell_reason;
      NotifySignal(false, closed_bar_time, m1_rates[1].high + 12 * SymbolPoint(), m1_rsi[1], m5_rsi[1], sell_reason);
      UpdateStatus(mode_text, signal_text, support, resistance, m1_rsi[1], m5_rsi[1], detail);
      return rates_total;
     }

   if(bullish_div && !m5_buy_ok)
      signal_text = "看涨背离存在，但 M5 未确认";
   else if(bearish_div && !m5_sell_ok)
      signal_text = "看跌背离存在，但 M5 未确认";
   else if(bullish_div || bearish_div)
      signal_text = "背离存在，但未同时满足 RSI / 量能 / 关键位";

   if(bullish_div)
      detail = "看涨背离确认：" + (buy_context ? buy_reason : "未命中");
   else if(bearish_div)
      detail = "看跌背离确认：" + (sell_context ? sell_reason : "未命中");

   UpdateStatus(mode_text, signal_text, support, resistance, m1_rsi[1], m5_rsi[1], detail);
   return rates_total;
  }
//+------------------------------------------------------------------+
