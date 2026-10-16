import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models.dart';
import '../theme.dart';
import 'common.dart';

/// Column widths and row height for [BreakdownTable], measured from the text
/// that will actually be drawn. Measuring rather than guessing is what lets
/// the table know whether it fits, instead of switching layouts on a fixed
/// breakpoint that says nothing about the content.
class BreakdownLayout {
  const BreakdownLayout({
    required this.nameWidth,
    required this.metricWidths,
    required this.rowHeight,
  });

  final double nameWidth;
  final List<double> metricWidths; // one per entry in [metrics], same order
  final double rowHeight;

  double get metricsWidth => metricWidths.fold(0.0, (a, b) => a + b);

  /// Everything side by side, nothing scrolled.
  double get fullWidth => nameWidth + metricsWidth;

  /// The name column plus the first [n] metric columns.
  double widthForFirst(int n) =>
      nameWidth + metricWidths.take(n).fold(0.0, (a, b) => a + b);

  /// Narrowest width the table is still worth showing at: the name column
  /// plus Posts…Reach, the four the Total row has to show without sideways
  /// scrolling. Below this the card layout takes over.
  double get minWidth => widthForFirst(4);
}

/// Text geometry of the breakdown for [entries]/[totals] at this context's
/// text scale.
BreakdownLayout measureBreakdown(
  BuildContext context,
  List<Entry> entries,
  Map<String, int> totals,
) {
  final scaler = MediaQuery.textScalerOf(context);
  final painter = TextPainter(
    textDirection: TextDirection.ltr,
    textScaler: scaler,
    maxLines: 1,
  );
  Size measure(String text, TextStyle style) {
    painter.text = TextSpan(text: text, style: style);
    painter.layout();
    return painter.size;
  }

  var lineHeight = 0.0;
  double column(Iterable<(String, TextStyle)> cells) {
    var w = 0.0;
    for (final (text, style) in cells) {
      final size = measure(text, style);
      w = math.max(w, size.width);
      lineHeight = math.max(lineHeight, size.height);
    }
    return w + _cellPadding * 2;
  }

  final nameWidth = column([
    ('Employee Name', _headerStyle),
    ('Total', _totalStyle),
    for (final e in entries) (e.employeeName, _cellStyle),
  ]).clamp(_minNameWidth, _maxNameWidth);

  final metricWidths = [
    for (final m in metrics)
      math.max(
        _minMetricWidth,
        column([
          (m.short, _headerStyle),
          (fmt(totals[m.key] ?? 0), _totalStyle),
          for (final e in entries) (fmt(e[m.key]), _cellStyle),
        ]),
      ),
  ];

  painter.dispose();
  return BreakdownLayout(
    nameWidth: nameWidth,
    metricWidths: metricWidths,
    rowHeight: math.max(_minRowHeight, lineHeight + _cellPadding * 2),
  );
}

const _cellPadding = 14.0;
const _minRowHeight = 44.0;
const _minNameWidth = 140.0;
const _maxNameWidth = 260.0;
const _minMetricWidth = 72.0;

/// Width of the gradient hinting at content scrolled out of view.
const _fadeWidth = 28.0;

/// Empty band under the rows the horizontal scrollbar sits in, so the thumb
/// never covers the Total row.
const _scrollbarBand = 14.0;

const _headerStyle = TextStyle(
  fontSize: 13,
  fontWeight: FontWeight.w600,
  color: AppColors.textSecondary,
);
const _cellStyle = TextStyle(fontSize: 13, color: AppColors.textPrimary);
const _totalStyle = TextStyle(
  fontSize: 13,
  fontWeight: FontWeight.w600,
  color: AppColors.textPrimary,
);

/// Per-employee numbers for one week.
///
/// The Employee Name column is pinned and the metric columns scroll under it,
/// with an always-visible scrollbar and an edge gradient, because Academy and
/// Studios — the two columns that fall off a narrow screen first — are the
/// funnel metrics people come here for. Where even Posts…Reach would not fit
/// ([BreakdownLayout.minWidth]), the card layout is used instead of a table
/// that is mostly off-screen.
class BreakdownTable extends StatefulWidget {
  const BreakdownTable({
    super.key,
    required this.entries,
    required this.totals,
  });
  final List<Entry> entries;
  final Map<String, int> totals;

  @override
  State<BreakdownTable> createState() => _BreakdownTableState();
}

