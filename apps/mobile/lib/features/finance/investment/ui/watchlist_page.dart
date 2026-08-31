import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:naviwealth/core/forms/form_dirty_guard.dart';
import 'package:naviwealth/core/forms/form_submission.dart';
import 'package:naviwealth/core/logging/providers.dart';
import 'package:naviwealth/core/shell/master_detail_layout.dart';
import 'package:naviwealth/core/shell/selection_query.dart';
import 'package:naviwealth/core/shell/shell_chrome.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/finance/composition/finance_route_paths.dart';
import 'package:naviwealth/features/finance/market/domain/asset_market.dart';
import 'package:naviwealth/features/finance/market/domain/market_data_service.dart';
import 'package:naviwealth/features/finance/shared/ui/forms/symbol_field.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

import '../data/watchlist_providers.dart';
import '../data/watchlist_repository.dart';

const _pollInterval = Duration(minutes: 5);
const _collectionQueryKey = 'collection';
const _ungroupedQueryValue = 'ungrouped';

class WatchlistPage extends ConsumerStatefulWidget {
  const WatchlistPage({super.key});

  @override
  ConsumerState<WatchlistPage> createState() => _WatchlistPageState();
}

class _WatchlistPageState extends ConsumerState<WatchlistPage> {
  Timer? _pollTimer;
  final Set<String> _alertSignatures = {};

