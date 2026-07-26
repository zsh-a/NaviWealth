import 'package:decimal/decimal.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/ai/runtime/device/anthropic/anthropic_wire.dart';
import 'package:naviwealth/core/ai/runtime/device/device_session.dart';
import 'package:naviwealth/core/ai/runtime/device/tools/device_tool.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:naviwealth/features/finance/income_strategy/application/income_strategy_asset_resolver.dart';
import 'package:naviwealth/features/finance/income_strategy/application/leaps_income_sleeve_adapter.dart';
import 'package:naviwealth/features/finance/income_strategy/application/wheel_income_sleeve_adapter.dart';
import 'package:naviwealth/features/finance/income_strategy/application/wheel_strategy_view.dart';
import 'package:naviwealth/features/finance/income_strategy/data/providers.dart';
import 'package:naviwealth/features/finance/income_strategy/domain/income_strategy_assembler.dart';
import 'package:naviwealth/features/finance/options_income/ai_tools/get_wheel_lifecycle_tool.dart';
import 'package:naviwealth/features/finance/options_income/domain/leaps_call_position.dart';
import 'package:naviwealth/features/finance/options_income/domain/options_strategy_profile.dart';
import 'package:naviwealth/features/finance/options_income/domain/trade_journal_entry.dart';

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

ProviderContainer _container(
  List<TradeJournalEntry> entries, {
  List<LeapsCallPosition> leaps = const [],
}) => ProviderContainer(
  overrides: [
    wheelStrategyViewsProvider.overrideWith(
      (ref) => AsyncData(_views(entries, leaps)),
    ),
  ],
);

List<WheelStrategyView> _views(
  List<TradeJournalEntry> entries,
  List<LeapsCallPosition> leaps,
) {
  final assets = IncomeStrategyAssetResolver(const []);
  return buildWheelStrategyViews(
    const IncomeStrategyAssembler().assemble(
      baseCurrency: 'USD',
      plans: const [],
      contributions: [
        ...const WheelIncomeSleeveAdapter().buildFromEntries(
          entries: entries,
          assets: assets,
        ),
        ...const LeapsIncomeSleeveAdapter().build(
          positions: leaps,
          assets: assets,
        ),
      ],
    ),
  );
}

/// Runs [body] inside a probe so it gets a real Riverpod [Ref].
Future<T> _withRef<T>(ProviderContainer c, Future<T> Function(Ref ref) body) {
  final probe = FutureProvider<T>((ref) => body(ref));
  c.listen(probe, (_, _) {});
  return c.read(probe.future);
}

/// Run [tool.invoke] with a real [Ref] sourced from [container]. Awaits
Future<Map<String, Object?>> _invoke(
  GetWheelLifecycleTool tool,
  ProviderContainer container,
  Map<String, Object?> input, {
  bool drainStream = true,
}) async {
  if (drainStream) container.read(wheelStrategyViewsProvider);
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
      final c = ProviderContainer(
        overrides: [
          wheelStrategyViewsProvider.overrideWith(
            (ref) => const AsyncLoading<List<WheelStrategyView>>(),
          ),
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

    test('open positions are serialised without collapsing exposure', () async {
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
      final open = (cycle['open_positions']! as List).single as Map;
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

    test('returns LEAPS overlay metrics and evidence separately', () async {
      final c = _container(
        [
          _entry(
            id: 'put',
            symbol: 'TSM',
            strategy: OptionsStrategyKind.cashSecuredPut,
            status: TradeJournalStatus.open,
          ),
        ],
        leaps: [
          LeapsCallPosition(
            id: 'leaps',
            symbol: 'TSM',
            optionSymbol: 'TSM280121C00200000',
            openedAt: DateTime.utc(2026, 7, 1),
            expirationAt: DateTime.utc(2028, 1, 21),
            closedAt: null,
            strikePrice: Decimal.fromInt(200),
            entryDebit: Decimal.fromInt(1000),
            exitCredit: null,
            fees: Decimal.zero,
            currency: 'USD',
            contractSize: 100,
            contractQuantity: 1,
            status: LeapsCallStatus.open,
            currentMark: Decimal.fromInt(1100),
            currentDelta: Decimal.parse('0.65'),
            markedAt: DateTime.utc(2026, 7, 20),
            brokerageAccountId: null,
            notes: null,
            sync: _meta(),
          ),
        ],
      );
      addTearDown(c.dispose);
      final out = await _invoke(tool, c, const {'symbol': 'TSM'});
      final cycle = (out['cycles']! as List).single as Map;
      final overlay = cycle['leaps_overlay']! as Map;
      expect(overlay['open_premium_at_risk'], '1000');
      expect(overlay['delta_equivalent_shares'], '65');
      final evidence = (out['evidence']! as List).cast<Map<Object?, Object?>>();
      expect(
        evidence.map((value) => value['entity_table']),
        contains('options_leaps_call_positions'),
      );
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
