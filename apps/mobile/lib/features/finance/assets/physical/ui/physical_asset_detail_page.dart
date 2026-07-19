import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:intl/intl.dart';

import 'package:naviwealth/core/format/formatters.dart';
import 'package:naviwealth/core/format/providers.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';
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
    return ObjectDetailScaffold(
      title: assetAsync.maybeWhen(
        data: (a) => a?.name ?? l10n.physicalAssetNotFound,
        orElse: () => '',
      ),
      actions: [
        assetAsync.maybeWhen(
          data: (a) => a == null
              ? const SizedBox.shrink()
              : AppHeaderAction(
                  semanticsLabel: l10n.physicalAssetDeleteAction,
                  icon: const Icon(FLucideIcons.trash2),
                  onPress: () => _confirmDelete(context, ref, a.id),
                ),
          orElse: () => const SizedBox.shrink(),
        ),
      ],
      childPad: false,
      child: assetAsync.when(
        loading: () => const AssetDetailSkeleton(),
        error: (error, stackTrace) => AppEmptyState.error(
          title: l10n.commonLoadFailed,
          message: userSafeErrorMessage(context, error, stackTrace: stackTrace),
          retryLabel: l10n.commonRetry,
          onRetry: () => ref.invalidate(physicalAssetDetailProvider(id)),
        ),
        data: (asset) {
          if (asset == null) {
            return Center(child: Text(l10n.physicalAssetNotFound));
          }
          return _DetailBody(asset: asset);
        },
      ),
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    String assetId,
  ) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showConfirmDialog(
      context: context,
      title: Text(l10n.physicalAssetDeleteConfirmTitle),
      body: Text(l10n.physicalAssetDeleteConfirmBody),
      cancelLabel: l10n.commonCancel,
      confirmLabel: l10n.physicalAssetDeleteAction,
      destructive: true,
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
    final formatters = context.formatters(ref);
    final historyAsync = ref.watch(
      physicalAssetValuationHistoryProvider(asset.id),
    );

    final estimatedToday = _estimatedToday(asset);

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.s16),
      children: [
        SoftCard.raised(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.s20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.physicalAssetDetailValuationTitle,
                  style: context.theme.typography.body.md,
                ),
                const SizedBox(height: AppSpacing.s8),
                AnimatedMoneyText(
                  amount: asset.currentValuation.toDouble(),
                  currencyCode: asset.currency,
                  style: TypographyTokens.displayMedium,
                ),
                if (asset.lastValuationAt != null) ...[
                  const SizedBox(height: AppSpacing.s4),
                  Text(
                    formatters.date(asset.lastValuationAt!),
                    style: context.captionStyle,
                  ),
                ],
                if (estimatedToday != null) ...[
                  const SizedBox(height: AppSpacing.s8),
                  Text(
                    l10n.physicalAssetDetailEstimatedToday(estimatedToday),
                    style: context.bodyCaptionStyle,
                  ),
                ],
                const SizedBox(height: AppSpacing.s16),
                FButton(
                  variant: FButtonVariant.primary,
                  onPress: () =>
                      ValuationUpdateSheet.show(context, asset: asset),
                  prefix: const Icon(
                    FLucideIcons.pencil,
                    size: AppIconSizes.sm,
                  ),
                  child: Text(l10n.physicalAssetUpdateValuationAction),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.s12),
        _FactsCard(asset: asset, formatters: formatters),
        const SizedBox(height: AppSpacing.s12),
        SoftCard.raised(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.s16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.physicalAssetDetailHistoryTitle,
                  style: context.theme.typography.body.md,
                ),
                const SizedBox(height: AppSpacing.s12),
                historyAsync.when(
                  loading: () => const Column(
                    children: [
                      SkeletonBox(height: 180),
                      SizedBox(height: AppSpacing.s12),
                      SkeletonBox(height: 18),
                      SizedBox(height: AppSpacing.s8),
                      SkeletonBox(height: 18),
                    ],
                  ),
                  error: (error, stackTrace) => AppEmptyState.error(
                    title: l10n.commonLoadFailed,
                    message: userSafeErrorMessage(
                      context,
                      error,
                      stackTrace: stackTrace,
                    ),
                    retryLabel: l10n.commonRetry,
                    onRetry: () => ref.invalidate(
                      physicalAssetValuationHistoryProvider(asset.id),
                    ),
                  ),
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
                        const SizedBox(height: AppSpacing.s8),
                        ...history.reversed.map(
                          (p) => _HistoryRow(
                            point: p,
                            currency: asset.currency,
                            formatters: formatters,
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
  const _FactsCard({required this.asset, required this.formatters});

  final PhysicalAsset asset;
  final AppFormatters formatters;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final entries = <(String, String)>[
      (
        l10n.physicalAssetFieldPurchaseDate,
        formatters.date(asset.purchaseDate),
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
    return SoftCard.raised(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.s16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final (label, value) in entries) ...[
              Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.s4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(label, style: context.bodyCaptionStyle),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(
                        value,
                        style: context.theme.typography.body.sm,
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
    required this.formatters,
  });

  final ValuationPoint point;
  final String currency;
  final AppFormatters formatters;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final label = switch (point.kind) {
      ValuationPointKind.purchase => l10n.physicalAssetDetailPurchaseLabel,
      ValuationPointKind.manual => l10n.physicalAssetDetailManualUpdateLabel,
      ValuationPointKind.projected => l10n.physicalAssetDetailAutoEstimateLabel,
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.s4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: context.theme.typography.body.xs),
                Text(
                  formatters.date(point.asOf),
                  style: context.theme.typography.body.sm,
                ),
                if (point.note != null && point.note!.isNotEmpty)
                  Text(point.note!, style: context.captionStyle),
              ],
            ),
          ),
          MoneyText(
            amount: point.value.toDouble(),
            currencyCode: currency,
            style: context.theme.typography.body.sm,
          ),
        ],
      ),
    );
  }
}
