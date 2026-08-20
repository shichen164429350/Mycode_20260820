//+------------------------------------------------------------------+
//|                      Gold_Volume_Profile_RightSide.mq5           |
//|                 Volume profile mapped to the chart right side    |
//+------------------------------------------------------------------+
#property strict
#property indicator_chart_window
#property indicator_plots 0

#include <Canvas\Canvas.mqh>

input ENUM_TIMEFRAMES InpSourceTF = PERIOD_M1;      // Source timeframe
input int            InpLookbackBars = 720;         // Bars to scan
input double         InpRangeUsd = 50.0;            // Show +/- range around current price
input int            InpRows = 32;                  // Price buckets in the range
input int            InpStripWidth = 190;           // Right-side strip width
input int            InpRightGap = 1;               // Gap from chart right edge
input int            InpTopPadding = 14;            // Top padding
input int            InpRowHeight = 10;             // Row height
input int            InpMinRowPixels = 8;           // Minimum vertical spacing between rows
input color          InpBarColor = clrDeepSkyBlue;  // Normal volume bar color
input color          InpPocColor = clrOrange;       // POC bar color
input color          InpCurrentColor = clrTomato;   // Current price bar color
input color          InpTextColor = clrWhite;       // Text color
input color          InpMutedTextColor = clrSilver; // Secondary text color
input bool           InpUseRealVolume = true;       // Prefer real volume when available

string g_prefix = "";
int    g_visible_rows = 0;
string g_canvas_name = "";
bool   g_canvas_ready = false;
CCanvas g_canvas;

struct ProfileRow
  {
   double low;
   double high;
   double volume;
   int    y;
   bool   is_current;
   bool   is_poc;
  };

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

string TfText(const ENUM_TIMEFRAMES tf)
  {
   if(tf == PERIOD_CURRENT)
      return EnumToString((ENUM_TIMEFRAMES)Period());
   return EnumToString(tf);
  }

string PriceText(const double price)
  {
   const int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   return DoubleToString(price, digits);
  }

string VolumeText(const double volume)
  {
   if(volume >= 1000000.0)
      return DoubleToString(volume / 1000000.0, 1) + "M";
   if(volume >= 1000.0)
      return DoubleToString(volume / 1000.0, 1) + "K";
   if(volume >= 100.0)
      return DoubleToString(volume, 1);
   return DoubleToString(volume, 2);
  }

string NameOf(const string suffix)
  {
   return g_prefix + "_" + suffix;
  }

string RowName(const int row, const string suffix)
  {
   return g_prefix + "_r" + IntegerToString(row) + "_" + suffix;
  }

void MakeRectLabel(const string name,
                   const int x,
                   const int y,
                   const int width,
                   const int height,
                   const color bg,
                   const color border,
                   const bool back = false)
  {
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, width);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, height);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, bg);
   ObjectSetInteger(0, name, OBJPROP_COLOR, border);
   ObjectSetInteger(0, name, OBJPROP_BACK, back);
   ObjectSetInteger(0, name, OBJPROP_ZORDER, 200);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
  }

void MakeLabel(const string name,
               const string text,
               const int x,
               const int y,
               const int font_size,
               const color clr,
               const ENUM_ANCHOR_POINT anchor = ANCHOR_LEFT_UPPER)
  {
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, font_size);
   ObjectSetString(0, name, OBJPROP_FONT, "Arial");
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_ANCHOR, anchor);
   ObjectSetInteger(0, name, OBJPROP_ZORDER, 210);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
  }

void DeletePrefixedObjects(const string skip_name = "")
  {
   const int total = ObjectsTotal(0, -1, -1);
   for(int i = total - 1; i >= 0; --i)
     {
      const string name = ObjectName(0, i, -1, -1);
      if(StringFind(name, g_prefix) == 0 && name != skip_name)
         ObjectDelete(0, name);
     }
  }

double RateVolume(const MqlRates &rate)
  {
   double volume = 0.0;
   if(InpUseRealVolume)
      volume = (double)rate.real_volume;
   if(volume <= 0.0)
      volume = (double)rate.tick_volume;
   if(volume <= 0.0)
      volume = 1.0;
   return volume;
  }

