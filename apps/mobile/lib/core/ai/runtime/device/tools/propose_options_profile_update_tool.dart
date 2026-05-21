import '../../../../../features/options_income/data/providers.dart';
import '../../../../../features/options_income/domain/options_strategy_profile.dart';
import 'device_tool.dart';
import 'propose/proposal_plan.dart';

/// `propose_options_profile_update` — propose changes to the options
/// strategy profile (`docs/options-income.md` §8.2).
///
/// Returns a `ProposalEnvelope`-shaped JSON. Never writes directly.
class ProposeOptionsProfileUpdateTool implements DeviceTool {
  const ProposeOptionsProfileUpdateTool();

  @override
  String get name => 'propose_options_profile_update';

  @override
  String get description =>
      '提议更新 Income Planner 偏好(mode / dte_min / dte_max / 收益阈值 / '
      'open_interest 阈值 / 资金占比上限 / avoid_earnings / only_on_approved_underlyings 等)。'
      '本工具不会立即写入,而是返回 plan,前端会展示 diff 并请用户确认。'
      '请只填写需要调整的字段;不要触碰 risk_disclosure_ack_at。';

  @override
  Map<String, Object?> get inputSchema => const <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'mode': <String, Object?>{
            'type': 'string',
            'enum': ['conservative', 'balanced', 'aggressive', 'custom'],
          },
          'min_dte': <String, Object?>{
            'type': 'integer',
            'minimum': 0,
            'maximum': 365,
          },
          'max_dte': <String, Object?>{
            'type': 'integer',
            'minimum': 0,
            'maximum': 365,
          },
          'min_annualized_yield': <String, Object?>{
            'type': 'number',
            'minimum': 0,
            'maximum': 1,
          },
          'min_open_interest': <String, Object?>{
            'type': 'integer',
            'minimum': 0,
          },
          'min_volume': <String, Object?>{
            'type': 'integer',
            'minimum': 0,
          },
          'max_capital_per_trade_pct': <String, Object?>{
            'type': 'number',
            'minimum': 0,
            'maximum': 1,
          },
          'avoid_earnings': <String, Object?>{'type': 'boolean'},
          'avoid_macro_events': <String, Object?>{'type': 'boolean'},
          'only_on_approved_underlyings': <String, Object?>{
            'type': 'boolean',
          },
          'note': <String, Object?>{'type': 'string'},
        },
      };

  @override
  Future<Object?> invoke(
    DeviceToolContext ctx,
    Map<String, Object?> input,
  ) async {
    const knownFields = <String>{
      'mode',
      'min_dte',
      'max_dte',
      'min_annualized_yield',
      'min_open_interest',
      'min_volume',
      'max_capital_per_trade_pct',
      'avoid_earnings',
      'avoid_macro_events',
      'only_on_approved_underlyings',
    };
    final updates = <String, Object?>{};
    for (final field in knownFields) {
      if (input.containsKey(field) && input[field] != null) {
        updates[field] = input[field];
      }
    }
    if (updates.isEmpty) {
      return proposalBadRequest(
        'propose_options_profile_update: at least one field must be supplied',
      );
    }
    final current = ctx.ref.read(optionsStrategyProfileProvider).value;
    if (current == null) {
      return proposalBadRequest(
        'propose_options_profile_update: profile not configured yet '
        '— ask the user to set up Income Planner first',
      );
    }
    final before = <String, Object?>{
      'mode': current.mode.wire,
      'min_dte': current.minDte,
      'max_dte': current.maxDte,
      'min_annualized_yield': current.minAnnualizedYield.toString(),
      'min_open_interest': current.minOpenInterest,
      'min_volume': current.minVolume,
      'max_capital_per_trade_pct':
          current.maxCapitalPerTradePct.toString(),
      'avoid_earnings': current.avoidEarnings,
      'avoid_macro_events': current.avoidMacroEvents,
      'only_on_approved_underlyings': current.onlyOnApprovedUnderlyings,
    };
    return readyPlan(
      kind: 'options_profile_update',
      summaryZh: _summary(updates),
      payload: <String, Object?>{
        'before': before,
        'after': updates,
        if (input['note'] != null) 'note': input['note'],
      },
    );
  }
}

String _summary(Map<String, Object?> updates) {
  final parts = <String>[];
  updates.forEach((k, v) => parts.add('$k → $v'));
  return '更新 Income Planner 偏好:${parts.join('、')}';
}
