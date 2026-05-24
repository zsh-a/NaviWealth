import '../../../../../features/options_income/data/providers.dart';
import '../../../../../features/options_income/domain/options_strategy_profile.dart';
import '../../../../../features/options_income/domain/wheel_lifecycle.dart';
import '../../../contracts/evidence_anchor.dart';
import 'device_tool.dart';

/// `get_wheel_lifecycle` — return the per-underlying Wheel cycle posture
/// (`docs/roadmap-next.md` §3.3 P4). Read-only derived view over the
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
    final cyclesAsync = ctx.ref.read(wheelLifecyclesProvider);
    final cycles = cyclesAsync.value;
    if (cycles == null) {
      return <String, Object?>{
        'cycles': <Object?>[],
        'guidance': '交易日志尚未加载完毕,请稍后再问;或先邀请用户在 Income Planner 录入一笔交易。',
      };
    }

    final filter = (input['symbol'] as String?)?.trim().toUpperCase();
    final filtered = filter == null || filter.isEmpty
        ? cycles
        : cycles
              .where((c) => c.symbol.toUpperCase() == filter)
              .toList(growable: false);

    final result = <String, Object?>{
      'cycles': [for (final cycle in filtered) _cycleToWire(cycle)],
      if (filter != null && filtered.isEmpty)
        'guidance': '$filter 没有任何 Wheel 周期记录;请先建议用户在 Income Planner 录入一笔交易。',
    };
    return withEvidence(
      result: result,
      anchors: [
        for (final cycle in filtered)
          for (final entry in cycle.entries)
            EvidenceAnchor(
              entityTable: 'options_trade_journal',
              entityId: entry.id,
              label: '${cycle.symbol} · ${entry.strategy.wire}',
            ),
      ],
    );
  }

  Map<String, Object?> _cycleToWire(WheelLifecycle cycle) => <String, Object?>{
    'symbol': cycle.symbol,
    'currency': cycle.currency,
    'stage': _stageWire(cycle.stage),
    'has_open_position': cycle.hasOpenPosition,
    'holds_shares': cycle.holdsShares,
    'cumulative_income': cycle.cumulativeIncome.toString(),
    'entry_count': cycle.entries.length,
    'open_position': cycle.openPosition == null
        ? null
        : <String, Object?>{
            'id': cycle.openPosition!.id,
            'strategy': cycle.openPosition!.strategy.wire,
            'option_symbol': cycle.openPosition!.optionSymbol,
            'opened_at': cycle.openPosition!.openedAt.toUtc().toIso8601String(),
            'entry_credit': cycle.openPosition!.entryCredit.toString(),
          },
  };

  static String _stageWire(WheelStage stage) => switch (stage) {
    WheelStage.between => 'between',
    WheelStage.cashWaiting => 'cash_waiting',
    WheelStage.shortPut => 'short_put',
    WheelStage.putExpired => 'put_expired',
    WheelStage.putAssigned => 'put_assigned',
    WheelStage.sharesHeld => 'shares_held',
    WheelStage.shortCall => 'short_call',
    WheelStage.callExpired => 'call_expired',
    WheelStage.callCalled => 'call_called',
  };
}