  @override
  void initState() {
    super.initState();
    _pollTimer = Timer.periodic(_pollInterval, (_) {
      if (mounted) {
        ref.invalidate(watchlistQuoteSnapshotsProvider);
        ref.invalidate(watchlistQuoteSnapshotsForScopeProvider);
      }
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final allItems = ref.watch(watchlistItemsProvider);
    final collectionsAsync = ref.watch(watchlistCollectionsProvider);
    final membersAsync = ref.watch(watchlistCollectionMembersProvider);
    final collections = collectionsAsync.value ?? const <WatchlistCollection>[];
    final requestedScope = _watchlistScopeOf(context);
    final selectedCollection = requestedScope.collectionId == null
        ? null
        : collections
              .where((entry) => entry.id == requestedScope.collectionId)
              .firstOrNull;
    final scope =
        requestedScope.collectionId != null &&
            collectionsAsync.hasValue &&
            selectedCollection == null
        ? const WatchlistScope.all()
        : requestedScope;
    final items = scope.isAll
        ? allItems
        : ref.watch(watchlistItemsForScopeProvider(scope));
    final quotes = scope.isAll
        ? ref.watch(watchlistQuoteSnapshotsProvider)
        : ref.watch(watchlistQuoteSnapshotsForScopeProvider(scope));

    ref.listen(
      scope.isAll
          ? watchlistQuoteSnapshotsProvider
          : watchlistQuoteSnapshotsForScopeProvider(scope),
      (_, next) {
        next.whenData((snapshots) => _notifyAlerts(context, snapshots));
      },
    );

    return AppPageScaffold(
      title: l10n.watchlistTitle,
      actions: [
        AppHeaderAction(
          icon: const Icon(FLucideIcons.refreshCw),
          semanticsLabel: l10n.commonRefresh,
          onPress: () {
            ref.invalidate(watchlistQuoteSnapshotsProvider);
            ref.invalidate(watchlistQuoteSnapshotsForScopeProvider);
          },
        ),
        if (selectedCollection != null)
          AppHeaderAction(
            icon: const Icon(FLucideIcons.folderCog),
            semanticsLabel: l10n.watchlistEditCollectionAction,
            onPress: () => _editCollection(selectedCollection),
          ),
        AppHeaderAction(
          icon: const Icon(FLucideIcons.plus),
          semanticsLabel: l10n.watchlistAddAction,
          onPress: () => showWatchlistItemSheet(
            context: context,
            initialCollectionId: scope.collectionId,
          ),
        ),
      ],
      childPad: false,
      child: items.whenOrError(
        context: context,
        data: (items) => _WatchlistBody(
          items: items,
          collections: collections,
          scope: scope,
          snapshots: quotes.value ?? const [],
          loadingQuotes: quotes.isLoading,
          onScopeSelected: (next) => _replaceWatchlistScope(context, next),
          onCreateCollection: _createCollection,
          onAdd: () => showWatchlistItemSheet(
            context: context,
            initialCollectionId: scope.collectionId,
          ),
          onEdit: (item) =>
              showWatchlistItemSheet(context: context, item: item),
          onManageCollections: (item) =>
              showWatchlistMembershipSheet(context: context, item: item),
          onRemoveFromCollection: scope.collectionId == null
              ? null
              : (item) => _removeFromCollection(
                  item,
                  scope.collectionId!,
                  membersAsync.value ?? const <WatchlistCollectionMember>[],
                ),
          onRemove: (item) => _removeItem(item),
        ),
        error: (error, _) => AppEmptyState.error(
          title: l10n.commonLoadFailed,
          message: userSafeErrorMessage(context, error),
          retryLabel: l10n.commonRetry,
          onRetry: () {
            ref.invalidate(watchlistItemsProvider);
            ref.invalidate(watchlistQuoteSnapshotsProvider);
            ref.invalidate(watchlistCollectionsProvider);
            ref.invalidate(watchlistCollectionMembersProvider);
            ref.invalidate(watchlistQuoteSnapshotsForScopeProvider);
          },
        ),
      ),
    );
  }

  void _notifyAlerts(
    BuildContext context,
    List<WatchlistQuoteSnapshot> snapshots,
  ) {
    if (!mounted) return;
    final l10n = AppLocalizations.of(context);
    for (final snapshot in snapshots) {
      final quote = snapshot.quote;
      final rules = snapshot.item.alertRules;
      if (quote == null || !rules.enabled || !rules.hasRule) continue;
      final price = quote.price;
      final above = rules.above;
      if (above != null && price >= above) {
        _showOnce(
          context,
          '${snapshot.item.id}:above:${above.toString()}',
          l10n.watchlistAlertTriggeredAbove(
            snapshot.item.displaySymbol,
            price.toString(),
          ),
        );
      }
      final below = rules.below;
      if (below != null && price <= below) {
        _showOnce(
          context,
          '${snapshot.item.id}:below:${below.toString()}',
          l10n.watchlistAlertTriggeredBelow(
            snapshot.item.displaySymbol,
            price.toString(),
          ),
        );
      }
    }
  }

  void _showOnce(BuildContext context, String signature, String message) {
    if (!_alertSignatures.add(signature)) return;
    AppMessenger.show(context, ToastKind.warning, message);
  }

  Future<void> _removeItem(WatchlistItem item) async {
    final l10n = AppLocalizations.of(context);
    final repo = await ref.read(watchlistRepositoryProvider.future);
    final collectionIds = await repo.remove(item);
    ref.invalidate(watchlistQuoteSnapshotsProvider);
    ref.invalidate(watchlistQuoteSnapshotsForScopeProvider);
    if (!mounted) return;
    final undo = FormUndoAction(() async {
      await repo.add(
        symbol: item.symbol,
        market: item.market,
        rules: item.alertRules,
        collectionIds: collectionIds,
      );
      ref.invalidate(watchlistQuoteSnapshotsProvider);
      ref.invalidate(watchlistQuoteSnapshotsForScopeProvider);
    });
    AppMessenger.show(
      context,
      ToastKind.success,
      l10n.commonDeleted,
      actionLabel: l10n.commonUndo,
      onAction: () => unawaited(
        runFormUndoWithFeedback(
          context: context,
          action: undo,
          logger: ref.read(loggerProvider),
          successMessage: l10n.commonUndoSucceeded,
          failureMessage: (_) => l10n.commonUndoFailed,
          retryLabel: l10n.commonRetry,
          tag: 'watchlist-remove',
        ),
      ),
    );
  }

  Future<void> _createCollection() async {
    await showWatchlistCollectionSheet(context: context);
  }

  Future<void> _editCollection(WatchlistCollection collection) async {
    final deleted = await showWatchlistCollectionSheet(
      context: context,
      collection: collection,
    );
    if (deleted == true && mounted) {
      _replaceWatchlistScope(context, const WatchlistScope.all());
    }
  }

  Future<void> _removeFromCollection(
    WatchlistItem item,
    String collectionId,
    List<WatchlistCollectionMember> members,
  ) async {
    final previousIds = members
        .where((entry) => entry.watchlistItemId == item.id)
        .map((entry) => entry.collectionId)
        .toSet();
    final remainingIds = Set<String>.from(previousIds)..remove(collectionId);
    final repo = await ref.read(watchlistRepositoryProvider.future);
    await repo.setCollectionsForItem(item: item, collectionIds: remainingIds);
    ref.invalidate(watchlistQuoteSnapshotsForScopeProvider);
    if (!mounted) return;
    final l10n = AppLocalizations.of(context);
    final undo = FormUndoAction(() async {
      await repo.setCollectionsForItem(item: item, collectionIds: previousIds);
      ref.invalidate(watchlistQuoteSnapshotsForScopeProvider);
    });
    AppMessenger.show(
      context,
      ToastKind.success,
      l10n.watchlistRemovedFromCollection,
      actionLabel: l10n.commonUndo,
      onAction: () => unawaited(
        runFormUndoWithFeedback(
          context: context,
          action: undo,
          logger: ref.read(loggerProvider),
          successMessage: l10n.commonUndoSucceeded,
          failureMessage: (_) => l10n.commonUndoFailed,
          retryLabel: l10n.commonRetry,
          tag: 'watchlist-remove-from-collection',
        ),
      ),
    );
  }
}

class _WatchlistBody extends StatelessWidget {
  const _WatchlistBody({
    required this.items,
    required this.collections,
    required this.scope,
    required this.snapshots,
    required this.loadingQuotes,
    required this.onScopeSelected,
    required this.onCreateCollection,
    required this.onAdd,
    required this.onEdit,
    required this.onManageCollections,
    required this.onRemoveFromCollection,
    required this.onRemove,
  });

  final List<WatchlistItem> items;
  final List<WatchlistCollection> collections;
  final WatchlistScope scope;
  final List<WatchlistQuoteSnapshot> snapshots;
  final bool loadingQuotes;
  final ValueChanged<WatchlistScope> onScopeSelected;
  final VoidCallback onCreateCollection;
  final VoidCallback onAdd;
  final ValueChanged<WatchlistItem> onEdit;
  final ValueChanged<WatchlistItem> onManageCollections;
  final ValueChanged<WatchlistItem>? onRemoveFromCollection;
  final ValueChanged<WatchlistItem> onRemove;

  @override
  Widget build(BuildContext context) {
    final byId = {for (final snapshot in snapshots) snapshot.item.id: snapshot};
    Widget list({ValueChanged<String>? onSelect}) => AdaptiveContentFrame(
      maxWidth: AdaptiveMaxWidth.narrow,
      expandSinglePrimary: true,
      primary: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: shellTabContentPadding(
          context,
          left: AppSpacing.s0,
          top: AppSpacing.s0,
          right: AppSpacing.s0,
          bottom: AppSpacing.s16,
        ),
        children: [
          _WatchlistCollectionBar(
            collections: collections,
            scope: scope,
            onSelected: onScopeSelected,
            onCreate: onCreateCollection,
          ),
          const SizedBox(height: AppSpacing.s8),
          if (items.isEmpty)
            _WatchlistEmpty(onAdd: onAdd)
          else
            AppGroupedSurface(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  for (var i = 0; i < items.length; i++) ...[
                    _WatchlistRow(
                      item: items[i],
                      snapshot: byId[items[i].id],
                      loadingQuote: loadingQuotes && byId[items[i].id] == null,
                      onEdit: () => onEdit(items[i]),
                      onManageCollections: () => onManageCollections(items[i]),
                      onRemoveFromCollection: onRemoveFromCollection == null
                          ? null
                          : () => onRemoveFromCollection!(items[i]),
                      onRemove: () => onRemove(items[i]),
                      onSelect: onSelect == null
                          ? null
                          : () => onSelect(items[i].id),
                    ),
                    if (i != items.length - 1)
                      const AppGroupedDivider(
                        indent: AppSpacing.s12,
                        endIndent: AppSpacing.s12,
                      ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (GoRouter.maybeOf(context) == null ||
            !MasterDetailLayout.shouldUseMasterDetail(constraints.maxWidth) ||
            items.isEmpty) {
          return list();
        }
        final selectedId = selectedQueryOf(context);
        final selectedItem = items
            .where((item) => item.id == selectedId)
            .firstOrNull;
        return MasterDetailLayout(
          master: list(
            onSelect: (id) => replaceSelectedQuery(
              context,
              path: FinanceRoutes.wealthWatchlist,
              selected: id,
            ),
          ),
          detail: selectedItem == null
              ? MasterDetailEmpty(
                  message: AppLocalizations.of(context).watchlistSelectItem,
                  icon: FLucideIcons.bellRing,
                )
              : _WatchlistDetail(
                  item: selectedItem,
                  snapshot: byId[selectedItem.id],
                  loadingQuote: loadingQuotes && byId[selectedItem.id] == null,
                  onEdit: () => onEdit(selectedItem),
                  onManageCollections: () => onManageCollections(selectedItem),
                  onRemoveFromCollection: onRemoveFromCollection == null
                      ? null
                      : () => onRemoveFromCollection!(selectedItem),
                  onRemove: () => onRemove(selectedItem),
                ),
        );
      },
    );
  }
}

class _WatchlistCollectionBar extends StatelessWidget {
  const _WatchlistCollectionBar({
    required this.collections,
    required this.scope,
    required this.onSelected,
    required this.onCreate,
  });

  final List<WatchlistCollection> collections;
  final WatchlistScope scope;
  final ValueChanged<WatchlistScope> onSelected;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.s12,
        AppSpacing.s8,
        AppSpacing.s12,
        AppSpacing.s4,
      ),
      child: Row(
        children: [
          AppFilterChip(
            label: l10n.watchlistAllCollection,
            active: scope.isAll,
            onPress: () => onSelected(const WatchlistScope.all()),
          ),
          const SizedBox(width: AppSpacing.s8),
          AppFilterChip(
            label: l10n.watchlistUngroupedCollection,
            active: scope.ungrouped,
            onPress: () => onSelected(const WatchlistScope.ungrouped()),
          ),
          for (final collection in collections) ...[
            const SizedBox(width: AppSpacing.s8),
            AppFilterChip(
              label: collection.name,
              active: scope.collectionId == collection.id,
              onPress: () =>
                  onSelected(WatchlistScope.collection(collection.id)),
            ),
          ],
          const SizedBox(width: AppSpacing.s8),
          AppIconButton(
            icon: FLucideIcons.folderPlus,
            tooltip: l10n.watchlistCreateCollectionAction,
            onPress: onCreate,
            size: appActionTargetSize(context),
            iconSize: AppIconSizes.sm,
            surface: AppIconButtonSurface.softMuted,
          ),
        ],
      ),
    );
  }
}

class _WatchlistEmpty extends StatelessWidget {
  const _WatchlistEmpty({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AppEmptyState(
      icon: FLucideIcons.bellRing,
      title: l10n.watchlistEmptyTitle,
      message: l10n.watchlistEmptyBody,
      action: FButton(onPress: onAdd, child: Text(l10n.watchlistAddAction)),
    );
  }
}

class _WatchlistRow extends StatelessWidget {
  const _WatchlistRow({
    required this.item,
    required this.snapshot,
    required this.loadingQuote,
    required this.onEdit,
    required this.onManageCollections,
    required this.onRemoveFromCollection,
    required this.onRemove,
    this.onSelect,
  });

  final WatchlistItem item;
  final WatchlistQuoteSnapshot? snapshot;
  final bool loadingQuote;
  final VoidCallback onEdit;
  final VoidCallback onManageCollections;
  final VoidCallback? onRemoveFromCollection;
  final VoidCallback onRemove;
  final VoidCallback? onSelect;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.theme.colors;
    final quote = snapshot?.quote;
    final actionsTitle = l10n.watchlistRowActionsTitle(item.displaySymbol);
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.s12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: colors.foreground.withValues(
                    alpha: AppOpacity.whisper,
                  ),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                alignment: Alignment.center,
                child: Icon(
                  _marketIcon(item.market),
                  size: AppIconSizes.md,
                  color: colors.mutedForeground,
                ),
              ),
              const SizedBox(width: AppSpacing.s12),
              Expanded(
                child: AppTappable(
                  onPress: onSelect,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: AppSpacing.s8,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.displaySymbol, style: context.labelStyle),
                        Text(
                          _marketLabel(l10n, item.market),
                          style: context.captionStyle,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              if (loadingQuote)
                const SizedBox(
                  width: AppIconSizes.h18,
                  height: AppIconSizes.h18,
                  child: FCircularProgress(),
                )
              else if (quote == null)
                Text(
                  l10n.watchlistPriceUnavailable,
                  style: context.theme.typography.body.lg,
                )
              else
                MoneyText(
                  amount: quote.price.toDouble(),
                  currencyCode: quote.currency,
                  style: context.theme.typography.body.lg,
                ),
              const SizedBox(width: AppSpacing.s4),
              AppAdaptiveActionMenu(
                title: actionsTitle,
                actions: <AppAdaptiveAction>[
                  AppAdaptiveAction(
                    icon: FLucideIcons.layers,
                    title: l10n.watchlistManageCollectionsAction,
                    onPress: onManageCollections,
                  ),
                  AppAdaptiveAction(
                    icon: FLucideIcons.bell,
                    title: l10n.watchlistEditAlertsAction,
                    onPress: onEdit,
                  ),
                  if (onRemoveFromCollection != null)
                    AppAdaptiveAction(
                      icon: FLucideIcons.folderMinus,
                      title: l10n.watchlistRemoveFromCollectionAction,
                      onPress: onRemoveFromCollection!,
                    ),
                  AppAdaptiveAction(
                    icon: FLucideIcons.trash2,
                    title: l10n.watchlistRemoveAction,
                    destructive: true,
                    onPress: onRemove,
                  ),
                ],
                triggerBuilder: (context, openMenu, focusNode) => Focus(
                  focusNode: focusNode,
                  child: AppIconButton(
                    icon: FLucideIcons.ellipsisVertical,
                    tooltip: actionsTitle,
                    onPress: openMenu,
                    size: appActionTargetSize(context),
                    iconSize: AppIconSizes.sm,
                    surface: AppIconButtonSurface.softMuted,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s10),
          Wrap(
            spacing: AppSpacing.s8,
            runSpacing: AppSpacing.s8,
            children: [
              _FreshnessChip(snapshot: snapshot),
              if (item.alertRules.above != null)
                _RuleChip(
                  label: l10n.watchlistAlertAboveChip(
                    item.alertRules.above.toString(),
                  ),
                ),
              if (item.alertRules.below != null)
                _RuleChip(
                  label: l10n.watchlistAlertBelowChip(
                    item.alertRules.below.toString(),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _WatchlistDetail extends StatelessWidget {
  const _WatchlistDetail({
    required this.item,
    required this.snapshot,
    required this.loadingQuote,
    required this.onEdit,
    required this.onManageCollections,
    required this.onRemoveFromCollection,
    required this.onRemove,
  });

  final WatchlistItem item;
  final WatchlistQuoteSnapshot? snapshot;
  final bool loadingQuote;
  final VoidCallback onEdit;
  final VoidCallback onManageCollections;
  final VoidCallback? onRemoveFromCollection;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final quote = snapshot?.quote;
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.s24),
      children: [
        Text(item.displaySymbol, style: context.theme.typography.body.xl),
        const SizedBox(height: AppSpacing.s4),
        Text(_marketLabel(l10n, item.market), style: context.captionStyle),
        const SizedBox(height: AppSpacing.s24),
        if (loadingQuote)
          const Align(
            alignment: Alignment.centerLeft,
            child: FCircularProgress(),
          )
        else if (quote == null)
          Text(
            l10n.watchlistPriceUnavailable,
            style: context.theme.typography.body.md,
          )
        else
          MoneyText(
            amount: quote.price.toDouble(),
            currencyCode: quote.currency,
            style: context.theme.typography.body.xl,
          ),
        const SizedBox(height: AppSpacing.s16),
        Wrap(
          spacing: AppSpacing.s8,
          runSpacing: AppSpacing.s8,
          children: [
            _FreshnessChip(snapshot: snapshot),
            if (item.alertRules.above case final above?)
              _RuleChip(label: l10n.watchlistAlertAboveChip(above.toString())),
            if (item.alertRules.below case final below?)
              _RuleChip(label: l10n.watchlistAlertBelowChip(below.toString())),
          ],
        ),
        const SizedBox(height: AppSpacing.s24),
        FButton(
          variant: FButtonVariant.outline,
          onPress: onManageCollections,
          prefix: const Icon(FLucideIcons.layers),
          child: Text(l10n.watchlistManageCollectionsAction),
        ),
        const SizedBox(height: AppSpacing.s8),
        FButton(
          onPress: onEdit,
          prefix: const Icon(FLucideIcons.bell),
          child: Text(l10n.watchlistEditAlertsAction),
        ),
        if (onRemoveFromCollection != null) ...[
          const SizedBox(height: AppSpacing.s8),
          FButton(
            variant: FButtonVariant.outline,
            onPress: onRemoveFromCollection,
            prefix: const Icon(FLucideIcons.folderMinus),
            child: Text(l10n.watchlistRemoveFromCollectionAction),
          ),
        ],
        const SizedBox(height: AppSpacing.s8),
        FButton(
          variant: FButtonVariant.ghost,
          onPress: onRemove,
          prefix: const Icon(FLucideIcons.trash2),
          child: Text(l10n.watchlistRemoveAction),
        ),
      ],
    );
  }
}

class _FreshnessChip extends StatelessWidget {
  const _FreshnessChip({required this.snapshot});

  final WatchlistQuoteSnapshot? snapshot;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final label = switch (snapshot?.response?.freshness) {
      DataFreshness.live => l10n.watchlistFreshnessLive,
      DataFreshness.cachedFresh => l10n.watchlistFreshnessCache,
      DataFreshness.stale => l10n.watchlistFreshnessStale,
      null => l10n.watchlistFreshnessStale,
    };
    return _RuleChip(label: label);
  }
}

class _RuleChip extends StatelessWidget {
  const _RuleChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: context.theme.colors.foreground.withValues(
          alpha: AppOpacity.whisper,
        ),
        borderRadius: BorderRadius.circular(AppRadius.full),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s10,
          vertical: AppSpacing.s6,
        ),
        child: Text(label, style: context.theme.typography.body.xs),
      ),
    );
  }
}

Future<void> showWatchlistItemSheet({
  required BuildContext context,
  WatchlistItem? item,
  String? initialCollectionId,
}) async {
  final l10n = AppLocalizations.of(context);
  final dirty = FormDirtyController();
  try {
    await showAppSheet<void>(
      context: context,
      title: item == null
          ? l10n.watchlistAddTitle
          : l10n.watchlistEditAlertTitle(item.displaySymbol),
      maxHeightFactor: 0.9,
      dirtyGuard: dirty,
      confirmDismiss: () => confirmDiscardIfDirty(context, dirty),
      builder: (_) => _WatchlistItemSheet(
        dirty: dirty,
        item: item,
        initialCollectionId: initialCollectionId,
      ),
    );
  } finally {
    dirty.dispose();
  }
}

class _WatchlistItemSheet extends ConsumerStatefulWidget {
  const _WatchlistItemSheet({
    required this.dirty,
    required this.item,
    required this.initialCollectionId,
  });

  final FormDirtyController dirty;
  final WatchlistItem? item;
  final String? initialCollectionId;

  @override
  ConsumerState<_WatchlistItemSheet> createState() =>
      _WatchlistItemSheetState();
}

class _WatchlistItemSheetState extends ConsumerState<_WatchlistItemSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _above;
  late final TextEditingController _below;
  LocalSecurityChoice? _choice;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final item = widget.item;
    _above = TextEditingController(text: item?.alertRules.above?.toString());
    _below = TextEditingController(text: item?.alertRules.below?.toString());
    widget.dirty.bindTextControllers([_above, _below]);
    widget.dirty.snapshotBaseline();
  }

  @override
  void dispose() {
    _above.dispose();
    _below.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Form(
      key: _formKey,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.item == null) ...[
            SymbolField(
              markets: _editableMarkets,
              onChanged: (choice) {
                setState(() => _choice = choice);
                widget.dirty.markDirty();
              },
            ),
            const SizedBox(height: AppSpacing.s12),
          ],
          FTextFormField(
            control: FTextFieldControl.managed(controller: _above),
            label: Text(l10n.watchlistAlertAboveField),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
            ],
            validator: _validateDecimal,
          ),
          const SizedBox(height: AppSpacing.s12),
          FTextFormField(
            control: FTextFieldControl.managed(controller: _below),
            label: Text(l10n.watchlistAlertBelowField),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
            ],
            validator: _validateDecimal,
          ),
          const SizedBox(height: AppSpacing.s20),
          AppSheetFooter(
            cancelLabel: l10n.commonCancel,
            submitLabel: widget.item == null
                ? l10n.watchlistAddAction
                : l10n.watchlistSaveAlertsAction,
            busy: _saving,
            onSubmit: _save,
          ),
        ],
      ),
    );
  }

  String? _validateDecimal(String? value) {
    final raw = value?.trim() ?? '';
    if (raw.isEmpty) return null;
    final parsed = Decimal.tryParse(raw);
    if (parsed == null || parsed <= Decimal.zero) {
      return AppLocalizations.of(context).watchlistInvalidNumber;
    }
    return null;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final item = widget.item;
    final choice = _choice;
    if (item == null && choice == null) return; // add path requires a pick
    setState(() => _saving = true);
    widget.dirty.busy = true;
    try {
      final repo = await ref.read(watchlistRepositoryProvider.future);
      final rules = PriceAlertRules(
        above: Decimal.tryParse(_above.text.trim()),
        below: Decimal.tryParse(_below.text.trim()),
      );
      if (item == null) {
        await repo.add(
          symbol: choice!.symbol,
          market: choice.market,
          rules: rules,
          collectionIds: <String>[?widget.initialCollectionId],
        );
      } else {
        await repo.updateAlertRules(item: item, rules: rules);
      }
      ref.invalidate(watchlistQuoteSnapshotsProvider);
      ref.invalidate(watchlistQuoteSnapshotsForScopeProvider);
      widget.dirty.markPristine();
      if (mounted) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _saving = false);
      widget.dirty.busy = false;
    }
  }
}

