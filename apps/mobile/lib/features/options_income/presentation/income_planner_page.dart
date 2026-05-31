import 'package:decimal/decimal.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../../design_system/design_system.dart';
import '../../../domain/values/asset_market.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../application/scan_controller.dart';
import '../application/scan_inputs_bridge.dart';
import '../application/scan_orchestrator.dart' show ScanResult;
import '../data/options_opportunity_cache_repository.dart';
import '../data/providers.dart';
import '../domain/approved_underlying.dart';
import '../domain/option_contract.dart';
import '../domain/options_opportunity.dart';
import '../domain/options_strategy_profile.dart';
import 'approved_underlying_form_sheet.dart';
import 'income_planner_labels.dart';
import 'occ_disclosure_sheet.dart';
import 'opportunity_detail_sheet.dart';
import 'strategy_profile_sheet.dart';
import 'trade_journal_sheet.dart';

/// Top-level Income Planner page (`docs/options-income.md` §9).
class IncomePlannerPage extends ConsumerWidget {
  const IncomePlannerPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (kIsWeb) {
      return const _UnsupportedOnWebPage();
    }
    final l10n = AppLocalizations.of(context);
    final profileAsync = ref.watch(optionsStrategyProfileProvider);
    final acked = profileAsync.value?.hasAcknowledgedRiskDisclosure ?? false;
    final FHeaderAction? settingsAction = acked
        ? FHeaderAction(
            icon: const Icon(FLucideIcons.slidersHorizontal),
            onPress: () => showStrategyProfileSheet(context),
          )
        : null;
    return FScaffold(
      header: FHeader.nested(
        title: Text(l10n.incomePlannerTitle),
        prefixes: [backHeaderAction(context)],
        suffixes: [?settingsAction],
      ),
      childPad: false,
      child: Material(
        color: Colors.transparent,
        child: profileAsync.when(
          loading: () => const _LoadingState(),
          error: (e, _) => _ErrorState(message: '$e'),
          data: (profile) {
            if (profile == null || !profile.hasAcknowledgedRiskDisclosure) {
              return const _StartState();
            }
            return _ConfiguredBody(profile: profile);
          },
        ),
      ),
    );
  }
}

class _LoadingState extends StatelessWidget {
  const _LoadingState();

  @override
  Widget build(BuildContext context) {
    return const Center(child: FCircularProgress());
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.s24),
      child: Text(
        message,
        style: TextStyle(color: context.theme.colors.destructive),
      ),
    );
  }
}

class _UnsupportedOnWebPage extends StatelessWidget {
  const _UnsupportedOnWebPage();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return FScaffold(
      header: FHeader.nested(
        title: Text(l10n.incomePlannerTitle),
        prefixes: [backHeaderAction(context)],
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.s24),
        child: Text(l10n.incomePlannerUnsupportedOnWeb),
      ),
    );
  }
}

