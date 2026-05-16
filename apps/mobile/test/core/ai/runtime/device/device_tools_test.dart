import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/ai/runtime/device/device_session.dart';
import 'package:naviwealth/core/ai/runtime/device/tools/device_tool.dart';
import 'package:naviwealth/core/ai/runtime/device/tools/device_tool_registry.dart';
import 'package:naviwealth/core/ai/runtime/device/tools/get_holdings_tool.dart';
import 'package:naviwealth/core/ai/runtime/device/tools/list_payment_accounts_tool.dart';
import 'package:naviwealth/data/domain/account.dart';
import 'package:naviwealth/data/domain/enums.dart';
import 'package:naviwealth/data/domain/hlc.dart';
import 'package:naviwealth/data/domain/sync_meta.dart';

SyncMeta _stamp() => SyncMeta(
  ownerUserId: 'u',
  updatedAt: DateTime.utc(2026),
  updatedByDevice: 'd',
  hlc: const Hlc(wallMillis: 1700000000000, counter: 0, nodeId: 'd'),
);

Account _acct(
  String id,
  String name, {
  AccountCategory type = AccountCategory.bank,
  AccountSide category = AccountSide.asset,
  String currency = 'CNY',
  bool archived = false,
}) => Account(
  id: id,
  type: type,
  name: name,
  currency: currency,
  archived: archived,
  category: category,
  sync: _stamp(),
);

DeviceSession _session() => DeviceSession(messages: []);

class _ThrowingTool implements DeviceTool {
  @override
  String get name => 'boom';
  @override
  String get description => 'd';
  @override
  Map<String, Object?> get inputSchema => const {'type': 'object'};
  @override
  Future<Object?> invoke(DeviceToolContext ctx, Map<String, Object?> i) async =>
      throw StateError('kaboom');
}

class _SlowTool implements DeviceTool {
  @override
  String get name => 'slow';
  @override
  String get description => 'd';
  @override
  Map<String, Object?> get inputSchema => const {'type': 'object'};
  @override
  Future<Object?> invoke(
    DeviceToolContext ctx,
    Map<String, Object?> i,
  ) async {
    await Future<void>.delayed(const Duration(seconds: 1));
    return {'ok': true};
  }
}

/// Runs [body] with a real Riverpod [Ref] from inside the container.
Future<T> _withRef<T>(
  ProviderContainer c,
  Future<T> Function(Ref ref) body,
) {
  // Non-autoDispose so the probe (and the autoDispose providers it
  // reads, e.g. accountsStreamProvider) stay mounted until the
  // container is torn down — an autoDispose probe gets reclaimed
  // mid-load and the stream never emits.
  final probe = FutureProvider<T>((ref) => body(ref));
  c.listen(probe, (_, _) {});
  return c.read(probe.future);
}

