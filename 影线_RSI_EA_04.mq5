//+------------------------------------------------------------------+
//|                                                影线_RSI_EA_04       |
//|   影线长度 + RSI 收盘信号 EA for MetaTrader 5.                     |
//+------------------------------------------------------------------+
#property copyright "2026"
#property link      ""
#property version   "4.00"
#property strict

#include <Trade/Trade.mqh>

input group "基础设置"
input string          交易品种                  = "";          // 留空=当前图表品种
input bool            启用交易                  = true;        // 是否允许真实下单
input double          基础手数                  = 0.01;        // 基准余额对应手数
input bool            启用余额动态手数          = true;        // 余额变化时自动增减手数
input double          手数基准余额              = 0.0;         // 0=EA启动时账户余额
input double          余额阶梯金额              = 100.0;       // 余额每变化多少美金调整一次
input double          手数增减步长              = 0.01;        // 每个余额阶梯增减手数
input double          最小交易手数              = 0.01;        // 动态手数下限
input double          最大交易手数              = 0.0;         // 动态手数上限，0=券商上限
input ulong           魔术编号                  = 2026082104;  // EA 魔术编号
input int             允许滑点_原始点           = 20;          // 最大滑点，按券商原始 point
input double          策略点值覆盖              = 0.0;         // 0=自动；黄金示例可填 0.01
input double          最大点差_策略点           = 0.0;         // 最大点差，0=不限制

input group "信号条件"
input ENUM_TIMEFRAMES 信号K线周期               = PERIOD_M1;   // 检查影线的K线周期
input double          最小影线点数              = 500.0;       // 上/下影线最低点数
input bool            启用RSI过滤               = true;        // true=使用RSI过滤，false=只看影线
input ENUM_TIMEFRAMES RSI时间周期               = PERIOD_M1;   // RSI 所在周期
input int             RSI计算周期               = 14;          // RSI 计算周期
input double          做空RSI大于               = 70.0;        // 上影线信号要求 RSI 大于
input double          做多RSI小于               = 30.0;        // 下影线信号要求 RSI 小于

input group "止损设置"
input bool            启用固定止损              = true;        // 是否启用固定点数止损
input double          固定止损点数              = 300.0;       // 固定止损点数
input bool            启用影线止损              = true;        // 是否启用影线倍数止损
input double          影线止损倍数              = 1.5;         // 信号影线止损倍数

input group "固定止盈"
input bool            启用固定止盈              = true;        // 是否启用固定点数止盈
input double          固定止盈点数              = 1000.0;      // 固定止盈点数

input group "移动止盈"
input bool            启用移动止盈              = true;        // 是否启用移动止盈
input double          移动止盈启动点数          = 500.0;       // 盈利达到多少点启动
input double          移动止盈跟踪距离点数      = 100.0;       // 止损与当前价的跟踪距离
input double          移动止盈步长点数          = 50.0;        // 每次移动止损的最小步长

input group "持仓限制"
input int             同时允许空单数            = 1;           // 同时允许存在的空单数
input int             同时允许多单数            = 1;           // 同时允许存在的多单数

input group "日志"
input bool            输出详细日志              = true;        // 是否输出跳过信号原因

struct WickSignal
{
   bool     valid;
   int      direction;          // 1 = buy, -1 = sell
   datetime bar_time;
   datetime close_time;
   double   open;
   double   high;
   double   low;
   double   close;
   double   upper_wick_points;
   double   lower_wick_points;
   double   rsi;
};

CTrade  g_trade;
string  g_symbol = "";
double  g_strategy_point = 0.0;
int     g_digits = 0;
int     g_rsi_handle = INVALID_HANDLE;
datetime g_last_scanned_bar_time = 0;
double  g_lot_base_balance = 0.0;

//+------------------------------------------------------------------+
//| Basic helpers                                                     |
//+------------------------------------------------------------------+
ENUM_TIMEFRAMES SignalTimeframe()
{
   if(信号K线周期 == PERIOD_CURRENT)
      return (ENUM_TIMEFRAMES)_Period;
   return 信号K线周期;
}

