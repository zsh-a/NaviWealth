import '../../../../../features/options_income/data/providers.dart';
import '../../../../../features/options_income/domain/options_strategy_profile.dart';
import 'device_tool.dart';

/// `get_options_strategy_profile` — return the user's current Income
/// Planner stance (preset mode, DTE / delta / yield windows, hard caps,
/// approved-only flag). Read-only mirror of the synced singleton row.
class GetOptionsStrategyProfileTool implements DeviceTool {
  const GetOptionsStrategyProfileTool();

  @override
  String get name => 'get_options_strategy_profile';

  @override
  String get description =>
      '返回用户当前的期权现金流策略偏好(保守/平衡/激进 / DTE / delta / 收益阈值 / '
      '资金占比上限 / approved-list 开关)。`is_configured=false` 表示用户尚未配置,'
      '请先邀请用户配置而非凭空建议数字。修改建议必须通过 '
      '`propose_options_profile_update`,从不直接断言"我已修改"。';

  @override
  Map<String, Object?> get inputSchema => const <String, Object?>{
    'type': 'object',
    'properties': <String, Object?>{},
  };

  @override
  Future<Object?> invoke(
    DeviceToolContext ctx,
    Map<String, Object?> input,
  ) async {
    final profile = ctx.ref.read(optionsStrategyProfileProvider).value;
    if (profile == null) {
      return <String, Object?>{
        'is_configured': false,
        'guidance': '用户尚未填写期权策略偏好。请引导用户先在 Income Planner 页面完成 OCC 风险披露并配置偏好。',
      };
    }
    return <String, Object?>{
      'is_configured': true,
      'mode': profile.mode.wire,
      'allowed_strategies': [for (final s in profile.allowedStrategies) s.wire],
      'dte_range': <String, Object?>{
        'min': profile.minDte,
        'max': profile.maxDte,
      },
      'delta_put': <String, Object?>{
        'min': profile.deltaPutMin.toString(),
        'max': profile.deltaPutMax.toString(),
      },
      'delta_call': <String, Object?>{
        'min': profile.deltaCallMin.toString(),
        'max': profile.deltaCallMax.toString(),
      },
      'max_capital_per_trade_pct': profile.maxCapitalPerTradePct.toString(),
      'max_underlying_exposure_pct': profile.maxUnderlyingExposurePct
          .toString(),
      'min_annualized_yield': profile.minAnnualizedYield.toString(),
      'min_open_interest': profile.minOpenInterest,
      'min_volume': profile.minVolume,
      'max_bid_ask_spread_pct': profile.maxBidAskSpreadPct.toString(),
      'avoid_earnings': profile.avoidEarnings,
      'avoid_macro_events': profile.avoidMacroEvents,
      'only_on_approved_underlyings': profile.onlyOnApprovedUnderlyings,
      'risk_disclosure_ack_at_iso': profile.riskDisclosureAckAt
          ?.toUtc()
          .toIso8601String(),
    };
  }
}