void main() {
  group('DeviceToolRegistry', () {
    test('schemas() are sorted and expose the ported tool surface', () {
      final reg = DeviceToolRegistry(const [
        ListPaymentAccountsTool(),
        GetHoldingsTool(),
      ]);
      final schemas = reg.schemas();
      expect(
        schemas.map((s) => s.name),
        ['get_holdings', 'list_payment_accounts'], // sorted
      );
      expect(
        schemas.firstWhere((s) => s.name == 'list_payment_accounts').description,
        contains('支付账户候选'),
      );
      expect(reg.lookup('get_holdings'), isNotNull);
      expect(reg.lookup('nope'), isNull);
    });
  });

  group('DriftDeviceToolDispatcher — backend error envelopes', () {
    test('unknown tool → policy_denied envelope', () async {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final reg = DeviceToolRegistry(const []);
      final out = await _withRef(
        c,
        (ref) => DriftDeviceToolDispatcher(ref: ref, registry: reg)
            .dispatch(_session(), 'ghost', const {}),
      );
      final m = out! as Map;
      expect(m['policy_denied'], true);
      expect((m['error'] as Map)['code'], 'policy_denied');
      expect((m['error'] as Map)['policy'], 'unknown_tool');
      expect((m['error'] as Map)['tool'], 'ghost');
    });

    test('throwing tool → tool_error', () async {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final reg = DeviceToolRegistry([_ThrowingTool()]);
      final out = await _withRef(
        c,
        (ref) => DriftDeviceToolDispatcher(ref: ref, registry: reg)
            .dispatch(_session(), 'boom', const {}),
      );
      final m = out! as Map;
      expect(m['code'], 'tool_error');
      expect(m['error'], contains('kaboom'));
    });

    test('slow tool → tool_timeout with the backend shape', () async {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final reg = DeviceToolRegistry([_SlowTool()]);
      final out = await _withRef(
        c,
        (ref) => DriftDeviceToolDispatcher(
          ref: ref,
          registry: reg,
          perToolTimeout: const Duration(milliseconds: 20),
        ).dispatch(_session(), 'slow', const {}),
      );
      final m = out! as Map;
      expect(m['code'], 'tool_timeout');
      expect(m['tool'], 'slow');
      expect(m['error'], contains('timed out after 20ms'));
    });
  });

  group('ListPaymentAccountsTool.shape', () {
    test('keeps only non-archived asset-side payment containers', () {
      final m = ListPaymentAccountsTool.shape(
        [
          _acct('a', 'Alpha Bank', type: AccountCategory.bank),
          _acct('b', 'Cash', type: AccountCategory.cash),
          _acct('c', 'Archived', type: AccountCategory.bank, archived: true),
          // generic manual-valuation container — excluded like backend
          _acct('d', 'House', type: AccountCategory.asset),
          _acct(
            'e',
            'Mortgage',
            type: AccountCategory.loan,
            category: AccountSide.liability,
          ),
        ],
        purpose: 'record_expense',
      );
      final ids = (m['accounts'] as List).map((a) => (a as Map)['id']);
      expect(ids, ['a', 'b']); // sorted by name: Alpha Bank, Cash
      expect(m['total_count'], 2);
      expect(m['truncated'], false);
      expect(m['status'], 'ready');
      expect((m['accounts'] as List).first, containsPair('type', 'bank'));
    });

    test('currency filter is case-insensitive', () {
      final m = ListPaymentAccountsTool.shape(
        [
          _acct('u', 'USD acct', currency: 'USD'),
          _acct('c', 'CNY acct', currency: 'CNY'),
        ],
        purpose: 'account_selection',
        currency: 'usd',
      );
      expect((m['accounts'] as List).single, containsPair('id', 'u'));
      expect(m['currency_filter'], 'USD');
    });

    test('max_results clamps and flags truncation', () {
      final m = ListPaymentAccountsTool.shape(
        [
          for (var i = 0; i < 5; i++)
            _acct('id$i', 'Acct $i', type: AccountCategory.bank),
        ],
        purpose: 'record_expense',
        maxResults: 2,
      );
      expect((m['accounts'] as List), hasLength(2));
      expect(m['total_count'], 5);
      expect(m['truncated'], true);
    });
  });

  group('ListPaymentAccountsTool.invoke', () {
    test('rejects an unsupported purpose before any provider read',
        () async {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final out = await _withRef(
        c,
        (ref) => const ListPaymentAccountsTool().invoke(
          DeviceToolContext(ref: ref, session: _session()),
          const {'purpose': 'mining'},
        ),
      );
      expect((out! as Map)['code'], 'bad_request');
    });
  });

  group('GetHoldingsTool.shape — mirrors client_portfolio_snapshot', () {
    final snapshot = <String, Object?>{
      'as_of': '2026-05-01T00:00:00.000Z',
      'base_currency': 'CNY',
      'holdings': {
        'a1': {'asset_id': 'a1', 'net_quantity': '10'},
      },
    };

    test('passes the device snapshot through verbatim', () {
      final m = GetHoldingsTool.shape(snapshot);
      expect(m['source'], 'client_portfolio_snapshot');
      expect(m['conversion_source'], 'client_portfolio_snapshot');
      expect(m['approximation'], false);
      expect(m['as_of'], '2026-05-01T00:00:00.000Z');
      expect(m['base_currency'], 'CNY');
      expect(m['snapshot_base_currency'], 'CNY');
      expect((m['holdings'] as Map)['a1'], isNotNull);
    });

    test('input base_currency overrides and is trimmed + uppercased', () {
      final m = GetHoldingsTool.shape(snapshot, inputBaseCurrency: ' usd ');
      expect(m['base_currency'], 'USD');
      expect(m['snapshot_base_currency'], 'CNY'); // raw snapshot value
    });

    test('input as_of overrides the snapshot timestamp', () {
      final m = GetHoldingsTool.shape(snapshot, inputAsOf: '2026-06-09T00:00:00Z');
      expect(m['as_of'], '2026-06-09T00:00:00Z');
    });

    test('no holdings → empty map, still a device-sourced answer', () {
      final m = GetHoldingsTool.shape(null);
      expect(m['holdings'], isEmpty);
      expect(m['source'], 'client_portfolio_snapshot');
      expect(m['base_currency'], isNull);
      expect(m['snapshot_base_currency'], isNull);
      expect(m['as_of'], isA<String>());
      expect((m['as_of'] as String).isNotEmpty, isTrue);
    });
  });
}
