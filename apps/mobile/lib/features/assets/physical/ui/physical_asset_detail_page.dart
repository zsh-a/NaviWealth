import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:intl/intl.dart';

import '../../../../design_system/design_system.dart';
import '../../../../l10n/gen/app_localizations.dart';
import '../data/physical_asset.dart';
import '../data/providers.dart';
import '../domain/vehicle_depreciation.dart';
import 'valuation_trend_chart.dart';
import 'valuation_update_sheet.dart';

class PhysicalAssetDetailPage extends ConsumerWidget {
  const PhysicalAssetDetailPage({super.key, required this.id});

  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final assetAsync = ref.watch(physicalAssetDetailProvider(id));
    return FScaffold(
      header: FHeader.nested(
        title: assetAsync.maybeWhen(
          data: (a) => Text(a?.name ?? l10n.physicalAssetNotFound),
          orElse: () => const SizedBox.shrink(),
        ),
        suffixes: [
          assetAsync.maybeWhen(
            data: (a) => a == null
                ? const SizedBox.shrink()
                : FHeaderAction(
                    icon: const Icon(Icons.delete_outline),
                    onPress: () => _confirmDelete(context, ref, a.id),
                  ),
            orElse: () => const SizedBox.shrink(),
          ),
        ],
      ),
      childPad: false,
      child: Material(
        color: Colors.transparent,
        child: assetAsync.when(
          loading: () => const Center(child: FCircularProgress()),
          error: (e, st) => Center(child: Text('$e')),
          data: (asset) {
            if (asset == null) {
              return Center(child: Text(l10n.physicalAssetNotFound));
            }
            return _DetailBody(asset: asset);
          },
        ),
      ),
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    String assetId,
  ) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showFSheet<bool>(
      side: FLayout.btt,
      context: context,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.physicalAssetDeleteConfirmTitle,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(l10n.physicalAssetDeleteConfirmBody),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                FButton(
                  variant: FButtonVariant.ghost,
                  onPress: () => Navigator.of(ctx).pop(false),
                  child: Text(l10n.commonCancel),
                ),
                const SizedBox(width: 8),
                FButton(
                  variant: FButtonVariant.outline,
                  onPress: () => Navigator.of(ctx).pop(true),
                  child: Text(l10n.physicalAssetDeleteAction),
                ),
              ],
            ),
            SizedBox(height: MediaQuery.paddingOf(ctx).bottom),
          ],
        ),
      ),
    );
    if (confirmed != true) return;
    final repo = await ref.read(physicalAssetRepositoryProvider.future);
    await repo.delete(assetId);
    if (context.mounted) Navigator.of(context).pop();
  }
}

class _DetailBody extends ConsumerWidget {
  const _DetailBody({required this.asset});

  final PhysicalAsset asset;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final dateFormat = DateFormat.yMMMd(
      Localizations.maybeLocaleOf(context)?.toString(),
    );
    final historyAsync = ref.watch(
      physicalAssetValuationHistoryProvider(asset.id),
    );

