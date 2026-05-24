import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/data/domain/asset.dart';
import 'package:naviwealth/data/repositories/providers.dart';
import 'package:naviwealth/design_system/preferences/theme_preferences.dart';
import 'package:naviwealth/domain/entities/fx_rate.dart';
import 'package:naviwealth/features/assets/physical/data/providers.dart';
import 'package:naviwealth/features/fire/presentation/fire_page.dart';
import 'package:naviwealth/features/investment/data/providers.dart';
import 'package:naviwealth/features/investment/domain/models/holding_snapshot.dart';
import 'package:naviwealth/features/liabilities/data/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '_golden_setup.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  // FirePage with no goal configured renders the empty-state CTA — that's
  // the canonical "first time user" surface for FIRE and the highest-value
  // moment to lock down visually.
  runAllVariants('fire_page_unconfigured', (tester, variant) async {
    final prefs = await SharedPreferences.getInstance();
    await pumpAndSnapshotMobile(
      tester,
      name: 'fire_page_unconfigured',
      variant: variant,
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        manualAssetsStreamProvider.overrideWith(
          (_) => Stream.value(const <Asset>[]),
        ),
        physicalAssetsListProvider.overrideWith((_) => Stream.value(const [])),
        liabilitiesStreamProvider.overrideWith((_) => Stream.value(const [])),
        fxRatesStreamProvider.overrideWith(
          (_) => Stream<List<FxRate>>.value(const []),
        ),
        allAssetsStreamProvider.overrideWith((_) => Stream.value(const [])),
        holdingsSnapshotProvider.overrideWith(
          (_) async => const <String, HoldingSnapshot>{},
        ),
      ],
      child: const FirePage(),
    );
  });
}
