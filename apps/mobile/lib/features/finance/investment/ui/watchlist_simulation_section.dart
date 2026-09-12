import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/core/format/formatters.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/finance/investment/data/watchlist_providers.dart';
import 'package:naviwealth/features/finance/investment/data/watchlist_repository.dart';
import 'package:naviwealth/features/finance/investment/data/watchlist_simulation_providers.dart';
import 'package:naviwealth/features/finance/investment/data/watchlist_simulation_repository.dart';
import 'package:naviwealth/features/finance/investment/domain/watchlist_simulation_projection.dart';
import 'package:naviwealth/features/finance/market/domain/market_corporate_action.dart';
import 'package:naviwealth/features/finance/market/domain/market_data_service.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

import 'watchlist_simulation_sheets.dart';
import 'watchlist_simulation_support.dart';

/// Paper scenario panel for one watchlist collection.
///
/// Reads only: create/edit/delete all live behind the sheets in
/// `watchlist_simulation_sheets.dart`, and every number shown here is either a
/// point-in-time projection or an observed value series derived on this device.
class WatchlistSimulationSection extends ConsumerWidget {
  const WatchlistSimulationSection({
    super.key,
    required this.collection,
    required this.items,
    required this.snapshots,
  });

  final WatchlistCollection collection;
  final List<WatchlistItem> items;
  final List<WatchlistQuoteSnapshot> snapshots;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final simulationsAsync = ref.watch(watchlistSimulationsProvider);
    final scoped =
        simulationsAsync.asData?.value
            .where((simulation) => simulation.collectionId == collection.id)
            .toList(growable: false) ??
        const <WatchlistSimulation>[];
    return Column(
      key: const ValueKey<String>('watchlist-simulation-section'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _WatchlistSimulationSectionHeader(
          canCreate: items.isNotEmpty,
          onCreate: () => unawaited(
            showWatchlistSimulationCreateSheet(
              context: context,
              collection: collection,
              items: items,
              snapshots: snapshots,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.s8),
        simulationsAsync.whenOrLoading(
          context: context,
          loading: () => const AppGroupedSurface(
            child: Center(child: FCircularProgress()),
          ),
          error: (_, _) => AppGroupedSurface(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.commonLoadFailed, style: context.captionStyle),
                const SizedBox(height: AppSpacing.s8),
                FButton(
                  variant: FButtonVariant.outline,
                  onPress: () => ref.invalidate(watchlistSimulationsProvider),
                  child: Text(l10n.commonRetry),
                ),
              ],
            ),
          ),
          data: (_) {
            if (scoped.isEmpty) {
              return _WatchlistSimulationEmpty(itemsEmpty: items.isEmpty);
            }
            return Column(
              children: [
                for (var index = 0; index < scoped.length; index++) ...[
                  _WatchlistSimulationCard(
                    simulation: scoped[index],
                    items: items,
                    snapshots: snapshots,
                  ),
                  if (index != scoped.length - 1)
                    const SizedBox(height: AppSpacing.s8),
                ],
              ],
            );
          },
        ),
      ],
    );
  }
}

class _WatchlistSimulationSectionHeader extends StatelessWidget {
  const _WatchlistSimulationSectionHeader({
    required this.canCreate,
    required this.onCreate,
  });

  final bool canCreate;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.watchlistSimulationSectionTitle,
                style: context.labelStyle,
              ),
              const SizedBox(height: AppSpacing.s2),
              Text(
                l10n.watchlistSimulationSectionSubtitle,
                style: context.captionStyle,
              ),
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.s8),
        FButton(
          variant: FButtonVariant.outline,
          onPress: canCreate ? onCreate : null,
          child: Text(l10n.watchlistSimulationCreateAction),
        ),
      ],
    );
  }
}

class _WatchlistSimulationEmpty extends StatelessWidget {
  const _WatchlistSimulationEmpty({required this.itemsEmpty});

  final bool itemsEmpty;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AppGroupedSurface(
      padding: const EdgeInsets.all(AppSpacing.s12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            itemsEmpty
                ? l10n.watchlistSimulationNeedsSymbols
                : l10n.watchlistSimulationEmptyBody,
            style: context.captionStyle,
          ),
          const SizedBox(height: AppSpacing.s8),
          Text(
            l10n.watchlistSimulationIsolationNote,
            style: context.captionStyle,
          ),
        ],
      ),
    );
  }
}

class _WatchlistSimulationCard extends ConsumerWidget {
  const _WatchlistSimulationCard({
    required this.simulation,
    required this.items,
    required this.snapshots,
  });

