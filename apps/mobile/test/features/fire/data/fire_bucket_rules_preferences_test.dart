import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/design_system/preferences/theme_preferences.dart';
import 'package:naviwealth/features/fire/data/fire_bucket_rules_preferences.dart';
import 'package:naviwealth/features/fire/domain/fire_bucket.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
    expect(c.read(fireBucketRulesProvider), isEmpty);
  });

  test('upsert + remove + clear all round-trip across containers',
      () async {
    final prefs = await SharedPreferences.getInstance();
    final c = container(prefs);

    await c.read(fireBucketRulesProvider.notifier).upsert(
      const FireBucketRule(
        id: 'asset-1',
        role: FireBucketRole.growth,
        targetTable: 'assets',
        targetId: 'asset-1',
      ),
    );
    await c.read(fireBucketRulesProvider.notifier).upsert(
      const FireBucketRule(
        id: 'asset-2',
        role: FireBucketRole.defensive,
        targetTable: 'assets',
        targetId: 'asset-2',
      ),
    );

    // Replacement keyed by id.
    await c.read(fireBucketRulesProvider.notifier).upsert(
      const FireBucketRule(
        id: 'asset-1',
        role: FireBucketRole.cash,
        targetTable: 'assets',
        targetId: 'asset-1',
      ),
    );
    expect(c.read(fireBucketRulesProvider), hasLength(2));
    expect(
      c
          .read(fireBucketRulesProvider)
          .firstWhere((r) => r.id == 'asset-1')
          .role,
      FireBucketRole.cash,
    );

    // Reload to confirm persistence.
    final reload = container(prefs);
    final reloaded = reload.read(fireBucketRulesProvider);
    expect(reloaded, hasLength(2));

    // Remove.
    await c.read(fireBucketRulesProvider.notifier).remove('asset-1');
    expect(c.read(fireBucketRulesProvider), hasLength(1));

    // Clear.
    await c.read(fireBucketRulesProvider.notifier).clear();
    expect(c.read(fireBucketRulesProvider), isEmpty);
  });

  test('corrupt JSON yields empty rule list (no throw)', () async {
    SharedPreferences.setMockInitialValues({
      'naviwealth.fire.bucket_rules_json': 'not valid',
    });
    final prefs = await SharedPreferences.getInstance();
    final c = container(prefs);
    expect(c.read(fireBucketRulesProvider), isEmpty);
  });
}
