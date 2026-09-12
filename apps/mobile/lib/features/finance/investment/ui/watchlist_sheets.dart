import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/core/forms/form_dirty_guard.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/finance/market/domain/asset_market.dart';
import 'package:naviwealth/features/finance/shared/ui/forms/symbol_field.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

import '../data/watchlist_providers.dart';
import '../data/watchlist_repository.dart';
import 'watchlist_labels.dart';
import 'watchlist_rows.dart';

/// Every create / edit / order / filter surface for the watchlist.
///
/// Split out of the page so the page owns composition and these own
/// interaction; nothing here knows how the list is scoped or sorted.

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

/// Read-only detail for one watched symbol.
///
/// This is the mobile counterpart of the desktop detail pane: below the
/// master/detail breakpoint a row tap used to do nothing at all.
Future<void> showWatchlistSymbolSheet({
  required BuildContext context,
  required WatchlistItem item,
  required WatchlistQuoteSnapshot? snapshot,
  required bool loadingQuote,
  required VoidCallback onEdit,
  required VoidCallback onManageCollections,
  required VoidCallback? onRemoveFromCollection,
  required VoidCallback onRemove,
}) {
  final l10n = AppLocalizations.of(context);
  return showAppSheet<void>(
    context: context,
    title: l10n.watchlistSymbolDetailTitle(item.displaySymbol),
    maxHeightFactor: 0.9,
    builder: (_) => WatchlistSymbolView(
      item: item,
      snapshot: snapshot,
      loadingQuote: loadingQuote,
      onEdit: onEdit,
      onManageCollections: onManageCollections,
      onRemoveFromCollection: onRemoveFromCollection,
      onRemove: onRemove,
    ),
  );
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
  late final Set<String> _selectedCollectionIds;
  LocalSecurityChoice? _choice;
  bool _saving = false;

  /// Alerts are optional, so they start folded away when adding a symbol and
  /// open when the user came here specifically to change them.
  late bool _alertsExpanded;

  @override
  void initState() {
    super.initState();
    final item = widget.item;
    _above = TextEditingController(text: item?.alertRules.above?.toString());
    _below = TextEditingController(text: item?.alertRules.below?.toString());
    _selectedCollectionIds = <String>{?widget.initialCollectionId};
    _alertsExpanded = item != null;
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
    final collections = widget.item == null
        ? ref.watch(watchlistCollectionsProvider)
        : null;
    return Form(
      key: _formKey,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.item == null) ...[
            SymbolField(
              markets: watchlistEditableMarkets,
              onChanged: (choice) {
                setState(() => _choice = choice);
                widget.dirty.markDirty();
              },
            ),
            const SizedBox(height: AppSpacing.s12),
            AppSheetSectionLabel(l10n.watchlistAddToCollectionsField),
            if (collections!.isLoading)
              const Align(
                alignment: Alignment.centerLeft,
                child: FCircularProgress(),
              )
            else if (collections.hasError)
              FButton(
                variant: FButtonVariant.outline,
                onPress: () => ref.invalidate(watchlistCollectionsProvider),
                child: Text(l10n.commonRetry),
              )
            else if ((collections.value ?? const <WatchlistCollection>[])
                .isEmpty)
              Text(l10n.watchlistNoCollectionsBody, style: context.captionStyle)
            else
              AppGroupedSurface(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    for (
                      var index = 0;
                      index < collections.value!.length;
                      index++
                    ) ...[
                      _WatchlistCollectionCheckboxRow(
                        key: ValueKey<String>(
                          'watchlist-add-collection-${collections.value![index].id}',
                        ),
                        collection: collections.value![index],
                        selected: _selectedCollectionIds.contains(
                          collections.value![index].id,
                        ),
                        onToggle: () =>
                            _toggleCollection(collections.value![index].id),
                      ),
                      if (index != collections.value!.length - 1)
                        const AppGroupedDivider(
                          indent: AppSpacing.s12,
                          endIndent: AppSpacing.s12,
                        ),
                    ],
                  ],
                ),
              ),
            const SizedBox(height: AppSpacing.s16),
          ],
          AppDisclosureHeader(
            title: l10n.watchlistAlertOptionalSection,
            subtitle: l10n.watchlistAlertOptionalHint,
            expanded: _alertsExpanded,
            onToggle: () => setState(() => _alertsExpanded = !_alertsExpanded),
          ),
          AnimatedSizeFade(
            visible: _alertsExpanded,
            child: Padding(
              padding: const EdgeInsets.only(top: AppSpacing.s12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FTextFormField(
                    key: const ValueKey<String>('watchlist-alert-above'),
                    control: FTextFieldControl.managed(controller: _above),
                    label: Text(l10n.watchlistAlertAboveField),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                    ],
                    validator: _validateDecimal,
                  ),
                  const SizedBox(height: AppSpacing.s12),
                  FTextFormField(
                    key: const ValueKey<String>('watchlist-alert-below'),
                    control: FTextFieldControl.managed(controller: _below),
                    label: Text(l10n.watchlistAlertBelowField),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                    ],
                    validator: _validateDecimal,
                  ),
                  const SizedBox(height: AppSpacing.s12),
                  Row(
                    children: [
                      Icon(
                        FLucideIcons.bellRing,
                        size: AppIconSizes.sm,
                        color: context.theme.colors.mutedForeground,
                      ),
                      const SizedBox(width: AppSpacing.s8),
                      Expanded(
                        child: Text(
                          l10n.watchlistAlertNotificationNote,
                          style: context.captionStyle,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
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

  void _toggleCollection(String collectionId) {
    setState(() {
      if (!_selectedCollectionIds.add(collectionId)) {
        _selectedCollectionIds.remove(collectionId);
      }
      widget.dirty.markDirty();
    });
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
          collectionIds: _selectedCollectionIds,
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

/// Sort order is a four-way choice, so it reuses the filter sheet's chip
/// language rather than inventing a second selection idiom in the toolbar.
///
/// Unlike the filter, it applies on tap: there is nothing to compose, and a
/// confirm step only meant an "Apply filters" button on a sheet that does not
/// filter anything.
Future<WatchlistSortOrder?> showWatchlistSortSheet({
  required BuildContext context,
  required WatchlistSortOrder initial,
}) => showAppSheet<WatchlistSortOrder>(
  context: context,
  title: AppLocalizations.of(context).watchlistSortAction,
  builder: (sheetContext) => _WatchlistSortSheet(
    initial: initial,
    onSelected: (order) => Navigator.of(sheetContext).pop(order),
  ),
);

class _WatchlistSortSheet extends StatelessWidget {
  const _WatchlistSortSheet({required this.initial, required this.onSelected});

  final WatchlistSortOrder initial;
  final ValueChanged<WatchlistSortOrder> onSelected;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Wrap(
      spacing: AppSpacing.s8,
      runSpacing: AppSpacing.s8,
      children: [
        for (final option in WatchlistSortOrder.values)
          AppFilterChip(
            label: switch (option) {
              WatchlistSortOrder.defaultOrder => l10n.watchlistSortDefault,
              WatchlistSortOrder.gainers => l10n.watchlistSortGainers,
              WatchlistSortOrder.decliners => l10n.watchlistSortDecliners,
              WatchlistSortOrder.symbol => l10n.watchlistSortSymbol,
            },
            active: initial == option,
            onPress: () => onSelected(option),
          ),
      ],
    );
  }
}

Future<WatchlistFilter?> showWatchlistFilterSheet({
  required BuildContext context,
  required WatchlistFilter initial,
}) => showAppSheet<WatchlistFilter>(
  context: context,
  title: AppLocalizations.of(context).watchlistFilterAction,
  builder: (_) => _WatchlistFilterSheet(initial: initial),
);

class _WatchlistFilterSheet extends StatefulWidget {
  const _WatchlistFilterSheet({required this.initial});

  final WatchlistFilter initial;

  @override
  State<_WatchlistFilterSheet> createState() => _WatchlistFilterSheetState();
}

class _WatchlistFilterSheetState extends State<_WatchlistFilterSheet> {
  late AssetMarket? _market;
  late WatchlistAlertFilter _alerts;
  late WatchlistFreshnessFilter _freshness;

  @override
  void initState() {
    super.initState();
    _market = widget.initial.market;
    _alerts = widget.initial.alerts;
    _freshness = widget.initial.freshness;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppSheetSectionLabel(l10n.watchlistFilterMarketSection),
        Wrap(
          spacing: AppSpacing.s8,
          runSpacing: AppSpacing.s8,
          children: [
            AppFilterChip(
              label: l10n.watchlistFilterAllOption,
              active: _market == null,
              onPress: () => setState(() => _market = null),
            ),
            for (final market in watchlistEditableMarkets)
              AppFilterChip(
                label: watchlistMarketLabel(l10n, market),
                active: _market == market,
                onPress: () => setState(() => _market = market),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.s16),
        AppSheetSectionLabel(l10n.watchlistFilterAlertsSection),
        Wrap(
          spacing: AppSpacing.s8,
          runSpacing: AppSpacing.s8,
          children: [
            for (final option in WatchlistAlertFilter.values)
              AppFilterChip(
                label: switch (option) {
                  WatchlistAlertFilter.all => l10n.watchlistFilterAllOption,
                  WatchlistAlertFilter.configured =>
                    l10n.watchlistFilterAlertsConfigured,
                  WatchlistAlertFilter.none => l10n.watchlistFilterAlertsNone,
                },
                active: _alerts == option,
                onPress: () => setState(() => _alerts = option),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.s16),
        AppSheetSectionLabel(l10n.watchlistFilterFreshnessSection),
        Wrap(
          spacing: AppSpacing.s8,
          runSpacing: AppSpacing.s8,
          children: [
            for (final option in WatchlistFreshnessFilter.values)
              AppFilterChip(
                label: switch (option) {
                  WatchlistFreshnessFilter.all => l10n.watchlistFilterAllOption,
                  WatchlistFreshnessFilter.live => l10n.watchlistFreshnessLive,
                  WatchlistFreshnessFilter.cached =>
                    l10n.watchlistFreshnessCache,
                  WatchlistFreshnessFilter.stale =>
                    l10n.watchlistFreshnessStale,
                  WatchlistFreshnessFilter.unavailable =>
                    l10n.watchlistPriceUnavailable,
                },
                active: _freshness == option,
                onPress: () => setState(() => _freshness = option),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.s16),
        FButton(
          variant: FButtonVariant.outline,
          onPress: _reset,
          child: Text(l10n.watchlistFilterClearAction),
        ),
        const SizedBox(height: AppSpacing.s20),
        AppSheetFooter(
          cancelLabel: l10n.commonCancel,
          submitLabel: l10n.watchlistFilterApplyAction,
          onSubmit: () => Navigator.of(context).pop(
            WatchlistFilter(
              market: _market,
              alerts: _alerts,
              freshness: _freshness,
            ),
          ),
        ),
      ],
    );
  }

  void _reset() {
    setState(() {
      _market = null;
      _alerts = WatchlistAlertFilter.all;
      _freshness = WatchlistFreshnessFilter.all;
    });
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

Future<void> showWatchlistOrderSheet<T>({
  required BuildContext context,
  required String title,
  required List<T> entries,
  required String Function(T entry) idOf,
  required String Function(T entry) labelOf,
  required Future<void> Function(List<T> ordered) onSave,
}) async {
  final dirty = FormDirtyController();
  try {
    await showAppSheet<void>(
      context: context,
      title: title,
      maxHeightFactor: 0.9,
      dirtyGuard: dirty,
      confirmDismiss: () => confirmDiscardIfDirty(context, dirty),
      builder: (_) => _WatchlistOrderSheet<T>(
        entries: entries,
        idOf: idOf,
        labelOf: labelOf,
        onSave: onSave,
        dirty: dirty,
      ),
    );
  } finally {
    dirty.dispose();
  }
}

class _WatchlistOrderSheet<T> extends StatefulWidget {
  const _WatchlistOrderSheet({
    required this.entries,
    required this.idOf,
    required this.labelOf,
    required this.onSave,
    required this.dirty,
  });

  final List<T> entries;
  final String Function(T entry) idOf;
  final String Function(T entry) labelOf;
  final Future<void> Function(List<T> ordered) onSave;
  final FormDirtyController dirty;

  @override
  State<_WatchlistOrderSheet<T>> createState() =>
      _WatchlistOrderSheetState<T>();
}

class _WatchlistOrderSheetState<T> extends State<_WatchlistOrderSheet<T>> {
  late final List<T> _entries;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _entries = List<T>.of(widget.entries);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ReorderableListView.builder(
          shrinkWrap: true,
          buildDefaultDragHandles: false,
          itemCount: _entries.length,
          onReorderItem: _reorder,
          itemBuilder: (context, index) {
            final entry = _entries[index];
            return Padding(
              key: ValueKey<String>(widget.idOf(entry)),
              padding: EdgeInsets.only(
                bottom: index == _entries.length - 1 ? 0 : AppSpacing.s8,
              ),
              child: AppGroupedSurface(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.s10),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          widget.labelOf(entry),
                          style: context.labelStyle,
                        ),
                      ),
                      ReorderableDragStartListener(
                        index: index,
                        child: const Padding(
                          padding: EdgeInsets.all(AppSpacing.s8),
                          child: Icon(
                            FLucideIcons.gripVertical,
                            size: AppIconSizes.sm,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
        const SizedBox(height: AppSpacing.s20),
        AppSheetFooter(
          cancelLabel: l10n.commonCancel,
          submitLabel: l10n.commonSave,
          busy: _saving,
          enabled: widget.dirty.isDirty,
          onSubmit: _save,
        ),
      ],
    );
  }

  void _reorder(int oldIndex, int newIndex) {
    setState(() {
      final entry = _entries.removeAt(oldIndex);
      _entries.insert(newIndex, entry);
      widget.dirty.markDirty();
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    widget.dirty.busy = true;
    try {
      await widget.onSave(List<T>.unmodifiable(_entries));
      widget.dirty.markPristine();
      if (mounted) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _saving = false);
      widget.dirty.busy = false;
    }
  }
}

Future<void> showWatchlistBulkMembershipSheet({
  required BuildContext context,
  required List<WatchlistItem> items,
  required List<WatchlistCollection> collections,
  String? removalCollectionId,
}) => showAppSheet<void>(
  context: context,
  title: AppLocalizations.of(context).watchlistBulkManageAction,
  maxHeightFactor: 0.9,
  builder: (_) => _WatchlistBulkMembershipSheet(
    items: items,
    collections: collections,
    removalCollectionId: removalCollectionId,
  ),
);

class _WatchlistBulkMembershipSheet extends ConsumerStatefulWidget {
  const _WatchlistBulkMembershipSheet({
    required this.items,
    required this.collections,
    required this.removalCollectionId,
  });

  final List<WatchlistItem> items;
  final List<WatchlistCollection> collections;
  final String? removalCollectionId;

  @override
  ConsumerState<_WatchlistBulkMembershipSheet> createState() =>
      _WatchlistBulkMembershipSheetState();
}

class _WatchlistBulkMembershipSheetState
    extends ConsumerState<_WatchlistBulkMembershipSheet> {
  final Set<String> _selectedItemIds = <String>{};
  bool _saving = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final allSelected = _selectedItemIds.length == widget.items.length;
    final removing = widget.removalCollectionId != null;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l10n.watchlistBulkSelectedCount(_selectedItemIds.length),
          style: context.captionStyle,
        ),
        const SizedBox(height: AppSpacing.s8),
        AppGroupedSurface(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              _WatchlistBulkSelectRow(
                key: const ValueKey<String>('watchlist-bulk-select-all'),
                title: l10n.watchlistBulkSelectAll,
                selected: allSelected,
                enabled: !_saving,
                onToggle: _toggleAll,
              ),
              const AppGroupedDivider(
                indent: AppSpacing.s12,
                endIndent: AppSpacing.s12,
              ),
              for (var index = 0; index < widget.items.length; index++) ...[
                _WatchlistBulkSelectRow(
                  key: ValueKey<String>(
                    'watchlist-bulk-item-${widget.items[index].id}',
                  ),
                  title: watchlistItemLabel(context, widget.items[index]),
                  subtitle: watchlistMarketLabel(
                    l10n,
                    widget.items[index].market,
                  ),
                  selected: _selectedItemIds.contains(widget.items[index].id),
                  enabled: !_saving,
                  onToggle: () => _toggleItem(widget.items[index].id),
                ),
                if (index != widget.items.length - 1)
                  const AppGroupedDivider(
                    indent: AppSpacing.s12,
                    endIndent: AppSpacing.s12,
                  ),
              ],
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.s20),
        AppSheetFooter(
          cancelLabel: l10n.commonCancel,
          submitLabel: removing
              ? l10n.watchlistBulkRemoveAction
              : l10n.watchlistBulkAddAction,
          enabled: _selectedItemIds.isNotEmpty,
          busy: _saving,
          onSubmit: _apply,
        ),
      ],
    );
  }

  void _toggleAll() {
    setState(() {
      if (_selectedItemIds.length == widget.items.length) {
        _selectedItemIds.clear();
      } else {
        _selectedItemIds
          ..clear()
          ..addAll(widget.items.map((item) => item.id));
      }
    });
  }

  void _toggleItem(String itemId) {
    setState(() {
      if (!_selectedItemIds.add(itemId)) _selectedItemIds.remove(itemId);
    });
  }

  Future<void> _apply() async {
    final removalCollectionId = widget.removalCollectionId;
    final targetCollectionId = removalCollectionId ?? await _chooseCollection();
    if (targetCollectionId == null || !mounted) return;
    setState(() => _saving = true);
    try {
      final selectedItems = widget.items
          .where((item) => _selectedItemIds.contains(item.id))
          .toList(growable: false);
      final repo = await ref.read(watchlistRepositoryProvider.future);
      if (removalCollectionId == null) {
        await repo.addItemsToCollection(
          items: selectedItems,
          collectionId: targetCollectionId,
        );
      } else {
        await repo.removeItemsFromCollection(
          items: selectedItems,
          collectionId: targetCollectionId,
        );
      }
      ref.invalidate(watchlistQuoteSnapshotsForScopeProvider);
      if (!mounted) return;
      AppMessenger.show(
        context,
        ToastKind.success,
        AppLocalizations.of(context).watchlistBulkUpdated(selectedItems.length),
      );
      Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<String?> _chooseCollection() => showAppSheet<String>(
    context: context,
    title: AppLocalizations.of(context).watchlistBulkChooseCollectionTitle,
    builder: (sheetContext) => AppGroupedSurface(
      padding: EdgeInsets.zero,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var index = 0; index < widget.collections.length; index++) ...[
            AppTappable(
              key: ValueKey<String>(
                'watchlist-bulk-target-${widget.collections[index].id}',
              ),
              onPress: () =>
                  Navigator.of(sheetContext).pop(widget.collections[index].id),
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.s12),
                child: Row(
                  children: [
                    const Icon(FLucideIcons.layers, size: AppIconSizes.sm),
                    const SizedBox(width: AppSpacing.s12),
                    Expanded(
                      child: Text(
                        widget.collections[index].name,
                        style: context.labelStyle,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (index != widget.collections.length - 1)
              const AppGroupedDivider(
                indent: AppSpacing.s12,
                endIndent: AppSpacing.s12,
              ),
          ],
        ],
      ),
    ),
  );
}

class _WatchlistBulkSelectRow extends StatelessWidget {
  const _WatchlistBulkSelectRow({
    super.key,
    required this.title,
    required this.selected,
    required this.enabled,
    required this.onToggle,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final bool selected;
  final bool enabled;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return AppTappable(
      onPress: enabled ? onToggle : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s12,
          vertical: AppSpacing.s10,
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title, style: context.labelStyle),
                  if (subtitle case final subtitle?)
                    Text(subtitle, style: context.captionStyle),
                ],
              ),
            ),
            FCheckbox(
              value: selected,
              onChange: enabled ? (_) => onToggle() : null,
            ),
          ],
        ),
      ),
    );
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

class _WatchlistCollectionCheckboxRow extends StatelessWidget {
  const _WatchlistCollectionCheckboxRow({
    super.key,
    required this.collection,
    required this.selected,
    required this.onToggle,
    this.enabled = true,
  });

  final WatchlistCollection collection;
  final bool selected;
  final VoidCallback onToggle;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return AppTappable(
      onPress: enabled ? onToggle : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s4,
          vertical: AppSpacing.s8,
        ),
        child: Row(
          children: [
            Expanded(child: Text(collection.name, style: context.labelStyle)),
            FCheckbox(
              value: selected,
              onChange: enabled ? (_) => onToggle() : null,
            ),
          ],
        ),
      ),
    );
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
            _WatchlistCollectionCheckboxRow(
              collection: collection,
              selected: selected.contains(collection.id),
              enabled: !_saving,
              onToggle: () => _toggle(collection.id),
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
