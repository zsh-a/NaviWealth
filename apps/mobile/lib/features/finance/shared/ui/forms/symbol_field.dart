import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/features/finance/domain/models/enums.dart';

import '../../../../../core/forms/form_dirty_guard.dart';
import '../../../../../design_system/design_system.dart';
import '../../../../../l10n/gen/app_localizations.dart';
import '../../../data/securities_catalog/asset_search_hit.dart';
import '../../../data/securities_catalog/providers.dart';
import '../../../data/securities_catalog/securities_search_service.dart';
import '../../../market/domain/asset_market.dart';
import 'manual_security_sheet.dart';

/// Selection produced by [SymbolField].
///
/// Either resolves to an existing catalog / owned hit, or to a freshly
/// hand-entered security from the manual-add sheet. Callers that need to
/// know whether the row is already persisted check [fromCatalog].
class LocalSecurityChoice {
  const LocalSecurityChoice({
    required this.symbol,
    required this.market,
    required this.type,
    required this.currency,
    required this.fromCatalog,
    this.name,
    this.isin,
  });

  factory LocalSecurityChoice.fromHit(AssetSearchHit hit) {
    return LocalSecurityChoice(
      symbol: hit.symbol,
      market: hit.market,
      type: hit.type,
      currency: hit.currency,
      fromCatalog: true,
      name: hit.nameCn ?? hit.nameEn,
    );
  }

  final String symbol;
  final AssetMarket market;
  final AssetType type;
  final String currency;
  final String? name;
  final String? isin;
  final bool fromCatalog;
}

/// Canonical "pick a security symbol" widget.
///
/// One field for every place the user enters a stock / ETF / crypto /
/// fund symbol. Behaviour scales with the [markets] prop:
///
/// * `markets == null` — search across all markets, no market chip.
///   Used by the trade-entry form where any symbol is valid.
/// * `markets.length == 1` — search constrained to that single market;
///   the chip row is hidden because there's nothing to choose.
/// * `markets.length >= 2` — render a market selector above the search
///   field; selection narrows the search and becomes the manual-add
///   default. Used by watchlist + options-income.
///
/// The widget self-watches [securitiesSearchServiceProvider], so callers
/// don't have to unwrap the FutureProvider themselves.
class SymbolField extends ConsumerStatefulWidget {
  const SymbolField({
    super.key,
    this.markets,
    this.initialMarket,
    this.initialValue,
    this.readOnly = false,
    this.allowManualAdd = true,
    this.label,
    this.hint,
    this.onChanged,
  });

  /// Markets the user is allowed to pick from. See class doc for layout
  /// semantics. `null` means "no constraint, no UI".
  final List<AssetMarket>? markets;

  /// Initial market filter. Defaults to [initialValue]'s market when set,
  /// otherwise the first entry of [markets].
  final AssetMarket? initialMarket;

  /// Pre-fill (edit mode). When [readOnly] is true the field shows this
  /// as a non-editable summary row.
  final LocalSecurityChoice? initialValue;

  /// Symbol is part of the row's primary key and can't be changed; render
  /// a static summary instead of an input.
  final bool readOnly;

  /// Show the "未找到？手动添加" tile in the dropdown.
  final bool allowManualAdd;

  final String? label;
  final String? hint;
  final ValueChanged<LocalSecurityChoice?>? onChanged;

  @override
  ConsumerState<SymbolField> createState() => _SymbolFieldState();
}

class _SymbolFieldState extends ConsumerState<SymbolField> {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    if (widget.readOnly && widget.initialValue != null) {
      return _ReadOnlySummary(choice: widget.initialValue!);
    }

    final asyncSearch = ref.watch(securitiesSearchServiceProvider);
    return asyncSearch.whenOrLoading(
      context: context,
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.s12),
        child: FProgress(),
      ),
      error: (e, _) => Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.s8),
        child: Text(
          l10n.tradeEntryCatalogLoadError('$e'),
          style: context.theme.typography.body.sm,
        ),
      ),
      data: (search) => SymbolFieldBody(
        search: search,
        markets: widget.markets,
        initialMarket: widget.initialMarket,
        initialValue: widget.initialValue,
        allowManualAdd: widget.allowManualAdd,
        label: widget.label,
        hint: widget.hint,
        onChanged: widget.onChanged,
      ),
    );
  }
}

/// Stateless wrapper around the search/selection logic. Split out so it
/// can be unit-tested without a Riverpod container — tests inject a
/// stub [SecuritiesSearchService] directly.
@visibleForTesting
class SymbolFieldBody extends StatefulWidget {
  const SymbolFieldBody({
    super.key,
    required this.search,
    this.markets,
    this.initialMarket,
    this.initialValue,
    this.allowManualAdd = true,
    this.label,
    this.hint,
    this.onChanged,
  });

  final SecuritiesSearchService search;
  final List<AssetMarket>? markets;
  final AssetMarket? initialMarket;
  final LocalSecurityChoice? initialValue;
  final bool allowManualAdd;
  final String? label;
  final String? hint;
  final ValueChanged<LocalSecurityChoice?>? onChanged;