bool GetChartMetrics(int &width, int &height, double &price_min, double &price_max)
  {
   long w = 0;
   long h = 0;
   double min_price = 0.0;
   double max_price = 0.0;
   if(!ChartGetInteger(0, CHART_WIDTH_IN_PIXELS, 0, w))
      return false;
   if(!ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS, 0, h))
      return false;
   if(!ChartGetDouble(0, CHART_PRICE_MIN, 0, min_price))
      return false;
   if(!ChartGetDouble(0, CHART_PRICE_MAX, 0, max_price))
      return false;
   if(w <= 0 || h <= 0 || max_price <= min_price)
      return false;
   width = (int)w;
   height = (int)h;
   price_min = min_price;
   price_max = max_price;
   return true;
  }

int PriceToY(const double price,
             const double price_min,
             const double price_max,
             const int chart_height,
             const int top_padding,
             const int bottom_padding)
  {
   const double usable = MathMax(1.0, (double)chart_height - top_padding - bottom_padding);
   const double ratio = ClampDouble((price_max - price) / (price_max - price_min), 0.0, 1.0);
   return top_padding + (int)MathRound(ratio * usable);
  }

bool BuildProfile(MqlRates &rates[],
                  const double current_price,
                  const int desired_rows,
                  double &window_low,
                  double &bucket_step,
                  double &bucket_volumes[],
                  int &bucket_count,
                  int &poc_index)
  {
   const int size = ArraySize(rates);
   if(size <= 0)
      return false;

   const double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   const double half_range = MathMax(InpRangeUsd, point * 100.0);
   window_low = current_price - half_range;
   const double window_high = current_price + half_range;
   bucket_count = ClampInt(desired_rows, 8, 48);
   bucket_step = MathMax((window_high - window_low) / (double)bucket_count, point);

   ArrayResize(bucket_volumes, bucket_count);
   ArrayInitialize(bucket_volumes, 0.0);

   for(int i = 0; i < size; ++i)
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

   poc_index = 0;
   double max_volume = bucket_volumes[0];
   for(int i = 1; i < bucket_count; ++i)
     {
      if(bucket_volumes[i] > max_volume)
        {
         max_volume = bucket_volumes[i];
         poc_index = i;
        }
     }
   return true;
  }

void AddMergedRow(ProfileRow &rows[], const ProfileRow &row)
  {
   const int size = ArraySize(rows);
   ArrayResize(rows, size + 1);
   rows[size] = row;
  }

void BuildMergedRows(const double current_price,
                     const double price_min,
                     const double price_max,
                     const int chart_height,
                     const int top,
                     const int bottom,
                     const double window_low,
                     const double bucket_step,
                     double &bucket_volumes[],
                     const int bucket_count,
                     const int poc_index,
                     ProfileRow &rows[])
  {
   ArrayResize(rows, 0);
   const int min_gap = MathMax(8, InpMinRowPixels);

   for(int idx = bucket_count - 1; idx >= 0; --idx)
     {
      const double row_low = window_low + (double)idx * bucket_step;
      const double row_high = row_low + bucket_step;
      if(row_high < price_min || row_low > price_max)
         continue;

      ProfileRow row;
      row.low = row_low;
      row.high = row_high;
      row.volume = bucket_volumes[idx];
      row.y = PriceToY((row_low + row_high) * 0.5, price_min, price_max, chart_height, top + 26, bottom);
      row.is_current = (current_price >= row_low && current_price < row_high);
      row.is_poc = (idx == poc_index);

      const int size = ArraySize(rows);
      if(size <= 0)
        {
         AddMergedRow(rows, row);
         continue;
        }

      ProfileRow last = rows[size - 1];
      if(MathAbs(row.y - last.y) < min_gap)
        {
         const double merged_volume = last.volume + row.volume;
         last.low = MathMin(last.low, row.low);
         last.high = MathMax(last.high, row.high);
         if(merged_volume > 0.0)
            last.y = (int)MathRound((last.y * last.volume + row.y * row.volume) / merged_volume);
         last.volume = merged_volume;
         last.is_current = last.is_current || row.is_current;
         last.is_poc = last.is_poc || row.is_poc;
         rows[size - 1] = last;
         continue;
        }

      AddMergedRow(rows, row);
     }
  }

double CurrentPrice()
  {
   double price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if(price <= 0.0)
      price = SymbolInfoDouble(_Symbol, SYMBOL_LAST);
   if(price <= 0.0)
      price = iClose(_Symbol, (InpSourceTF == PERIOD_CURRENT ? (ENUM_TIMEFRAMES)Period() : InpSourceTF), 0);
   return price;
  }