class _BreakdownTableState extends State<BreakdownTable> {
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Widget _cell(
    String text,
    TextStyle style, {
    required double width,
    required double height,
    bool left = false,
    Color color = Colors.white,
    Border? border,
  }) {
    return Container(
      width: width,
      height: height,
      alignment: left ? Alignment.centerLeft : Alignment.centerRight,
      padding: const EdgeInsets.symmetric(horizontal: _cellPadding),
      decoration: BoxDecoration(color: color, border: border),
      child: Text(
        text,
        style: style,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final entries = widget.entries;
    final totals = widget.totals;

    return LayoutBuilder(
      builder: (context, c) {
        final layout = measureBreakdown(context, entries, totals);
        final available = c.maxWidth.isFinite ? c.maxWidth : layout.fullWidth;
        if (available < layout.minWidth) {
          return _MobileBreakdown(entries: entries, totals: totals);
        }

        // When everything fits, the slack goes to the name column, the way
        // the old flex-2 first column absorbed it.
        final fits = layout.fullWidth <= available;
        final nameWidth =
            fits ? available - layout.metricsWidth : layout.nameWidth;
        final viewport = available - nameWidth;

        const divider = BorderSide(color: AppColors.divider);
        const rowBorder = Border(bottom: divider);
        const pinnedRowBorder = Border(bottom: divider, right: divider);
        final h = layout.rowHeight;

        final pinned = Column(
          children: [
            _cell(
              'Employee Name',
              _headerStyle,
              width: nameWidth,
              height: h,
              left: true,
              color: AppColors.card,
              border: pinnedRowBorder,
            ),
            for (final e in entries)
              _cell(
                e.employeeName,
                _cellStyle,
                width: nameWidth,
                height: h,
                left: true,
                border: pinnedRowBorder,
              ),
            _cell(
              'Total',
              _totalStyle,
              width: nameWidth,
              height: h,
              left: true,
              border: const Border(right: divider),
            ),
            const SizedBox(height: _scrollbarBand),
          ],
        );

        Widget metricRow(
          String Function(Metric) text,
          TextStyle style, {
          Color color = Colors.white,
          Border? border = rowBorder,
        }) => Row(
          children: [
            for (final (i, m) in metrics.indexed)
              _cell(
                text(m),
                style,
                width: layout.metricWidths[i],
                height: h,
                color: color,
                border: border,
              ),
          ],
        );

        final scrolling = SizedBox(
          width: math.max(layout.metricsWidth, viewport),
          child: Column(
            children: [
              metricRow((m) => m.short, _headerStyle, color: AppColors.card),
              for (final e in entries)
                metricRow((m) => fmt(e[m.key]), _cellStyle),
              metricRow(
                (m) => fmt(totals[m.key] ?? 0),
                _totalStyle,
                border: null,
              ),
              const SizedBox(height: _scrollbarBand),
            ],
          ),
        );

        final overflow = math.max(0.0, layout.metricsWidth - viewport);
        return ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              pinned,
              Expanded(
                child: overflow == 0
                    ? scrolling
                    : Stack(
                        children: [
                          Scrollbar(
                            controller: _scroll,
                            thumbVisibility: true,
                            child: SingleChildScrollView(
                              controller: _scroll,
                              scrollDirection: Axis.horizontal,
                              child: scrolling,
                            ),
                          ),
                          Positioned.fill(
                            child: BreakdownScrollFades(
                              controller: _scroll,
                              initialExtentAfter: overflow,
                            ),
                          ),
                        ],
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Gradients over either edge of the scrolling columns, each shown only while
/// there is something out of view on that side.
class BreakdownScrollFades extends StatelessWidget {
  const BreakdownScrollFades({
    super.key,
    required this.controller,
    required this.initialExtentAfter,
  });

  final ScrollController controller;

  /// What is out of view to the right before the controller has a position
  /// attached, i.e. on the very first frame.
  final double initialExtentAfter;

  static const rightKey = Key('breakdown-fade-right');
  static const leftKey = Key('breakdown-fade-left');

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          // During the first layout pass the controller already has a
          // client but no dimensions yet, so reading extentBefore would
          // throw. Fall back to what the table measured for itself.
          final p = controller.hasClients ? controller.position : null;
          final ready =
              p != null && p.hasPixels && p.hasContentDimensions;
          final before = ready ? p.extentBefore : 0.0;
          final after = ready ? p.extentAfter : initialExtentAfter;
          Widget fade(Key key, Alignment from, Alignment to) => Align(
            alignment: from,
            child: Container(
              key: key,
              width: _fadeWidth,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: from,
                  end: to,
                  colors: [Colors.white, Colors.white.withValues(alpha: 0)],
                ),
              ),
            ),
          );
          return Stack(
            fit: StackFit.expand,
            children: [
              if (before > 0.5)
                fade(leftKey, Alignment.centerLeft, Alignment.centerRight),
              if (after > 0.5)
                fade(rightKey, Alignment.centerRight, Alignment.centerLeft),
            ],
          );
        },
      ),
    );
  }
}

class _MobileBreakdown extends StatelessWidget {
  const _MobileBreakdown({required this.entries, required this.totals});
  final List<Entry> entries;
  final Map<String, int> totals;

  @override
  Widget build(BuildContext context) {
    Widget card(
      String name,
      Map<String, int> v, {
      bool total = false,
    }) => Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: total ? AppColors.card : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            name,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
          ),
          const SizedBox(height: 10),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            childAspectRatio: 6,
            children: [
              for (final m in metrics)
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        m.short,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: Text(
                        fmt(v[m.key] ?? 0),
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: total ? FontWeight.w700 : FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ],
      ),
    );

    return Column(
      children: [
        for (final e in entries) card(e.employeeName, e.values),
        card('Total', totals, total: true),
      ],
    );
  }
}