class _StartState extends ConsumerWidget {
  const _StartState();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final colors = context.theme.colors;
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.s24),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              FLucideIcons.candlestickChart,
              size: AppIconSizes.hero,
              color: colors.mutedForeground,
            ),
            const SizedBox(height: AppSpacing.s16),
            Text(
              l10n.incomePlannerStartTitle,
              style: context.theme.typography.lg.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: AppSpacing.s8),
            Text(
              l10n.incomePlannerStartBody,
              textAlign: TextAlign.center,
              style: context.theme.typography.sm.copyWith(
                color: colors.mutedForeground,
              ),
            ),
            const SizedBox(height: AppSpacing.s20),
            FButton(
              onPress: () => showOccDisclosureSheet(context),
              child: Text(l10n.incomePlannerStartCta),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConfiguredBody extends ConsumerWidget {
  const _ConfiguredBody({required this.profile});

  final OptionsStrategyProfile profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final approvedAsync = ref.watch(approvedUnderlyingsProvider);
    final scanState = ref.watch(scanControllerProvider);
    final cacheState = ref.watch(latestScanStateProvider);
    final opportunitiesAsync = ref.watch(cachedOpportunitiesProvider);
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.s16),
      children: [
        SectionHeader(
          title: l10n.incomePlannerApprovedSectionTitle,
          trailing: FButton(
            variant: FButtonVariant.outline,
            onPress: () => showApprovedUnderlyingSheet(context),
            child: Text(l10n.incomePlannerAddApprovedCta),
          ),
        ),
        const SizedBox(height: AppSpacing.s8),
        approvedAsync.when(
          loading: () => const _LoadingTile(),
          error: (e, _) => _ErrorState(message: '$e'),
          data: (items) => items.isEmpty
              ? const _ApprovedEmpty()
              : _ApprovedList(items: items),
        ),
        const SizedBox(height: AppSpacing.s24),
        _OpportunitiesHeader(
          state: scanState,
          cacheState: cacheState.value,
          onRefresh: () => _runScan(context, ref),
        ),
        const SizedBox(height: AppSpacing.s8),
        _OpportunitiesBody(
          state: scanState,
          opportunitiesAsync: opportunitiesAsync,
        ),
        const SizedBox(height: AppSpacing.s24),
        const _TradeJournalSection(),
      ],
    );
  }

  Future<void> _runScan(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final controller = ref.read(scanControllerProvider.notifier);
    final side = await ref.read(scanSideInputsProvider.future);
    final result = await controller.runScan(
      availableCash: side.availableCash,
      holdingsBySymbol: side.holdingsBySymbol,
    );
    if (!context.mounted || result == null || result.opportunities.isNotEmpty) {
      return;
    }
    AppMessenger.show(
      context,
      ToastKind.warning,
      result.universe.isEmpty
          ? l10n.incomePlannerRefreshUniverseEmpty
          : l10n.incomePlannerScanNoMatchesToast,
      duration: const Duration(seconds: 5),
    );
  }
}

class _OpportunitiesHeader extends StatelessWidget {
  const _OpportunitiesHeader({
    required this.state,
    required this.cacheState,
    required this.onRefresh,
  });

  final ScanState state;
  final ScanCacheState? cacheState;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final running = state is ScanRunning;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.incomePlannerOpportunitiesSectionTitle,
                style: context.theme.typography.lg.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (cacheState != null) ...[
                const SizedBox(height: AppSpacing.s2),
                Text(
                  _formatLastScan(l10n, cacheState!),
                  style: context.theme.typography.xs.copyWith(
                    color: cacheState!.isStale
                        ? context.theme.colors.destructive
                        : context.theme.colors.mutedForeground,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.s8),
        FButton(
          variant: FButtonVariant.primary,
          onPress: running ? null : onRefresh,
          child: Text(
            running
                ? l10n.incomePlannerRefreshRunning
                : l10n.incomePlannerRefreshAction,
          ),
        ),
      ],
    );
  }

  String _formatLastScan(AppLocalizations l10n, ScanCacheState s) {
    final delta = DateTime.now().toUtc().difference(s.scannedAt);
    final ago = delta.inMinutes < 60
        ? l10n.incomePlannerLastScanMinutes(delta.inMinutes)
        : delta.inHours < 24
        ? l10n.incomePlannerLastScanHours(delta.inHours)
        : l10n.incomePlannerLastScanDays(delta.inDays);
    if (s.isStale) {
      return l10n.incomePlannerLastScanStaleSummary(
        l10n.incomePlannerLastScanLabel,
        ago,
        l10n.incomePlannerLastScanStale,
      );
    }
    return l10n.incomePlannerLastScanFresh(
      l10n.incomePlannerLastScanLabel,
      ago,
      s.count,
    );
  }
}

class _OpportunitiesBody extends StatelessWidget {
  const _OpportunitiesBody({
    required this.state,
    required this.opportunitiesAsync,
  });