  final WatchlistSimulation simulation;
  final List<WatchlistItem> items;
  final List<WatchlistQuoteSnapshot> snapshots;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final allocationAsync = ref.watch(
      watchlistSimulationAllocationProvider(simulation.id),
    );
    return allocationAsync.whenOrLoading(
      context: context,
      loading: () =>
          const AppGroupedSurface(child: Center(child: FCircularProgress())),
      error: (_, _) => AppGroupedSurface(
        child: FButton(
          variant: FButtonVariant.outline,
          onPress: () => ref.invalidate(
            watchlistSimulationAllocationProvider(simulation.id),
          ),
          child: Text(AppLocalizations.of(context).commonRetry),
        ),
      ),
      data: (allocation) {
        if (allocation.isUsable && allocation.cashWeight != null) {
          return _WatchlistSimulationBody(
            simulation: simulation,
            positions: allocation.positions,
            resolvedCashWeight: allocation.cashWeight!,
            allocationBasisKey: allocation.allocationBasisKey!,
            validAllocationBasisKeys: allocation.validAllocationBasisKeys,
            items: items,
            snapshots: snapshots,
          );
        }
        return _WatchlistSimulationUnavailable(
          simulation: simulation,
          allocation: allocation,
          items: items,
          snapshots: snapshots,
        );
      },
    );
  }
}

/// Recovery surface for a scenario whose allocation snapshot is missing,
/// pending sync, or no longer sums to 100%.
class _WatchlistSimulationUnavailable extends StatelessWidget {
  const _WatchlistSimulationUnavailable({
    required this.simulation,
    required this.allocation,
    required this.items,
    required this.snapshots,
  });

  final WatchlistSimulation simulation;
  final ResolvedWatchlistSimulationAllocation allocation;
  final List<WatchlistItem> items;
  final List<WatchlistQuoteSnapshot> snapshots;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isPending =
        allocation.status == WatchlistSimulationAllocationStatus.pending;
    return AppGroupedSurface(
      key: ValueKey<String>('watchlist-simulation-${simulation.id}'),
      padding: const EdgeInsets.all(AppSpacing.s12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  simulation.name,
                  style: context.rowTitleStyle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              AppIconButton(
                icon: FLucideIcons.pencil,
                tooltip: l10n.watchlistSimulationAdjustAction,
                onPress: () => unawaited(
                  showWatchlistSimulationAllocationSheet(
                    context: context,
                    simulation: simulation,
                    positions: const [],
                    cashWeight: Decimal.one,
                    items: items,
                    snapshots: snapshots,
                  ),
                ),
                size: appActionTargetSize(context),
                iconSize: AppIconSizes.sm,
                surface: AppIconButtonSurface.softMuted,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s8),
          Text(
            isPending
                ? l10n.watchlistSimulationAllocationSyncing
                : l10n.watchlistSimulationAllocationInvalid,
            style: context.captionStyle,
          ),
        ],
      ),
    );
  }
}

class _WatchlistSimulationBody extends ConsumerWidget {
  const _WatchlistSimulationBody({
    required this.simulation,
    required this.positions,
    required this.resolvedCashWeight,
    required this.allocationBasisKey,
    required this.validAllocationBasisKeys,
    required this.items,
    required this.snapshots,
  });

  final WatchlistSimulation simulation;
  final List<WatchlistSimulationPosition> positions;
  final Decimal resolvedCashWeight;
  final String allocationBasisKey;
  final Set<String> validAllocationBasisKeys;
  final List<WatchlistItem> items;
  final List<WatchlistQuoteSnapshot> snapshots;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final formatters = AppFormatters(locale: Localizations.localeOf(context));
    final itemById = {for (final item in items) item.id: item};

    final quoteInputs = _resolveQuoteInputs(snapshots, positions);
    final projection = WatchlistSimulationProjection.calculate(
      positions: positions.map(
        (position) => WatchlistSimulationQuoteInput(
          watchlistItemId: position.watchlistItemId,
          targetWeight: position.targetWeight,
          changePercent: quoteInputs.changeByItemId[position.watchlistItemId],
        ),
      ),
      cashWeight: resolvedCashWeight,
    );

    final observationsAsync = ref.watch(
      watchlistSimulationObservationsProvider(simulation.id),
    );
    final observations = _validObservations(
      observationsAsync.asData?.value,
      simulation: simulation,
      validAllocationBasisKeys: validAllocationBasisKeys,
    );
    final performance = WatchlistSimulationPerformance.fromSeries(
      projectedValues: observations.map(
        (observation) => observation.projectedValue,
      ),
      startingCapital: simulation.startingCapital,
    );

