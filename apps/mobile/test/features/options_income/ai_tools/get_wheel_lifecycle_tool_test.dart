import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/ai/runtime/device/anthropic/anthropic_wire.dart';
import 'package:naviwealth/core/ai/runtime/device/device_session.dart';
import 'package:naviwealth/core/ai/runtime/device/tools/device_tool.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:naviwealth/features/options_income/ai_tools/get_wheel_lifecycle_tool.dart';
import 'package:naviwealth/features/options_income/data/providers.dart';
import 'package:naviwealth/features/options_income/domain/options_strategy_profile.dart';
import 'package:naviwealth/features/options_income/domain/trade_journal_entry.dart';

SyncMeta _meta() => SyncMeta(
  ownerUserId: 'u',
  updatedAt: DateTime.utc(2026, 5, 24),
  updatedByDevice: 'd',
  hlc: const Hlc(wallMillis: 1, counter: 0, nodeId: 'd'),
);

TradeJournalEntry _entry({
  String id = 'e',
  String symbol = 'TSM',
  required OptionsStrategyKind strategy,
  required TradeJournalStatus status,
  String entryCredit = '0',
  String? exitDebit,
  String currency = 'USD',
}) => TradeJournalEntry(
  id: id,
  strategy: strategy,
  symbol: symbol,
  optionSymbol: '$symbol-OPT',
  openedAt: DateTime.utc(2026, 5, 1),
  closedAt: status == TradeJournalStatus.open
      ? null
      : DateTime.utc(2026, 5, 15),
  entryCredit: Decimal.parse(entryCredit),
  exitDebit: exitDebit == null ? null : Decimal.parse(exitDebit),
  realizedPnl: null,
  currency: currency,
  status: status,
  notes: null,
  sync: _meta(),
);

ProviderContainer _container(List<TradeJournalEntry> entries) =>
    ProviderContainer(
      overrides: [
        tradeJournalEntriesProvider.overrideWith((ref) async* {
          yield entries;
        }),
      ],
    );

/// Runs [body] inside a probe so it gets a real Riverpod [Ref].
Future<T> _withRef<T>(ProviderContainer c, Future<T> Function(Ref ref) body) {
  final probe = FutureProvider<T>((ref) => body(ref));
  c.listen(probe, (_, _) {});
  return c.read(probe.future);
}

/// Run [tool.invoke] with a real [Ref] sourced from [container]. Awaits
/// the upstream journal stream's first emission so the derived
/// [wheelLifecyclesProvider] has data before the tool reads it.
Future<Map<String, Object?>> _invoke(
  GetWheelLifecycleTool tool,
  ProviderContainer container,
  Map<String, Object?> input, {
  bool drainStream = true,
}) async {
  if (drainStream) {
    // Subscribe so autoDispose providers stay mounted across the read.
    container.listen(tradeJournalEntriesProvider, (_, _) {});
    await container.read(tradeJournalEntriesProvider.future);
  }
  return _withRef(container, (ref) async {
    final out = await tool.invoke(
      DeviceToolContext(
        ref: ref,
        session: DeviceSession(messages: const <AnthropicChatMessage>[]),
      ),
      input,
    );
    return (out! as Map).cast<String, Object?>();
  });
}

