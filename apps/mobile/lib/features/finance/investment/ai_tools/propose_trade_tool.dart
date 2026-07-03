/// `propose_trade` — device port (final propose_*).
///
/// Schema + description verbatim from
/// the historical backend `propose_trade` tool; logic a verbatim port
/// of `proposals::propose_trade`. Resolves asset + account against the
/// device typed providers (mirrors backend `resolve_asset` /
/// `resolve_account`) and returns the same `ready_plan` /
/// `needs_clarification` JSON; device never auto-writes (§4.5).
library;

import 'package:naviwealth/core/ai/runtime/device/tools/device_tool.dart';
import 'package:naviwealth/features/finance/ai_tools/shared/propose/proposal_plan.dart';
import 'package:naviwealth/features/finance/data/repositories/providers.dart';
import 'package:naviwealth/features/finance/investment/data/providers.dart';

const _kTradeTypes = <String>[
  'buy',
  'sell',
  'transferIn',
  'transferOut',
  'valuationAdjust',
];

class ProposeTradeTool implements DeviceTool {
  const ProposeTradeTool();

  @override
  String get name => 'propose_trade';

  @override
  String get description =>
      '提议一笔证券 / 加密交易（买入 / 卖出 / 转入 / 转出 / 估值调整）。'
      '⚠ 这是只提议、不落库的工具：返回一个 plan，前端会让用户在确认 UI 上点确认后才走 '
      'TradeEntryService.buildPlan + JournalEntryRepository。'
      '- asset 通过 asset_id 或 asset_symbol / asset_name 任一指认；多个匹配会返回 candidates。'
      '- account 同理。'
      '- 缺少字段时优先反问用户，不要硬编值。'
      '- 日期相对值（昨天 / 上周三）请你解析为 ISO-8601 后传入。';

  @override
  Map<String, Object?> get inputSchema => {
    'type': 'object',
    'required': ['type', 'quantity'],
    'properties': {
      'type': {'type': 'string', 'enum': _kTradeTypes},
      'asset_id': {'type': 'string'},
      'asset_symbol': {
        'type': 'string',
        'description': '如 AAPL / 600519 / BTC',
      },
      'asset_name': {'type': 'string', 'description': '如 苹果 / 茅台'},
      'account_id': {'type': 'string'},
      'account_name': {'type': 'string'},
      'quantity': {'type': 'number', 'minimum': 0},
      'price': {
        'type': 'number',
        'minimum': 0,
        'description': '成交价。留空时前端会从行情回填，并 warn 用户。',
      },
      'fee': {'type': 'number', 'minimum': 0, 'default': 0},
      'tax': {'type': 'number', 'minimum': 0, 'default': 0},
      'currency': {'type': 'string', 'description': 'ISO 4217；留空时取账户币种'},
      'trade_date': {'type': 'string', 'description': 'ISO-8601；相对日期请你先解析'},
      'note': {'type': 'string'},
    },
  };

