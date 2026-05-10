import 'dart:async';

import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

import '../../../data/domain/enums.dart';
import '../../../data/securities_catalog/asset_search_hit.dart';
import '../../../data/securities_catalog/securities_search_service.dart';
import '../../../domain/values/asset_market.dart';
import '../../../l10n/gen/app_localizations.dart';
import 'manual_security_sheet.dart';

/// Selection produced by [LocalSecuritiesPicker].
///
/// Either resolves to an existing catalog / owned hit, or to a freshly
/// hand-entered security from the manual-add sheet. The trade-entry page
/// uses the union to decide whether it needs to call `upsertSecurity`
/// before recording the trade.
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

  /// Construct a choice from a catalog / owned search hit.
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

  /// `true` for hits sourced from the catalog or owned table; `false`
  /// when the user hand-entered the row through the manual-add sheet.
  /// Drives whether the form should treat the row as already known.
  final bool fromCatalog;
}

/// Asset picker for the trade-entry form. Reads exclusively from the
/// local catalog + owned-asset table — never makes a network call.
///
/// Typing 2+ characters fires a debounced [SecuritiesSearchService.searchLocal]
/// call. Results render in two groups, "我的资产" (owned) and "本地目录"
/// (catalog), with a fixed "未找到？手动添加" entry at the bottom that opens
/// the [ManualSecuritySheet] for hand entry. Manual entries flow back
/// through the same [onSelected] callback as catalog hits, so the
/// caller doesn't need to branch on source.
class LocalSecuritiesPicker extends StatefulWidget {
  const LocalSecuritiesPicker({
    super.key,
    required this.search,
    this.onSelected,
    this.label = '',
    this.hintText = '',
  });

  final SecuritiesSearchService search;
  final ValueChanged<LocalSecurityChoice?>? onSelected;
  final String label;
  final String hintText;

  @override
  State<LocalSecuritiesPicker> createState() => _LocalSecuritiesPickerState();
}

class _LocalSecuritiesPickerState extends State<LocalSecuritiesPicker> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  Timer? _debounce;
  List<AssetSearchHit> _results = const [];
  bool _loading = false;
  LocalSecurityChoice? _selected;
  String _lastQuery = '';

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onChanged(String query) {
    _debounce?.cancel();
    final trimmed = query.trim();
    _lastQuery = trimmed;
    // Clearing the field also clears the current selection so a stale
    // pick doesn't survive a partial edit.
    if (_selected != null) {
      _selected = null;
      widget.onSelected?.call(null);
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
    final hits = await widget.search.searchLocal(query);
    if (!mounted || query != _lastQuery) return;
    setState(() {
      _results = hits;
      _loading = false;
    });
  }

  void _select(AssetSearchHit hit) {
    final choice = LocalSecurityChoice.fromHit(hit);
    final display = hit.nameCn ?? hit.nameEn;
    setState(() {
      _selected = choice;
      _controller.text = display == null
          ? hit.symbol
          : '${hit.symbol} — $display';
      _results = const [];
    });
    _focusNode.unfocus();
    widget.onSelected?.call(choice);
  }

  void _selectManual(LocalSecurityChoice choice) {
    setState(() {
      _selected = choice;
      _controller.text = choice.name == null
          ? choice.symbol
          : '${choice.symbol} — ${choice.name}';
      _results = const [];
    });
    _focusNode.unfocus();
    widget.onSelected?.call(choice);
  }

  void _clear() {
    setState(() {
      _selected = null;
      _controller.clear();
      _results = const [];
    });
    widget.onSelected?.call(null);
  }

  Future<void> _openManualSheet({String? prefillSymbol}) async {
    final result = await showFSheet<LocalSecurityChoice>(
      side: FLayout.btt,
      context: context,
      mainAxisMaxRatio: null,
      builder: (ctx) => ManualSecuritySheet(prefillSymbol: prefillSymbol),
    );
    if (result != null) {
      _selectManual(result);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final effectiveLabel = widget.label.isEmpty
        ? l10n.localSecuritiesSearchLabel
        : widget.label;
    final effectiveHint = widget.hintText.isEmpty
        ? l10n.localSecuritiesSearchHint
        : widget.hintText;
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
        TextFormField(
          key: const Key('local-securities-picker-field'),
          controller: _controller,
          focusNode: _focusNode,
          decoration: InputDecoration(
            labelText: effectiveLabel,
            hintText: effectiveHint,
            border: const OutlineInputBorder(),
            prefixIcon: const Icon(Icons.search),
            suffixIcon: _selected != null
                ? IconButton(icon: const Icon(Icons.clear), onPressed: _clear)
                : _loading
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: FCircularProgress(),
                    ),
                  )
                : null,
          ),
          onChanged: _onChanged,
          // Re-render so focus changes flip the dropdown.
          onTap: () => setState(() {}),
          validator: (_) =>
              _selected == null ? l10n.localSecuritiesValidationRequired : null,
        ),
        if (showDropdown)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: FCard.raw(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 320),
                child: ListView(
                  key: const Key('local-securities-picker-results'),
                  shrinkWrap: true,
                  children: [
                    if (owned.isNotEmpty) ...[
                      _SectionHeader(text: l10n.localSecuritiesMyAssets),
                      for (final hit in owned)
                        _HitTile(hit: hit, onTap: () => _select(hit)),
                    ],
                    if (catalog.isNotEmpty) ...[
                      _SectionHeader(text: l10n.localSecuritiesCatalog),
                      for (final hit in catalog)
                        _HitTile(hit: hit, onTap: () => _select(hit)),
                    ],
                    const FDivider(),
                    FTile(
                      key: const Key('local-securities-picker-manual'),
                      prefix: const Icon(Icons.add),
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
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: context.theme.colors.primary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _HitTile extends StatelessWidget {
  const _HitTile({required this.hit, required this.onTap});

  final AssetSearchHit hit;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final display = hit.nameCn ?? hit.nameEn;
    return FTile(
      title: Text(
        hit.symbol,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: display == null
          ? null
          : Text(display, maxLines: 1, overflow: TextOverflow.ellipsis),
      suffix: Text(hit.currency, style: Theme.of(context).textTheme.bodySmall),
      onPress: onTap,
    );
  }
}