void main() {
  group('GetWheelLifecycleTool', () {
    const tool = GetWheelLifecycleTool();

    test('descriptor matches the contract surface', () {
      expect(tool.name, 'get_wheel_lifecycle');
      expect(tool.inputSchema['properties'], contains('symbol'));
      expect(tool.inputSchema['additionalProperties'], isFalse);
    });

    test('returns guidance when the journal hasn\'t loaded yet', () async {
      // Override with a stream that never emits — the derived
      // wheelLifecyclesProvider stays in AsyncLoading and `.value` is
      // null, exercising the guidance branch.
      final c = ProviderContainer(
        overrides: [
          tradeJournalEntriesProvider.overrideWith((ref) async* {
            // Never emits — pause indefinitely.
            await Completer<void>().future;
          }),
        ],
      );
      addTearDown(c.dispose);
      final out = await _invoke(
        tool,
        c,
        const <String, Object?>{},
        drainStream: false,
      );
      expect(out['cycles'], isEmpty);
      expect(out['guidance'], isNotNull);
    });

    test('returns every cycle when no symbol filter is given', () async {
      final c = _container([
        _entry(
          id: 'tsm',
          symbol: 'TSM',
          strategy: OptionsStrategyKind.cashSecuredPut,
          status: TradeJournalStatus.open,
          entryCredit: '120',
        ),
        _entry(
          id: 'aapl',
          symbol: 'AAPL',
          strategy: OptionsStrategyKind.coveredCall,
          status: TradeJournalStatus.expired,
          entryCredit: '80',
          exitDebit: '0',
        ),
      ]);
      addTearDown(c.dispose);
      final out = await _invoke(tool, c, const <String, Object?>{});
      final cycles = out['cycles']! as List;
      expect(cycles, hasLength(2));
      final symbols = cycles.map((c) => (c as Map)['symbol']).toSet();
      expect(symbols, {'TSM', 'AAPL'});
    });

    test(
      'symbol filter narrows to one underlying (case-insensitive)',
      () async {
        final c = _container([
          _entry(
            id: 'tsm',
            symbol: 'TSM',
            strategy: OptionsStrategyKind.cashSecuredPut,
            status: TradeJournalStatus.open,
          ),
          _entry(
            id: 'aapl',
            symbol: 'AAPL',
            strategy: OptionsStrategyKind.coveredCall,
            status: TradeJournalStatus.open,
          ),
        ]);
        addTearDown(c.dispose);
        final out = await _invoke(tool, c, const {'symbol': 'tsm'});
        final cycles = out['cycles']! as List;
        expect(cycles, hasLength(1));
        expect((cycles.single as Map)['symbol'], 'TSM');
      },
    );

    test('symbol filter with no match returns empty + guidance', () async {
      final c = _container([
        _entry(
          id: 'tsm',
          symbol: 'TSM',
          strategy: OptionsStrategyKind.cashSecuredPut,
          status: TradeJournalStatus.open,
        ),
      ]);
      addTearDown(c.dispose);
      final out = await _invoke(tool, c, const {'symbol': 'NVDA'});
      expect(out['cycles'], isEmpty);
      expect(out['guidance'], contains('NVDA'));
    });

    test('open position is serialised under open_position', () async {
      final c = _container([
        _entry(
          id: 'open-put',
          symbol: 'TSM',
          strategy: OptionsStrategyKind.cashSecuredPut,
          status: TradeJournalStatus.open,
          entryCredit: '120',
        ),
      ]);
      addTearDown(c.dispose);
      final out = await _invoke(tool, c, const <String, Object?>{});
      final cycle = (out['cycles']! as List).single as Map;
      expect(cycle['has_open_position'], isTrue);
      expect(cycle['stage'], 'short_put');
      final open = cycle['open_position']! as Map;
      expect(open['id'], 'open-put');
      expect(open['strategy'], 'cash_secured_put');
      expect(open['entry_credit'], '120');
    });

    test('output carries evidence anchors per journal entry', () async {
      final c = _container([
        _entry(
          id: 'tsm-1',
          symbol: 'TSM',
          strategy: OptionsStrategyKind.cashSecuredPut,
          status: TradeJournalStatus.assigned,
          entryCredit: '120',
          exitDebit: '0',
        ),
        _entry(
          id: 'tsm-2',
          symbol: 'TSM',
          strategy: OptionsStrategyKind.coveredCall,
          status: TradeJournalStatus.open,
          entryCredit: '80',
        ),
      ]);
      addTearDown(c.dispose);
      final out = await _invoke(tool, c, const <String, Object?>{});
      final evidence = out['evidence']! as List;
      expect(evidence, hasLength(2));
      final ids = evidence
          .map((e) => (e as Map)['entity_id'] as String)
          .toSet();
      expect(ids, {'tsm-1', 'tsm-2'});
      // Anchors point at the synced trade journal table — the chat UI
      // dispatches the deep-link from here.
      for (final e in evidence.cast<Map<Object?, Object?>>()) {
        expect(e['entity_table'], 'options_trade_journal');
      }
    });

    test(
      'closed cycle has null open_position and reports cumulative income',
      () async {
        final c = _container([
          _entry(
            id: 'closed-put',
            symbol: 'TSM',
            strategy: OptionsStrategyKind.cashSecuredPut,
            status: TradeJournalStatus.expired,
            entryCredit: '120',
            exitDebit: '0',
          ),
        ]);
        addTearDown(c.dispose);
        final out = await _invoke(tool, c, const <String, Object?>{});
        final cycle = (out['cycles']! as List).single as Map;
        expect(cycle['has_open_position'], isFalse);
        expect(cycle['stage'], 'cash_waiting');
        expect(cycle['open_position'], isNull);
        expect(cycle['cumulative_income'], '120');
      },
    );
  });
}
