import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../../core/format/formatters.dart';
import '../../../core/format/providers.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../data/fire_providers.dart';
import '../domain/fire_bucket.dart';
import '../domain/fire_bucket_allocator.dart';
import 'fire_bucket_mapping_sheet.dart';

/// Buckets card — the second piece of the FIRE OS page after the hero.
///
/// One row per role (cash / defensive / growth / risk reserve / dream)
/// with the current value, the target (if any) and a coverage bar.
/// Tapping the "Manage" CTA opens the per-asset mapping sheet.
class FireBucketsCard extends ConsumerWidget {
  const FireBucketsCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final formatters = ref.watch(
      appFormattersProvider(Localizations.localeOf(context)),
    );
    final allocationAsync = ref.watch(fireBucketAllocationProvider);
    return allocationAsync.when(
      loading: () => const _BucketsSkeleton(),
      error: (e, _) => const SizedBox.shrink(),
      data: (allocation) => FCard.raw(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.fireOsBucketsTitle, style: context.theme.typography.md),
              const SizedBox(height: 4),
              Text(
                l10n.fireOsBucketsSubtitle,
                style: context.theme.typography.xs.copyWith(
                  color: context.theme.colors.mutedForeground,
                ),
              ),
              const SizedBox(height: 12),
              for (final bucket in allocation.buckets) ...[
                _BucketRow(
                  bucket: bucket,
                  formatters: formatters,
                  l10n: l10n,
                ),
                const SizedBox(height: 10),
              ],
              if (allocation.unmappedHoldings.isNotEmpty) ...[
                _UnmappedSection(
                  unmapped: allocation.unmappedHoldings,
                  formatters: formatters,
                  l10n: l10n,
                ),
                const SizedBox(height: 12),
              ],
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: FButton(
                  variant: FButtonVariant.outline,
                  onPress: () => showFireBucketMappingSheet(context),
                  prefix: const Icon(Icons.tune, size: 14),
                  child: Text(l10n.fireOsBucketsManageCta),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BucketRow extends StatelessWidget {
  const _BucketRow({
    required this.bucket,
    required this.formatters,
    required this.l10n,
  });

  final FireBucketState bucket;
  final AppFormatters formatters;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final statusColor = _statusColor(colors, bucket.status);
    final coverage = bucket.coverageRatio?.clamp(0.0, 1.5) ?? 0.0;
    final hasTarget = bucket.targetValue.amount.toDouble() > 0;
    final currentText = formatters.currency(
      bucket.currentValue.amount,
      code: bucket.currentValue.currency,
    );
    final targetText = formatters.currency(
      bucket.targetValue.amount,
      code: bucket.targetValue.currency,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                _roleLabel(l10n, bucket.role),
                style: context.theme.typography.sm.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 2,
              ),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: statusColor.withValues(alpha: 0.4),
                ),
              ),
              child: Text(
                _statusLabel(l10n, bucket.status),
                style: context.theme.typography.xs.copyWith(color: statusColor),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          hasTarget
              ? l10n.fireOsBucketCoverage(currentText, targetText)
              : '$currentText · ${l10n.fireOsBucketNoTarget}',
          style: context.theme.typography.xs.copyWith(
            color: colors.mutedForeground,
          ),
        ),
        if (hasTarget) ...[
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: coverage > 1.5 ? 1.0 : coverage / 1.5,
              minHeight: 6,
              backgroundColor: colors.muted,
              valueColor: AlwaysStoppedAnimation<Color>(statusColor),
            ),
          ),
        ],
        if (bucket.assetIds.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            l10n.fireOsBucketAssets(bucket.assetIds.length),
            style: context.theme.typography.xs.copyWith(
              color: colors.mutedForeground,
            ),
          ),
        ],
      ],
    );
  }
}

class _UnmappedSection extends StatelessWidget {
  const _UnmappedSection({
    required this.unmapped,
    required this.formatters,
    required this.l10n,
  });

  final List<FireUnmappedHolding> unmapped;
  final AppFormatters formatters;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: colors.muted.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.fireOsUnmappedTitle,
            style: context.theme.typography.sm.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            l10n.fireOsUnmappedSubtitle,
            style: context.theme.typography.xs.copyWith(
              color: colors.mutedForeground,
            ),
          ),
          const SizedBox(height: 6),
          for (final u in unmapped.take(5))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      u.name,
                      style: context.theme.typography.xs,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    formatters.currency(
                      u.value.amount,
                      code: u.value.currency,
                    ),
                    style: context.theme.typography.xs.copyWith(
                      color: colors.mutedForeground,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _BucketsSkeleton extends StatelessWidget {
  const _BucketsSkeleton();

  @override
  Widget build(BuildContext context) {
    return FCard.raw(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(width: 80, height: 16, color: context.theme.colors.muted),
            const SizedBox(height: 12),
            for (var i = 0; i < 3; i++) ...[
              Container(
                width: double.infinity,
                height: 20,
                color: context.theme.colors.muted,
              ),
              const SizedBox(height: 8),
            ],
          ],
        ),
      ),
    );
  }
}

String _roleLabel(AppLocalizations l10n, FireBucketRole role) {
  switch (role) {
    case FireBucketRole.cash:
      return l10n.fireOsBucketRoleCash;
    case FireBucketRole.defensive:
      return l10n.fireOsBucketRoleDefensive;
    case FireBucketRole.growth:
      return l10n.fireOsBucketRoleGrowth;
    case FireBucketRole.riskReserve:
      return l10n.fireOsBucketRoleRiskReserve;
    case FireBucketRole.dream:
      return l10n.fireOsBucketRoleDream;
  }
}

String _statusLabel(AppLocalizations l10n, FireBucketStatus status) {
  switch (status) {
    case FireBucketStatus.onTrack:
      return l10n.fireOsBucketStatusOnTrack;
    case FireBucketStatus.underTarget:
      return l10n.fireOsBucketStatusUnder;
    case FireBucketStatus.overTarget:
      return l10n.fireOsBucketStatusOver;
    case FireBucketStatus.empty:
      return l10n.fireOsBucketStatusEmpty;
  }
}

Color _statusColor(FColors colors, FireBucketStatus status) {
  switch (status) {
    case FireBucketStatus.onTrack:
      return Colors.green.shade600;
    case FireBucketStatus.underTarget:
      return Colors.amber.shade700;
    case FireBucketStatus.overTarget:
      return Colors.blueGrey.shade500;
    case FireBucketStatus.empty:
      return colors.mutedForeground;
  }
}