    final sortedPositions = positions.toList()
      ..sort((left, right) => right.targetWeight.compareTo(left.targetWeight));
    final maxWeight = sortedPositions.isEmpty
        ? Decimal.one
        : sortedPositions.first.targetWeight;

    final unpricedLabels = <String>[
      for (final position in sortedPositions)
        if (quoteInputs.changeByItemId[position.watchlistItemId] == null)
          watchlistSimulationSymbolLabel(
            itemById[position.watchlistItemId],
            fallbackId: position.watchlistItemId,
          ),
    ];

    return AppGroupedSurface(
      key: ValueKey<String>('watchlist-simulation-${simulation.id}'),
      padding: const EdgeInsets.all(AppSpacing.s12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _WatchlistSimulationCardHeader(
            simulation: simulation,
            positions: positions,
            resolvedCashWeight: resolvedCashWeight,
            allocationBasisKey: allocationBasisKey,
            items: items,
            snapshots: snapshots,
          ),
          const SizedBox(height: AppSpacing.s12),
          _WatchlistSimulationHero(
            simulation: simulation,
            performance: performance,
            formatters: formatters,
          ),
          const SizedBox(height: AppSpacing.s12),
          _WatchlistSimulationObservationRecorder(
            simulation: simulation,
            projection: projection,
            observedAt: quoteInputs.latestQuoteAt,
            allocationBasisKey: allocationBasisKey,
          ),
          observationsAsync.whenOrLoading(
            context: context,
            loading: () => const SizedBox(
              height: AppControlHeights.chartLoadingState,
              child: Center(child: FCircularProgress()),
            ),
            error: (_, _) => Align(
              alignment: Alignment.centerLeft,
              child: FButton(
                variant: FButtonVariant.outline,
                onPress: () => ref.invalidate(
                  watchlistSimulationObservationsProvider(simulation.id),
                ),
                child: Text(l10n.commonRetry),
              ),
            ),
            data: (raw) => _WatchlistSimulationHistoryChart(
              simulation: simulation,
              observations: _validObservations(
                raw,
                simulation: simulation,
                validAllocationBasisKeys: validAllocationBasisKeys,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.s12),
          AppMetricCluster(
            dense: true,
            items: [
              AppMetricItem(
                label: l10n.watchlistSimulationDailyMove,
                value: formatters.signedPercent(
                  projection.weightedDailyChange.toDouble(),
                  decimalDigits: 2,
                ),
              ),
              AppMetricItem(
                label: l10n.watchlistSimulationPricedWeight,
                value: formatters.percent(
                  projection.pricedWeight.toDouble(),
                  decimalDigits: 0,
                ),
              ),
              AppMetricItem(
                label: l10n.watchlistSimulationCashWeight,
                value: formatters.percent(
                  resolvedCashWeight.toDouble(),
                  decimalDigits: 0,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s8),
          Text(
            l10n.watchlistSimulationDailyMoveAmount(
              formatters.signedMoney(
                projection.dailyMoveAmount(simulation.startingCapital),
                unit: simulation.baseCurrency,
              ),
            ),
            style: context.captionStyle,
          ),
          const SizedBox(height: AppSpacing.s12),
          _WatchlistSimulationPositions(
            positions: sortedPositions,
            maxWeight: maxWeight,
            quoteInputs: quoteInputs,
            itemById: itemById,
            formatters: formatters,
          ),
          if (unpricedLabels.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.s8),
            _WatchlistSimulationMissingQuotes(symbols: unpricedLabels),
          ],
          _WatchlistSimulationDividendRecords(simulation: simulation),
          const SizedBox(height: AppSpacing.s12),
          _WatchlistSimulationMethodDisclosure(
            simulationId: simulation.id,
            notes: [
              l10n.watchlistSimulationMethodNote,
              l10n.watchlistSimulationHistoryDisclaimer,
              l10n.watchlistSimulationIsolationNote,
            ],
          ),
        ],
      ),
    );
  }
}

/// Quote eligibility shared by the projection, the contribution column and the
/// observation recorder.
///
/// Only quotes stamped on the latest available observation day count, and stale
/// quotes are treated as missing rather than frozen at their last price.
class _WatchlistSimulationQuoteInputs {
  const _WatchlistSimulationQuoteInputs({
    required this.changeByItemId,
    required this.latestQuoteAt,
  });

  final Map<String, Decimal?> changeByItemId;
  final DateTime? latestQuoteAt;
}

_WatchlistSimulationQuoteInputs _resolveQuoteInputs(
  List<WatchlistQuoteSnapshot> snapshots,
  List<WatchlistSimulationPosition> positions,
) {
  final positionItemIds = positions
      .map((position) => position.watchlistItemId)
      .toSet();
  DateTime? latestObservationDay;
  for (final snapshot in snapshots) {
    final quote = snapshot.quote;
    if (!positionItemIds.contains(snapshot.item.id) ||
        quote == null ||
        quote.changePercent == null ||
        snapshot.response?.freshness == DataFreshness.stale) {
      continue;
    }
    final day = watchlistSimulationUtcDay(quote.asOf);
    if (latestObservationDay == null || day.isAfter(latestObservationDay)) {
      latestObservationDay = day;
    }
  }
  final changeByItemId = <String, Decimal?>{};
  DateTime? latestQuoteAt;
  for (final snapshot in snapshots) {
    final quote = snapshot.quote;
    final eligible =
        positionItemIds.contains(snapshot.item.id) &&
        quote != null &&
        quote.changePercent != null &&
        snapshot.response?.freshness != DataFreshness.stale &&
        latestObservationDay != null &&
        watchlistSimulationUtcDay(quote.asOf) == latestObservationDay;
    changeByItemId[snapshot.item.id] = eligible ? quote.changePercent : null;
    if (eligible &&
        (latestQuoteAt == null || quote.asOf.isAfter(latestQuoteAt))) {
      latestQuoteAt = quote.asOf;
    }
  }
  return _WatchlistSimulationQuoteInputs(
    changeByItemId: changeByItemId,
    latestQuoteAt: latestQuoteAt,
  );
}

List<WatchlistSimulationObservation> _validObservations(
  List<WatchlistSimulationObservation>? observations, {
  required WatchlistSimulation simulation,
  required Set<String> validAllocationBasisKeys,
}) {
  if (observations == null) return const <WatchlistSimulationObservation>[];
  final baselineDay = watchlistSimulationUtcDay(simulation.baselineAt)
      .toIso8601String()
      .substring(0, 10);
  return observations
      .where((observation) {
        final basisKey = observation.allocationBasisKey;
        if (basisKey != null) {
          return validAllocationBasisKeys.contains(basisKey);
        }
        return observation.observationDay == baselineDay;
      })
      .toList(growable: false);
}

class _WatchlistSimulationCardHeader extends StatelessWidget {
  const _WatchlistSimulationCardHeader({
    required this.simulation,
    required this.positions,
    required this.resolvedCashWeight,
    required this.allocationBasisKey,
    required this.items,
    required this.snapshots,
  });

  final WatchlistSimulation simulation;
  final List<WatchlistSimulationPosition> positions;
  final Decimal resolvedCashWeight;
  final String allocationBasisKey;
  final List<WatchlistItem> items;
  final List<WatchlistQuoteSnapshot> snapshots;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                simulation.name,
                style: context.rowTitleStyle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: AppSpacing.s6),
              AppBadge(
                label: l10n.watchlistSimulationPaperBadge,
                size: AppBadgeSize.compact,
                tone: AppBadgeTone.info,
                icon: FLucideIcons.sparkles,
              ),
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.s8),
        AppIconButton(
          icon: FLucideIcons.slidersHorizontal,
          tooltip: l10n.watchlistSimulationAdjustAction,
          onPress: () => unawaited(
            showWatchlistSimulationAllocationSheet(
              context: context,
              simulation: simulation,
              positions: positions,
              cashWeight: resolvedCashWeight,
              items: items,
              snapshots: snapshots,
            ),
          ),
          size: appActionTargetSize(context),
          iconSize: AppIconSizes.sm,
          surface: AppIconButtonSurface.softMuted,
        ),
        const SizedBox(width: AppSpacing.s8),
        AppIconButton(
          icon: FLucideIcons.trash2,
          tooltip: l10n.watchlistSimulationDeleteAction,
          onPress: () => unawaited(
            deleteWatchlistSimulation(context: context, simulation: simulation),
          ),
          size: appActionTargetSize(context),
          iconSize: AppIconSizes.sm,
          surface: AppIconButtonSurface.softMuted,
        ),
      ],
    );
  }
}