  @override
  Future<Object?> invoke(
    DeviceToolContext ctx,
    Map<String, Object?> input,
  ) async {
    final txType = proposalRequireStr(input, 'type');
    if (txType == null) {
      return proposalBadRequest("missing or non-string field 'type'");
    }
    if (!_kTradeTypes.contains(txType)) {
      return proposalBadRequest(
        "propose_trade: unsupported transaction type '$txType'",
      );
    }
    final qty = proposalRequireNum(input, 'quantity');
    if (qty == null) {
      return proposalBadRequest("missing or non-numeric field 'quantity'");
    }
    if (qty <= 0) {
      return proposalBadRequest('propose_trade: quantity must be > 0');
    }
    final price = proposalRequireNum(input, 'price');
    final fee = proposalRequireNum(input, 'fee') ?? 0.0;
    final tax = proposalRequireNum(input, 'tax') ?? 0.0;
    final note = proposalOptionalStr(input, 'note');
    final warnings = <String>[];

    final assets = await ctx.ref.read(allAssetsStreamProvider.future);
    final resolvedA = resolveAsset(
      assets,
      byId: proposalOptionalStr(input, 'asset_id'),
      bySymbol: proposalOptionalStr(input, 'asset_symbol'),
      byName: proposalOptionalStr(input, 'asset_name'),
    );
    final asset = switch (resolvedA) {
      ResolvedOne(:final row) => row,
      _ => null,
    };
    if (asset == null) {
      return switch (resolvedA) {
        ResolvedMany(:final candidates) => needsClarification(
          kind: 'trade',
          field: 'asset',
          reason: 'Multiple assets matched. Ask the user to choose one.',
          candidates: candidates,
        ),
        _ => needsClarification(
          kind: 'trade',
          field: 'asset',
          reason:
              'No matching asset was found. Ask the user to confirm the '
              'symbol/name, or create it with propose_account_create and '
              'propose_asset_valuation first.',
          candidates: const [],
        ),
      };
    }

    final accounts = await ctx.ref.read(accountsStreamProvider.future);
    final resolvedAcc = resolveAccount(
      accounts,
      byId: proposalOptionalStr(input, 'account_id'),
      byName: proposalOptionalStr(input, 'account_name'),
    );
    final account = switch (resolvedAcc) {
      ResolvedOne(:final row) => row,
      _ => null,
    };
    if (account == null) {
      return switch (resolvedAcc) {
        ResolvedMany(:final candidates) => needsClarification(
          kind: 'trade',
          field: 'account',
          reason: 'Multiple accounts matched. Ask the user to choose one.',
          candidates: candidates,
        ),
        _ => needsClarification(
          kind: 'trade',
          field: 'account',
          reason:
              'No matching account was found. Create one with '
              'propose_account_create or ask the user for the exact account '
              'name.',
          candidates: const [],
        ),
      };
    }

    // Backend: explicit → account.currency → asset.currency → ('USD' +
    // warn). Device Account.currency is required non-null, so the
    // USD+warn arm is unreachable — faithfully no currency warning.
    final currency = proposalOptionalStr(input, 'currency') ?? account.currency;

    final tradeDate = proposalOptionalStr(input, 'trade_date');
    if (tradeDate == null) {
      warnings.add(
        'trade_date was not specified; the confirmation UI will default to today.',
      );
    } else if (!isRfc3339(tradeDate)) {
      return proposalBadRequest(
        "propose_trade: trade_date '$tradeDate' is not RFC3339",
      );
    }
    if (price == null) {
      warnings.add(
        'price was not specified; the confirmation UI will try to backfill '
        'the trade-date close via MarketDataService and let the user override it.',
      );
    }

    final payload = <String, Object?>{
      'type': txType,
      'asset_id': asset.id,
      'asset_symbol': asset.symbol,
      'asset_name': asset.name,
      'account_id': account.id,
      'account_name': account.name,
      'quantity': qty,
      'price': price,
      'fee': fee,
      'tax': tax,
      'currency': currency,
      'trade_date': tradeDate,
      'note': note,
    };

    final action = switch (txType) {
      'buy' => 'Buy',
      'sell' => 'Sell',
      'transferIn' => 'Transfer in',
      'transferOut' => 'Transfer out',
      'valuationAdjust' => 'Adjust valuation',
      _ => txType,
    };
    final symbol = asset.symbol.isNotEmpty
        ? asset.symbol
        : (asset.name ?? '(unknown)');
    final pricePhrase = price != null
        ? ' @ ${formatProposalAmount(price)}'
        : '';
    final feePhrase = fee > 0 ? ', fee ${formatProposalAmount(fee)}' : '';
    final summary =
        '$action $symbol${_qty(qty)}$pricePhrase$feePhrase (${account.name})';

    return readyPlan(
      kind: 'trade',
      summaryZh: summary,
      payload: payload,
      warnings: warnings,
    );
  }

  /// Port of `format_args_qty`: integer → " {n} shares", else " {qty}"
  /// (note the leading space, matching the Rust format string).
  static String _qty(double q) => q == q.roundToDouble()
      ? ' ${q.toInt()} shares'
      : ' ${formatProposalAmount(q)}';
}
