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
  final step = [1, 2, 2.5, 5, 10]
      .map((m) => m * magnitude)
      .firstWhere((s) => s >= raw);
  return (step / 200).ceil() * 200.0;
}

/// Which Y-axis scaling rules a [MetricLineChart] follows.
enum ChartPeriod { weekly, monthly }

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
  final magnitude = math.pow(10, (math.log(raw) / math.ln10).floor()).toDouble();
  final step = [1, 2, 2.5, 5, 10]
      .map((m) => m * magnitude)
      .firstWhere((s) => s >= raw - 1e-9);
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
  for (var mag = 1;; mag *= 10) {
    for (final k in [1, 2, 5]) {
      final step = k * mag;
      if (lines / step * minLabelSpacing <= plotHeight || step >= lines) {
        return scale.interval * step;
      }
    }
  }
}

/// Smooth curved multi-line chart: one line per metric, one x position per
/// label (weeks on the dashboard, employees in the breakdown).
class MetricLineChart extends StatefulWidget {
  const MetricLineChart({
    super.key,
    required this.labels,
    required this.values,
    this.period = ChartPeriod.weekly,
  });

  /// X-axis labels.
  final List<String> labels;

  /// values[i] holds the 8 metric totals for labels[i].
  final List<Map<String, int>> values;

  /// Selects the weekly or monthly Y-axis scaling rules.
  final ChartPeriod period;

  @override
  State<MetricLineChart> createState() => _MetricLineChartState();
}

class _MetricLineChartState extends State<MetricLineChart> {
  final _hidden = <String>{};

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
    final yLabelStep =
        labelInterval(scale, chartHeight - 24 - bottomReserved);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 16,
          runSpacing: 8,
          children: [
            for (final m in metrics)
              InkWell(
                borderRadius: BorderRadius.circular(6),
                onTap: () => setState(() =>
                    _hidden.contains(m.key) ? _hidden.remove(m.key) : _hidden.add(m.key)),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  child: Opacity(
                    opacity: _hidden.contains(m.key) ? 0.35 : 1,
                    child: LegendDot(color: m.color, label: m.label),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        const Text('Tap a legend item to hide or show its line.',
            style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
        Container(
          height: chartHeight,
          color: AppColors.background,
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
          child: n == 0
              ? const Center(
                  child: Text('No data yet',
                      style: TextStyle(color: AppColors.textSecondary)))
              : LineChart(
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
                      getDrawingHorizontalLine: (_) => const FlLine(
                          color: AppColors.divider, strokeWidth: 0.5),
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
                            child: Text(fmt(v),
                                style: const TextStyle(
                                    fontSize: 11,
                                    color: AppColors.textSecondary)),
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
                              textAlign:
                                  rotate ? TextAlign.right : TextAlign.center,
                              style: const TextStyle(
                                  fontSize: 11,
                                  color: AppColors.textSecondary),
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
                            const FlLine(
                                color: AppColors.cardBorder, strokeWidth: 1),
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
                        tooltipBorder:
                            const BorderSide(color: AppColors.cardBorder),
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
                              FlSpot(i.toDouble(),
                                  (widget.values[i][m.key] ?? 0).toDouble()),
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
                ),
        ),
      ],
    );
  }

  /// One tooltip row per visible metric, header = x label.
  List<LineTooltipItem?> _tooltipItems(
      List<LineBarSpot> spots, List<Metric> shown) {
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
            height: 1.8),
        textAlign: TextAlign.left,
        children: [
          TextSpan(text: '● ', style: TextStyle(color: m.color, fontSize: 12)),
          TextSpan(
            text: '${m.label}: ',
            style: const TextStyle(
                fontWeight: FontWeight.w400,
                color: AppColors.textSecondary,
                fontSize: 12),
          ),
          TextSpan(
            text: fmt(s.y),
            style: const TextStyle(
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
                fontSize: 12),
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
  if (v >= 1000000) return '${(v / 1000000).toStringAsFixed(v % 1000000 == 0 ? 0 : 1)}M';
  if (v >= 1000) return '${(v / 1000).toStringAsFixed(v % 1000 == 0 ? 0 : 1)}K';
  return v.toInt().toString();
}
