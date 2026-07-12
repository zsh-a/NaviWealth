import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/core/ai/visual/ai_hover_overlay.dart';
import 'package:naviwealth/core/format/formatters.dart';
import 'package:naviwealth/core/format/providers.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/finance/application/read_models/dashboard_providers.dart';
import 'package:naviwealth/features/finance/home/domain/dashboard_models.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

import '../data/fire_providers.dart';
import '../domain/fire_bucket.dart';
import '../domain/fire_bucket_allocator.dart';
import 'fire_ai_capsule.dart';
import 'fire_bucket_mapping_sheet.dart';
import 'fire_status_colors.dart';

/// Buckets card — the second piece of the FIRE OS page after the hero.
///
/// One row per role (cash / defensive / growth / risk reserve / dream)
/// with the current value, the target (if any) and a coverage bar.
/// Tapping a bucket row reveals the contributing assets pulled from
/// the dashboard snapshot. Tapping the "Manage" CTA opens the
/// per-asset mapping sheet.
class FireBucketsCard extends ConsumerStatefulWidget {
  const FireBucketsCard({super.key});

  @override
  ConsumerState<FireBucketsCard> createState() => _FireBucketsCardState();
}

class _FireBucketsCardState extends ConsumerState<FireBucketsCard> {
  final Set<FireBucketRole> _expanded = <FireBucketRole>{};

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final formatters = ref.watch(
      appFormattersProvider(Localizations.localeOf(context)),
    );
    final allocationAsync = ref.watch(fireBucketAllocationProvider);
    // Snapshot is async; an empty map is the safe fallback while it
    // loads so the bucket row's "tap to expand" path doesn't lock up
    // waiting on the network-y bits.
    final snapshotAsync = ref.watch(dashboardSnapshotProvider);
    final itemsById = _itemsById(snapshotAsync.asData?.value);
    return allocationAsync.when(
      loading: () => const _BucketsSkeleton(),
      error: (e, _) => const SizedBox.shrink(),
      data: (allocation) => AiHoverOverlay(
        capsule: FireAiCapsule(
          intent: 'review_cash_bucket',
          source: 'fire_buckets_card',
          objectLabel: l10n.fireOsBucketsTitle,
        ),
        child: SoftCard(
          padding: const EdgeInsets.all(AppSpacing.s16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.fireOsBucketsTitle,
                style: context.theme.typography.body.md,
              ),
              const SizedBox(height: AppSpacing.s4),
              Text(l10n.fireOsBucketsSubtitle, style: context.captionStyle),
              const SizedBox(height: AppSpacing.s12),
              for (final bucket in allocation.buckets) ...[
                _BucketRow(
                  bucket: bucket,
                  formatters: formatters,
                  l10n: l10n,
                  expanded: _expanded.contains(bucket.role),
                  onTap: () => setState(() {
                    if (!_expanded.add(bucket.role)) {
                      _expanded.remove(bucket.role);
                    }
                  }),
                  itemsById: itemsById,
                ),
                const SizedBox(height: AppSpacing.s10),
              ],
              if (allocation.unmappedHoldings.isNotEmpty) ...[
                _UnmappedSection(
                  unmapped: allocation.unmappedHoldings,
                  formatters: formatters,
                  l10n: l10n,
                ),
                const SizedBox(height: AppSpacing.s12),
              ],
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: FButton(
                  variant: FButtonVariant.outline,
                  onPress: () => showFireBucketMappingSheet(context),
                  prefix: const Icon(
                    FLucideIcons.slidersHorizontal,
                    size: AppIconSizes.xs,
                  ),
                  child: Text(l10n.fireOsBucketsManageCta),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Map<String, CategoryItem> _itemsById(DashboardSnapshot? snapshot) {
    if (snapshot == null) return const <String, CategoryItem>{};
    final out = <String, CategoryItem>{};
    for (final allocation in snapshot.allocations) {
      for (final item in allocation.items) {
        out[item.id] = item;
      }
    }
    return out;
  }
}

class _BucketRow extends StatelessWidget {
  const _BucketRow({
    required this.bucket,
    required this.formatters,
    required this.l10n,
    required this.expanded,
    required this.onTap,
    required this.itemsById,
  });

  final FireBucketState bucket;
  final AppFormatters formatters;
  final AppLocalizations l10n;
  final bool expanded;
  final VoidCallback onTap;
  final Map<String, CategoryItem> itemsById;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final statusColor = fireBucketStatusColor(
      SemanticColors.of(context),
      colors,
      bucket.status,
    );
    final coverage = bucket.coverageRatio?.clamp(0.0, 1.5) ?? 0.0;
    final hasTarget = bucket.targetValue.amount.toDouble() > 0;
    final hasAssets = bucket.assetIds.isNotEmpty;
    final currentText = formatters.currency(
      bucket.currentValue.amount,
      code: bucket.currentValue.currency,
    );
    final targetText = formatters.currency(
      bucket.targetValue.amount,
      code: bucket.targetValue.currency,
    );

    return GestureDetector(
      onTap: hasAssets ? onTap : null,
      behavior: HitTestBehavior.opaque,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _roleLabel(l10n, bucket.role),
                  style: context.labelStyle,
                ),
              ),
              if (hasAssets)
                Icon(
                  expanded ? FLucideIcons.chevronUp : FLucideIcons.chevronDown,
                  size: AppIconSizes.sm,
                  color: colors.mutedForeground,
                ),
              const SizedBox(width: AppSpacing.s6),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.s8,
                  vertical: AppSpacing.s2,
                ),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: AppOpacity.light),
                  borderRadius: BorderRadius.circular(AppRadius.full),
                  border: Border.all(
                    color: statusColor.withValues(alpha: AppOpacity.disabled),
                  ),
                ),
                child: Text(
                  _statusLabel(l10n, bucket.status),
                  style: context.captionLabelStyle.copyWith(color: statusColor),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s4),
          Text(
            hasTarget
                ? l10n.fireOsBucketCoverage(currentText, targetText)
                : '$currentText · ${l10n.fireOsBucketNoTarget}',
            style: context.captionStyle,
          ),
          if (hasTarget) ...[
            const SizedBox(height: AppSpacing.s6),
            FDeterminateProgress(
              value: coverage > 1.5 ? 1.0 : coverage / 1.5,
              style: FDeterminateProgressStyle(
                trackDecoration: ShapeDecoration(
                  shape: RoundedSuperellipseBorder(
                    borderRadius: context.theme.style.borderRadius.pill,
                  ),
                  color: colors.muted,
                ),
                fillDecoration: ShapeDecoration(
                  shape: RoundedSuperellipseBorder(
                    borderRadius: context.theme.style.borderRadius.pill,
                  ),
                  color: statusColor,
                ),
              ),
            ),
          ],
          if (hasAssets) ...[
            const SizedBox(height: AppSpacing.s4),
            Text(
              l10n.fireOsBucketAssets(bucket.assetIds.length),
              style: context.captionStyle,
            ),
          ],
          if (expanded && hasAssets) ...[
            const SizedBox(height: AppSpacing.s6),
            _BucketAssetList(
              assetIds: bucket.assetIds,
              itemsById: itemsById,
              formatters: formatters,
            ),
          ],
        ],
      ),
    );
  }
}

