import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/design_system/preferences/theme_preferences.dart';
import 'package:naviwealth/domain/values/money.dart';
import 'package:naviwealth/features/fire/data/fire_review_cache.dart';
import 'package:naviwealth/features/fire/domain/fire_review.dart';
import 'package:naviwealth/features/fire/domain/fire_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

FireReview _review({
  required FireReviewKind kind,
  required String periodKey,
}) {
  return FireReview(
    kind: kind,
    periodKey: periodKey,
    generatedAt: DateTime.utc(2026, 5, 20),
    baseCurrency: 'CNY',
    safetyLevel: FireSafetyLevel.safe,
    netWorth: Money.parse('1000', 'CNY'),
    investableAssets: Money.parse('1000', 'CNY'),
    liquidAssets: Money.parse('100', 'CNY'),
    annualSpend: Money.parse('100', 'CNY'),
    withdrawalRate: 0.04,
    safeWithdrawalRate: 0.04,
    cashBucketMonths: 12,
    targetCashBucketMonths: 12,
    fireEtaMonths: 60,
    findings: const [],
    suggestedActions: const [],
  );
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  ProviderContainer container(SharedPreferences prefs) {
    final c = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    addTearDown(c.dispose);
    return c;
  }

  test('starts empty', () async {
    final prefs = await SharedPreferences.getInstance();
    final c = container(prefs);
    expect(c.read(fireReviewCacheProvider), isEmpty);
  });

  test('upsert deduplicates by (kind, periodKey)', () async {
    final prefs = await SharedPreferences.getInstance();
    final c = container(prefs);
    await c.read(fireReviewCacheProvider.notifier).upsert(
      _review(kind: FireReviewKind.monthly, periodKey: '2026-05'),
    );
    await c.read(fireReviewCacheProvider.notifier).upsert(
      _review(kind: FireReviewKind.monthly, periodKey: '2026-05'),
    );
    expect(c.read(fireReviewCacheProvider), hasLength(1));

    await c.read(fireReviewCacheProvider.notifier).upsert(
      _review(kind: FireReviewKind.quarterly, periodKey: '2026-Q2'),
    );
    expect(c.read(fireReviewCacheProvider), hasLength(2));
  });

  test('latest returns the most recently upserted review per kind',
      () async {
    final prefs = await SharedPreferences.getInstance();
    final c = container(prefs);
    final controller = c.read(fireReviewCacheProvider.notifier);
    await controller
        .upsert(_review(kind: FireReviewKind.monthly, periodKey: '2026-04'));
    await controller
        .upsert(_review(kind: FireReviewKind.monthly, periodKey: '2026-05'));
    expect(controller.latest(FireReviewKind.monthly)!.periodKey, '2026-05');
  });

  test('persistence survives a container restart', () async {
    final prefs = await SharedPreferences.getInstance();
    final write = container(prefs);
    await write.read(fireReviewCacheProvider.notifier).upsert(
      _review(kind: FireReviewKind.annual, periodKey: '2026'),
    );

    final reload = container(prefs);
    expect(reload.read(fireReviewCacheProvider), hasLength(1));
    expect(
      reload.read(fireReviewCacheProvider).first.periodKey,
      '2026',
    );
  });
}
