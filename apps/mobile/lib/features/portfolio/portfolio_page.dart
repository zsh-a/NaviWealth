import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/domain/enums.dart';
import '../../design_system/design_system.dart';
import '../../l10n/gen/app_localizations.dart';
import '../assets/assets_page.dart';
import '../assets/physical/ui/physical_asset_create_sheet.dart';

/// Portfolio tab — shows the unified asset list (securities, manual assets,
/// physical assets) with a simplified add button in the app bar.
class PortfolioPage extends ConsumerWidget {
  const PortfolioPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: GlassAppBar(
        title: Text(l10n.navPortfolio),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_circle_outline),
            tooltip: l10n.assetsAddAction,
            onPressed: () => _showAddSheet(context),
          ),
        ],
      ),
      body: const AssetsPage(),
    );
  }

  void _showAddSheet(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    showGlassModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => ListView(
        shrinkWrap: true,
        children: [
          _sectionHeader(theme, l10n.portfolioAssetsTab),
          ListTile(
            leading: const Icon(Icons.account_balance_wallet_outlined),
            title: Text(l10n.assetsAddCashTitle),
            subtitle: Text(l10n.assetsAddCashSubtitle),
            onTap: () {
              Navigator.of(ctx).pop();
              context.push('/portfolio/new/cash');
            },
          ),
          ListTile(
            leading: const Icon(Icons.savings_outlined),
            title: Text(l10n.assetsAddDepositTitle),
            subtitle: Text(l10n.assetsAddDepositSubtitle),
            onTap: () {
              Navigator.of(ctx).pop();
              context.push('/portfolio/new/deposit');
            },
          ),
          ListTile(
            leading: const Icon(Icons.auto_graph_outlined),
            title: Text(l10n.assetsAddWealthTitle),
            subtitle: Text(l10n.assetsAddWealthSubtitle),
            onTap: () {
              Navigator.of(ctx).pop();
              context.push('/portfolio/new/wealth');
            },
          ),
          ListTile(
            leading: const Icon(Icons.home_outlined),
            title: Text(l10n.physicalAssetAddRealEstate),
            subtitle: Text(l10n.assetsAddRealEstateSubtitle),
            onTap: () {
              Navigator.of(ctx).pop();
              _openPhysicalCreate(context, AssetType.realEstate);
            },
          ),
          ListTile(
            leading: const Icon(Icons.directions_car_outlined),
            title: Text(l10n.physicalAssetAddVehicle),
            subtitle: Text(l10n.assetsAddVehicleSubtitle),
            onTap: () {
              Navigator.of(ctx).pop();
              _openPhysicalCreate(context, AssetType.vehicle);
            },
          ),
          _sectionHeader(theme, l10n.portfolioLiabilitiesTab),
          ListTile(
            leading: const Icon(Icons.payments_outlined),
            title: Text(l10n.assetsAddLiabilityTitle),
            subtitle: Text(l10n.assetsAddLiabilitySubtitle),
            onTap: () {
              Navigator.of(ctx).pop();
              context.push('/portfolio/liabilities/new');
            },
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(ThemeData theme, String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        title,
        style: theme.textTheme.labelMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Future<void> _openPhysicalCreate(
    BuildContext context,
    AssetType type,
  ) async {
    final created = await PhysicalAssetCreateSheet.show(context, type: type);
    if (created != null && context.mounted) {
      context.goNamed(
        'physicalAssetDetail',
        pathParameters: {'id': created.id},
      );
    }
  }
}
