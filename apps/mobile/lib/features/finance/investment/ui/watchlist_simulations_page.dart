import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

import '../data/watchlist_providers.dart';
import 'watchlist_simulation_section.dart';

/// Collection-scoped workspace with a stable route and a single scroll owner.
class WatchlistSimulationsPage extends ConsumerWidget {
  const WatchlistSimulationsPage({super.key, required this.collectionId});

  final String collectionId;

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
                      return quotes.whenOrError(
                        context: context,
                        onRetry: () => ref.invalidate(
                          watchlistQuoteSnapshotsForScopeProvider(scope),
                        ),
                        data: (snapshots) => SingleChildScrollView(
                          key: const PageStorageKey(
                            'watchlist-simulations-scroll',
                          ),
                          padding: const EdgeInsets.all(AppSpacing.s16),
                          child: AdaptiveContentFrame(
                            maxWidth: AdaptiveMaxWidth.narrow,
                            primary: WatchlistSimulationSection(
                              collection: collection,
                              items: items,
                              snapshots: snapshots,
                            ),
                          ),
                        ),
                      );
                    },
                  );
            },
          ),
    );
  }
}
