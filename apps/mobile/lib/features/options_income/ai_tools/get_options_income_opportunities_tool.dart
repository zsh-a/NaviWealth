import 'package:decimal/decimal.dart';
import 'package:naviwealth/core/ai/runtime/device/tools/device_tool.dart';
import 'package:naviwealth/features/finance/data/repositories/mutation_context.dart';
import 'package:naviwealth/features/options_income/data/providers.dart';
import 'package:naviwealth/features/options_income/domain/options_opportunity.dart';
import 'package:naviwealth/features/options_income/domain/options_strategy_profile.dart';

/// `get_options_income_opportunities` — read-only cache surface.
///
/// **Critical contract** (`docs/options-income.md` §8): this tool MUST
/// NOT trigger a live scan. It reads the most recent cached batch only.
/// If the cache is stale (>24h) or empty, the tool returns guidance text
/// asking the user to refresh in the Income Planner UI.
class GetOptionsIncomeOpportunitiesTool implements DeviceTool {
  const GetOptionsIncomeOpportunitiesTool();

  @override
  String get name => 'get_options_income_opportunities';

  @override
  String get description =>
      '返回最近一次扫描出的期权现金流机会(sell put / covered call)。'
      '只读 cache,**不会触发实时扫描**。'
      '当 `cache_state.is_stale=true` 或 `opportunities` 为空时,'
      '请引导用户回到 Income Planner 页面手动刷新,不要凭空生成数字。'
      '解释字段(why_good / why_risky / worst_case)由本地评分引擎产出,'
      'LLM 只可引用与转述,不得改写。';

  @override
  Map<String, Object?> get inputSchema => const <String, Object?>{
    'type': 'object',
    'properties': <String, Object?>{
      'strategy': <String, Object?>{
        'type': ['string', 'null'],
        'enum': ['cash_secured_put', 'covered_call', null],
        'description': 'Filter to one strategy (null = both)',
      },
      'max_results': <String, Object?>{
        'type': 'integer',
        'minimum': 1,
        'maximum': 20,
        'description': 'Cap on returned opportunities (default 5).',
      },
      'min_score': <String, Object?>{
        'type': 'number',
        'minimum': 0,
        'maximum': 1,
        'description': 'Soft-score floor (default 0.6).',
      },
    },
  };

  @override
  Future<Object?> invoke(
    DeviceToolContext ctx,
    Map<String, Object?> input,
  ) async {
    final ownerUserId = await ctx.ref.read(currentUserIdProvider)();
    final repo = await ctx.ref.read(
      optionsOpportunityCacheRepositoryProvider.future,
    );
    final scanState = await repo.latestScanState(ownerUserId);
    final all = await repo.getLatest(ownerUserId);

    final strategyFilter = _parseStrategy(input['strategy']);
    final maxResults = (input['max_results'] as num?)?.toInt() ?? 5;
    final minScoreRaw = (input['min_score'] as num?) ?? 0.6;
    final minScore = Decimal.parse(minScoreRaw.toString());

    var filtered = all
        .where((o) => strategyFilter == null || o.strategy == strategyFilter)
        .where((o) => o.score >= minScore)
        .toList();
    filtered.sort((a, b) => b.score.compareTo(a.score));
    if (filtered.length > maxResults) {
      filtered = filtered.sublist(0, maxResults);
    }

    final guidance = scanState == null
        ? '尚未扫描:请在 Income Planner 页面点击 "Refresh opportunities" 触发首次扫描。'
        : scanState.isStale
        ? '缓存已超过 24 小时:建议用户在 Income Planner 页面手动刷新后再决策。'
        : null;

    return <String, Object?>{
      'opportunities': filtered.map(_toJson).toList(),
      'cache_state': scanState == null
          ? null
          : <String, Object?>{
              'scan_id': scanState.scanId,
              'last_scanned_at_iso': scanState.scannedAt
                  .toUtc()
                  .toIso8601String(),
              'is_stale': scanState.isStale,
              'count': scanState.count,
            },
      'guidance': ?guidance,
    };
  }

  OptionsStrategyKind? _parseStrategy(Object? raw) {
    if (raw is! String) return null;
    return parseOptionsStrategyKind(raw);
  }
}

Map<String, Object?> _toJson(OptionsOpportunity opp) {
  final c = opp.contract;
  final m = opp.metrics;
  return <String, Object?>{
    'strategy': opp.strategy.wire,
    'underlying': c.underlying,
    'option_symbol': c.optionSymbol,
    'expiration_iso': c.expiration.toUtc().toIso8601String(),
    'dte': c.dte,
    'currency': c.strike.currency,
    'strike': c.strike.amount.toString(),
    'underlying_price': c.underlyingPrice.amount.toString(),
    'bid': c.bid.amount.toString(),
    'ask': c.ask.amount.toString(),
    'mid': c.mid.amount.toString(),
    'volume': c.volume,
    'open_interest': c.openInterest,
    'implied_volatility': c.impliedVolatility?.toString(),
    'delta': c.delta?.toString(),
    'metrics': <String, Object?>{
      'premium': m.premium.amount.toString(),
      'cash_required': m.cashRequired.amount.toString(),
      'breakeven': m.breakeven.amount.toString(),
      'static_return': m.staticReturn.toString(),
      'annualized_yield': m.annualizedYield.toString(),
      'margin_of_safety': m.marginOfSafety.toString(),
    },
    'risk_level': opp.risk.wire,
    'explanation': opp.explanation.toJson(),
    'score': opp.score.toString(),
    'scanned_at_iso': opp.scannedAt.toUtc().toIso8601String(),
  };
}