bool EnsureCanvas(const int x,
                  const int y,
                  const int width,
                  const int height)
  {
   if(width <= 0 || height <= 0)
      return false;

   if(!g_canvas_ready || g_canvas.Width() != width || g_canvas.Height() != height || ObjectFind(0, g_canvas_name) < 0)
     {
      g_canvas.Destroy();
      if(!g_canvas.CreateBitmapLabel(0, 0, g_canvas_name, x, y, width, height, COLOR_FORMAT_ARGB_NORMALIZE))
         return false;

      ObjectSetInteger(0, g_canvas_name, OBJPROP_BACK, false);
      ObjectSetInteger(0, g_canvas_name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, g_canvas_name, OBJPROP_HIDDEN, true);
      ObjectSetInteger(0, g_canvas_name, OBJPROP_ZORDER, 0);
      g_canvas_ready = true;
     }

   ObjectSetInteger(0, g_canvas_name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, g_canvas_name, OBJPROP_YDISTANCE, y);
   if(g_canvas.Width() != width || g_canvas.Height() != height)
      g_canvas.Resize(width, height);

   return true;
  }

void DrawText(const string text,
              const int x,
              const int y,
              const int size,
              const color clr,
              const uint alignment)
  {
   g_canvas.FontSet("Arial", size, 0, 0);
   g_canvas.TextOut(x, y, text, clr, alignment);
  }

void DrawBadge(const int x,
               const int y,
               const int width,
               const int height,
               const string text,
               const color fill,
               const color border,
               const color text_color)
  {
   g_canvas.FillRectangle(x, y, x + width, y + height, ColorToARGB(fill, 235));
   g_canvas.Rectangle(x, y, x + width, y + height, ColorToARGB(border, 255));
   DrawText(text, x + 8, y + 3, 10, text_color, TA_LEFT | TA_TOP);
  }

void ShowRightPriceMarker(const string name,
                          const datetime time,
                          const double price,
                          const color clr)
  {
   if(!ObjectCreate(0, name, OBJ_ARROW_RIGHT_PRICE, 0, time, price))
      ObjectMove(0, name, 0, time, price);

   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_SOLID);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 2);
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTED, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, name, OBJPROP_ZORDER, 220);
  }

void DrawRowPolygon(const int left_top,
                    const int left_bottom,
                    const int right_edge,
                    const int top_y,
                    const int bottom_y,
                    const color fill_color,
                    const color line_color)
  {
   int x[4];
   int y[4];
   x[0] = right_edge;
   y[0] = top_y;
   x[1] = right_edge;
   y[1] = bottom_y;
   x[2] = left_bottom;
   y[2] = bottom_y;
   x[3] = left_top;
   y[3] = top_y;
   g_canvas.FillPolygon(x, y, ColorToARGB(fill_color, 170));
   g_canvas.PolygonAA(x, y, ColorToARGB(line_color, 230), UINT_MAX);
  }