Future<bool?> showWatchlistCollectionSheet({
  required BuildContext context,
  WatchlistCollection? collection,
}) async {
  final dirty = FormDirtyController();
  try {
    return await showAppSheet<bool>(
      context: context,
      title: collection == null
          ? AppLocalizations.of(context).watchlistCreateCollectionAction
          : AppLocalizations.of(context).watchlistEditCollectionAction,
      dirtyGuard: dirty,
      confirmDismiss: () => confirmDiscardIfDirty(context, dirty),
      builder: (_) =>
          _WatchlistCollectionSheet(dirty: dirty, collection: collection),
    );
  } finally {
    dirty.dispose();
  }
}

class _WatchlistCollectionSheet extends ConsumerStatefulWidget {
  const _WatchlistCollectionSheet({
    required this.dirty,
    required this.collection,
  });

  final FormDirtyController dirty;
  final WatchlistCollection? collection;

  @override
  ConsumerState<_WatchlistCollectionSheet> createState() =>
      _WatchlistCollectionSheetState();
}

class _WatchlistCollectionSheetState
    extends ConsumerState<_WatchlistCollectionSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.collection?.name);
    widget.dirty.bindTextControllers([_name]);
    widget.dirty.snapshotBaseline();
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FTextFormField(
            autofocus: true,
            control: FTextFieldControl.managed(controller: _name),
            label: Text(l10n.watchlistCollectionNameField),
            validator: (value) => (value?.trim().isEmpty ?? true)
                ? l10n.watchlistCollectionNameRequired
                : null,
          ),
          if (widget.collection != null) ...[
            const SizedBox(height: AppSpacing.s12),
            FButton(
              variant: FButtonVariant.destructive,
              onPress: _saving ? null : _delete,
              prefix: const Icon(FLucideIcons.trash2),
              child: Text(l10n.watchlistDeleteCollectionAction),
            ),
          ],
          const SizedBox(height: AppSpacing.s20),
          AppSheetFooter(
            cancelLabel: l10n.commonCancel,
            submitLabel: l10n.commonSave,
            busy: _saving,
            onSubmit: _save,
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    widget.dirty.busy = true;
    try {
      final repo = await ref.read(watchlistRepositoryProvider.future);
      final collection = widget.collection;
      if (collection == null) {
        await repo.createCollection(_name.text);
      } else {
        await repo.renameCollection(collection: collection, name: _name.text);
      }
      widget.dirty.markPristine();
      if (mounted) Navigator.of(context).pop(false);
    } finally {
      if (mounted) setState(() => _saving = false);
      widget.dirty.busy = false;
    }
  }

  Future<void> _delete() async {
    final collection = widget.collection!;
    final l10n = AppLocalizations.of(context);
    final confirmed = await showConfirmDialog(
      context: context,
      title: Text(l10n.watchlistDeleteCollectionTitle(collection.name)),
      body: Text(l10n.watchlistDeleteCollectionBody),
      confirmLabel: l10n.watchlistDeleteCollectionAction,
      cancelLabel: l10n.commonCancel,
      destructive: true,
      icon: FLucideIcons.trash2,
    );
    if (confirmed != true || !mounted) return;
    setState(() => _saving = true);
    widget.dirty.busy = true;
    try {
      final repo = await ref.read(watchlistRepositoryProvider.future);
      await repo.deleteCollection(collection);
      widget.dirty.markPristine();
      if (mounted) Navigator.of(context).pop(true);
    } finally {
      if (mounted) setState(() => _saving = false);
      widget.dirty.busy = false;
    }
  }
}

