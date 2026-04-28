import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/domain/enums.dart';
import '../../design_system/design_system.dart';
import '../../l10n/gen/app_localizations.dart';
import 'physical/data/providers.dart';
import 'physical/ui/physical_asset_card.dart';
import 'physical/ui/physical_asset_create_sheet.dart';

class AssetsPage extends ConsumerWidget {
  const AssetsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final physicalAsync = ref.watch(physicalAssetsListProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.assetsAppBarTitle)),
      body: ListView(
        padding: Spacing.pageMobile,
        children: [
          _SectionHeader(title: l10n.physicalAssetsSectionTitle),
          const SizedBox(height: Spacing.s8),
          physicalAsync.when(
            loading: () =>
                const Padding(
                  padding: EdgeInsets.all(Spacing.s24),
                  child: Center(child: CircularProgressIndicator()),
                ),
            error: (e, st) => Card(
              child: Padding(
                padding: Spacing.card,
                child: Text('$e'),
              ),
            ),
            data: (assets) {
              if (assets.isEmpty) {
                return Card(
                  child: Padding(
                    padding: Spacing.card,
                    child: Text(l10n.physicalAssetsEmpty),
                  ),
                );
              }
              return Column(
                children: [
                  for (final asset in assets) ...[
                    PhysicalAssetCard(asset: asset),
                    const SizedBox(height: Spacing.s8),
                  ],
                ],
              );
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddMenu(context),
        icon: const Icon(Icons.add),
        label: Text(l10n.assetsAddAction),
      ),
    );
  }

  Future<void> _showAddMenu(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final picked = await showModalBottomSheet<AssetType>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.home_outlined),
              title: Text(l10n.physicalAssetAddRealEstate),
              onTap: () => Navigator.of(ctx).pop(AssetType.realEstate),
            ),
            ListTile(
              leading: const Icon(Icons.directions_car_outlined),
              title: Text(l10n.physicalAssetAddVehicle),
              onTap: () => Navigator.of(ctx).pop(AssetType.vehicle),
            ),
          ],
        ),
      ),
    );
    if (picked == null || !context.mounted) return;
    final created =
        await PhysicalAssetCreateSheet.show(context, type: picked);
    if (created != null && context.mounted) {
      context.goNamed(
        'physicalAssetDetail',
        pathParameters: {'id': created.id},
      );
    }
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Spacing.s4),
      child: Text(title, style: theme.textTheme.titleMedium),
    );
  }
}
