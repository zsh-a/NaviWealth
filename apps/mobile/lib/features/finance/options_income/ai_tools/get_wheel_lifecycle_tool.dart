import 'package:naviwealth/core/ai/contracts/evidence_anchor.dart';
import 'package:naviwealth/core/ai/runtime/device/tools/device_tool.dart';
import 'package:naviwealth/features/finance/income_strategy/application/wheel_strategy_view.dart';
import 'package:naviwealth/features/finance/income_strategy/data/providers.dart';
import 'package:naviwealth/features/finance/options_income/domain/options_strategy_profile.dart';
import 'package:naviwealth/features/finance/options_income/domain/wheel_lifecycle.dart';

/// `get_wheel_lifecycle` — return the per-underlying Wheel cycle posture
/// (`docs/domains/options-income.md` §12 P4). Read-only derived view over the
/// already-synced trade journal — no extra IO. When [input.symbol] is
/// provided, returns just that underlying's cycle; otherwise returns the
/// full list ordered by stage salience (open positions first).
class GetWheelLifecycleTool implements DeviceTool {
  const GetWheelLifecycleTool();

  @override
  String get name => 'get_wheel_lifecycle';

  @override
  String get description =>
      '返回用户期权 Wheel 策略每个标的当前的周期阶段(cash → short put → assigned → '
      'shares held → short call → called away),包含累计已实现收益、是否有开仓、'
      '是否当前持股。读自交易日志,**不**触发任何扫描或行情请求。'
      '可传入 `symbol` 只取单一标的;不传则返回全部。'
      '回答用户"我的 X 在哪个阶段?"前先调用本工具。';

  @override
  Map<String, Object?> get inputSchema => const <String, Object?>{
    'type': 'object',
    'properties': <String, Object?>{
      'symbol': <String, Object?>{
        'type': 'string',
        'description': '只读取这个标的的周期(大小写不敏感)。不传则返回所有标的的周期列表。',
      },
    },
    'additionalProperties': false,
  };

  @override
  Future<Object?> invoke(
    DeviceToolContext ctx,
    Map<String, Object?> input,
  ) async {
    final overlaysAsync = ctx.ref.read(wheelStrategyViewsProvider);
    final overlays = overlaysAsync.value;
    if (overlays == null) {
      return <String, Object?>{
        'cycles': <Object?>[],
        'guidance': '交易日志尚未加载完毕,请稍后再问;或先邀请用户在 Income Planner 录入一笔交易。',
      };
    }

    final filter = (input['symbol'] as String?)?.trim().toUpperCase();
    final filtered = filter == null || filter.isEmpty
        ? overlays
        : overlays
              .where((value) => value.wheel.symbol.toUpperCase() == filter)
              .toList(growable: false);

    final result = <String, Object?>{
      'cycles': [for (final overlay in filtered) _cycleToWire(overlay)],
      if (filter != null && filtered.isEmpty)
        'guidance': '$filter 没有任何 Wheel 周期记录;请先建议用户在 Income Planner 录入一笔交易。',
    };
    return withEvidence(
      result: result,
      anchors: [
        for (final overlay in filtered) ...[
          for (final entry in overlay.wheel.entries)
            EvidenceAnchor(
              entityTable: 'options_trade_journal',
              entityId: entry.id,
              label: '${overlay.wheel.symbol} · ${entry.strategy.wire}',
            ),
          for (final position in overlay.positions)
            EvidenceAnchor(
              entityTable: 'options_leaps_call_positions',
              entityId: position.id,
              label: '${overlay.wheel.symbol} · LEAPS long call',
            ),
        ],
      ],
    );
  }

  Map<String, Object?> _cycleToWire(WheelStrategyView overlay) {
    final cycle = overlay.wheel;
    return <String, Object?>{
      'symbol': cycle.symbol,
      'currency': cycle.currency,
      'stage': _stageWire(cycle.stage),
      'has_open_position': cycle.hasOpenPosition,
      'holds_shares': cycle.holdsShares,
      'cumulative_income': cycle.cumulativeIncome.toString(),
      'entry_count': cycle.entries.length,
      'open_positions': [
        for (final position in cycle.openPositions)
          <String, Object?>{
            'id': position.id,
            'strategy': position.strategy.wire,
            'option_symbol': position.optionSymbol,
            'opened_at': position.openedAt.toUtc().toIso8601String(),
            'expiration_at': position.expirationAt?.toUtc().toIso8601String(),
            'entry_credit': position.entryCredit.toString(),
            'contract_quantity': position.contractQuantity,
          },
      ],
      'leaps_overlay': <String, Object?>{
        'open_position_count': overlay.openPositions.length,
        'open_premium_at_risk': overlay.openLeapsCost.toString(),
        'realized_leaps_pnl': overlay.realizedLeapsPnl.toString(),
        'underlying_realized_result': overlay.underlyingRealizedResult
            .toString(),
        'wheel_income_coverage_ratio': overlay.wheelIncomeCoverageRatio
            ?.toString(),
        'delta_equivalent_shares': overlay.deltaEquivalentShares?.toString(),
        'warnings': [for (final risk in overlay.risks) risk.code.name],
        'positions': [
          for (final position in overlay.openPositions)
            <String, Object?>{
              'id': position.id,
              'option_symbol': position.optionSymbol,
              'expiration_at': position.expirationAt.toUtc().toIso8601String(),
              'strike_price': position.strikePrice.toString(),
              'entry_debit': position.entryDebit.toString(),
              'contract_quantity': position.contractQuantity,
              'current_mark': position.currentMark?.toString(),
              'current_delta': position.currentDelta?.toString(),
            },
        ],
      },
    };
  }

  static String _stageWire(WheelStage stage) => switch (stage) {
    WheelStage.between => 'between',
    WheelStage.cashWaiting => 'cash_waiting',
    WheelStage.shortPut => 'short_put',
    WheelStage.putExpired => 'put_expired',
    WheelStage.putAssigned => 'put_assigned',
    WheelStage.sharesHeld => 'shares_held',
    WheelStage.shortCall => 'short_call',
    WheelStage.mixedOpen => 'mixed_open',
    WheelStage.callExpired => 'call_expired',
    WheelStage.callCalled => 'call_called',
  };
}