    final estimatedToday = _estimatedToday(asset);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        FCard.raw(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.physicalAssetDetailValuationTitle,
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                AnimatedMoneyText(
                  amount: asset.currentValuation.toDouble(),
                  currencyCode: asset.currency,
                  style: const TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (asset.lastValuationAt != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    dateFormat.format(asset.lastValuationAt!),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
                if (estimatedToday != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    l10n.physicalAssetDetailEstimatedToday(estimatedToday),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.tertiary,
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                FButton(
                  variant: FButtonVariant.primary,
                  onPress: () =>
                      ValuationUpdateSheet.show(context, asset: asset),
                  prefix: const Icon(Icons.edit_outlined, size: 16),
                  child: Text(l10n.physicalAssetUpdateValuationAction),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        _FactsCard(asset: asset, dateFormat: dateFormat),
        const SizedBox(height: 12),
        FCard.raw(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.physicalAssetDetailHistoryTitle,
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                historyAsync.when(
                  loading: () => const Center(child: FCircularProgress()),
                  error: (e, st) => Text('$e'),
                  data: (history) {
                    final projection = _projectionFor(asset, history);
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        ValuationTrendChart(
                          points: history,
                          projection: projection,
                          currency: asset.currency,
                        ),
                        const SizedBox(height: 8),
                        ...history.reversed.map(
                          (p) => _HistoryRow(
                            point: p,
                            currency: asset.currency,
                            dateFormat: dateFormat,
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  String? _estimatedToday(PhysicalAsset a) {
    if (!a.isVehicle || !a.autoDepreciation || a.annualResidualRate == null) {
      return null;
    }
    final estimate = VehicleDepreciation.estimate(
      purchasePrice: a.purchasePrice,
      purchaseDate: a.purchaseDate,
      annualResidualRate: a.annualResidualRate!,
      asOf: DateTime.now(),
    );
    return NumberFormat.simpleCurrency(
      name: a.currency,
    ).format(estimate.toDouble());
  }

  List<ValuationPoint> _projectionFor(
    PhysicalAsset a,
    List<ValuationPoint> history,
  ) {
    if (!a.isVehicle || !a.autoDepreciation || a.annualResidualRate == null) {
      return const [];
    }
    final lastManual = history
        .where((p) => p.kind != ValuationPointKind.projected)
        .fold<DateTime?>(
          null,
          (acc, p) => acc == null || p.asOf.isAfter(acc) ? p.asOf : acc,
        );
    final from = lastManual ?? a.purchaseDate;
    final to = DateTime.now();
    if (!to.isAfter(from)) return const [];
    return VehicleDepreciation.projectMonthly(
      purchasePrice: a.purchasePrice,
      purchaseDate: a.purchaseDate,
      annualResidualRate: a.annualResidualRate!,
      from: from,
      to: to,
    );
  }
}

class _FactsCard extends StatelessWidget {
  const _FactsCard({required this.asset, required this.dateFormat});

  final PhysicalAsset asset;
  final DateFormat dateFormat;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final entries = <(String, String)>[
      (
        l10n.physicalAssetFieldPurchaseDate,
        dateFormat.format(asset.purchaseDate),
      ),
      (
        l10n.physicalAssetFieldPurchasePrice,
        NumberFormat.simpleCurrency(
          name: asset.currency,
        ).format(asset.purchasePrice.toDouble()),
      ),
      if (asset.address != null && asset.address!.isNotEmpty)
        (l10n.physicalAssetFieldAddress, asset.address!),
      if (asset.annualResidualRate != null)
        (
          l10n.physicalAssetFieldAnnualResidualRate,
          asset.annualResidualRate!.toString(),
        ),
      if (asset.linkedLiabilityId != null &&
          asset.linkedLiabilityId!.isNotEmpty)
        (l10n.physicalAssetFieldLinkedLiability, asset.linkedLiabilityId!),
    ];
    return FCard.raw(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final (label, value) in entries) ...[
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        label,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(
                        value,
                        style: theme.textTheme.bodyMedium,
                        textAlign: TextAlign.end,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({
    required this.point,
    required this.currency,
    required this.dateFormat,
  });

  final ValuationPoint point;
  final String currency;
  final DateFormat dateFormat;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final label = switch (point.kind) {
      ValuationPointKind.purchase => l10n.physicalAssetDetailPurchaseLabel,
      ValuationPointKind.manual => l10n.physicalAssetDetailManualUpdateLabel,
      ValuationPointKind.projected => l10n.physicalAssetDetailAutoEstimateLabel,
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: theme.textTheme.bodySmall),
                Text(
                  dateFormat.format(point.asOf),
                  style: theme.textTheme.bodyMedium,
                ),
                if (point.note != null && point.note!.isNotEmpty)
                  Text(
                    point.note!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          MoneyText(
            amount: point.value.toDouble(),
            currencyCode: currency,
            style: theme.textTheme.titleSmall,
          ),
        ],
      ),
    );
  }
}
