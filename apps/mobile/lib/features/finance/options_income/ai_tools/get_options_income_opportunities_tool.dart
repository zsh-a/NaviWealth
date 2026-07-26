import 'package:decimal/decimal.dart';
import 'package:naviwealth/core/ai/runtime/device/tools/device_tool.dart';
import 'package:naviwealth/core/sync/mutation_context.dart';
import 'package:naviwealth/features/finance/options_income/data/providers.dart';
import 'package:naviwealth/features/finance/options_income/domain/options_opportunity.dart';

/// `get_options_income_opportunities` — read-only cache surface.
///
/// **Critical contract** (`docs/domains/options-income.md` §8): this tool MUST
/// NOT trigger a live scan. It reads the most recent cached batch only.
/// If the cache is stale (>24h) or empty, the tool returns guidance text
/// asking the user to refresh in the Income Planner UI.
class GetOptionsIncomeOpportunitiesTool implements DeviceTool {
  const GetOptionsIncomeOpportunitiesTool();

  @override
  String get name => 'get_options_income_opportunities';

  @override
  String get description =>
      '返回最近一次扫描出的期权机会(sell put / covered call / LEAPS call)。'
      '只读 cache,**不会触发实时扫描**。'
      '`score` 只在同一 strategy 通道内可比:卖方是收益合成分,'
      'leaps_call 是成本效率分,不要跨通道比较分数。'
      '不传 strategy 时结果按通道配额混合,建议尽量指定 strategy。'
      '当 `cache_state.is_stale=true` 或 `opportunities` 为空时,'
      '请引导用户回到期权工作台手动刷新,不要凭空生成数字。'
      '解释字段(why_good / why_risky / worst_case)由本地评分引擎产出,'
      'LLM 只可引用与转述,不得改写。';

  @override
  Map<String, Object?> get inputSchema => const <String, Object?>{
    'type': 'object',
    'properties': <String, Object?>{
      'strategy': <String, Object?>{
        'type': ['string', 'null'],
        'enum': ['cash_secured_put', 'covered_call', 'leaps_call', null],
        'description': 'Filter to one strategy (null = all lanes, quota-mixed)',
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

    final passing = all
        .where((o) => strategyFilter == null || o.strategy == strategyFilter)
        .where((o) => o.score >= minScore)
        .toList();
    passing.sort((a, b) => b.score.compareTo(a.score));
    List<OptionsOpportunity> filtered;
    if (strategyFilter != null) {
      filtered = passing.take(maxResults).toList();
    } else {
      // Scores are lane-relative (LEAPS cost-efficiency runs ~0.95+,
      // sell-side composites ~0.5–0.85), so a merged top-N would return
      // only LEAPS. Split the budget: sell first, LEAPS fills the rest.
      final sell = passing
          .where((o) => o.strategy != OpportunityStrategy.leapsCall)
          .toList(growable: false);
      final leaps = passing
          .where((o) => o.strategy == OpportunityStrategy.leapsCall)
          .toList(growable: false);
      final sellQuota = (maxResults + 1) ~/ 2;
      final sellTaken = sell.take(sellQuota).toList();
      final leapsTaken = leaps.take(maxResults - sellTaken.length).toList();
      filtered = [
        ...sellTaken,
        ...sell
            .skip(sellTaken.length)
            .take(maxResults - sellTaken.length - leapsTaken.length),
        ...leapsTaken,
      ];
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

  OpportunityStrategy? _parseStrategy(Object? raw) {
    if (raw is! String) return null;
    return parseOpportunityStrategy(raw);
  }
}

Map<String, Object?> _toJson(OptionsOpportunity opp) {
  final c = opp.contract;
  final metrics = switch (opp.metrics) {
    final OpportunityMetrics m => <String, Object?>{
      'premium': m.premium.amount.toString(),
      'cash_required': m.cashRequired.amount.toString(),
      'breakeven': m.breakeven.amount.toString(),
      'static_return': m.staticReturn.toString(),
      'annualized_yield': m.annualizedYield.toString(),
      'margin_of_safety': m.marginOfSafety.toString(),
    },
    final LeapsOpportunityMetrics m => <String, Object?>{
      'total_cost': m.totalCost.amount.toString(),
      'breakeven': m.breakeven.amount.toString(),
      'extrinsic_value': m.extrinsicValue.amount.toString(),
      'extrinsic_ratio': m.extrinsicRatio.toString(),
      'leverage_ratio': m.leverageRatio?.toString(),
      'annualized_extrinsic_cost_pct': m.annualizedExtrinsicCostPct?.toString(),
      'funding_coverage_pct': m.fundingCoveragePct?.toString(),
    },
  };
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
    'metrics': metrics,
    'risk_level': opp.risk.wire,
    'explanation': opp.explanation.toJson(),
    'score': opp.score.toString(),
    'scanned_at_iso': opp.scannedAt.toUtc().toIso8601String(),
  };
}