ENUM_TIMEFRAMES RsiTimeframe()
{
   if(RSI时间周期 == PERIOD_CURRENT)
      return (ENUM_TIMEFRAMES)_Period;
   return RSI时间周期;
}

int TimeframeSeconds(const ENUM_TIMEFRAMES timeframe)
{
   int seconds = PeriodSeconds(timeframe);
   if(seconds <= 0)
      seconds = PeriodSeconds((ENUM_TIMEFRAMES)_Period);
   return seconds;
}

double RawPoint()
{
   double point = 0.0;
   if(!SymbolInfoDouble(g_symbol, SYMBOL_POINT, point) || point <= 0.0)
      point = _Point;
   return point;
}

double CalculateStrategyPoint()
{
   if(策略点值覆盖 > 0.0)
      return 策略点值覆盖;

   const double raw_point = RawPoint();
   const int digits = (int)SymbolInfoInteger(g_symbol, SYMBOL_DIGITS);

   if(digits == 3 || digits == 5)
      return raw_point * 10.0;

   return raw_point;
}

double PointsToPrice(const double points)
{
   return points * g_strategy_point;
}

double PriceToPoints(const double price_distance)
{
   if(g_strategy_point <= 0.0)
      return 0.0;
   return price_distance / g_strategy_point;
}

double NormalizePrice(const double price)
{
   return NormalizeDouble(price, g_digits);
}

string DirectionText(const int direction)
{
   if(direction > 0)
      return "BUY";
   if(direction < 0)
      return "SELL";
   return "NONE";
}

void ResetSignal(WickSignal &signal)
{
   signal.valid = false;
   signal.direction = 0;
   signal.bar_time = 0;
   signal.close_time = 0;
   signal.open = 0.0;
   signal.high = 0.0;
   signal.low = 0.0;
   signal.close = 0.0;
   signal.upper_wick_points = 0.0;
   signal.lower_wick_points = 0.0;
   signal.rsi = 0.0;
}

void LogVerbose(const string text)
{
   if(输出详细日志)
      Print(text);
}

bool GetBidAsk(double &bid, double &ask)
{
   MqlTick tick;
   if(!SymbolInfoTick(g_symbol, tick))
      return false;

   bid = tick.bid;
   ask = tick.ask;
   return (bid > 0.0 && ask > 0.0 && ask >= bid);
}

bool SpreadAllows()
{
   if(最大点差_策略点 <= 0.0)
      return true;

   double bid = 0.0;
   double ask = 0.0;
   if(!GetBidAsk(bid, ask))
      return false;

   const double spread_points = PriceToPoints(ask - bid);
   if(spread_points > 最大点差_策略点)
   {
      LogVerbose(StringFormat("Signal waits: spread %.1f > max %.1f strategy points",
                              spread_points,
                              最大点差_策略点));
      return false;
   }

   return true;
}

//+------------------------------------------------------------------+
//| Volume and position helpers                                       |
//+------------------------------------------------------------------+
int VolumeDigits(const double step)
{
   if(step <= 0.0)
      return 2;

   double value = step;
   int digits = 0;
   while(value < 1.0 && digits < 8)
   {
      value *= 10.0;
      digits++;
   }
   return digits;
}

double NormalizeVolume(const double requested_volume)
{
   double min_volume = SymbolInfoDouble(g_symbol, SYMBOL_VOLUME_MIN);
   double max_volume = SymbolInfoDouble(g_symbol, SYMBOL_VOLUME_MAX);
   double step_volume = SymbolInfoDouble(g_symbol, SYMBOL_VOLUME_STEP);

   if(min_volume <= 0.0 || max_volume <= 0.0 || step_volume <= 0.0)
      return requested_volume;

   double volume = MathMax(min_volume, MathMin(max_volume, requested_volume));
   double steps = MathFloor((volume - min_volume) / step_volume + 0.0000001);
   volume = min_volume + steps * step_volume;
   volume = MathMax(min_volume, MathMin(max_volume, volume));

   return NormalizeDouble(volume, VolumeDigits(step_volume));
}