/// Headline answer to "how is this basket doing since I set it up".
class _WatchlistSimulationHero extends StatelessWidget {
  const _WatchlistSimulationHero({
    required this.simulation,
    required this.performance,
    required this.formatters,
  });

  final WatchlistSimulation simulation;
  final WatchlistSimulationPerformance? performance;
  final AppFormatters formatters;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final observed = performance;
    final cumulativeReturn = observed?.hasMoved ?? false
        ? observed!.cumulativeReturn
        : null;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.watchlistSimulationCumulativeReturn,
                style: context.captionStyle,
              ),
              const SizedBox(height: AppSpacing.s6),
              if (cumulativeReturn == null)
                Text('—', style: context.strongTitleStyle)
              else
                DeltaChip(
                  value: cumulativeReturn.toDouble() * 100,
                  format: DeltaFormat.percent,
                  fractionDigits: 2,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.s8,
                    vertical: AppSpacing.s2,
                  ),
                  style: context.strongTitleStyle,
                ),
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.s12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              l10n.watchlistSimulationObservedValue,
              style: context.captionStyle,
            ),
            const SizedBox(height: AppSpacing.s6),
            Text(
              formatters.currency(
                observed?.latestValue ?? simulation.startingCapital,
                code: simulation.baseCurrency,
                decimalDigits: 2,
              ),
              style: context.labelStyle,
            ),
          ],
        ),
      ],
    );
  }
}

