/// `get_watchlist` — device port.
///
/// Read-only companion to `get_holdings`: the assistant could describe what
/// the user owns but had no way to see what the user is *watching*, even though
/// both live in the same local finance store. The watchlist is intent data —
/// symbols under consideration, with the alert thresholds the user set on them
/// — so answering "how is my watchlist doing?" previously required the user to
/// read the numbers out loud.
///
/// Quotes are best-effort: the tool reports whatever the local cache can serve
/// and marks the row unpriced rather than failing the whole call, because the
/// alert thresholds and the symbol set are useful on their own.
library;

import 'package:naviwealth/core/ai/contracts/evidence_anchor.dart';
import 'package:naviwealth/core/ai/runtime/device/tools/device_tool.dart';
import 'package:naviwealth/features/finance/investment/data/watchlist_providers.dart';
import 'package:naviwealth/features/finance/investment/data/watchlist_repository.dart';
import 'package:naviwealth/features/finance/market/domain/asset_market.dart';

class GetWatchlistTool implements DeviceTool {
  const GetWatchlistTool();

  @override
  String get name => 'get_watchlist';

  @override
  String get description =>
      '返回用户的本地自选清单：自选标的、市场、最近一次可取到的报价与涨跌幅，'
      '以及用户为每个标的设置的价格提醒阈值。报价取不到时仍返回标的与阈值。';

  @override
  Map<String, Object?> get inputSchema => {
    'type': 'object',
    'properties': {
      'market': {
        'type': 'string',
        'description': '只返回该市场的自选标的，例如 us_stock、hk_stock、cn_a。',
      },
      'with_quotes': {
        'type': 'boolean',
        'description': '是否尝试读取报价，默认 true。false 时只返回标的与提醒阈值。',
      },
    },
  };

  @override
  Future<Object?> invoke(
    DeviceToolContext ctx,
    Map<String, Object?> input,
  ) async {
    final items = await ctx.ref.read(watchlistItemsProvider.future);
    final market = input['market'];
    final wanted = market is String && market.trim().isNotEmpty
        ? market.trim()
        : null;
    final selected = wanted == null
        ? items
        : items.where((item) => item.market.wire == wanted).toList();

    final withQuotes = input['with_quotes'] != false;
    final quotesByItemId = withQuotes
        ? await _quotesById(ctx)
        : const <String, WatchlistQuoteSnapshot>{};

    final rows = [
      for (final item in selected)
        _row(item, quotesByItemId[item.id]),
    ];
    return withEvidence(
      result: {
        'as_of': DateTime.now().toUtc().toIso8601String(),
        'count': rows.length,
        'quotes_included': withQuotes,
        'items': rows,
        'source': 'watchlist_items',
      },
      anchors: [
        for (final item in selected.take(8))
          EvidenceAnchor(
            entityTable: 'watchlist_items',
            entityId: item.id,
            label: item.displaySymbol,
          ),
      ],
    );
  }

  /// Quote loading touches the network and can fail outright. The tool answers
  /// with the symbol set and thresholds in that case instead of erroring.
  Future<Map<String, WatchlistQuoteSnapshot>> _quotesById(
    DeviceToolContext ctx,
  ) async {
    try {
      final snapshots = await ctx.ref.read(
        watchlistQuoteSnapshotsProvider.future,
      );
      return {for (final snapshot in snapshots) snapshot.item.id: snapshot};
    } on Object {
      return const {};
    }
  }

  static Map<String, Object?> _row(
    WatchlistItem item,
    WatchlistQuoteSnapshot? snapshot,
  ) {
    final quote = snapshot?.quote;
    final rules = item.alertRules;
    return <String, Object?>{
      'symbol': item.displaySymbol,
      'market': item.market.wire,
      'name_en': item.nameEn,
      'name_cn': item.nameCn,
      'price': quote?.price.toString(),
      'currency': quote?.currency,
      'change_percent': quote?.changePercent?.toString(),
      'price_as_of': quote?.asOf.toUtc().toIso8601String(),
      'price_freshness': snapshot?.response?.freshness.name,
      'alert_enabled': rules.enabled && rules.hasRule,
      'alert_above': rules.above?.toString(),
      'alert_below': rules.below?.toString(),
    };
  }
}