double CalculateOrderLots()
{
   double requested_lots = 基础手数;

   if(启用余额动态手数 && 余额阶梯金额 > 0.0 && 手数增减步长 > 0.0)
   {
      const double balance = AccountInfoDouble(ACCOUNT_BALANCE);
      const double diff = balance - g_lot_base_balance;
      const int balance_steps = (int)MathFloor(MathAbs(diff) / 余额阶梯金额);
      const double lot_delta = (double)balance_steps * 手数增减步长;

      if(diff >= 0.0)
         requested_lots = 基础手数 + lot_delta;
      else
         requested_lots = 基础手数 - lot_delta;
   }

   double broker_min = SymbolInfoDouble(g_symbol, SYMBOL_VOLUME_MIN);
   double broker_max = SymbolInfoDouble(g_symbol, SYMBOL_VOLUME_MAX);
   if(broker_min <= 0.0)
      broker_min = 0.01;
   if(broker_max <= 0.0)
      broker_max = 100.0;

   const double min_allowed = MathMax(最小交易手数, broker_min);
   const double max_allowed = (最大交易手数 > 0.0 ? MathMin(最大交易手数, broker_max) : broker_max);

   requested_lots = MathMax(min_allowed, requested_lots);
   requested_lots = MathMin(max_allowed, requested_lots);

   return NormalizeVolume(requested_lots);
}

int CountEaPositions(const int direction)
{
   int count = 0;

   for(int i = PositionsTotal() - 1; i >= 0; --i)
   {
      const ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;

      if(PositionGetString(POSITION_SYMBOL) != g_symbol)
         continue;

      if((ulong)PositionGetInteger(POSITION_MAGIC) != 魔术编号)
         continue;

      const long type = PositionGetInteger(POSITION_TYPE);
      const int position_direction = (type == POSITION_TYPE_BUY ? 1 : -1);

      if(direction == 0 || position_direction == direction)
         count++;
   }

   return count;
}

bool PositionLimitAllows(const int direction)
{
   if(direction > 0)
   {
      if(同时允许多单数 < 0)
         return true;
      return CountEaPositions(1) < 同时允许多单数;
   }

   if(direction < 0)
   {
      if(同时允许空单数 < 0)
         return true;
      return CountEaPositions(-1) < 同时允许空单数;
   }

   return false;
}

//+------------------------------------------------------------------+
//| Stop and target helpers                                           |
//+------------------------------------------------------------------+
double BrokerMinStopDistance()
{
   const long stops_level = SymbolInfoInteger(g_symbol, SYMBOL_TRADE_STOPS_LEVEL);
   return MathMax((double)stops_level, 0.0) * RawPoint();
}

void AdjustInitialStopsToBrokerRules(const int direction, double &sl, double &tp)
{
   double bid = 0.0;
   double ask = 0.0;
   if(!GetBidAsk(bid, ask))
      return;

   const double min_distance = BrokerMinStopDistance();
   if(min_distance <= 0.0)
   {
      if(sl > 0.0)
         sl = NormalizePrice(sl);
      if(tp > 0.0)
         tp = NormalizePrice(tp);
      return;
   }

   if(direction > 0)
   {
      if(sl > 0.0)
         sl = MathMin(sl, bid - min_distance);
      if(tp > 0.0)
         tp = MathMax(tp, bid + min_distance);
   }
   else
   {
      if(sl > 0.0)
         sl = MathMax(sl, ask + min_distance);
      if(tp > 0.0)
         tp = MathMin(tp, ask - min_distance);
   }

   if(sl > 0.0)
      sl = NormalizePrice(sl);
   if(tp > 0.0)
      tp = NormalizePrice(tp);
}