class _WatchlistSimulationPositions extends StatelessWidget {
  const _WatchlistSimulationPositions({
    required this.positions,
    required this.maxWeight,
    required this.quoteInputs,
    required this.itemById,
    required this.formatters,
  });

  final List<WatchlistSimulationPosition> positions;
  final Decimal maxWeight;
  final _WatchlistSimulationQuoteInputs quoteInputs;
  final Map<String, WatchlistItem> itemById;
  final AppFormatters formatters;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (positions.isEmpty) {
      return Text(
        l10n.watchlistSimulationNoPositions,
        style: context.captionStyle,
      );
    }
    final maxWeightValue = maxWeight.toDouble();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                l10n.watchlistSimulationPositionsTitle,
                style: context.labelStyle,
              ),
            ),
            Text(
              l10n.watchlistSimulationPositionCount(positions.length),
              style: context.captionStyle,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.s8),
        for (var index = 0; index < positions.length; index++) ...[
          _WatchlistSimulationPositionRow(
            position: positions[index],
            maxWeight: maxWeightValue,
            changePercent:
                quoteInputs.changeByItemId[positions[index].watchlistItemId],
            label: watchlistSimulationItemLabel(
              context,
              itemById[positions[index].watchlistItemId],
              fallbackId: positions[index].watchlistItemId,
            ),
            formatters: formatters,
          ),
          if (index != positions.length - 1)
            const SizedBox(height: AppSpacing.s10),
        ],
      ],
    );
  }
}

class _WatchlistSimulationPositionRow extends StatelessWidget {
  const _WatchlistSimulationPositionRow({
    required this.position,
    required this.maxWeight,
    required this.changePercent,
    required this.label,
    required this.formatters,
  });

  final WatchlistSimulationPosition position;
  final double maxWeight;
  final Decimal? changePercent;
  final String label;
  final AppFormatters formatters;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final contribution = watchlistSimulationContribution(
      targetWeight: position.targetWeight,
      changePercent: changePercent,
    );
    final fraction = maxWeight <= 0
        ? 0.0
        : position.targetWeight.toDouble() / maxWeight;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: context.bodyCaptionStyle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: AppSpacing.s6),
              _WatchlistSimulationWeightBar(fraction: fraction),
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.s12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              formatters.percent(
                position.targetWeight.toDouble(),
                decimalDigits: 2,
              ),
              style: context.captionStrongStyle,
            ),
            const SizedBox(height: AppSpacing.s4),
            if (contribution == null)
              Text(
                l10n.watchlistSimulationPositionUnpriced,
                style: context.captionStyle,
              )
            else
              DeltaText(
                value: contribution.toDouble() * 100,
                format: DeltaFormat.percent,
                fractionDigits: 2,
                style: context.captionStyle,
              ),
          ],
        ),
      ],
    );
  }
}

class _WatchlistSimulationWeightBar extends StatelessWidget {
  const _WatchlistSimulationWeightBar({required this.fraction});

