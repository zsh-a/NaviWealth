import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/ai/contracts/task_context.dart'
    show AnalyticalUpload;
import 'package:naviwealth/core/ai/local/skills/skills.dart'
    show RecurringCadence, RecurringPattern, recurringPatternToUpload;
import 'package:naviwealth/core/ai/runtime/device/device_session.dart';
import 'package:naviwealth/core/ai/runtime/device/tools/device_tool.dart';
import 'package:naviwealth/core/ai/runtime/device/tools/device_tool_registry.dart';
import 'package:naviwealth/core/ai/runtime/device/tools/get_anomaly_flags_tool.dart';
import 'package:naviwealth/core/ai/runtime/device/tools/get_asset_allocation_tool.dart';
import 'package:naviwealth/core/ai/runtime/device/tools/get_holdings_tool.dart';
import 'package:naviwealth/core/ai/runtime/device/tools/get_recurring_patterns_tool.dart';
import 'package:naviwealth/core/ai/runtime/device/tools/list_payment_accounts_tool.dart';
import 'package:naviwealth/data/domain/account.dart';
import 'package:naviwealth/data/domain/enums.dart';
import 'package:naviwealth/data/domain/hlc.dart';
import 'package:naviwealth/data/domain/sync_meta.dart';
import 'package:naviwealth/features/expense/data/expense_anomaly_insight_provider.dart';

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
        GetAssetAllocationTool(),
        GetAnomalyFlagsTool(),
        GetRecurringPatternsTool(),
      ]);
      final schemas = reg.schemas();
      expect(schemas.map((s) => s.name), [
        'get_anomaly_flags',
        'get_asset_allocation',
        'get_holdings',
        'get_recurring_patterns',
        'list_payment_accounts',
      ]);
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

  group('GetAssetAllocationTool.shape — ports aggregate()', () {
    Map<String, Object?> snap(List<Map<String, Object?>> hs) => {
      'holdings': {for (var i = 0; i < hs.length; i++) 'h$i': hs[i]},
    };

    Map<String, Object?> h(
      String type,
      String ccy,
      String cost,
    ) => {
      'type': type,
      'asset_currency': ccy,
      'cost_basis_asset_currency': cost,
    };

    test('aggregates by (type,currency) and normalises weight per ccy', () {
      final m = GetAssetAllocationTool.shape(
        snap([
          h('stock', 'USD', '600'),
          h('stock', 'USD', '200'), // → stock/USD = 800, count 2
          h('crypto', 'USD', '200'), // → crypto/USD = 200
        ]),
      );
      final buckets = (m['buckets'] as List).cast<Map<String, Object?>>();
      expect(m['count'], 2);
      // sorted: currency asc then weight desc → stock first (0.8)
      expect(buckets[0]['bucket_key'], 'stock');
      expect(buckets[0]['currency'], 'USD');
      expect(buckets[0]['position_count'], 2);
      expect(buckets[0]['total_cost_minor'], '80000');
      expect(buckets[0]['weight'], closeTo(0.8, 1e-9));
      expect(buckets[1]['bucket_key'], 'crypto');
      expect(buckets[1]['weight'], closeTo(0.2, 1e-9));
      // weights within USD sum to 1
      final sum = buckets.fold<double>(
        0,
        (a, b) => a + (b['weight'] as double),
      );
      expect(sum, closeTo(1.0, 1e-9));
    });

    test('separate currencies normalise independently; ccy sorted asc', () {
      final m = GetAssetAllocationTool.shape(
        snap([h('stock', 'USD', '100'), h('bond', 'CNY', '50')]),
      );
      final b = (m['buckets'] as List).cast<Map<String, Object?>>();
      expect(b.map((x) => x['currency']), ['CNY', 'USD']);
      expect(b.every((x) => (x['weight'] as double) == 1.0), isTrue);
    });

    test('missing type falls back to "unknown"', () {
      final m = GetAssetAllocationTool.shape(
        snap([
          {'asset_currency': 'USD', 'cost_basis_asset_currency': '10'},
        ]),
      );
      expect((m['buckets'] as List).single, containsPair('bucket_key', 'unknown'));
    });

    test('no holdings → empty buckets', () {
      final m = GetAssetAllocationTool.shape(null);
      expect(m['buckets'], isEmpty);
      expect(m['count'], 0);
      expect(m['note'], contains('cost basis'));
    });
  });

  group('analyticalAnomalyUpload — shared cloud/device converter', () {
    test('null anomaly → null upload', () {
      expect(analyticalAnomalyUpload(null), isNull);
    });

    test('buckets severity by |deltaRatio| and stamps stable id', () {
      final u = analyticalAnomalyUpload(
        const ExpenseAnomalySummary(deltaRatio: 0.6),
        now: DateTime.utc(2026, 5, 16),
      )!;
      expect(u.kind, 'anomaly_flag');
      expect(u.id, 'expense_monthly_spike|2026-05');
      expect(u.payload['severity'], 'critical');
      expect(u.payload['delta_pct'], 60);
      expect(u.payload['kind'], 'monthly_spike');
      expect(u.payload['category'], 'all_expense');
      expect(
        analyticalAnomalyUpload(
          const ExpenseAnomalySummary(deltaRatio: 0.3),
          now: DateTime.utc(2026),
        )!.payload['severity'],
        'warn',
      );
      expect(
        analyticalAnomalyUpload(
          const ExpenseAnomalySummary(deltaRatio: 0.1),
          now: DateTime.utc(2026),
        )!.payload['severity'],
        'info',
      );
    });
  });

  group('GetAnomalyFlagsTool.shape — projects upload → flag row', () {
    AnalyticalUpload up(double d) => analyticalAnomalyUpload(
      ExpenseAnomalySummary(deltaRatio: d),
      now: DateTime.utc(2026, 5, 16),
    )!;

    test('no anomaly → empty, device-sourced envelope', () {
      final m = GetAnomalyFlagsTool.shape(null);
      expect(m['flags'], isEmpty);
      expect(m['count'], 0);
      expect(m['source'], 'device_analytical_read_model');
      expect(m['note'], contains('device-sourced'));
    });

    test('projects the backend flag-row shape', () {
      final m = GetAnomalyFlagsTool.shape(up(0.6));
      final f = (m['flags'] as List).single as Map<String, Object?>;
      expect(f['id'], 'expense_monthly_spike|2026-05');
      expect(f['category'], 'all_expense');
      expect(f['kind'], 'monthly_spike');
      expect(f['delta_pct'], 60);
      expect(f['severity'], 'critical');
      expect(f['detected_at'], isA<String>());
      expect(f['payload'], isA<Map<String, Object?>>());
      expect(m['count'], 1);
    });

    test('severity_min filters (info ≤ warn ≤ critical)', () {
      expect(
        (GetAnomalyFlagsTool.shape(up(0.3), severityMin: 'critical')['flags']
                as List)
            .isEmpty,
        isTrue, // warn < critical → dropped
      );
      expect(
        (GetAnomalyFlagsTool.shape(up(0.6), severityMin: 'warn')['flags']
                as List)
            .length,
        1, // critical ≥ warn → kept
      );
    });

    test('invalid severity_min is ignored (no filter)', () {
      expect(
        (GetAnomalyFlagsTool.shape(up(0.1), severityMin: 'weird')['flags']
                as List)
            .length,
        1,
      );
    });
  });

  group('recurringPatternToUpload — shared cloud/device converter', () {
    RecurringPattern pat({
      String merchant = 'netflix',
      RecurringCadence cadence = RecurringCadence.monthly,
      int median = 1299,
      String currency = 'USD',
    }) => RecurringPattern(
      merchantKey: merchant,
      cadence: cadence,
      medianAmountMinor: median,
      currency: currency,
      occurrenceIds: const ['a', 'b', 'c'],
      lastSeenAt: DateTime.utc(2026, 5, 1),
    );

    test('stable id + payload shape (mirrors backend read model)', () {
      final u = recurringPatternToUpload(pat());
      expect(u.kind, 'recurring_pattern');
      expect(u.id, 'netflix|USD');
      expect(u.payload['merchant_key'], 'netflix');
      expect(u.payload['cadence'], 'monthly');
      expect(u.payload['median_amount_minor'], '1299');
      expect(u.payload['currency'], 'USD');
      expect(u.payload['occurrences'], 3);
      expect(u.payload['last_seen_at'], '2026-05-01T00:00:00.000Z');
    });

    test('GetRecurringPatternsTool.shape projects + filters', () {
      final uploads = [
        recurringPatternToUpload(pat()), // netflix monthly USD
        recurringPatternToUpload(
          pat(
            merchant: 'gym',
            cadence: RecurringCadence.weekly,
            currency: 'CNY',
          ),
        ),
      ];

      final all = GetRecurringPatternsTool.shape(uploads);
      expect(all['count'], 2);
      expect(all['source'], 'device_analytical_read_model');
      final first = (all['patterns'] as List).first as Map;
      expect(first['id'], 'netflix|USD');
      expect(first['merchant_key'], 'netflix');
      expect(first['cadence'], 'monthly');
      expect(first['median_amount_minor'], '1299');
      expect(first['occurrences'], 3);
      expect(first['payload'], isA<Map<String, Object?>>());

      // currency filter (case-insensitive)
      final usd = GetRecurringPatternsTool.shape(uploads, currency: 'usd');
      expect((usd['patterns'] as List).single, containsPair('id', 'netflix|USD'));

      // cadence filter
      final weekly = GetRecurringPatternsTool.shape(
        uploads,
        cadence: 'weekly',
      );
      expect((weekly['patterns'] as List).single, containsPair('cadence', 'weekly'));

      // invalid cadence ignored (no filter)
      expect(
        GetRecurringPatternsTool.shape(uploads, cadence: 'daily')['count'],
        2,
      );
    });

    test('empty uploads → empty patterns, device-sourced envelope', () {
      final m = GetRecurringPatternsTool.shape(const []);
      expect(m['patterns'], isEmpty);
      expect(m['count'], 0);
      expect(m['note'], contains('device-sourced'));
    });
  });
}