bool BuildInitialStopDistancePoints(const WickSignal &signal, double &stop_points, string &mode_text)
{
   bool has_candidate = false;
   double best_points = 0.0;
   string best_mode = "";

   if(启用固定止损 && 固定止损点数 > 0.0)
   {
      best_points = 固定止损点数;
      best_mode = "fixed";
      has_candidate = true;
   }

   if(启用影线止损 && 影线止损倍数 > 0.0)
   {
      const double wick_points = (signal.direction > 0 ?
                                  signal.lower_wick_points :
                                  signal.upper_wick_points);
      const double wick_stop_points = wick_points * 影线止损倍数;
      if(wick_stop_points > 0.0 && (!has_candidate || wick_stop_points < best_points))
      {
         best_points = wick_stop_points;
         best_mode = "wick";
         has_candidate = true;
      }
   }

   if(!has_candidate)
      return false;

   stop_points = best_points;
   mode_text = best_mode;
   return true;
}

bool BuildOrderPrices(const WickSignal &signal, const double entry,
                      double &sl, double &tp, string &stop_mode_text)
{
   double stop_points = 0.0;
   if(!BuildInitialStopDistancePoints(signal, stop_points, stop_mode_text))
      return false;

   if(signal.direction > 0)
      sl = entry - PointsToPrice(stop_points);
   else
      sl = entry + PointsToPrice(stop_points);

   if(启用固定止盈 && 固定止盈点数 > 0.0)
   {
      if(signal.direction > 0)
         tp = entry + PointsToPrice(固定止盈点数);
      else
         tp = entry - PointsToPrice(固定止盈点数);
   }
   else
   {
      tp = 0.0;
   }

   AdjustInitialStopsToBrokerRules(signal.direction, sl, tp);
   return (sl > 0.0);
}

bool StopDistanceAllows(const int type, const double candidate_sl)
{
   double bid = 0.0;
   double ask = 0.0;
   if(!GetBidAsk(bid, ask))
      return false;

   const double min_distance = BrokerMinStopDistance();
   if(type == POSITION_TYPE_BUY)
      return (bid - candidate_sl) >= min_distance;

   return (candidate_sl - ask) >= min_distance;
}

bool ImproveStop(const int type, const double current_sl, const double candidate_sl)
{
   const double step = PointsToPrice(移动止盈步长点数);

   if(current_sl <= 0.0)
      return true;

   if(type == POSITION_TYPE_BUY)
      return candidate_sl >= current_sl + step;

   return candidate_sl <= current_sl - step;
}

//+------------------------------------------------------------------+
//| Signal detection                                                  |
//+------------------------------------------------------------------+
bool GetRsiAtSignalClose(const datetime signal_close_time, double &rsi)
{
   const datetime probe_time = signal_close_time - 1;
   int rsi_shift = iBarShift(g_symbol, RsiTimeframe(), probe_time, false);
   if(rsi_shift < 0)
   {
      LogVerbose("Cannot locate RSI bar for signal close time.");
      return false;
   }

   double values[1];
   if(CopyBuffer(g_rsi_handle, 0, rsi_shift, 1, values) != 1)
   {
      LogVerbose(StringFormat("Cannot copy RSI buffer. Error=%d", GetLastError()));
      return false;
   }

   rsi = values[0];
   return (rsi >= 0.0 && rsi <= 100.0);
}