void DrawProfile()
  {
   int chart_width = 0;
   int chart_height = 0;
   double price_min = 0.0;
   double price_max = 0.0;
   if(!GetChartMetrics(chart_width, chart_height, price_min, price_max))
      return;

   const ENUM_TIMEFRAMES tf = (InpSourceTF == PERIOD_CURRENT ? (ENUM_TIMEFRAMES)Period() : InpSourceTF);
   const int bars_to_copy = MathMax(50, InpLookbackBars);
   MqlRates rates[];
   ArraySetAsSeries(rates, false);
   const int copied = CopyRates(_Symbol, tf, 0, bars_to_copy, rates);
   if(copied <= 0)
      return;

   const double current_price = CurrentPrice();
   if(current_price <= 0.0)
      return;

   const int chart_top = MathMax(8, InpTopPadding);
   const int chart_bottom = 24;
   const int usable_height = MathMax(120, chart_height - chart_top - chart_bottom - 30);
   const int max_rows_by_height = MathMax(8, usable_height / MathMax(8, InpMinRowPixels));
   const int desired_rows = ClampInt(MathMin(InpRows, max_rows_by_height), 8, 48);

   double window_low = 0.0;
   double bucket_step = 0.0;
   double bucket_volumes[];
   int bucket_count = 0;
   int poc_index = 0;
   if(!BuildProfile(rates, current_price, desired_rows, window_low, bucket_step, bucket_volumes, bucket_count, poc_index))
      return;

   const int strip_width = ClampInt(InpStripWidth, 150, 320);
   const int right_gap = ClampInt(InpRightGap, 0, 16);
   const int strip_left = MathMax(0, chart_width - strip_width - right_gap);
   const int canvas_top = MathMax(8, InpTopPadding);
   const int canvas_bottom = 22;
   const int canvas_height = MathMax(120, chart_height - canvas_top - canvas_bottom);
   const int canvas_width = strip_width;
   if(!EnsureCanvas(strip_left, canvas_top, canvas_width, canvas_height))
      return;

   DeletePrefixedObjects(g_canvas_name);
   g_canvas.Erase(ColorToARGB(clrBlack, 0));

   const double half_range = MathMax(InpRangeUsd, SymbolInfoDouble(_Symbol, SYMBOL_POINT) * 100.0);

   double total_volume = 0.0;
   double poc_volume = bucket_volumes[poc_index];
   for(int i = 0; i < bucket_count; ++i)
     {
      total_volume += bucket_volumes[i];
     }

   ProfileRow display_rows[];
   BuildMergedRows(current_price, price_min, price_max, chart_height, chart_top, chart_bottom, window_low, bucket_step, bucket_volumes, bucket_count, poc_index, display_rows);
   const int display_count = ArraySize(display_rows);
   double display_max_volume = 1.0;
   const int right_edge = canvas_width - 4;
   const int left_limit = 4;
   const int max_bar_width = MathMax(70, canvas_width - 24);
   const int min_bar_width = 6;
   const int header_h = 18;
   int row_widths[];
   ArrayResize(row_widths, display_count);
   for(int i = 0; i < display_count; ++i)
     {
      if(display_rows[i].volume > display_max_volume)
         display_max_volume = display_rows[i].volume;
     }

   for(int row = 0; row < display_count; ++row)
     {
      const double volume = display_rows[row].volume;
      const bool is_poc = display_rows[row].is_poc;
      const bool is_current = display_rows[row].is_current;
      const double raw_ratio = volume / display_max_volume;
      const double prev_ratio = (row > 0 ? display_rows[row - 1].volume / display_max_volume : raw_ratio);
      const double next_ratio = (row < display_count - 1 ? display_rows[row + 1].volume / display_max_volume : raw_ratio);
      const double smooth_ratio = MathMax(0.02, (prev_ratio + raw_ratio * 2.0 + next_ratio) / 4.0);

      int bar_width = (int)MathRound((double)min_bar_width + smooth_ratio * (double)(max_bar_width - min_bar_width));
      bar_width = ClampInt(bar_width, min_bar_width, max_bar_width);
      if(is_current)
         bar_width = ClampInt(bar_width + 10, min_bar_width, max_bar_width);
      else if(is_poc)
         bar_width = ClampInt(bar_width + 6, min_bar_width, max_bar_width);
      row_widths[row] = bar_width;
     }

   g_visible_rows = 0;

   g_canvas.FillRectangle(0, 0, canvas_width - 1, canvas_height - 1, ColorToARGB(clrBlack, 10));
   g_canvas.LineVertical(right_edge, 6, canvas_height - 7, ColorToARGB(clrWhite, 72));
   DrawText(StringFormat("%s  %s  |  bars:%d  |  +/-%.1f",
                         _Symbol,
                         TfText(tf),
                         copied,
                         half_range),
            6,
            4,
            8,
            InpTextColor,
            TA_LEFT | TA_TOP);
   DrawText(StringFormat("Total %s  |  POC %s",
                         VolumeText(total_volume),
                         VolumeText(poc_volume)),
            6,
            14,
            7,
            InpMutedTextColor,
            TA_LEFT | TA_TOP);

   const int hi_y = ClampInt(PriceToY(price_max, price_min, price_max, chart_height, chart_top, chart_bottom) - canvas_top, 4, canvas_height - 26);
   const int lo_y = ClampInt(PriceToY(price_min, price_min, price_max, chart_height, chart_top, chart_bottom) - canvas_top, 4, canvas_height - 26);
   const int badge_x = 6;
   const int badge_w = MathMax(108, canvas_width - 12);
   DrawBadge(badge_x, hi_y, badge_w, 18, StringFormat("最高价  %s", PriceText(price_max)), clrBlack, clrLime, clrWhite);
   DrawBadge(badge_x, lo_y - 2, badge_w, 18, StringFormat("最低价  %s", PriceText(price_min)), clrBlack, clrAqua, clrWhite);
   g_canvas.LineHorizontal(badge_x, right_edge - 4, hi_y + 9, ColorToARGB(clrLime, 120));
   g_canvas.LineHorizontal(badge_x, right_edge - 4, lo_y + 7, ColorToARGB(clrAqua, 120));

   for(int row = 0; row < display_count; ++row)
     {
      const double row_low = display_rows[row].low;
      const double row_high = display_rows[row].high;
      const double volume = display_rows[row].volume;
      const bool is_poc = display_rows[row].is_poc;
      const bool is_current = display_rows[row].is_current;
      const int y_center = display_rows[row].y - canvas_top;
      const int line_h = MathMax(8, MathMin(InpRowHeight, MathMax(8, (canvas_height - header_h - 10) / MathMax(1, display_count))));
      const int row_top = ClampInt(y_center - line_h / 2, header_h + 2, canvas_height - 8 - line_h);
      const int row_bottom = row_top + line_h;
      const int bar_width = row_widths[row];

      color fill_color = InpBarColor;
      if(is_poc)
         fill_color = InpPocColor;
      if(is_current)
         fill_color = InpCurrentColor;

      const int prev_width = (row > 0 ? row_widths[row - 1] : bar_width);
      const int next_width = (row < display_count - 1 ? row_widths[row + 1] : bar_width);
      const int left_top = ClampInt(right_edge - (int)MathRound((double)(bar_width + prev_width) * 0.5), left_limit, right_edge - 1);
      const int left_bottom = ClampInt(right_edge - (int)MathRound((double)(bar_width + next_width) * 0.5), left_limit, right_edge - 1);

      DrawRowPolygon(left_top,
                     left_bottom,
                     right_edge,
                     row_top,
                     row_bottom,
                     fill_color,
                     is_current ? InpCurrentColor : (is_poc ? InpPocColor : InpMutedTextColor));

      if(is_current || is_poc)
        {
         const color tag_color = is_current ? InpCurrentColor : InpPocColor;
         g_canvas.LineHorizontal(left_top, right_edge, row_top + line_h / 2, ColorToARGB(tag_color, 150));
         DrawText(PriceText((row_low + row_high) * 0.5),
                  6,
                  row_top - 1,
                  8,
                  tag_color,
                  TA_LEFT | TA_TOP);
         DrawText(VolumeText(volume),
                  right_edge - 2,
                  row_top - 1,
                  8,
                  tag_color,
                  TA_RIGHT | TA_TOP);
         DrawText(is_current ? "CUR" : "POC",
                  right_edge - 30,
                  row_top - 1,
                  8,
                  tag_color,
                  TA_RIGHT | TA_TOP);
        }
      else if(display_count <= 14 && (row % 3 == 0))
        {
         DrawText(PriceText((row_low + row_high) * 0.5),
                  6,
                  row_top - 1,
                  7,
                  InpMutedTextColor,
                  TA_LEFT | TA_TOP);
        }

      if(is_current)
         g_canvas.LineHorizontal(6, right_edge - 2, row_top + line_h / 2, ColorToARGB(InpCurrentColor, 70));
      else if(is_poc)
         g_canvas.LineHorizontal(6, right_edge - 2, row_top + line_h / 2, ColorToARGB(InpPocColor, 55));
      g_visible_rows++;
     }

   g_canvas.Update(false);
   ChartRedraw(0);
  }

int OnInit()
  {
   g_prefix = "VP_RIGHT_" + IntegerToString((int)(GetTickCount64() % 100000));
   g_canvas_name = g_prefix + "_canvas";
   IndicatorSetString(INDICATOR_SHORTNAME, "Gold Volume Profile Right Side");
   EventSetTimer(2);
   DrawProfile();
   return INIT_SUCCEEDED;
  }

void OnDeinit(const int reason)
  {
   EventKillTimer();
   g_canvas.Destroy();
   DeletePrefixedObjects();
   ChartRedraw(0);
  }

void OnTimer()
  {
   DrawProfile();
  }

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
   DrawProfile();
   return rates_total;
  }

void OnChartEvent(const int id,
                  const long& lparam,
                  const double& dparam,
                  const string& sparam)
  {
   if(id == CHARTEVENT_CHART_CHANGE)
      DrawProfile();
  }
//+------------------------------------------------------------------+