  @override
  State<SymbolFieldBody> createState() => _SymbolFieldBodyState();
}

class _SymbolFieldBodyState extends State<SymbolFieldBody> {
  final _fieldKey = GlobalKey<FormFieldState<String>>();
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  Timer? _debounce;
  List<AssetSearchHit> _results = const [];
  bool _loading = false;
  LocalSecurityChoice? _selected;
  String _lastQuery = '';
  bool _settingTextFromSelection = false;
  AssetMarket? _market;

  bool get _hasMarketSelector =>
      widget.markets != null && widget.markets!.length >= 2;

  @override
  void initState() {
    super.initState();
    _selected = widget.initialValue;
    _market =
        widget.initialMarket ??
        widget.initialValue?.market ??
        (widget.markets != null && widget.markets!.isNotEmpty
            ? widget.markets!.first
            : null);
    final initial = widget.initialValue;
    if (initial != null) {
      _setControllerText(_formatChoice(initial));
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  String _formatChoice(LocalSecurityChoice choice) {
    return choice.name == null
        ? choice.symbol
        : '${choice.symbol} — ${choice.name}';
  }

  AssetMarket? _searchMarketFilter() {
    final markets = widget.markets;
    if (markets == null) return null;
    if (markets.length == 1) return markets.first;
    return _market;
  }

  void _onChanged(String query) {
    if (_settingTextFromSelection) return;
    _debounce?.cancel();
    final trimmed = query.trim();
    _lastQuery = trimmed;
    if (_selected != null) {
      _selected = null;
      widget.onChanged?.call(null);
    }
    if (trimmed.length < 2) {
      setState(() {
        _results = const [];
        _loading = false;
      });
      return;
    }
    _debounce = Timer(
      const Duration(milliseconds: 200),
      () => _search(trimmed),
    );
  }

  Future<void> _search(String query) async {
    setState(() => _loading = true);
    final hits = await widget.search.searchLocal(
      query,
      market: _searchMarketFilter(),
    );
    if (!mounted || query != _lastQuery) return;
    setState(() {
      _results = hits;
      _loading = false;
    });
  }

  void _onMarketChanged(AssetMarket? value) {
    if (value == null || value == _market) return;
    setState(() {
      _market = value;
      _results = const [];
    });
    if (_lastQuery.length >= 2) _search(_lastQuery);
  }

  void _select(AssetSearchHit hit) {
    final choice = LocalSecurityChoice.fromHit(hit);
    setState(() {
      _selected = choice;
      _setControllerText(_formatChoice(choice));
      _results = const [];
      if (_hasMarketSelector) _market = hit.market;
    });
    _focusNode.unfocus();
    widget.onChanged?.call(choice);
    _fieldKey.currentState?.validate();
  }

  void _selectManual(LocalSecurityChoice choice) {
    setState(() {
      _selected = choice;
      _setControllerText(_formatChoice(choice));
      _results = const [];
      if (_hasMarketSelector) _market = choice.market;
    });
    _focusNode.unfocus();
    widget.onChanged?.call(choice);
    _fieldKey.currentState?.validate();
  }

  void _clear() {
    setState(() {
      _selected = null;
      _controller.clear();
      _results = const [];
    });
    widget.onChanged?.call(null);
    _fieldKey.currentState?.validate();
  }

  Future<void> _openManualSheet({String? prefillSymbol}) async {
    final result = await showGuardedFormSheet<LocalSecurityChoice>(
      context: context,
      builder: (ctx, dirty) =>
          ManualSecuritySheet(prefillSymbol: prefillSymbol, dirty: dirty),
    );
    if (result != null) {
      _selectManual(result);
    }
  }

  void _setControllerText(String text) {
    _settingTextFromSelection = true;
    try {
      _controller.text = text;
    } finally {
      _settingTextFromSelection = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final effectiveLabel = widget.label ?? l10n.localSecuritiesSearchLabel;
    final effectiveHint = widget.hint ?? l10n.localSecuritiesSearchHint;

    final owned = _results
        .where((h) => h.source == AssetSearchHitSource.owned)
        .toList(growable: false);
    final catalog = _results
        .where((h) => h.source == AssetSearchHitSource.catalog)
        .toList(growable: false);
    final showDropdown =
        _focusNode.hasFocus && _selected == null && _lastQuery.length >= 2;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_hasMarketSelector) ...[
          _MarketSelector(
            markets: widget.markets!,
            value: _market!,
            onChanged: _onMarketChanged,
          ),
          const SizedBox(height: AppSpacing.s8),
        ],
        FTextFormField(
          key: const Key('symbol-field-search'),
          formFieldKey: _fieldKey,
          control: FTextFieldControl.managed(
            controller: _controller,
            onChange: (v) => _onChanged(v.text),
          ),
          focusNode: _focusNode,
          label: RequiredLabel(effectiveLabel),
          hint: effectiveHint,
          prefixBuilder: (ctx, style, variants) => const Padding(
            padding: EdgeInsetsDirectional.only(start: 12, end: 8),
            child: Icon(FLucideIcons.search, size: AppIconSizes.h18),
          ),
          suffixBuilder: _selected != null
              ? (ctx, style, variants) => Padding(
                  padding: const EdgeInsetsDirectional.only(end: 4),
                  child: FButton.icon(
                    variant: FButtonVariant.ghost,
                    onPress: _clear,
                    child: const Icon(FLucideIcons.x, size: AppIconSizes.h18),
                  ),
                )
              : _loading
              ? (ctx, style, variants) => const Padding(
                  padding: EdgeInsets.all(AppSpacing.s12),
                  child: SizedBox(
                    width: AppIconSizes.md,
                    height: AppIconSizes.md,
                    child: FCircularProgress(),
                  ),
                )
              : null,
          onTap: () => setState(() {}),
          validator: (_) =>
              _selected == null ? l10n.localSecuritiesValidationRequired : null,
        ),
        if (showDropdown)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.s4),
            child: FCard(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 320),
                child: ListView(
                  key: const Key('symbol-field-results'),
                  shrinkWrap: true,
                  children: [
                    if (owned.isNotEmpty) ...[
                      _sectionHeader(context, l10n.localSecuritiesMyAssets),
                      for (final hit in owned)
                        _HitTile(hit: hit, onTap: () => _select(hit)),
                    ],
                    if (catalog.isNotEmpty) ...[
                      _sectionHeader(context, l10n.localSecuritiesCatalog),
                      for (final hit in catalog)
                        _HitTile(hit: hit, onTap: () => _select(hit)),
                    ],
                    if (widget.allowManualAdd) ...[
                      const FDivider(),
                      FTile(
                        key: const Key('symbol-field-manual'),
                        prefix: const Icon(FLucideIcons.plus),
                        title: Text(l10n.localSecuritiesManualAdd),
                        subtitle: _lastQuery.isEmpty
                            ? null
                            : Text(
                                l10n.localSecuritiesUseQueryAsCode(_lastQuery),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                        onPress: () =>
                            _openManualSheet(prefillSymbol: _lastQuery),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _MarketSelector extends StatelessWidget {
  const _MarketSelector({
    required this.markets,
    required this.value,
    required this.onChanged,
  });

  final List<AssetMarket> markets;
  final AssetMarket value;
  final ValueChanged<AssetMarket?> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return FSelect<AssetMarket>(
      key: const Key('symbol-field-market'),
      items: {for (final m in markets) symbolFieldMarketLabel(l10n, m): m},
      control: FSelectControl<AssetMarket>.managed(
        initial: value,
        onChange: onChanged,
      ),
      label: Text(l10n.localSecuritiesMarketLabel),
    );
  }
}

class _ReadOnlySummary extends StatelessWidget {
  const _ReadOnlySummary({required this.choice});

  final LocalSecurityChoice choice;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final subtitleParts = <String>[
      symbolFieldMarketLabel(l10n, choice.market),
      choice.currency,
    ];
    return FCard(
      builder: (context, style, _) => Padding(
        padding: style.padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              choice.name == null
                  ? choice.symbol
                  : '${choice.symbol} — ${choice.name}',
              style: context.labelStyle,
            ),
            const SizedBox(height: AppSpacing.s4),
            Text(
              subtitleParts.join(' · '),
              style: context.theme.typography.body.xs,
            ),
          ],
        ),
      ),
    );
  }
}

/// Quiet caption label for the picker result groups.
Widget _sectionHeader(BuildContext context, String text) {
  return SectionHeader(
    title: text,
    titleStyle: context.captionLabelStyle,
    titleColor: context.theme.colors.primary,
    padding: const EdgeInsets.fromLTRB(
      AppSpacing.s16,
      AppSpacing.s12,
      AppSpacing.s16,
      AppSpacing.s4,
    ),
  );
}

class _HitTile extends StatelessWidget {
  const _HitTile({required this.hit, required this.onTap});

  final AssetSearchHit hit;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final display = hit.nameCn ?? hit.nameEn;
    return FTile(
      title: Text(hit.symbol, style: context.labelStyle),
      subtitle: display == null
          ? null
          : Text(display, maxLines: 1, overflow: TextOverflow.ellipsis),
      suffix: Text(hit.currency, style: context.theme.typography.body.xs),
      onPress: onTap,
    );
  }
}

/// Human label for an [AssetMarket], shared by the selector and the
/// read-only summary row. Exposed (top-level) so feature pages with
/// existing market-aware UI can reuse the same translations.
String symbolFieldMarketLabel(AppLocalizations l10n, AssetMarket market) {
  return switch (market) {
    AssetMarket.cnA => l10n.watchlistMarketCnA,
    AssetMarket.hkStock => l10n.watchlistMarketHkStock,
    AssetMarket.usStock => l10n.watchlistMarketUsStock,
    AssetMarket.crypto => l10n.watchlistMarketCrypto,
    AssetMarket.fx => l10n.watchlistMarketFx,
    AssetMarket.unknown => l10n.watchlistMarketUnknown,
  };
}