  final ScanState state;
  final AsyncValue<List<OptionsOpportunity>> opportunitiesAsync;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (state is ScanFailure) {
      return _ErrorCard(
        title: l10n.incomePlannerRefreshFailedTitle,
        message: '${(state as ScanFailure).error}',
      );
    }
    return opportunitiesAsync.when(
      loading: () => const _LoadingTile(),
      error: (e, _) => _ErrorCard(
        title: l10n.incomePlannerRefreshFailedTitle,
        message: '$e',
      ),
      data: (items) {
        if (items.isEmpty) {
          if (state is ScanSuccess) {
            return _ScanEmptyResultCard(result: (state as ScanSuccess).result);
          }
          return _EmptyCard(body: l10n.incomePlannerOpportunitiesEmpty);
        }
        return Column(
          children: [
            for (final opp in items)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.s4),
                child: _OpportunityCard(opportunity: opp),
              ),
          ],
        );
      },
    );
  }
}

class _OpportunityCard extends StatelessWidget {
  const _OpportunityCard({required this.opportunity});

  final OptionsOpportunity opportunity;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.theme.colors;
    final metrics = opportunity.metrics;
    final contract = opportunity.contract;
    return SoftCard(
      onPress: () => showOpportunityDetailSheet(context, opportunity),
      borderRadius: AppRadius.md,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.s16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _StrategyBadge(strategy: opportunity.strategy),
                const SizedBox(width: AppSpacing.s8),
                _RiskBadge(risk: opportunity.risk),
                const Spacer(),
                Text(
                  '${contract.underlying} ${contract.dte}DTE',
                  style: context.theme.typography.sm.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.s12),
            _MetricsRow(metrics: metrics, contract: contract),
            const SizedBox(height: AppSpacing.s12),
            if (opportunity.explanation.whyGood.isNotEmpty) ...[
              Text(
                l10n.incomePlannerDetailWhyGood,
                style: context.theme.typography.xs.copyWith(
                  fontWeight: FontWeight.w600,
                  color: colors.mutedForeground,
                ),
              ),
              const SizedBox(height: AppSpacing.s2),
              for (final line in opportunity.explanation.whyGood.take(2))
                _BulletRow(line: line),
            ],
            if (opportunity.explanation.whyRisky.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.s8),
              Text(
                l10n.incomePlannerDetailWhyRisky,
                style: context.theme.typography.xs.copyWith(
                  fontWeight: FontWeight.w600,
                  color: colors.destructive,
                ),
              ),
              const SizedBox(height: AppSpacing.s2),
              for (final line in opportunity.explanation.whyRisky.take(2))
                _BulletRow(line: line),
            ],
          ],
        ),
      ),
    );
  }
}

class _MetricsRow extends StatelessWidget {
  const _MetricsRow({required this.metrics, required this.contract});