Future<void> showWatchlistMembershipSheet({
  required BuildContext context,
  required WatchlistItem item,
}) async {
  final dirty = FormDirtyController();
  try {
    await showAppSheet<void>(
      context: context,
      title: AppLocalizations.of(context)
          .watchlistManageCollectionsTitle(item.displaySymbol),
      dirtyGuard: dirty,
      confirmDismiss: () => confirmDiscardIfDirty(context, dirty),
      builder: (_) => _WatchlistMembershipSheet(item: item, dirty: dirty),
    );
  } finally {
    dirty.dispose();
  }
}

class _WatchlistMembershipSheet extends ConsumerStatefulWidget {
  const _WatchlistMembershipSheet({required this.item, required this.dirty});

  final WatchlistItem item;
  final FormDirtyController dirty;

  @override
  ConsumerState<_WatchlistMembershipSheet> createState() =>
      _WatchlistMembershipSheetState();
}

class _WatchlistMembershipSheetState
    extends ConsumerState<_WatchlistMembershipSheet> {
  Set<String>? _selected;
  bool _saving = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final collections = ref.watch(watchlistCollectionsProvider);
    final members = ref.watch(watchlistCollectionMembersProvider);
    if (collections.isLoading || members.isLoading) {
      return const Center(child: FCircularProgress());
    }
    if (collections.hasError || members.hasError) {
      return AppEmptyState.error(
        title: l10n.commonLoadFailed,
        retryLabel: l10n.commonRetry,
        onRetry: () {
          ref.invalidate(watchlistCollectionsProvider);
          ref.invalidate(watchlistCollectionMembersProvider);
        },
      );
    }
    final available = collections.value ?? const <WatchlistCollection>[];
    final current = (members.value ?? const <WatchlistCollectionMember>[])
        .where((entry) => entry.watchlistItemId == widget.item.id)
        .map((entry) => entry.collectionId)
        .toSet();
    final selected = _selected ??= current;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (available.isEmpty)
          AppEmptyState(
            icon: FLucideIcons.layers,
            title: l10n.watchlistNoCollectionsBody,
            action: FButton(
              variant: FButtonVariant.outline,
              onPress: _saving ? null : _createCollection,
              child: Text(l10n.watchlistCreateCollectionAction),
            ),
          )
        else
          for (final collection in available)
            AppTappable(
              onPress: _saving ? null : () => _toggle(collection.id),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.s4,
                  vertical: AppSpacing.s8,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(collection.name, style: context.labelStyle),
                    ),
                    FCheckbox(
                      value: selected.contains(collection.id),
                      onChange: _saving ? null : (_) => _toggle(collection.id),
                    ),
                  ],
                ),
              ),
            ),
        const SizedBox(height: AppSpacing.s20),
        AppSheetFooter(
          cancelLabel: l10n.commonCancel,
          submitLabel: l10n.watchlistSaveCollectionsAction,
          busy: _saving,
          onSubmit: _save,
        ),
      ],
    );
  }

  void _toggle(String collectionId) {
    setState(() {
      final selected = _selected ?? <String>{};
      if (!selected.add(collectionId)) selected.remove(collectionId);
      _selected = selected;
      widget.dirty.markDirty();
    });
  }

  Future<void> _createCollection() async {
    final name = await showAppTextPromptSheet(
      context: context,
      title: AppLocalizations.of(context).watchlistCreateCollectionAction,
      fieldLabel: AppLocalizations.of(context).watchlistCollectionNameField,
      submitLabel: AppLocalizations.of(context).commonSave,
      cancelLabel: AppLocalizations.of(context).commonCancel,
      validator: (value) => value.trim().isEmpty
          ? AppLocalizations.of(context).watchlistCollectionNameRequired
          : null,
    );
    if (name == null || !mounted) return;
    final repo = await ref.read(watchlistRepositoryProvider.future);
    final collection = await repo.createCollection(name);
    setState(() {
      (_selected ??= <String>{}).add(collection.id);
      widget.dirty.markDirty();
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final repo = await ref.read(watchlistRepositoryProvider.future);
      await repo.setCollectionsForItem(
        item: widget.item,
        collectionIds: Set<String>.from(_selected ?? const <String>{}),
      );
      ref.invalidate(watchlistQuoteSnapshotsForScopeProvider);
      widget.dirty.markPristine();
      if (mounted) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

WatchlistScope _watchlistScopeOf(BuildContext context) {
  if (GoRouter.maybeOf(context) == null) return const WatchlistScope.all();
  final raw = GoRouterState.of(context)
      .uri
      .queryParameters[_collectionQueryKey];
  if (raw == null || raw.isEmpty) return const WatchlistScope.all();
  if (raw == _ungroupedQueryValue) return const WatchlistScope.ungrouped();
  return WatchlistScope.collection(raw);
}

void _replaceWatchlistScope(BuildContext context, WatchlistScope scope) {
  final router = GoRouter.maybeOf(context);
  if (router == null) return;
  final current = router.routeInformationProvider.value.uri;
  final query = <String, String>{...current.queryParameters}
    ..remove(kSelectedQueryKey);
  if (scope.isAll) {
    query.remove(_collectionQueryKey);
  } else {
    query[_collectionQueryKey] = scope.ungrouped
        ? _ungroupedQueryValue
        : scope.collectionId!;
  }
  router.go(
    Uri(
      path: FinanceRoutes.wealthWatchlist,
      queryParameters: query.isEmpty ? null : query,
    ).toString(),
  );
}

const _editableMarkets = <AssetMarket>[
  AssetMarket.usStock,
  AssetMarket.hkStock,
  AssetMarket.cnA,
  AssetMarket.crypto,
  AssetMarket.fx,
];

String _marketLabel(AppLocalizations l10n, AssetMarket market) {
  return switch (market) {
    AssetMarket.cnA => l10n.watchlistMarketCnA,
    AssetMarket.hkStock => l10n.watchlistMarketHkStock,
    AssetMarket.usStock => l10n.watchlistMarketUsStock,
    AssetMarket.crypto => l10n.watchlistMarketCrypto,
    AssetMarket.fx => l10n.watchlistMarketFx,
    AssetMarket.unknown => l10n.watchlistMarketUnknown,
  };
}

IconData _marketIcon(AssetMarket market) {
  return switch (market) {
    AssetMarket.crypto => FLucideIcons.bitcoin,
    AssetMarket.fx => FLucideIcons.arrowLeftRight,
    AssetMarket.cnA ||
    AssetMarket.hkStock ||
    AssetMarket.usStock => FLucideIcons.chartLine,
    AssetMarket.unknown => FLucideIcons.trendingUp,
  };
}
