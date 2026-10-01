import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:naviwealth/core/format/formatters.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/finance/composition/finance_route_paths.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

import '../data/watchlist_providers.dart';
import 'watchlist_simulation_section.dart';

/// Collection-scoped workspace with a stable route and a single scroll owner.
class WatchlistSimulationsPage extends ConsumerWidget {
  const WatchlistSimulationsPage({
    super.key,
    required this.collectionId,
    this.initialSimulationId,
  });

  final String collectionId;
  final String? initialSimulationId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final scope = WatchlistScope.collection(collectionId);
    return AppPageScaffold(
      title: l10n.watchlistSimulationSectionTitle,
      child: ref
          .watch(watchlistCollectionsProvider)
          .whenOrError(
            context: context,
            onRetry: () => ref.invalidate(watchlistCollectionsProvider),
            data: (collections) {
              final collection = collections
                  .where((entry) => entry.id == collectionId)
                  .firstOrNull;
              if (collection == null) {
                return AppEmptyState(
                  icon: FLucideIcons.folder,
                  title: l10n.watchlistCollectionUnavailable,
                );
              }
              return ref
                  .watch(watchlistItemsForScopeProvider(scope))
                  .whenOrError(
                    context: context,
                    onRetry: () =>
                        ref.invalidate(watchlistItemsForScopeProvider(scope)),
                    data: (items) {
                      // Only completed quote batches may materialize observations.
                      final quotes = ref.watch(
                        watchlistQuoteSnapshotsForScopeProvider(scope),
                      );
                      final snapshots =
                          quotes.value ?? const <WatchlistQuoteSnapshot>[];
                      void refreshQuotes() {
                        for (final item in items) {
                          ref.invalidate(
                            watchlistSymbolQuoteProvider(
                              watchlistSymbolKey(item),
                            ),
                          );
                        }
                        ref.invalidate(
                          watchlistQuoteSnapshotsForScopeProvider(scope),
                        );
                      }

                      return SingleChildScrollView(
                        key: PageStorageKey(
                          'watchlist-simulations-scroll-$collectionId',
                        ),
                        padding: const EdgeInsets.all(AppSpacing.s16),
                        child: AdaptiveContentFrame(
                          maxWidth: AdaptiveMaxWidth.narrow,
                          primary: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _SimulationQuotesStatus(
                                quotes: quotes,
                                snapshots: snapshots,
                                onRefresh: refreshQuotes,
                              ),
                              const SizedBox(height: AppSpacing.s16),
                              WatchlistSimulationSection(
                                collection: collection,
                                items: items,
                                snapshots: snapshots,
                                quotesReady:
                                    !quotes.isLoading && !quotes.hasError,
                                quotesLoading: quotes.isLoading,
                                initialSimulationId: initialSimulationId,
                                onSelected: (id) =>
                                    _selectScenario(context, id),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  );
            },
          ),
    );
  }

  void _selectScenario(BuildContext context, String id) {
    final router = GoRouter.maybeOf(context);
    if (router == null) return;
    final current = GoRouterState.of(context).uri;
    final next = Uri.parse(
      FinanceRoutes.wealthWatchlistSimulationsFor(
        collectionId,
        simulationId: id,
      ),
    );
    if (current == next) return;
    if (router.routerDelegate.currentConfiguration.uri == current) {
      // A directly opened workspace uses declarative routing so its browser
      // address follows selection without adding history or replacing the page.
      Router.neglect(context, () => router.go(next.toString()));
    } else {
      // A pushed workspace must retain the original page beneath it.
      router.replace<void>(next.toString());
    }
  }
}

class _SimulationQuotesStatus extends StatelessWidget {
  const _SimulationQuotesStatus({
    required this.quotes,
    required this.snapshots,
    required this.onRefresh,
  });

  final AsyncValue<List<WatchlistQuoteSnapshot>> quotes;
  final List<WatchlistQuoteSnapshot> snapshots;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final formatters = AppFormatters(locale: Localizations.localeOf(context));
    final unavailable = snapshots
        .where(
          (snapshot) => snapshot.response == null || snapshot.response!.isStale,
        )
        .length;
    final fetchedTimes =
        snapshots
            .map((snapshot) => snapshot.response?.fetchedAt)
            .whereType<DateTime>()
            .toList()
          ..sort();
    return Column(
      key: const ValueKey('watchlist-simulation-quotes-status'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          liveRegion: true,
          child: Text(
            quotes.isLoading
                ? l10n.watchlistSimulationQuotesLoading
                : quotes.hasError
                ? l10n.watchlistSimulationQuotesFailed
                : unavailable > 0
                ? l10n.watchlistSimulationQuoteBatchPartial(
                    unavailable,
                    snapshots.length,
                  )
                : l10n.watchlistSimulationQuotesReady,
            style: context.captionStyle,
          ),
        ),
        if (fetchedTimes.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.s4),
          Text(
            l10n.watchlistSimulationQuotesUpdated(
              formatters.dateTime(fetchedTimes.last),
            ),
            style: context.captionStyle,
          ),
        ],
        const SizedBox(height: AppSpacing.s4),
        AppActionButton(
          key: const ValueKey('watchlist-simulation-quotes-refresh'),
          variant: FButtonVariant.outline,
          mainAxisSize: MainAxisSize.min,
          onPress: quotes.isLoading ? null : onRefresh,
          child: Text(
            quotes.hasError || unavailable > 0
                ? l10n.commonRetry
                : l10n.commonRefresh,
          ),
        ),
      ],
    );
  }
}
