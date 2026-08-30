import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/product/product_metrics.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('records privacy-safe totals and repeat-cycle day buckets', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    var now = DateTime.utc(2026, 7, 19);
    final controller = ProductMetricsController(preferences, clock: () => now);

    await controller.record(ProductFunnelEvent.importReviewCompleted);
    expect(
      preferences.getString('naviwealth.product_metrics.aggregates.v5'),
      isNull,
    );

    await controller.setEnabled(true);
    await controller.record(ProductFunnelEvent.activationStarted);
    await controller.record(
      ProductFunnelEvent.importReviewCompleted,
      duration: const Duration(seconds: 2),
      success: true,
    );
    now = DateTime.utc(2026, 8, 2);
    await controller.record(
      ProductFunnelEvent.firstUsefulResultCompleted,
      success: true,
    );
    await controller.record(
      ProductFunnelEvent.firstUsefulResultCompleted,
      success: true,
    );
    await controller.record(
      ProductFunnelEvent.importReviewCompleted,
      success: true,
    );
    await controller.record(
      ProductFunnelEvent.monthlyCloseCompleted,
      success: true,
    );
    await controller.record(
      ProductFunnelEvent.financialSignalRevalidatedCleared,
      success: true,
      quantity: 2,
    );
    await controller.record(
      ProductFunnelEvent.importCycleCompleted,
      success: true,
      quantity: 3,
    );
    await controller.record(
      ProductFunnelEvent.importReviewCorrected,
      quantity: 2,
    );
    await controller.record(
      ProductFunnelEvent.knowledgeDecisionCreated,
      success: true,
      quantity: 2,
    );
    await controller.record(
      ProductFunnelEvent.knowledgeDecisionActionCreated,
      success: true,
    );
    await controller.record(
      ProductFunnelEvent.knowledgeDecisionReviewed,
      duration: const Duration(days: 7),
      success: true,
    );

    final stored = jsonDecode(
      preferences.getString('naviwealth.product_metrics.aggregates.v5')!,
    ) as Map<String, Object?>;
    expect(stored['schema_version'], 5);
    expect(
      (stored['totals']! as Map<String, Object?>)['importReviewCompleted'],
      <String, Object?>{
        'count': 2,
        'duration_ms_total': 2000,
        'success_count': 2,
      },
    );
    expect(
      (stored['totals']! as Map<String, Object?>)['firstUsefulResultCompleted'],
      <String, Object?>{
        'count': 1,
        'duration_ms_total': const Duration(days: 14).inMilliseconds,
        'success_count': 1,
      },
    );
    expect(
      (stored['totals']!
          as Map<String, Object?>)['financialSignalRevalidatedCleared'],
      <String, Object?>{'count': 2, 'success_count': 2},
    );
    expect(
      (stored['totals']! as Map<String, Object?>)['importReviewCorrected'],
      <String, Object?>{'count': 2},
    );

    final report = controller.exportAggregates();
    expect(report['derived'], <String, Object?>{
      'active_day_count': 2,
      'first_useful_result_day_count': 1,
      'import_cycle_day_count': 1,
      'import_cycle_count': 3,
      'completed_second_import_cycle': true,
      'completed_third_import_cycle': true,
      'inbox_clear_day_count': 0,
      'monthly_close_day_count': 1,
      'knowledge_decision_created_count': 2,
      'knowledge_decision_action_created_count': 1,
      'knowledge_decision_reviewed_count': 1,
      'knowledge_decision_created_day_count': 1,
      'knowledge_decision_reviewed_day_count': 1,
    });
  });
}