bool BuildSignalFromClosedBar(WickSignal &signal)
{
   ResetSignal(signal);

   MqlRates rates[1];
   const ENUM_TIMEFRAMES timeframe = SignalTimeframe();
   if(CopyRates(g_symbol, timeframe, 1, 1, rates) != 1)
   {
      LogVerbose(StringFormat("Cannot copy closed signal bar. Error=%d", GetLastError()));
      return false;
   }

   const datetime bar_time = rates[0].time;
   if(bar_time <= 0 || bar_time == g_last_scanned_bar_time)
      return false;

   g_last_scanned_bar_time = bar_time;

   const int seconds = TimeframeSeconds(timeframe);
   const datetime close_time = bar_time + seconds;

   double rsi = 50.0;
   if(启用RSI过滤 && !GetRsiAtSignalClose(close_time, rsi))
      return false;

   const double upper_wick = rates[0].high - MathMax(rates[0].open, rates[0].close);
   const double lower_wick = MathMin(rates[0].open, rates[0].close) - rates[0].low;
   const double upper_wick_points = MathMax(0.0, PriceToPoints(upper_wick));
   const double lower_wick_points = MathMax(0.0, PriceToPoints(lower_wick));

   const bool upper_ok = (upper_wick_points >= 最小影线点数);
   const bool lower_ok = (lower_wick_points >= 最小影线点数);

   int direction = 0;
   if(启用RSI过滤)
   {
      if(upper_ok && rsi > 做空RSI大于)
         direction = -1;
      else if(lower_ok && rsi < 做多RSI小于)
         direction = 1;
   }
   else
   {
      if(upper_ok && lower_ok)
      {
         if(upper_wick_points > lower_wick_points)
            direction = -1;
         else if(lower_wick_points > upper_wick_points)
            direction = 1;
      }
      else if(upper_ok)
         direction = -1;
      else if(lower_ok)
         direction = 1;
   }

   if(direction == 0)
   {
      LogVerbose(StringFormat("No signal on %s: upper=%.1f lower=%.1f RSI=%.2f rsi_filter=%s",
                              TimeToString(bar_time),
                              upper_wick_points,
                              lower_wick_points,
                              rsi,
                              启用RSI过滤 ? "true" : "false"));
      return false;
   }

   signal.valid = true;
   signal.direction = direction;
   signal.bar_time = bar_time;
   signal.close_time = close_time;
   signal.open = rates[0].open;
   signal.high = rates[0].high;
   signal.low = rates[0].low;
   signal.close = rates[0].close;
   signal.upper_wick_points = upper_wick_points;
   signal.lower_wick_points = lower_wick_points;
   signal.rsi = rsi;

   return true;
}

//+------------------------------------------------------------------+
//| Order execution                                                   |
//+------------------------------------------------------------------+
bool TradeEnvironmentAllows()
{
   const bool is_tester = (bool)MQLInfoInteger(MQL_TESTER);
   if(is_tester)
      return true;

   if(!TerminalInfoInteger(TERMINAL_CONNECTED))
   {
      LogVerbose("Signal waits: terminal is not connected.");
      return false;
   }

   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED))
   {
      LogVerbose("Signal waits: terminal trading is not allowed.");
      return false;
   }

   if(!MQLInfoInteger(MQL_TRADE_ALLOWED))
   {
      LogVerbose("Signal waits: EA trading is not allowed.");
      return false;
   }

   return true;
}

bool ExecuteSignalNow(const WickSignal &signal)
{
   if(!signal.valid)
      return false;

   if(!启用交易)
   {
      Print("Signal skipped because 启用交易=false.");
      return false;
   }

   if(!TradeEnvironmentAllows() || !SpreadAllows())
      return false;

   if(!PositionLimitAllows(signal.direction))
   {
      PrintFormat("%s signal skipped: position limit reached. buys=%d/%d sells=%d/%d",
                  DirectionText(signal.direction),
                  CountEaPositions(1),
                  同时允许多单数,
                  CountEaPositions(-1),
                  同时允许空单数);
      return false;
   }

   double bid = 0.0;
   double ask = 0.0;
   if(!GetBidAsk(bid, ask))
      return false;

   const double entry = (signal.direction > 0 ? ask : bid);
   double sl = 0.0;
   double tp = 0.0;
   string stop_mode_text = "";

   if(!BuildOrderPrices(signal, entry, sl, tp, stop_mode_text))
   {
      Print("Signal skipped: cannot build initial stop loss.");
      return false;
   }

   const double lots = CalculateOrderLots();
   if(lots <= 0.0)
   {
      Print("Signal skipped: normalized lot size <= 0.");
      return false;
   }

   const string comment = StringFormat("影线_RSI_04 %s", DirectionText(signal.direction));
   bool sent = false;
   ResetLastError();

   if(signal.direction > 0)
      sent = g_trade.Buy(lots, g_symbol, 0.0, sl, tp, comment);
   else
      sent = g_trade.Sell(lots, g_symbol, 0.0, sl, tp, comment);

   if(sent)
   {
      PrintFormat("%s opened lots=%.2f balance=%.2f base_balance=%.2f entry~%.*f SL=%.*f TP=%.*f SLMode=%s signal_bar=%s upper=%.1f lower=%.1f RSI=%.2f",
                  DirectionText(signal.direction),
                  lots,
                  AccountInfoDouble(ACCOUNT_BALANCE),
                  g_lot_base_balance,
                  g_digits,
                  NormalizePrice(entry),
                  g_digits,
                  sl,
                  g_digits,
                  tp,
                  stop_mode_text,
                  TimeToString(signal.bar_time, TIME_DATE | TIME_SECONDS),
                  signal.upper_wick_points,
                  signal.lower_wick_points,
                  signal.rsi);
      return true;
   }

   PrintFormat("%s order failed. retcode=%u %s last_error=%d",
               DirectionText(signal.direction),
               g_trade.ResultRetcode(),
               g_trade.ResultRetcodeDescription(),
               GetLastError());
   return false;
}

