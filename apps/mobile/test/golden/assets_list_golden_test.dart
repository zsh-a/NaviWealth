import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/data/domain/asset.dart';
import 'package:naviwealth/data/domain/enums.dart';
import 'package:naviwealth/data/domain/hlc.dart';
import 'package:naviwealth/data/domain/sync_meta.dart';
import 'package:naviwealth/data/repositories/providers.dart';
import 'package:naviwealth/design_system/preferences/theme_preferences.dart';
import 'package:naviwealth/features/assets/assets_page.dart';
import 'package:naviwealth/features/assets/physical/data/physical_asset.dart';
import 'package:naviwealth/features/assets/physical/data/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '_golden_setup.dart';

SyncMeta _meta() => SyncMeta(
      ownerUserId: 'u',
      updatedAt: DateTime.utc(2026, 4, 1),
      updatedByDevice: 't',
      hlc: Hlc.zero('t'),
    );

Asset _cash(String id, String name, String price) => Asset(
      id: id,
      type: AssetType.cash,
      symbol: id,
      name: name,
      currency: 'CNY',
      lastPrice: Decimal.parse(price),
      sync: _meta(),
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  runAllVariants('assets_list', (tester, variant) async {
    final prefs = await SharedPreferences.getInstance();
    await pumpAndSnapshotMobile(
      tester,
      name: 'assets_list',
      variant: variant,
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        manualAssetsStreamProvider.overrideWith(
          (_) => Stream.value([
            _cash('cash-1', '工资卡', '120000'),
            _cash('cash-2', '现金账户', '8500'),
            _cash('cash-3', '美元活期', '12000'),
          ]),
        ),
        physicalAssetsListProvider.overrideWith(
          (_) => Stream.value(const <PhysicalAsset>[]),
        ),
      ],
      child: const AssetsPage(),
    );
  });
}
