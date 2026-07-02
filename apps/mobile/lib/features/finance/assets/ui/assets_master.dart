import 'package:decimal/decimal.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:naviwealth/core/shell/selection_query.dart';
import 'package:naviwealth/core/shortcuts/master_detail_shortcuts.dart';
import 'package:naviwealth/features/finance/composition/finance_route_paths.dart';
import 'package:naviwealth/features/finance/data/domain/account.dart';
import 'package:naviwealth/features/finance/data/domain/enums.dart';
import 'package:naviwealth/features/finance/data/repositories/providers.dart';
import 'package:naviwealth/features/finance/investment/data/providers.dart';
import 'package:naviwealth/features/home/data/dashboard_providers.dart';
import 'package:naviwealth/features/home/domain/dashboard_models.dart';

import '../physical/data/providers.dart';
import 'assets_list_body.dart';
import 'assets_list_models.dart';

class AssetsMaster extends ConsumerWidget {
  const AssetsMaster({
    super.key,
    required this.selectedAssetId,
    required this.inMasterDetail,
  });

  final String? selectedAssetId;
  final bool inMasterDetail;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final manualAsync = ref.watch(manualAssetsStreamProvider);
    final physicalAsync = ref.watch(physicalAssetsListProvider);
    final securitiesAsync = ref.watch(securitiesAssetsStreamProvider);
    final holdingsAsync = ref.watch(holdingsSnapshotProvider);
    final valuationsAsync = ref.watch(dashboardManualAssetValuationsProvider);
    final accountsAsync = ref.watch(accountsStreamProvider);

    final securitiesOrdered = orderedSecurities(securitiesAsync.value);
    final valuationMap = _valuationMap(valuationsAsync.value);
    final accountById = _accountById(accountsAsync.value);

    final allIds = <String>[
      ...?(manualAsync.value?.map((a) => a.id)),
      ...securitiesOrdered.map((a) => a.id),
      ...?(physicalAsync.value?.map((a) => a.id)),
    ];

    final body = AssetsBody(
      manualAsync: manualAsync,
      physicalAsync: physicalAsync,
      securitiesAsync: securitiesAsync,
      holdingsAsync: holdingsAsync,
      valuationsAsync: valuationsAsync,
      accountsAsync: accountsAsync,
      onRetry: () {
        ref.invalidate(manualAssetsStreamProvider);
        ref.invalidate(physicalAssetsListProvider);
        ref.invalidate(securitiesAssetsStreamProvider);
        ref.invalidate(holdingsSnapshotProvider);
        ref.invalidate(dashboardManualAssetValuationsProvider);
        ref.invalidate(accountsStreamProvider);
      },
      securities: securitiesOrdered,
      holdings: holdingsAsync.value ?? const {},
      valuationMap: valuationMap,
      accountById: accountById,
      selectedAssetId: selectedAssetId,
      inMasterDetail: inMasterDetail,
    );

    return MasterDetailShortcuts(
      onSelectNext: allIds.isEmpty
          ? null
          : () => _selectAdjacent(context, allIds, delta: 1),
      onSelectPrevious: allIds.isEmpty
          ? null
          : () => _selectAdjacent(context, allIds, delta: -1),
      child: body,
    );
  }

  void _selectAdjacent(
    BuildContext context,
    List<String> allIds, {
    required int delta,
  }) {
    if (allIds.isEmpty) return;
    final current = selectedAssetId;
    int nextIndex;
    if (current == null) {
      nextIndex = delta > 0 ? 0 : allIds.length - 1;
    } else {
      final idx = allIds.indexOf(current);
      if (idx < 0) {
        nextIndex = 0;
      } else {
        nextIndex = (idx + delta) % allIds.length;
        if (nextIndex < 0) nextIndex += allIds.length;
      }
    }
    replaceSelectedQuery(
      context,
      path: FinanceRoutes.wealth,
      selected: allIds[nextIndex],
    );
  }
}

Map<String, Decimal> _valuationMap(List<ManualAssetValuation>? valuations) {
  final map = <String, Decimal>{};
  for (final v in valuations ?? const <ManualAssetValuation>[]) {
    final value = v.currentValue();
    if (value != null && (value.sign > 0 || v.asset.type == AssetType.cash)) {
      map[v.asset.id] = value;
    }
  }
  return map;
}

Map<String, Account> _accountById(List<Account>? accounts) {
  return {for (final a in accounts ?? const <Account>[]) a.id: a};
}