  final double fraction;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final clamped = fraction.isFinite ? fraction.clamp(0.0, 1.0) : 0.0;
    return LayoutBuilder(
      builder: (context, constraints) {
        return Stack(
          children: [
            Container(
              height: AppStroke.indicator,
              decoration: BoxDecoration(
                color: colors.border.withValues(alpha: AppOpacity.subtle),
                borderRadius: BorderRadius.circular(AppRadius.full),
              ),
            ),
            Container(
              height: AppStroke.indicator,
              width: constraints.maxWidth * clamped,
              decoration: BoxDecoration(
                color: colors.primary.withValues(alpha: AppOpacity.prominent),
                borderRadius: BorderRadius.circular(AppRadius.full),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _WatchlistSimulationMissingQuotes extends StatelessWidget {
  const _WatchlistSimulationMissingQuotes({required this.symbols});

  final List<String> symbols;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          FLucideIcons.triangleAlert,
          size: AppIconSizes.xs,
          color: context.appTheme.market.flat.fg,
        ),
        const SizedBox(width: AppSpacing.s6),
        Expanded(
          child: Text(
            l10n.watchlistSimulationMissingQuotes(symbols.join(' · ')),
            style: context.captionStyle,
          ),
        ),
      ],
    );
  }
}

/// Collapses the four fine-print blocks into one disclosure so the card reads
/// as numbers first and caveats on demand.
class _WatchlistSimulationMethodDisclosure extends StatefulWidget {
  const _WatchlistSimulationMethodDisclosure({
    required this.simulationId,
    required this.notes,
  });

  final String simulationId;
  final List<String> notes;

  @override
  State<_WatchlistSimulationMethodDisclosure> createState() =>
      _WatchlistSimulationMethodDisclosureState();
}

class _WatchlistSimulationMethodDisclosureState
    extends State<_WatchlistSimulationMethodDisclosure> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.theme.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppTappable(
          key: ValueKey<String>(
            'watchlist-simulation-method-${widget.simulationId}',
          ),
          onPress: () => setState(() => _expanded = !_expanded),
          borderRadius: const BorderRadius.all(Radius.circular(AppRadius.md)),
          semanticsLabel: l10n.watchlistSimulationMethodDisclosure,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.s4,
              vertical: AppSpacing.s8,
            ),
            child: Row(
              children: [
                Icon(
                  FLucideIcons.info,
                  size: AppIconSizes.sm,
                  color: colors.mutedForeground,
                ),
                const SizedBox(width: AppSpacing.s8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.watchlistSimulationMethodDisclosure,
                        style: context.captionLabelStyle,
                      ),
                      Text(
                        l10n.watchlistSimulationMethodDisclosureHint,
                        style: context.captionStyle,
                      ),
                    ],
                  ),
                ),
                AnimatedRotation(
                  turns: _expanded ? 0.5 : 0,
                  duration: const Duration(milliseconds: 180),
                  child: Icon(
                    FLucideIcons.chevronDown,
                    size: AppIconSizes.sm,
                    color: colors.mutedForeground,
                  ),
                ),
              ],
            ),
          ),
        ),
        AnimatedSizeFade(
          visible: _expanded,
          child: Padding(
            padding: const EdgeInsets.only(
              left: AppSpacing.s4,
              right: AppSpacing.s4,
              top: AppSpacing.s4,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final note in widget.notes) ...[
                  Text(note, style: context.captionStyle),
                  const SizedBox(height: AppSpacing.s8),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Writes one derived observation per UTC day. Renders nothing — it exists so
/// the write is scoped to a mounted subtree with a stable signature.
class _WatchlistSimulationObservationRecorder extends ConsumerStatefulWidget {
  const _WatchlistSimulationObservationRecorder({
    required this.simulation,
    required this.projection,
    required this.observedAt,
    required this.allocationBasisKey,
  });

  final WatchlistSimulation simulation;
  final WatchlistSimulationProjection projection;
  final DateTime? observedAt;
  final String allocationBasisKey;

  @override
  ConsumerState<_WatchlistSimulationObservationRecorder> createState() =>
      _WatchlistSimulationObservationRecorderState();
}

class _WatchlistSimulationObservationRecorderState
    extends ConsumerState<_WatchlistSimulationObservationRecorder> {
  String? _scheduledSignature;

  @override
  Widget build(BuildContext context) {
    _schedule();
    return const SizedBox.shrink();
  }

  void _schedule() {
    final observedAt = widget.observedAt;
    final projection = widget.projection;
    if (observedAt == null || projection.pricedWeight <= Decimal.zero) return;
    final signature = <Object>[
      observedAt.toUtc().toIso8601String(),
      projection.weightedDailyChange,
      projection.pricedWeight,
      projection.missingQuoteWeight,
      widget.simulation.sync.hlc,
      widget.allocationBasisKey,
    ].join('|');
    if (_scheduledSignature == signature) return;
    _scheduledSignature = signature;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || _scheduledSignature != signature) return;
      try {
        await ref.read(watchlistSimulationObservationRecorderProvider)(
          WatchlistSimulationObservationRequest(
            simulation: widget.simulation,
            observedAt: observedAt,
            weightedDailyChange: projection.weightedDailyChange,
            pricedWeight: projection.pricedWeight,
            missingQuoteWeight: projection.missingQuoteWeight,
            allocationBasisKey: widget.allocationBasisKey,
          ),
        );
      } catch (_) {
        if (mounted && _scheduledSignature == signature) {
          _scheduledSignature = null;
        }
      }
    });
  }
}

