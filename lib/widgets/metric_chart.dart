import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../models.dart';
import '../theme.dart';
import 'common.dart';

/// Y-axis gridline step: 200 per the spec, widened in multiples of 200 when
/// values get large so the axis never shows more than ~10 gridlines.
double gridInterval(num maxValue) {
  if (maxValue <= 2000) return 200;
  final raw = maxValue / 8;
  final magnitude = math.pow(10, (math.log(raw) / math.ln10).floor());
  final step = [
    1,
    2,
    2.5,
    5,
    10,
  ].map((m) => m * magnitude).firstWhere((s) => s >= raw);
  return (step / 200).ceil() * 200.0;
}

/// Which Y-axis scaling rules a [MetricLineChart] follows.
enum ChartPeriod { weekly, monthly }

/// How the metrics are drawn.
enum ChartKind { bar, line }

/// Y-axis bounds for a chart: starts at 0, [maxY] is always a multiple of
/// [interval] and never below the largest plotted value.
typedef AxisScale = ({double maxY, double interval});

/// Computes the Y-axis maximum and gridline interval for [maxValue].
///
/// Weekly: interval 200 up to 2,000; above that the step widens (always a
/// multiple of 200, via [gridInterval]) to keep about 6–10 gridlines. The max
/// is [maxValue] rounded up to the next multiple of that step (at least one
/// step), so 3,878 → 0–4,200 by 600 and 5,900 → 0–6,000 by 1,000.
///
/// Monthly: a "nice" interval (1/2/2.5/5 × 10ⁿ) giving about six gridlines,
/// e.g. 5,000 → 1,000, 10,000 → 2,000, 30,000 → 5,000.
AxisScale axisScale(num maxValue, ChartPeriod period) {
  final max = maxValue.isFinite && maxValue > 0 ? maxValue : 0;
  final double interval;
  if (period == ChartPeriod.weekly) {
    interval = gridInterval(max);
    final maxY = math.max(1, (max / interval).ceil()) * interval;
    return (maxY: maxY, interval: interval);
  }
  if (max == 0) return (maxY: 6, interval: 1);
  final raw = max / 6;
  final magnitude = math
      .pow(10, (math.log(raw) / math.ln10).floor())
      .toDouble();
  final step = [
    1,
    2,
    2.5,
    5,
    10,
  ].map((m) => m * magnitude).firstWhere((s) => s >= raw - 1e-9);
  // Counts are whole numbers, so never use a fractional step.
  interval = math.max(1, step).toDouble();
  final maxY = math.max(1, (max / interval).ceil()) * interval;
  return (maxY: maxY, interval: interval);
}

/// Step between Y-axis labels: the gridline [AxisScale.interval] when the
/// labels fit in [plotHeight] pixels, otherwise the smallest 2×/5×/10×…
/// multiple of it whose labels don't overlap. Gridlines are unaffected.
double labelInterval(AxisScale scale, double plotHeight) {
  const minLabelSpacing = 16.0;
  final lines = scale.maxY / scale.interval;
  for (var mag = 1; ; mag *= 10) {
    for (final k in [1, 2, 5]) {
      final step = k * mag;
      if (lines / step * minLabelSpacing <= plotHeight || step >= lines) {
        return scale.interval * step;
      }
    }
  }
}

/// Grouped bar chart: one bar per metric, one group per
/// label (weeks on the dashboard, employees in the breakdown).
class MetricLineChart extends StatefulWidget {
  const MetricLineChart({
    super.key,
    required this.labels,
    required this.values,
    this.period = ChartPeriod.weekly,
    this.description = 'Metric totals',
    this.unit = 'group',
  });

  /// X-axis labels.
  final List<String> labels;

  /// values[i] holds the 8 metric totals for labels[i].
  final List<Map<String, int>> values;

  /// Selects the weekly or monthly Y-axis scaling rules.
  final ChartPeriod period;

  /// What the chart shows, for its screen-reader label, e.g.
  /// 'Weekly totals, all employees'.
  final String description;

  /// Singular name for one X-axis group ('week', 'month', 'employee'), used
  /// in the same label.
  final String unit;

  @override
  State<MetricLineChart> createState() => _MetricLineChartState();
}

