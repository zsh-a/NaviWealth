import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/master_detail_layout.dart';
import '../../app/route_paths.dart';
import '../../app/selection_query.dart';
import '../../core/shortcuts/master_detail_shortcuts.dart';
import '../../data/domain/account.dart';
import '../../data/domain/enums.dart';
import '../../data/repositories/providers.dart';
import '../home/data/dashboard_providers.dart';
import '../home/domain/dashboard_models.dart';
import '../investment/data/providers.dart';
import 'asset_detail_page.dart';
import 'physical/data/providers.dart';
import 'ui/assets_list_body.dart';
import 'ui/assets_list_models.dart';

/// Tab body for the Portfolio page's Assets segment.
///
/// Mobile and tablet render a single list. Desktop renders the same list as
/// the master pane and drives the detail pane through the `?selected=` query
/// parameter. This page is always embedded inside [PortfolioPage], so it owns
/// no Scaffold, AppBar, or add action surface.
class AssetsPage extends ConsumerWidget {
  const AssetsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final masterDetail = MasterDetailLayout.shouldUseMasterDetail(
          constraints.maxWidth,
        );
        final selected = selectedQueryOf(context);
        if (masterDetail) {
          final detail = selected == null
              ? const AssetsDetailEmpty()
              : AssetDetailPage(assetId: selected);
          return MasterDetailLayout(
            master: _AssetsMaster(
              selectedAssetId: selected,
              inMasterDetail: true,
            ),
            detail: detail,
          );
        }
        return const _AssetsMaster(
          selectedAssetId: null,
          inMasterDetail: false,
        );
      },
    );
  }
}

class _AssetsMaster extends ConsumerWidget {
  const _AssetsMaster({
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
      path: AppRoutes.portfolio,
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
