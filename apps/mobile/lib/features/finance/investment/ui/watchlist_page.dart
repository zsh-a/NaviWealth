import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/core/forms/form_dirty_guard.dart';
import 'package:naviwealth/core/shell/shell_chrome.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/finance/market/domain/asset_market.dart';
import 'package:naviwealth/features/finance/market/domain/market_data_service.dart';
import 'package:naviwealth/features/finance/shared/ui/forms/symbol_field.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

import '../data/watchlist_providers.dart';
import '../data/watchlist_repository.dart';

const _pollInterval = Duration(minutes: 5);

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
      if (mounted) ref.invalidate(watchlistQuoteSnapshotsProvider);
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
    final items = ref.watch(watchlistItemsProvider);
    final quotes = ref.watch(watchlistQuoteSnapshotsProvider);

    ref.listen(watchlistQuoteSnapshotsProvider, (_, next) {
      next.whenData((snapshots) => _notifyAlerts(context, snapshots));
    });

    return AppPageScaffold(
      title: l10n.watchlistTitle,
      actions: [
        FHeaderAction(
          icon: const Icon(FLucideIcons.refreshCw),
          semanticsLabel: l10n.commonRetry,
          onPress: () => ref.invalidate(watchlistQuoteSnapshotsProvider),
        ),
        FHeaderAction(
          icon: const Icon(FLucideIcons.plus),
          semanticsLabel: l10n.watchlistAddAction,
          onPress: () => showWatchlistItemSheet(context: context),
        ),
      ],
      childPad: false,
      child: items.whenOrError(
        context: context,
        data: (items) => _WatchlistBody(
          items: items,
          snapshots: quotes.value ?? const [],
          loadingQuotes: quotes.isLoading,
          onAdd: () => showWatchlistItemSheet(context: context),
          onEdit: (item) =>
              showWatchlistItemSheet(context: context, item: item),
          onRemove: (item) => _removeItem(item),
        ),
        error: (error, _) => AppEmptyState.error(
          title: l10n.commonLoadFailed,
          message: userSafeErrorMessage(context, error),
          action: FButton(
            variant: FButtonVariant.ghost,
            onPress: () {
              ref.invalidate(watchlistItemsProvider);
              ref.invalidate(watchlistQuoteSnapshotsProvider);
            },
            child: Text(l10n.commonRetry),
          ),
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
    final repo = await ref.read(watchlistRepositoryProvider.future);
    await repo.remove(item);
    ref.invalidate(watchlistQuoteSnapshotsProvider);
  }
}

class _WatchlistBody extends StatelessWidget {
  const _WatchlistBody({
    required this.items,
    required this.snapshots,
    required this.loadingQuotes,
    required this.onAdd,
    required this.onEdit,
    required this.onRemove,
  });

  final List<WatchlistItem> items;
  final List<WatchlistQuoteSnapshot> snapshots;
  final bool loadingQuotes;
  final VoidCallback onAdd;
  final ValueChanged<WatchlistItem> onEdit;
  final ValueChanged<WatchlistItem> onRemove;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final hPad = Breakpoints.isMobile(width) ? AppSpacing.s16 : AppSpacing.s24;
    final byId = {for (final snapshot in snapshots) snapshot.item.id: snapshot};
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(
        hPad,
        AppSpacing.s8,
        hPad,
        kTabBarOffset + MediaQuery.paddingOf(context).bottom,
      ),
      children: [
        if (items.isEmpty)
          _WatchlistEmpty(onAdd: onAdd)
        else ...[
          for (final item in items) ...[
            _WatchlistRow(
              item: item,
              snapshot: byId[item.id],
              loadingQuote: loadingQuotes && byId[item.id] == null,
              onEdit: () => onEdit(item),
              onRemove: () => onRemove(item),
            ),
            const SizedBox(height: AppSpacing.s10),
          ],
        ],
      ],
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
    required this.onRemove,
  });

  final WatchlistItem item;
  final WatchlistQuoteSnapshot? snapshot;
  final bool loadingQuote;
  final VoidCallback onEdit;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.theme.colors;
    final quote = snapshot?.quote;
    return SoftCard(
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
          const SizedBox(height: AppSpacing.s10),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              FButton(
                variant: FButtonVariant.ghost,
                onPress: onEdit,
                child: Text(l10n.watchlistEditAlertsAction),
              ),
              const SizedBox(width: AppSpacing.s8),
              FButton(
                variant: FButtonVariant.destructive,
                onPress: onRemove,
                child: Text(l10n.watchlistRemoveAction),
              ),
            ],
          ),
        ],
      ),
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
      builder: (_) => _WatchlistItemSheet(dirty: dirty, item: item),
    );
  } finally {
    dirty.dispose();
  }
}

class _WatchlistItemSheet extends ConsumerStatefulWidget {
  const _WatchlistItemSheet({required this.dirty, this.item});

  final FormDirtyController dirty;
  final WatchlistItem? item;

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
        );
      } else {
        await repo.updateAlertRules(item: item, rules: rules);
      }
      ref.invalidate(watchlistQuoteSnapshotsProvider);
      widget.dirty.markPristine();
      if (mounted) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _saving = false);
      widget.dirty.busy = false;
    }
  }
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