//+------------------------------------------------------------------+
//| Trailing management                                               |
//+------------------------------------------------------------------+
void ManageTrailingStops()
{
   if(!启用移动止盈)
      return;

   double bid = 0.0;
   double ask = 0.0;
   if(!GetBidAsk(bid, ask))
      return;

   for(int i = PositionsTotal() - 1; i >= 0; --i)
   {
      const ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;

      if(PositionGetString(POSITION_SYMBOL) != g_symbol)
         continue;

      if((ulong)PositionGetInteger(POSITION_MAGIC) != 魔术编号)
         continue;

      const int type = (int)PositionGetInteger(POSITION_TYPE);
      const double open_price = PositionGetDouble(POSITION_PRICE_OPEN);
      const double current_sl = PositionGetDouble(POSITION_SL);
      const double current_tp = PositionGetDouble(POSITION_TP);
      const double current_price = (type == POSITION_TYPE_BUY ? bid : ask);
      const double profit_points = (type == POSITION_TYPE_BUY ?
                                    PriceToPoints(current_price - open_price) :
                                    PriceToPoints(open_price - current_price));

      if(profit_points < 移动止盈启动点数)
         continue;

      double candidate_sl = 0.0;
      if(type == POSITION_TYPE_BUY)
         candidate_sl = current_price - PointsToPrice(移动止盈跟踪距离点数);
      else
         candidate_sl = current_price + PointsToPrice(移动止盈跟踪距离点数);

      candidate_sl = NormalizePrice(candidate_sl);

      if(!ImproveStop(type, current_sl, candidate_sl))
         continue;

      if(!StopDistanceAllows(type, candidate_sl))
         continue;

      if(!g_trade.PositionModify(ticket, candidate_sl, current_tp))
      {
         PrintFormat("Trailing modify failed ticket=%I64u retcode=%u %s",
                     ticket,
                     g_trade.ResultRetcode(),
                     g_trade.ResultRetcodeDescription());
         continue;
      }

      PrintFormat("Trailing SL updated ticket=%I64u %s SL=%.*f profit=%.1f points",
                  ticket,
                  (type == POSITION_TYPE_BUY ? "BUY" : "SELL"),
                  g_digits,
                  candidate_sl,
                  profit_points);
   }
}

//+------------------------------------------------------------------+
//| Processing loop                                                   |
//+------------------------------------------------------------------+
void ProcessEa()
{
   ManageTrailingStops();

   WickSignal signal;
   if(BuildSignalFromClosedBar(signal))
      ExecuteSignalNow(signal);
}