class _MetricLineChartState extends State<MetricLineChart> {
  final _hidden = <String>{};
  ChartKind _kind = ChartKind.bar;

  /// e.g. "Weekly totals, all employees, bar chart, 23 weeks, 8 of 8 metrics
  /// shown". fl_chart paints onto a canvas, so this sentence is all a screen
  /// reader gets for the plot itself; the axis labels remain separate nodes.
  String _semanticsLabel(List<Metric> shown) {
    final kind = _kind == ChartKind.bar ? 'bar chart' : 'line chart';
    final n = widget.labels.length;
    if (n == 0) return '${widget.description}, $kind, no data yet';
    return '${widget.description}, $kind, '
        '$n ${widget.unit}${n == 1 ? '' : 's'}, '
        '${shown.length} of ${metrics.length} metrics shown';
  }

  @override
  Widget build(BuildContext context) {
    final mobile = isMobile(context);
    final n = widget.labels.length;
    final shown = metrics.where((m) => !_hidden.contains(m.key)).toList();
    final maxValue = [
      for (final v in widget.values)
        for (final m in shown) v[m.key] ?? 0,
    ].fold<int>(0, math.max);
    final scale = axisScale(maxValue, widget.period);
    final (:maxY, :interval) = scale;
    final rotate = n > 6;
    final chartHeight = mobile ? 300.0 : 400.0;
    final bottomReserved = rotate ? 72.0 : 32.0;
    final yLabelStep = labelInterval(scale, chartHeight - 24 - bottomReserved);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SegmentedButton<ChartKind>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(
              value: ChartKind.bar,
              icon: Icon(Icons.bar_chart, size: 18),
              label: Text('Bar'),
            ),
            ButtonSegment(
              value: ChartKind.line,
              icon: Icon(Icons.show_chart, size: 18),
              label: Text('Line'),
            ),
          ],
          selected: {_kind},
          onSelectionChanged: (v) => setState(() => _kind = v.first),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 16,
          runSpacing: 8,
          children: [
            for (final m in metrics)
              MergeSemantics(
                child: Semantics(
                  label: m.label,
                  hint: _hidden.contains(m.key)
                      ? 'Hidden. Activate to show on the chart'
                      : 'Shown. Activate to hide from the chart',
                  child: InkWell(
                    borderRadius: BorderRadius.circular(6),
                    onTap: () => setState(
                      () => _hidden.contains(m.key)
                          ? _hidden.remove(m.key)
                          : _hidden.add(m.key),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 2,
                      ),
                      child: Opacity(
                        opacity: _hidden.contains(m.key) ? 0.35 : 1,
                        child: ExcludeSemantics(
                          child: LegendDot(color: m.color, label: m.label),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        const Text(
          'Tap a legend item to hide or show it.',
          style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
        ),
        Semantics(
          label: _semanticsLabel(shown),
          container: true,
          // Keeps the axis labels as their own nodes instead of letting them
          // all collapse into the label above.
          explicitChildNodes: true,
          child: Container(
            height: chartHeight,
            color: AppColors.background,
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
            child: n == 0
                ? const Center(
                    child: Text(
                      'No data yet',
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                  )
                : _kind == ChartKind.line
                ? _buildLineChart(
                    shown,
                    maxY,
                    interval,
                    yLabelStep,
                    bottomReserved,
                    rotate,
                    n,
                  )
                : LayoutBuilder(
                    builder: (context, box) {
                      // Wide enough that every bar stays readable; scrolls when
                      // there are many weeks.
                      final groupWidth = math.max(shown.length, 1) * 7.0 + 14;
                      final yAxisWidth = 60.0;
                      final width = math.max(
                        box.maxWidth,
                        n * groupWidth + yAxisWidth,
                      );
                      final chart = SizedBox(
                        width: width,
                        child: _buildBarChart(
                          shown,
                          maxY,
                          interval,
                          yLabelStep,
                          bottomReserved,
                          rotate,
                          n,
                        ),
                      );
                      return width > box.maxWidth
                          ? SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: chart,
                            )
                          : chart;
                    },
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildBarChart(
    List<Metric> shown,
    double maxY,
    double interval,
    double yLabelStep,
    double bottomReserved,
    bool rotate,
    int n,
  ) {
    return BarChart(
      duration: const Duration(milliseconds: 250),
      BarChartData(
        minY: 0,
        maxY: maxY,
        alignment: BarChartAlignment.spaceAround,
        borderData: FlBorderData(show: false),
        gridData: FlGridData(
          drawVerticalLine: false,
          horizontalInterval: interval,
          getDrawingHorizontalLine: (_) =>
              const FlLine(color: AppColors.divider, strokeWidth: 0.5),
        ),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(),
          rightTitles: const AxisTitles(),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: yLabelStep,
              reservedSize: 60,
              getTitlesWidget: (v, meta) => SideTitleWidget(
                meta: meta,
                child: Text(
                  fmt(v),
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: 1,
              reservedSize: bottomReserved,
              getTitlesWidget: (v, meta) {
                final i = v.round();
                if ((v - i).abs() > 0.01 || i < 0 || i >= n) {
                  return const SizedBox.shrink();
                }
                final text = Text(
                  widget.labels[i],
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: rotate ? TextAlign.right : TextAlign.center,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                );
                if (!rotate) return SideTitleWidget(meta: meta, child: text);
                // Pin the label's end to the tick and rotate 45° around it
                // so long names hang down-left.
                const w = 96.0;
                return SideTitleWidget(
                  meta: meta,
                  space: 6,
                  child: Transform.translate(
                    offset: const Offset(-w / 2, 0),
                    child: Transform.rotate(
                      angle: -math.pi / 4,
                      alignment: Alignment.topRight,
                      child: SizedBox(width: w, child: text),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipColor: (_) => Colors.white,
            tooltipBorder: const BorderSide(color: AppColors.cardBorder),
            tooltipBorderRadius: BorderRadius.circular(8),
            tooltipPadding: const EdgeInsets.all(12),
            maxContentWidth: 260,
            fitInsideHorizontally: true,
            fitInsideVertically: true,
            getTooltipItem: (group, groupIndex, rod, rodIndex) =>
                _tooltipItem(groupIndex, shown),
          ),
        ),
        barGroups: [
          for (var i = 0; i < n; i++)
            BarChartGroupData(
              x: i,
              barsSpace: 1,
              barRods: [
                for (final m in shown)
                  BarChartRodData(
                    toY: (widget.values[i][m.key] ?? 0).toDouble(),
                    color: m.color,
                    width: 6,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(2),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildLineChart(
    List<Metric> shown,
    double maxY,
    double interval,
    double yLabelStep,
    double bottomReserved,
    bool rotate,
    int n,
  ) {
    return LineChart(
      duration: const Duration(milliseconds: 250),
      LineChartData(
        minX: -0.25,
        maxX: math.max(n - 1, 0) + 0.25,
        minY: 0,
        maxY: maxY,
        clipData: const FlClipData.all(),
        borderData: FlBorderData(show: false),
        gridData: FlGridData(
          drawVerticalLine: false,
          horizontalInterval: interval,
          getDrawingHorizontalLine: (_) =>
              const FlLine(color: AppColors.divider, strokeWidth: 0.5),
        ),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(),
          rightTitles: const AxisTitles(),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: yLabelStep,
              reservedSize: 60,
              getTitlesWidget: (v, meta) => SideTitleWidget(
                meta: meta,
                child: Text(
                  fmt(v),
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: 1,
              reservedSize: bottomReserved,
              getTitlesWidget: (v, meta) {
                final i = v.round();
                if ((v - i).abs() > 0.01 || i < 0 || i >= n) {
                  return const SizedBox.shrink();
                }
                final text = Text(
                  widget.labels[i],
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: rotate ? TextAlign.right : TextAlign.center,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                );
                if (!rotate) {
                  return SideTitleWidget(meta: meta, child: text);
                }
                // Pin the label's end to the tick and rotate
                // 45° around it so long names hang down-left.
                const w = 96.0;
                return SideTitleWidget(
                  meta: meta,
                  space: 6,
                  child: Transform.translate(
                    offset: const Offset(-w / 2, 0),
                    child: Transform.rotate(
                      angle: -math.pi / 4,
                      alignment: Alignment.topRight,
                      child: SizedBox(width: w, child: text),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        lineTouchData: LineTouchData(
          getTouchedSpotIndicator: (bar, idx) => [
            for (final _ in idx)
              TouchedSpotIndicatorData(
                const FlLine(color: AppColors.cardBorder, strokeWidth: 1),
                FlDotData(
                  getDotPainter: (s, p, b, i) => FlDotCirclePainter(
                    radius: 3.5,
                    color: b.color ?? AppColors.primary,
                    strokeWidth: 2,
                    strokeColor: Colors.white,
                  ),
                ),
              ),
          ],
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => Colors.white,
            tooltipBorder: const BorderSide(color: AppColors.cardBorder),
            tooltipBorderRadius: BorderRadius.circular(8),
            tooltipPadding: const EdgeInsets.all(12),
            maxContentWidth: 260,
            fitInsideHorizontally: true,
            fitInsideVertically: true,
            getTooltipItems: (spots) => _tooltipItems(spots, shown),
          ),
        ),
        lineBarsData: [
          for (final m in shown)
            LineChartBarData(
              spots: [
                for (var i = 0; i < n; i++)
                  FlSpot(
                    i.toDouble(),
                    (widget.values[i][m.key] ?? 0).toDouble(),
                  ),
              ],
              isCurved: true,
              curveSmoothness: 0.35,
              preventCurveOverShooting: true,
              // A single point has no line to draw, so show dots.
              dotData: FlDotData(show: n == 1),
              barWidth: 3,
              isStrokeCapRound: true,
              color: m.color,
              belowBarData: BarAreaData(show: false),
            ),
        ],
      ),
    );
  }

  /// One tooltip listing every visible metric for the touched week.
  BarTooltipItem _tooltipItem(int index, List<Metric> shown) {
    return BarTooltipItem(
      '${widget.labels[index]}\n',
      const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: AppColors.textPrimary,
        height: 1.8,
      ),
      textAlign: TextAlign.left,
      children: [
        for (final m in shown) ...[
          TextSpan(
            text: '● ',
            style: TextStyle(color: m.color, fontSize: 12),
          ),
          TextSpan(
            text: '${m.label}: ',
            style: const TextStyle(
              fontWeight: FontWeight.w400,
              color: AppColors.textSecondary,
              fontSize: 12,
            ),
          ),
          TextSpan(
            text: '${fmt((widget.values[index][m.key] ?? 0).toDouble())}\n',
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
              fontSize: 12,
            ),
          ),
        ],
      ],
    );
  }

  /// One tooltip row per visible metric, header = x label.
  List<LineTooltipItem?> _tooltipItems(
    List<LineBarSpot> spots,
    List<Metric> shown,
  ) {
    final sorted = [...spots]..sort((a, b) => a.barIndex.compareTo(b.barIndex));
    final items = <LineBarSpot, LineTooltipItem>{};
    for (var k = 0; k < sorted.length; k++) {
      final s = sorted[k];
      final m = shown[s.barIndex];
      final header = k == 0 ? '${widget.labels[s.x.round()]}\n' : '';
      items[s] = LineTooltipItem(
        header,
        const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimary,
          height: 1.8,
        ),
        textAlign: TextAlign.left,
        children: [
          TextSpan(
            text: '● ',
            style: TextStyle(color: m.color, fontSize: 12),
          ),
          TextSpan(
            text: '${m.label}: ',
            style: const TextStyle(
              fontWeight: FontWeight.w400,
              color: AppColors.textSecondary,
              fontSize: 12,
            ),
          ),
          TextSpan(
            text: fmt(s.y),
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
              fontSize: 12,
            ),
          ),
        ],
      );
    }
    // fl_chart expects the items in the same order as the touched spots.
    return [for (final s in spots) items[s]];
  }
}

/// 1200 → 1.2K for axis labels.
String compact(num v) {
  if (v >= 1000000)
    return '${(v / 1000000).toStringAsFixed(v % 1000000 == 0 ? 0 : 1)}M';
  if (v >= 1000) return '${(v / 1000).toStringAsFixed(v % 1000 == 0 ? 0 : 1)}K';
  return v.toInt().toString();
}
