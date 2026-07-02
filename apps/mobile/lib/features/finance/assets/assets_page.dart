import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:naviwealth/core/shell/master_detail_layout.dart';
import 'package:naviwealth/core/shell/selection_query.dart';
import 'asset_detail_page.dart';
import 'ui/assets_list_body.dart';
import 'ui/assets_master.dart';

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
            master: AssetsMaster(
              selectedAssetId: selected,
              inMasterDetail: true,
            ),
            detail: detail,
          );
        }
        return const AssetsMaster(selectedAssetId: null, inMasterDetail: false);
      },
    );
  }
}