//+------------------------------------------------------------------+
//| Expert lifecycle                                                  |
//+------------------------------------------------------------------+
int OnInit()
{
   g_symbol = 交易品种;
   if(g_symbol == "")
      g_symbol = _Symbol;

   if(!SymbolSelect(g_symbol, true))
   {
      Print("Cannot select trade symbol: ", g_symbol);
      return INIT_FAILED;
   }

   g_digits = (int)SymbolInfoInteger(g_symbol, SYMBOL_DIGITS);
   g_strategy_point = CalculateStrategyPoint();

   if(g_strategy_point <= 0.0)
   {
      Print("Invalid strategy point size.");
      return INIT_PARAMETERS_INCORRECT;
   }

   g_lot_base_balance = (手数基准余额 > 0.0 ? 手数基准余额 : AccountInfoDouble(ACCOUNT_BALANCE));

   if(基础手数 <= 0.0 ||
      最小交易手数 <= 0.0 ||
      最大交易手数 < 0.0 ||
      (最大交易手数 > 0.0 && 最大交易手数 < 最小交易手数) ||
      (启用余额动态手数 && (余额阶梯金额 <= 0.0 || 手数增减步长 <= 0.0 || g_lot_base_balance <= 0.0)) ||
      最小影线点数 <= 0.0 ||
      做多RSI小于 < 0.0 ||
      做空RSI大于 > 100.0 ||
      做多RSI小于 >= 做空RSI大于 ||
      同时允许多单数 < -1 ||
      同时允许空单数 < -1)
   {
      Print("Invalid general or signal parameters.");
      return INIT_PARAMETERS_INCORRECT;
   }

   if(启用RSI过滤 && RSI计算周期 < 1)
   {
      Print("Invalid RSI parameters.");
      return INIT_PARAMETERS_INCORRECT;
   }

   if((!启用固定止损 && !启用影线止损) ||
      (启用固定止损 && 固定止损点数 <= 0.0) ||
      (启用影线止损 && 影线止损倍数 <= 0.0))
   {
      Print("Invalid stop loss parameters.");
      return INIT_PARAMETERS_INCORRECT;
   }

   if(启用固定止盈 && 固定止盈点数 <= 0.0)
   {
      Print("Invalid fixed take profit parameters.");
      return INIT_PARAMETERS_INCORRECT;
   }

   if(启用移动止盈 &&
      (移动止盈启动点数 <= 0.0 ||
       移动止盈跟踪距离点数 <= 0.0 ||
       移动止盈步长点数 <= 0.0))
   {
      Print("Invalid trailing parameters.");
      return INIT_PARAMETERS_INCORRECT;
   }

   if(启用RSI过滤)
   {
      g_rsi_handle = iRSI(g_symbol, RsiTimeframe(), RSI计算周期, PRICE_CLOSE);
      if(g_rsi_handle == INVALID_HANDLE)
      {
         PrintFormat("Cannot create RSI handle. Error=%d", GetLastError());
         return INIT_FAILED;
      }
   }

   g_trade.SetExpertMagicNumber(魔术编号);
   g_trade.SetDeviationInPoints(允许滑点_原始点);
   g_trade.SetTypeFillingBySymbol(g_symbol);

   g_last_scanned_bar_time = iTime(g_symbol, SignalTimeframe(), 1);

   PrintFormat("影线_RSI_EA_04 initialized: symbol=%s signal_tf=%s rsi_filter=%s rsi_tf=%s rsi_period=%d base_lots=%.2f lot_base_balance=%.2f balance_step=%.2f lot_step=%.2f strategy_point=%.*f magic=%I64u tester=%s",
               g_symbol,
               EnumToString(SignalTimeframe()),
               启用RSI过滤 ? "true" : "false",
               EnumToString(RsiTimeframe()),
               RSI计算周期,
               基础手数,
               g_lot_base_balance,
               余额阶梯金额,
               手数增减步长,
               g_digits,
               g_strategy_point,
               魔术编号,
               MQLInfoInteger(MQL_TESTER) ? "true" : "false");

   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   if(g_rsi_handle != INVALID_HANDLE)
      IndicatorRelease(g_rsi_handle);

   PrintFormat("影线_RSI_EA_04 deinitialized. reason=%d", reason);
}

void OnTick()
{
   ProcessEa();
}

