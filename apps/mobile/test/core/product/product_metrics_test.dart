import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/product/product_metrics.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('records enum counters only after explicit opt in', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final controller = ProductMetricsController(preferences);

    await controller.record(ProductFunnelEvent.moneyRunwayOpened);
    expect(preferences.getString('naviwealth.product_metrics.counts'), isNull);

    await controller.setEnabled(true);
    await controller.record(ProductFunnelEvent.moneyRunwayOpened);
    final counts =
        jsonDecode(preferences.getString('naviwealth.product_metrics.counts')!)
            as Map<String, Object?>;
    expect(counts, {'moneyRunwayOpened': 1});
  });
}