  final OpportunityMetrics metrics;
  final OptionContract contract;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Wrap(
      spacing: AppSpacing.s12,
      runSpacing: AppSpacing.s8,
      children: [
        _Metric(
          label: l10n.incomePlannerMetricStrike,
          value: MoneyText(
            amount: contract.strike.amount.toDouble(),
            currencyCode: contract.strike.currency,
            symbolStyle: MoneySymbolStyle.isoCode,
            style: context.theme.typography.sm.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        _Metric(
          label: l10n.incomePlannerMetricAnnualized,
          value: Text(
            _pct(metrics.annualizedYield),
            style: context.theme.typography.sm.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        _Metric(
          label: l10n.incomePlannerMetricMargin,
          value: Text(
            _pct(metrics.marginOfSafety),
            style: context.theme.typography.sm.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        _Metric(
          label: l10n.incomePlannerMetricCash,
          value: MoneyText(
            amount: metrics.cashRequired.amount.toDouble(),
            currencyCode: metrics.cashRequired.currency,
            symbolStyle: MoneySymbolStyle.isoCode,
            style: context.theme.typography.sm.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

class _ScanEmptyResultCard extends StatelessWidget {
  const _ScanEmptyResultCard({required this.result});

  final ScanResult result;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.theme.colors;
    final universeEmpty = result.universe.isEmpty;
    final body = universeEmpty
        ? l10n.incomePlannerRefreshUniverseEmpty
        : l10n.incomePlannerOpportunitiesAllRejected;
    return SoftCard(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.s16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.incomePlannerNoMatchesTitle,
              style: context.theme.typography.sm.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: AppSpacing.s4),
            Text(
              body,
              style: context.theme.typography.sm.copyWith(
                color: colors.mutedForeground,
                height: 1.45,
              ),
            ),
            const SizedBox(height: AppSpacing.s8),
            Text(
              l10n.incomePlannerScanSummary(
                result.universe.length,
                result.rejected.length,
                result.errors.length,
              ),
              style: context.theme.typography.xs.copyWith(
                color: colors.mutedForeground,
              ),
            ),
            if (result.errors.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.s4),
              Text(
                result.errors.entries
                    .take(2)
                    .map((e) => '${e.key}: ${e.value}')
                    .join('\n'),
                style: context.theme.typography.xs.copyWith(
                  color: colors.destructive,
                  height: 1.35,
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.s12),
            Wrap(
              spacing: AppSpacing.s8,
              runSpacing: AppSpacing.s8,
              children: [
                FButton(
                  variant: FButtonVariant.outline,
                  onPress: () => showStrategyProfileSheet(context),
                  child: Text(l10n.incomePlannerPreferencesAction),
                ),
                FButton(
                  variant: FButtonVariant.outline,
                  onPress: () => showApprovedUnderlyingSheet(context),
                  child: Text(l10n.incomePlannerAddApprovedCta),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});

  final String label;
  final Widget value;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: context.theme.typography.xs.copyWith(
            color: colors.mutedForeground,
          ),
        ),
        const SizedBox(height: AppSpacing.s2),
        value,
      ],
    );
  }
}

class _BulletRow extends StatelessWidget {
  const _BulletRow({required this.line});

  final String line;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: AppSpacing.s4, top: AppSpacing.s2),
      child: Text(
        '• $line',
        style: context.theme.typography.xs.copyWith(height: 1.4),
      ),
    );
  }
}

class _StrategyBadge extends StatelessWidget {
  const _StrategyBadge({required this.strategy});

  final OptionsStrategyKind strategy;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final label = optionsStrategyKindShortLabel(l10n, strategy);
    final colors = context.theme.colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.primary.withValues(alpha: AppOpacity.light),
        borderRadius: BorderRadius.circular(AppRadius.full),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s8,
          vertical: AppSpacing.s2,
        ),
        child: Text(
          label,
          style: context.theme.typography.xs.copyWith(
            color: colors.primary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _RiskBadge extends StatelessWidget {
  const _RiskBadge({required this.risk});

  final OpportunityRiskLevel risk;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.theme.colors;
    final (label, color) = switch (risk) {
      OpportunityRiskLevel.low => (l10n.incomePlannerRiskLow, colors.primary),
      OpportunityRiskLevel.moderate => (
        l10n.incomePlannerRiskModerate,
        colors.mutedForeground,
      ),
      OpportunityRiskLevel.elevated => (
        l10n.incomePlannerRiskElevated,
        colors.destructive,
      ),
    };
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: AppOpacity.subtle),
        borderRadius: BorderRadius.circular(AppRadius.full),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s8,
          vertical: AppSpacing.s2,
        ),
        child: Text(
          label,
          style: context.theme.typography.xs.copyWith(
            color: color,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard({required this.body});

  final String body;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    return SoftCard(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.s16),
        child: Text(
          body,
          style: context.theme.typography.sm.copyWith(
            color: colors.mutedForeground,
            height: 1.45,
          ),
        ),
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    return SoftCard(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.s16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: context.theme.typography.sm.copyWith(
                fontWeight: FontWeight.w600,
                color: colors.destructive,
              ),
            ),
            const SizedBox(height: AppSpacing.s4),
            Text(
              message,
              style: context.theme.typography.xs.copyWith(
                color: colors.destructive,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ApprovedEmpty extends StatelessWidget {
  const _ApprovedEmpty();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.theme.colors;
    return SoftCard(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.s16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.incomePlannerNoApprovedTitle,
              style: context.theme.typography.sm.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: AppSpacing.s4),
            Text(
              l10n.incomePlannerNoApprovedBody,
              style: context.theme.typography.xs.copyWith(
                color: colors.mutedForeground,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ApprovedList extends StatelessWidget {
  const _ApprovedList({required this.items});

  final List<ApprovedUnderlying> items;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final item in items)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.s4),
            child: _ApprovedTile(item: item),
          ),
      ],
    );
  }
}

class _ApprovedTile extends StatelessWidget {
  const _ApprovedTile({required this.item});

  final ApprovedUnderlying item;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.theme.colors;
    return SoftCard(
      onPress: () => showApprovedUnderlyingSheet(context, existing: item),
      borderRadius: AppRadius.md,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s16,
          vertical: AppSpacing.s12,
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.displaySymbol,
                    style: context.theme.typography.sm.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.s2),
                  Text(
                    item.market.wire,
                    style: context.theme.typography.xs.copyWith(
                      color: colors.mutedForeground,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.s8),
            _StrategyChip(
              label: l10n.incomePlannerProfileAllowPut,
              enabled: item.allowPut,
            ),
            const SizedBox(width: AppSpacing.s6),
            _StrategyChip(
              label: l10n.incomePlannerProfileAllowCall,
              enabled: item.allowCall,
            ),
          ],
        ),
      ),
    );
  }
}

class _StrategyChip extends StatelessWidget {
  const _StrategyChip({required this.label, required this.enabled});

  final String label;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: enabled ? colors.primary.withValues(alpha: AppOpacity.light) : colors.muted,
        borderRadius: BorderRadius.circular(AppRadius.full),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s8,
          vertical: AppSpacing.s2,
        ),
        child: Text(
          label,
          style: context.theme.typography.xs.copyWith(
            color: enabled ? colors.primary : colors.mutedForeground,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

class _LoadingTile extends StatelessWidget {
  const _LoadingTile();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: AppSpacing.s12),
      child: Center(child: FCircularProgress()),
    );
  }
}

class _TradeJournalSection extends ConsumerWidget {
  const _TradeJournalSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final colors = context.theme.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: l10n.incomePlannerJournalSectionTitle,
          trailing: FButton(
            variant: FButtonVariant.outline,
            onPress: () => showTradeJournalSheet(context),
            child: Text(l10n.incomePlannerJournalAddCta),
          ),
        ),
        const SizedBox(height: AppSpacing.s8),
        // Inline live list — keep the planner page light; full history
        // can be opened from the sheet's "All entries" link.
        Consumer(
          builder: (context, ref, _) {
            final entriesAsync = ref.watch(tradeJournalEntriesProvider);
            return entriesAsync.when(
              loading: () => const _LoadingTile(),
              error: (e, _) => _ErrorCard(
                title: l10n.incomePlannerRefreshFailedTitle,
                message: '$e',
              ),
              data: (entries) {
                if (entries.isEmpty) {
                  return _EmptyCard(body: l10n.incomePlannerJournalEmpty);
                }
                return Column(
                  children: [
                    for (final entry in entries.take(3))
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: AppSpacing.s4,
                        ),
                        child: SoftCard(
                          onPress: () => showTradeJournalSheet(
                            context,
                            existingId: entry.id,
                          ),
                          borderRadius: AppRadius.md,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.s16,
                              vertical: AppSpacing.s12,
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '${entry.symbol} · ${entry.optionSymbol}',
                                        style: context.theme.typography.sm
                                            .copyWith(
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const SizedBox(height: AppSpacing.s2),
                                      Text(
                                        tradeJournalStatusLabel(
                                          l10n,
                                          entry.status,
                                        ),
                                        style: context.theme.typography.xs
                                            .copyWith(
                                          color: colors.mutedForeground,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Text(
                                  '+${entry.entryCredit}',
                                  style: context.theme.typography.sm.copyWith(
                                    fontWeight: FontWeight.w600,
                                    color: colors.primary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                );
              },
            );
          },
        ),
      ],
    );
  }
}

String _pct(Decimal value) {
  final pct = (value * Decimal.fromInt(100)).toStringAsFixed(1);
  return '$pct%';
}
