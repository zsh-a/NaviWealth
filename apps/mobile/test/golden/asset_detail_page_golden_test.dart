import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/design_system/preferences/theme_preferences.dart';
import 'package:naviwealth/features/assets/asset_detail_page.dart';
import 'package:naviwealth/features/finance/data/repositories/manual_asset_repository.dart';
import 'package:naviwealth/features/finance/data/repositories/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '_golden_setup.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  // Pin the AssetDetailSkeleton (loading state) by keeping the repository
  // future unresolved. The skeleton itself is the FIR-103 / T3 deliverable
  // we most need to lock visually — full equity-detail rendering would
  // require a Drift in-memory database (see asset_detail_page_test.dart)
  // and a market-data service stub, all for a card layout that's already
  // covered by the unit suite.
  runAllVariants('asset_detail_skeleton', (tester, variant) async {
    final prefs = await SharedPreferences.getInstance();
    final never = Completer<ManualAssetRepository>();
    addTearDown(() {
      if (!never.isCompleted) {
        never.completeError(StateError('test ended'));
      }
    });
    await pumpAndSnapshotMobile(
      tester,
      name: 'asset_detail_skeleton',
      variant: variant,
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        manualAssetRepositoryProvider.overrideWith((_) => never.future),
      ],
      child: const AssetDetailPage(assetId: 'cash-1'),
    );
  });
}
