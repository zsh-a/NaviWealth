import 'dart:async';

import 'package:flutter/material.dart';

import '../../../domain/entities/symbol_info.dart';
import '../../../domain/services/market_data_service.dart';

/// Autocomplete text field that searches for securities / crypto symbols via
/// [MarketDataService.searchSymbol].
///
/// Typing "茅台", "600519", or "AAPL" triggers a debounced search; the user
/// picks a [SymbolInfo] from the dropdown. The caller receives the selection
/// through [onSelected].
class AssetSearchField extends StatefulWidget {
  const AssetSearchField({
    super.key,
    required this.marketData,
    this.onSelected,
    this.label = '资产搜索',
    this.hintText = '输入股票代码、名称或简称',
  });

  final MarketDataService marketData;
  final ValueChanged<SymbolInfo?>? onSelected;
  final String label;
  final String hintText;

  @override
  State<AssetSearchField> createState() => _AssetSearchFieldState();
}

class _AssetSearchFieldState extends State<AssetSearchField> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  Timer? _debounce;
  List<SymbolInfo> _results = [];
  bool _loading = false;
  String? _error;
  SymbolInfo? _selected;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onChanged(String query) {
    _debounce?.cancel();
    if (query.trim().length < 2) {
      setState(() {
        _results = [];
        _loading = false;
        _error = null;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 400), () => _search(query));
  }

  Future<void> _search(String query) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final resp = await widget.marketData.searchSymbol(query.trim());
      if (!mounted) return;
      setState(() {
        _results = resp.data;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _results = [];
        _loading = false;
        _error = '搜索失败';
      });
    }
  }

  void _select(SymbolInfo info) {
    setState(() {
      _selected = info;
      _controller.text = '${info.symbol} — ${info.name}';
      _results = [];
    });
    _focusNode.unfocus();
    widget.onSelected?.call(info);
  }

  void _clear() {
    setState(() {
      _selected = null;
      _controller.clear();
      _results = [];
    });
    widget.onSelected?.call(null);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        TextFormField(
          controller: _controller,
          focusNode: _focusNode,
          decoration: InputDecoration(
            labelText: widget.label,
            hintText: widget.hintText,
            border: const OutlineInputBorder(),
            prefixIcon: const Icon(Icons.search),
            suffixIcon: _selected != null
                ? IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: _clear,
                  )
                : _loading
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : null,
          ),
          onChanged: _onChanged,
          validator: (_) {
            if (_selected == null) return '请选择一个资产';
            return null;
          },
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              _error!,
              style: TextStyle(
                color: Theme.of(context).colorScheme.error,
                fontSize: 12,
              ),
            ),
          ),
        if (_results.isNotEmpty)
          Card(
            margin: const EdgeInsets.only(top: 4),
            clipBehavior: Clip.antiAlias,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 240),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _results.length,
                itemBuilder: (ctx, i) {
                  final info = _results[i];
                  return ListTile(
                    dense: true,
                    title: Text(
                      info.symbol,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(
                      info.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: Text(
                      info.currency ?? '',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    onTap: () => _select(info),
                  );
                },
              ),
            ),
          ),
      ],
    );
  }
}
