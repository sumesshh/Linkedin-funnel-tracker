import 'package:flutter_test/flutter_test.dart';
import 'package:linkedin_dashboard/widgets/metric_chart.dart';

void main() {
  void check(AxisScale s, num maxValue) {
    expect(s.maxY % s.interval, 0, reason: 'maxY must be a multiple');
    expect(s.maxY, greaterThanOrEqualTo(maxValue), reason: 'no clipping');
    expect(s.interval, greaterThan(0));
  }

  group('weekly', () {
    test('A: 1,750 → 0–1,800 by 200', () {
      final s = axisScale(1750, ChartPeriod.weekly);
      expect(s, (maxY: 1800.0, interval: 200.0));
    });
    test('B: 2,350 → 0–2,400 by 600 (step widens past 2,000)', () {
      final s = axisScale(2350, ChartPeriod.weekly);
      expect(s, (maxY: 2400.0, interval: 600.0));
    });
    test('step is 200 up to 2,000', () {
      for (final v in [1, 199, 1000, 2000]) {
        final s = axisScale(v, ChartPeriod.weekly);
        check(s, v);
        expect(s.interval, 200);
      }
    });
    test('larger totals adapt: multiple-of-200 step, about 6–10 gridlines', () {
      for (final v in [2001, 3878, 5000, 5900, 7600, 10000, 23456, 150000]) {
        final s = axisScale(v, ChartPeriod.weekly);
        check(s, v);
        expect(s.interval % 200, 0);
        expect(s.maxY % 200, 0);
        expect(s.maxY / s.interval, inInclusiveRange(4, 12), reason: '$v');
      }
      expect(axisScale(3878, ChartPeriod.weekly), (maxY: 4200.0, interval: 600.0));
      expect(axisScale(5900, ChartPeriod.weekly), (maxY: 6000.0, interval: 1000.0));
    });
    test('zero / empty gives a valid 0–200 axis', () {
      expect(axisScale(0, ChartPeriod.weekly), (maxY: 200.0, interval: 200.0));
      expect(axisScale(double.nan, ChartPeriod.weekly),
          (maxY: 200.0, interval: 200.0));
    });
  });

  group('labelInterval', () {
    test('every gridline is labelled when there is room', () {
      expect(labelInterval((maxY: 1400, interval: 200), 300), 200);
    });
    test('labels thin to round multiples of 200 when crowded', () {
      final step = labelInterval((maxY: 7600, interval: 200), 296);
      expect(step % 200, 0);
      expect(7600 / step * 16, lessThanOrEqualTo(296));
      expect([200, 400, 1000, 2000], contains(step));
    });
  });

  group('monthly', () {
    test('5,000 → by 1,000 and 10,000 → by 2,000', () {
      expect(axisScale(5000, ChartPeriod.monthly),
          (maxY: 5000.0, interval: 1000.0));
      expect(axisScale(10000, ChartPeriod.monthly),
          (maxY: 10000.0, interval: 2000.0));
    });
    test('C: 30,000 → by 5,000', () {
      expect(axisScale(30000, ChartPeriod.monthly),
          (maxY: 30000.0, interval: 5000.0));
    });
    test('D: 60,000 → by 10,000', () {
      expect(axisScale(60000, ChartPeriod.monthly),
          (maxY: 60000.0, interval: 10000.0));
    });
    test('E: 12,000 → by 2,000', () {
      expect(axisScale(12000, ChartPeriod.monthly),
          (maxY: 12000.0, interval: 2000.0));
    });
    test('arbitrary values fit with readable gridline counts', () {
      for (final v in [1, 3, 7, 95, 31000, 87654, 1234567]) {
        final s = axisScale(v, ChartPeriod.monthly);
        check(s, v);
        expect(s.maxY / s.interval, inInclusiveRange(1, 12));
        expect(s.interval, s.interval.roundToDouble());
      }
    });
    test('F: zero / empty data is safe', () {
      check(axisScale(0, ChartPeriod.monthly), 0);
    });
  });
}