/// Drill-down list shown when a bucket row is expanded. Falls back to
/// "id only" when the snapshot hasn't loaded yet — refusing to draw
/// nothing would mask a real plumbing bug.
class _BucketAssetList extends StatelessWidget {
  const _BucketAssetList({
    required this.assetIds,
    required this.itemsById,
    required this.formatters,
  });

  final List<String> assetIds;
  final Map<String, CategoryItem> itemsById;
  final AppFormatters formatters;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s10,
        vertical: AppSpacing.s8,
      ),
      decoration: BoxDecoration(
        color: colors.muted.withValues(alpha: AppOpacity.muted),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final id in assetIds)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.s2),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      itemsById[id]?.name ?? id,
                      style: context.theme.typography.body.xs,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (itemsById[id] != null)
                    Text(
                      formatters.currency(
                        itemsById[id]!.valueInBase.amount,
                        code: itemsById[id]!.valueInBase.currency,
                      ),
                      style: context.captionStyle,
                    ),
                ],
              ),
            ),
        ],
      ),
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
      padding: const EdgeInsets.all(AppSpacing.s10),
      decoration: BoxDecoration(
        color: colors.muted.withValues(alpha: AppOpacity.muted),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.fireOsUnmappedTitle, style: context.labelStyle),
          const SizedBox(height: AppSpacing.s2),
          Text(l10n.fireOsUnmappedSubtitle, style: context.captionStyle),
          const SizedBox(height: AppSpacing.s6),
          for (final u in unmapped.take(5))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.s2),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      u.name,
                      style: context.theme.typography.body.xs,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    formatters.currency(u.value.amount, code: u.value.currency),
                    style: context.captionStyle,
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
    return SoftCard(
      padding: const EdgeInsets.all(AppSpacing.s16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(width: 80, height: 16, color: context.theme.colors.muted),
          const SizedBox(height: AppSpacing.s12),
          for (var i = 0; i < 3; i++) ...[
            Container(
              width: double.infinity,
              height: 20,
              color: context.theme.colors.muted,
            ),
            const SizedBox(height: AppSpacing.s8),
          ],
        ],
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