class _WatchlistSimulationHistoryChart extends StatelessWidget {
  const _WatchlistSimulationHistoryChart({
    required this.simulation,
    required this.observations,
  });

  final WatchlistSimulation simulation;
  final List<WatchlistSimulationObservation> observations;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (observations.isEmpty) {
      return Text(
        l10n.watchlistSimulationHistoryEmpty,
        style: context.captionStyle,
      );
    }
    final locale = Localizations.localeOf(context).toLanguageTag();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: AppChartHeights.simulationHistory,
          child: NwLineChart(
            key: ValueKey<String>(
              'watchlist-simulation-history-chart-${simulation.id}',
            ),
            series: [
              ChartSeries(
                name: l10n.watchlistSimulationHistorySeries,
                points: [
                  for (final observation in observations)
                    ChartPoint(
                      x: observation.observedAt.millisecondsSinceEpoch
                          .toDouble(),
                      y: observation.projectedValue.toDouble(),
                      meta: observation,
                    ),
                ],
              ),
            ],
            xAxis: TimeAxis(
              format: AxisDateFormat.dayMonth,
              locale: locale,
              maxLabels: 4,
            ),
            yAxis: ValueAxis.currency(
              currencyCode: simulation.baseCurrency,
              locale: locale,
              maxLabels: 4,
            ),
            semanticLabel: l10n.watchlistSimulationHistoryChartLabel,
            interpolation: ChartInterpolation.linear,
            filled: true,
            showDots: true,
            showTouchXAxisLabel: true,
          ),
        ),
        if (observations.length == 1) ...[
          const SizedBox(height: AppSpacing.s6),
          Text(
            l10n.watchlistSimulationHistoryBaselineOnly,
            style: context.captionStyle,
          ),
        ],
      ],
    );
  }
}

class _WatchlistSimulationDividendRecords extends ConsumerWidget {
  const _WatchlistSimulationDividendRecords({required this.simulation});

