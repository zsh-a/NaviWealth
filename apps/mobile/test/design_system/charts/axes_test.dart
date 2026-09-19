import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:naviwealth/design_system/charts/axes.dart';

void main() {
  test('money ticks distinguish small changes at large balances', () {
    for (final locale in ['en_US', 'zh_CN']) {
      final axis = ValueAxis.currency(currencyCode: 'USD', locale: locale);
      final label = axis.tickFormatter(min: 100000, max: 100900, interval: 300);
      expect(label(100300), isNot(axis.formatValue(100300)));
      expect(
        [100000.0, 100300.0, 100600.0, 100900.0].map(label).toSet(),
        hasLength(4),
      );
    }
  });

  test('inspected values use full currency precision', () {
    final axis = ValueAxis.currency(currencyCode: 'USD', locale: 'en_US');
    expect(axis.formatValue(100900.25), r'$100,900.25');
    expect(const ValueAxis(locale: 'en_US').formatValue(12345.67), '12,345.67');
    final percent = ValueAxis.percent(locale: 'en_US');
    final label = percent.tickFormatter(min: 1, max: 1.3, interval: 0.1);
    expect([1.0, 1.1, 1.2, 1.3].map(label).toSet(), hasLength(4));
  });

  test('sub-day time ticks never repeat the same date', () async {
    await initializeDateFormatting('en_US');
    final min = DateTime.utc(2026, 9, 1).millisecondsSinceEpoch.toDouble();
    final interval = const Duration(hours: 6).inMilliseconds.toDouble();
    const axis = TimeAxis(format: AxisDateFormat.dayMonth, locale: 'en_US');
    final meta = TitleMeta(
      min: min,
      max: min + interval * 4,
      parentAxisSize: 600,
      axisPosition: 0,
      appliedInterval: interval,
      sideTitles: const SideTitles(),
      formattedValue: '',
      axisSide: AxisSide.bottom,
      rotationQuarterTurns: 0,
    );
    final labels = [
      for (var i = 0; i <= 4; i++)
        if (shouldRenderAxisLabel(
          value: min + i * interval,
          meta: meta,
          range: interval * 4,
          maxLabels: 5,
          formatLabel: axis.formatTimestamp,
        ))
          axis.formatTimestamp(min + i * interval),
    ];
    expect(labels, ['Sep 1', 'Sep 2']);
  });
}