  final WatchlistSimulation simulation;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reconciliation = ref.watch(
      watchlistSimulationActionReconciliationProvider(simulation.id),
    );
    final entries = ref.watch(
      watchlistSimulationActionEntriesProvider(simulation.id),
    );
    final l10n = AppLocalizations.of(context);
    final formatters = AppFormatters(locale: Localizations.localeOf(context));
    return entries.whenOrLoading(
      context: context,
      loading: () => reconciliation.isLoading
          ? const SizedBox(
              height: AppSpacing.s32,
              child: Center(child: FCircularProgress()),
            )
          : const SizedBox.shrink(),
      error: (_, _) => Align(
        alignment: Alignment.centerLeft,
        child: FButton(
          variant: FButtonVariant.outline,
          onPress: () {
            ref
              ..invalidate(
                watchlistSimulationActionEntriesProvider(simulation.id),
              )
              ..invalidate(
                watchlistSimulationActionReconciliationProvider(simulation.id),
              );
          },
          child: Text(l10n.commonRetry),
        ),
      ),
      data: (records) {
        final summary = reconciliation.asData?.value;
        if (records.isEmpty) {
          if (summary?.hasCoverageIssues ?? false) {
            return Padding(
              padding: const EdgeInsets.only(top: AppSpacing.s12),
              child: _DividendCoverageWarning(
                summary: summary!,
                onRetry: () => ref.invalidate(
                  watchlistSimulationActionReconciliationProvider(
                    simulation.id,
                  ),
                ),
              ),
            );
          }
          if (!reconciliation.hasError) return const SizedBox.shrink();
          return Align(
            alignment: Alignment.centerLeft,
            child: FButton(
              variant: FButtonVariant.outline,
              onPress: () => ref.invalidate(
                watchlistSimulationActionReconciliationProvider(simulation.id),
              ),
              child: Text(l10n.commonRetry),
            ),
          );
        }
        final sorted = records.toList()
          ..sort((left, right) {
            final leftDate = left.payDate ?? left.exDate ?? left.recordDate;
            final rightDate = right.payDate ?? right.exDate ?? right.recordDate;
            if (leftDate == null) return rightDate == null ? 0 : 1;
            if (rightDate == null) return -1;
            return rightDate.compareTo(leftDate);
          });
        return Padding(
          padding: const EdgeInsets.only(top: AppSpacing.s12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l10n.watchlistSimulationDividendRecordsTitle,
                style: context.labelStyle,
              ),
              const SizedBox(height: AppSpacing.s8),
              for (var index = 0; index < sorted.length; index++) ...[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        _paperDividendLabel(
                          formatters,
                          sorted[index],
                          cancelledLabel:
                              l10n.watchlistSimulationDividendCancelled,
                          receivableLabel:
                              l10n.watchlistSimulationDividendReceivable,
                          cashPendingTaxLabel:
                              l10n.watchlistSimulationDividendCashPendingTax,
                        ),
                        style: context.bodyCaptionStyle,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.s8),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          l10n.watchlistSimulationDividendPerShare(
                            formatters.currency(
                              sorted[index].cashPerShare,
                              code: sorted[index].currency,
                            ),
                          ),
                          style: context.bodyCaptionStyle,
                        ),
                        if (sorted[index].grossAmount != null &&
                            sorted[index].eligibleQuantity != null)
                          Text(
                            l10n.watchlistSimulationDividendGross(
                              formatters.currency(
                                sorted[index].grossAmount!,
                                code: sorted[index].currency,
                              ),
                              sorted[index].eligibleQuantity!.toString(),
                            ),
                            style: context.captionStyle,
                          ),
                      ],
                    ),
                  ],
                ),
                if (index != sorted.length - 1)
                  const SizedBox(height: AppSpacing.s4),
              ],
              if (summary?.hasCoverageIssues ?? false) ...[
                const SizedBox(height: AppSpacing.s8),
                _DividendCoverageWarning(
                  summary: summary!,
                  onRetry: () => ref.invalidate(
                    watchlistSimulationActionReconciliationProvider(
                      simulation.id,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.s6),
              Text(
                sorted.any(
                      (record) =>
                          record.paperState ==
                              WatchlistSimulationPaperActionState
                                  .receivableGross ||
                          record.paperState ==
                              WatchlistSimulationPaperActionState
                                  .grossCashPendingTax,
                    )
                    ? l10n.watchlistSimulationDividendLifecycleNote
                    : sorted.any(
                        (record) =>
                            record.paperState ==
                            WatchlistSimulationPaperActionState
                                .entitlementRecorded,
                      )
                    ? l10n.watchlistSimulationDividendEntitlementNote
                    : l10n.watchlistSimulationDividendReferenceNote,
                style: context.captionStyle,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _DividendCoverageWarning extends StatelessWidget {
  const _DividendCoverageWarning({
    required this.summary,
    required this.onRetry,
  });

  final WatchlistSimulationActionReconciliation summary;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Text(
            l10n.watchlistSimulationDividendCoverageWarning(
              summary.failedSymbolCount,
              summary.unsupportedSymbolCount,
              summary.partialSymbolCount,
              summary.staleSymbolCount,
            ),
            style: context.captionStyle,
          ),
        ),
        const SizedBox(width: AppSpacing.s8),
        FButton(
          variant: FButtonVariant.outline,
          onPress: onRetry,
          child: Text(l10n.commonRetry),
        ),
      ],
    );
  }
}

String _paperDividendLabel(
  AppFormatters formatters,
  WatchlistSimulationActionEntry entry, {
  required String cancelledLabel,
  required String receivableLabel,
  required String cashPendingTaxLabel,
}) {
  final date = entry.payDate ?? entry.exDate ?? entry.recordDate;
  final parts = <String>[entry.symbol];
  if (date != null) parts.add(formatters.date(date));
  if (entry.status == MarketCorporateActionStatus.cancelled) {
    parts.add(cancelledLabel);
  } else if (entry.paperState ==
      WatchlistSimulationPaperActionState.receivableGross) {
    parts.add(receivableLabel);
  } else if (entry.paperState ==
      WatchlistSimulationPaperActionState.grossCashPendingTax) {
    parts.add(cashPendingTaxLabel);
  }
  return parts.join(' · ');
}
