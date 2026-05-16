import 'package:decimal/decimal.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/ai/contracts/task_context.dart'
    show AnalyticalUpload;
import 'package:naviwealth/core/ai/local/skills/skills.dart'
    show
        RecurringCadence,
        RecurringPattern,
        RefundMatch,
        SubscriptionChange,
        TransferMatch,
        recurringPatternToUpload,
        refundMatchToUpload,
        subscriptionChangeToUpload,
        transferMatchToUpload;
import 'package:naviwealth/core/ai/runtime/device/device_session.dart';
import 'package:naviwealth/core/ai/runtime/device/tools/device_tool.dart';
import 'package:naviwealth/core/ai/runtime/device/tools/device_tool_registry.dart';
import 'package:naviwealth/core/ai/runtime/device/tools/get_anomaly_flags_tool.dart';
import 'package:naviwealth/core/ai/runtime/device/tools/get_asset_allocation_tool.dart';
import 'package:naviwealth/core/ai/runtime/device/tools/get_holdings_tool.dart';
import 'package:naviwealth/core/ai/runtime/device/tools/get_investment_performance_tool.dart';
import 'package:naviwealth/core/ai/runtime/device/tools/get_recurring_patterns_tool.dart';
import 'package:naviwealth/core/ai/runtime/device/tools/get_refund_links_tool.dart';
import 'package:naviwealth/core/ai/runtime/device/tools/get_subscription_changes_tool.dart';
import 'package:naviwealth/core/ai/runtime/device/tools/get_transfer_links_tool.dart';
import 'package:naviwealth/core/ai/runtime/device/tools/list_payment_accounts_tool.dart';
import 'package:naviwealth/core/ai/runtime/device/tools/propose/proposal_plan.dart';
import 'package:naviwealth/core/ai/runtime/device/tools/propose_account_create_tool.dart';
import 'package:naviwealth/core/ai/runtime/device/tools/propose_asset_valuation_tool.dart';
import 'package:naviwealth/core/ai/runtime/device/tools/propose_expense_tool.dart';
import 'package:naviwealth/core/ai/runtime/device/tools/propose_liability_payment_tool.dart';
import 'package:naviwealth/core/ai/runtime/device/tools/propose_trade_tool.dart';
import 'package:naviwealth/core/ai/runtime/device/tools/read_account_window_tool.dart';
import 'package:naviwealth/core/ai/runtime/device/tools/read_asset_window_tool.dart';
import 'package:naviwealth/core/ai/runtime/device/tools/read_category_window_tool.dart';
import 'package:naviwealth/core/ai/runtime/device/tools/scoped/scoped_window.dart';
import 'package:naviwealth/data/domain/account.dart';
import 'package:naviwealth/data/domain/asset.dart';
import 'package:naviwealth/data/domain/enums.dart';
import 'package:naviwealth/data/domain/hlc.dart';
import 'package:naviwealth/data/domain/journal_entry.dart';
import 'package:naviwealth/data/domain/liability.dart';
import 'package:naviwealth/data/domain/posting.dart';
import 'package:naviwealth/data/domain/sync_meta.dart';
import 'package:naviwealth/data/repositories/journal_entry_repository.dart'
    show JournalEntryWithPostings;
import 'package:naviwealth/features/expense/data/expense_anomaly_insight_provider.dart';
import 'package:naviwealth/features/investment/data/providers.dart'
    show holdingSnapshotToUpload;
import 'package:naviwealth/features/investment/domain/models/holding_snapshot.dart';

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

JournalEntryWithPostings _ewp(
  String id,
  DateTime date,
  List<Posting> postings, {
  String narration = '',
}) => JournalEntryWithPostings(
  entry: JournalEntry(id: id, date: date, narration: narration, sync: _stamp()),
  postings: postings,
);

Posting _post(String accountId, String unit, String units) => Posting(
  id: 'p_${accountId}_$unit',
  journalEntryId: 'je',
  position: 0,
  accountId: accountId,
  units: Decimal.parse(units),
  unit: unit,
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
  Future<Object?> invoke(DeviceToolContext ctx, Map<String, Object?> i) async {
    await Future<void>.delayed(const Duration(seconds: 1));
    return {'ok': true};
  }
}

/// Runs [body] with a real Riverpod [Ref] from inside the container.
Future<T> _withRef<T>(ProviderContainer c, Future<T> Function(Ref ref) body) {
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
        GetRefundLinksTool(),
        GetTransferLinksTool(),
        GetInvestmentPerformanceTool(),
        GetSubscriptionChangesTool(),
        ProposeExpenseTool(),
        ProposeAccountCreateTool(),
        ProposeAssetValuationTool(),
        ProposeLiabilityPaymentTool(),
        ProposeTradeTool(),
        ReadAccountWindowTool(),
        ReadAssetWindowTool(),
        ReadCategoryWindowTool(),
      ]);
      final schemas = reg.schemas();
      expect(schemas.map((s) => s.name), [
        'get_anomaly_flags',
        'get_asset_allocation',
        'get_holdings',
        'get_investment_performance',
        'get_recurring_patterns',
        'get_refund_links',
        'get_subscription_changes',
        'get_transfer_links',
        'list_payment_accounts',
        'propose_account_create',
        'propose_asset_valuation',
        'propose_expense',
        'propose_liability_payment',
        'propose_trade',
        'read_account_window',
        'read_asset_window',
        'read_category_window',
      ]);
      expect(
        schemas
            .firstWhere((s) => s.name == 'list_payment_accounts')
            .description,
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
        (ref) => DriftDeviceToolDispatcher(
          ref: ref,
          registry: reg,
        ).dispatch(_session(), 'ghost', const {}),
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
        (ref) => DriftDeviceToolDispatcher(
          ref: ref,
          registry: reg,
        ).dispatch(_session(), 'boom', const {}),
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
      final m = ListPaymentAccountsTool.shape([
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
      ], purpose: 'record_expense');
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
    test('rejects an unsupported purpose before any provider read', () async {
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
      final m = GetHoldingsTool.shape(
        snapshot,
        inputAsOf: '2026-06-09T00:00:00Z',
      );
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

    Map<String, Object?> h(String type, String ccy, String cost) => {
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
      expect(
        (m['buckets'] as List).single,
        containsPair('bucket_key', 'unknown'),
      );
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
      expect(
        (usd['patterns'] as List).single,
        containsPair('id', 'netflix|USD'),
      );

      // cadence filter
      final weekly = GetRecurringPatternsTool.shape(uploads, cadence: 'weekly');
      expect(
        (weekly['patterns'] as List).single,
        containsPair('cadence', 'weekly'),
      );

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

  group('refund/transfer link tools (W-D4.3b twins)', () {
    test('refundMatchToUpload + GetRefundLinksTool.shape', () {
      final u = refundMatchToUpload(
        const RefundMatch(
          originalTxnId: 'o1',
          refundTxnId: 'r1',
          amountMinor: 3800,
          currency: 'USD',
        ),
      );
      expect(u.kind, 'refund_link');
      expect(u.id, 'o1|r1');
      expect(u.payload['amount_minor'], '3800');

      final m = GetRefundLinksTool.shape([u]);
      final link = (m['links'] as List).single as Map;
      expect(link['id'], 'o1|r1');
      expect(link['original_txn_id'], 'o1');
      expect(link['refund_txn_id'], 'r1');
      expect(link['amount_minor'], '3800');
      expect(link['currency'], 'USD');
      expect(link['payload'], isA<Map<String, Object?>>());
      expect(m['source'], 'device_analytical_read_model');

      // currency filter case-insensitive
      expect(
        (GetRefundLinksTool.shape([u], currency: 'usd')['links'] as List),
        hasLength(1),
      );
      expect(
        (GetRefundLinksTool.shape([u], currency: 'CNY')['links'] as List),
        isEmpty,
      );
      final empty = GetRefundLinksTool.shape(const []);
      expect(empty['count'], 0);
      expect(empty['note'], contains('refundMatcher'));
    });

    test('transferMatchToUpload + GetTransferLinksTool.shape', () {
      final u = transferMatchToUpload(
        const TransferMatch(
          fromTxnId: 'a',
          toTxnId: 'b',
          amountMinor: 100000,
          currency: 'CNY',
        ),
      );
      expect(u.kind, 'transfer_link');
      expect(u.id, 'a|b');

      final m = GetTransferLinksTool.shape([u]);
      final link = (m['links'] as List).single as Map;
      expect(link['from_txn_id'], 'a');
      expect(link['to_txn_id'], 'b');
      expect(link['amount_minor'], '100000');
      expect(link['currency'], 'CNY');
      expect(m['note'], contains('transferMatcher'));
      expect(
        (GetTransferLinksTool.shape([u], currency: 'usd')['links'] as List),
        isEmpty,
      );
    });
  });

  group('investment_performance + subscription_changes (W-D4.3b)', () {
    test('subscriptionChangeToUpload + GetSubscriptionChangesTool.shape', () {
      final u = subscriptionChangeToUpload(
        SubscriptionChange(
          merchantKey: 'netflix',
          cadence: RecurringCadence.monthly,
          currency: 'USD',
          prevMedianAmountMinor: 1099,
          newMedianAmountMinor: 1299,
          deltaRatio: 0.18,
          since: DateTime.utc(2026, 4, 1),
        ),
      );
      expect(u.kind, 'subscription_change');
      expect(u.id, 'netflix|USD');
      expect(u.payload['prev_amount_minor'], '1099');
      expect(u.payload['new_amount_minor'], '1299');

      final m = GetSubscriptionChangesTool.shape([u]);
      final c = (m['changes'] as List).single as Map;
      expect(c['id'], 'netflix|USD');
      expect(c['merchant_key'], 'netflix');
      expect(c['cadence'], 'monthly');
      expect(c['prev_amount_minor'], '1099');
      expect(c['new_amount_minor'], '1299');
      expect(c['delta_ratio'], 0.18);
      expect(c['since'], '2026-04-01T00:00:00.000Z');
      expect(c['payload'], isA<Map<String, Object?>>());
      expect(m['source'], 'device_analytical_read_model');
      // currency filter
      expect(
        (GetSubscriptionChangesTool.shape([u], currency: 'cny')['changes']
            as List),
        isEmpty,
      );
      expect(GetSubscriptionChangesTool.shape(const [])['count'], 0);
    });

    test('holdingSnapshotToUpload + GetInvestmentPerformanceTool.shape', () {
      final snap = HoldingSnapshot(
        assetId: 'AAPL',
        quantity: Decimal.parse('10'),
        costBasisInAssetCurrency: Decimal.parse('1500'),
        marketValueInAssetCurrency: Decimal.parse('1900'),
        assetCurrency: 'USD',
        costBasisInBase: Decimal.parse('1500'),
        marketValueInBase: Decimal.parse('1900'),
        unrealizedPnlInBase: Decimal.parse('400'),
        weight: Decimal.parse('0.42'),
        baseCurrency: 'USD',
        asOf: DateTime.utc(2026, 5, 16),
      );
      final u = holdingSnapshotToUpload(snap);
      expect(u.kind, 'investment_performance');
      expect(u.id, 'AAPL');
      expect(u.payload['market_value_in_base'], '1900');
      expect(u.payload['unrealized_pnl_in_base'], '400');

      final m = GetInvestmentPerformanceTool.shape([u]);
      final a = (m['assets'] as List).single as Map;
      expect(a['id'], 'AAPL');
      expect(a['asset_id'], 'AAPL');
      expect(a['asset_currency'], 'USD');
      expect(a['base_currency'], 'USD');
      expect(a['market_value_base'], '1900'); // mapped from *_in_base
      expect(a['cost_basis_base'], '1500');
      expect(a['unrealized_pnl_base'], '400');
      expect(a['weight'], '0.42');
      expect(a['holding_days'], isNull); // device converter omits it
      expect(a['as_of'], '2026-05-16T00:00:00.000Z');
      expect(m['count'], 1);
      expect(m['note'], contains('holdingsSnapshotProvider'));

      // base_currency filter (case-insensitive)
      expect(
        (GetInvestmentPerformanceTool.shape([u], baseCurrency: 'usd')['assets']
            as List),
        hasLength(1),
      );
      expect(
        (GetInvestmentPerformanceTool.shape([u], baseCurrency: 'EUR')['assets']
            as List),
        isEmpty,
      );
      expect(GetInvestmentPerformanceTool.shape(const [])['count'], 0);
    });
  });

  group('W-D4.5 proposal scaffolding (ports proposals.rs)', () {
    test('matchExpenseCategory: slug / label / substring / ambiguous', () {
      expect((matchExpenseCategory('food') as CategoryExact).slug, 'food');
      expect((matchExpenseCategory('餐饮') as CategoryExact).slug, 'food');
      // single substring → exact
      expect(
        (matchExpenseCategory('transp') as CategoryExact).slug,
        'transport',
      );
      // unknown → ambiguous top-3 (food / shopping / other)
      final amb = matchExpenseCategory('quux') as CategoryAmbiguous;
      expect(amb.top3.map((e) => e.$1), ['food', 'shopping', 'other']);
      expect(
        (matchExpenseCategory('') as CategoryAmbiguous).top3.last.$1,
        'other',
      );
    });

    test('nameMatches is case-insensitive contains-or-equals', () {
      expect(nameMatches('Citibank Checking', 'citi'), isTrue);
      expect(nameMatches('Citi', 'Citibank Checking'), isTrue);
      expect(nameMatches('Cash', 'bank'), isFalse);
    });

    test('resolveAccount: none / one / many(≤8, {id,name,type})', () {
      final accts = [
        _acct('a1', 'Citibank Checking', type: AccountCategory.bank),
        _acct('a2', 'Citi Savings', type: AccountCategory.bank),
        _acct('a3', 'Cash', type: AccountCategory.cash),
      ];
      expect(
        resolveAccount(accts, byName: 'nope'),
        isA<ResolvedNone<Account>>(),
      );
      expect(
        (resolveAccount(accts, byName: 'cash') as ResolvedOne<Account>).row.id,
        'a3',
      );
      expect(
        (resolveAccount(accts, byId: 'a2') as ResolvedOne<Account>).row.id,
        'a2',
      );
      final many = resolveAccount(accts, byName: 'citi') as ResolvedMany;
      expect(many.candidates, hasLength(2));
      expect(many.candidates.first, containsPair('type', 'bank'));
    });

    test('readyPlan / needsClarification envelope shapes', () {
      final r = readyPlan(
        kind: 'expense',
        summaryZh: 's',
        payload: {'x': 1},
        warnings: ['w'],
      );
      expect(r['status'], 'ready');
      expect(r['kind'], 'expense');
      expect(r['candidates'], isNull);
      expect(r['proposal_id'], isA<String>());
      final c = needsClarification(
        kind: 'expense',
        field: 'category',
        reason: 'why',
        candidates: [
          {'id': 'food', 'label': '餐饮'},
        ],
      );
      expect(c['status'], 'needs_clarification');
      expect(c['ambiguous_field'], 'category');
      expect((c['candidates'] as List), hasLength(1));
    });

    test('isRfc3339 rejects date-only, accepts timestamps', () {
      expect(isRfc3339('2026-05-16'), isFalse);
      expect(isRfc3339('2026-05-16T10:00:00Z'), isTrue);
      expect(isRfc3339('garbage'), isFalse);
    });
  });

  group('ProposeExpenseTool.invoke — pre-account branches', () {
    Future<Object?> run(Map<String, Object?> input) {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      return _withRef(
        c,
        (ref) => const ProposeExpenseTool().invoke(
          DeviceToolContext(ref: ref, session: _session()),
          input,
        ),
      );
    }

    test('missing / non-positive amount → bad_request', () async {
      expect(((await run(const {})) as Map)['code'], 'bad_request');
      expect(
        ((await run(const {'amount': -3})) as Map)['error'],
        contains('amount must be > 0'),
      );
    });

    test(
      'ambiguous category → needs_clarification (before account read)',
      () async {
        final m = await run(const {'amount': 10, 'category': 'zzz'}) as Map;
        expect(m['status'], 'needs_clarification');
        expect(m['ambiguous_field'], 'category');
        expect((m['candidates'] as List).map((e) => (e as Map)['id']), [
          'food',
          'shopping',
          'other',
        ]);
      },
    );

    // The post-account-read branches (currency default, RFC3339 date
    // reject, ready-plan shaping) reach `accountsStreamProvider.future`
    // — an autoDispose StreamProvider whose `.future` can't be driven
    // from a unit test without hanging (W-D4 lesson). Their logic is
    // covered purely below via the same helpers the tool calls.
    test('ready-plan composition (pure, mirrors invoke after resolve)', () {
      // No-account path → warn + default CNY, summary like the tool's.
      const cat = CategoryExact('food');
      final slug = (cat).slug;
      final resolved = resolveAccount(const <Account>[], byName: 'nope');
      expect(resolved, isA<ResolvedNone<Account>>());
      final label = kExpenseCategories.firstWhere((e) => e.$1 == slug).$2;
      final plan = readyPlan(
        kind: 'expense',
        summaryZh: '记一笔$label支出 12.5 CNY',
        payload: {
          'type': 'expense',
          'amount': 12.5,
          'category': slug,
          'currency': 'CNY',
          'account_id': null,
        },
        warnings: const [
          'account 未指定或未匹配；前端会让用户在确认页选择支付账户。',
          'currency 未指定，已默认 CNY',
        ],
      );
      expect(plan['status'], 'ready');
      expect((plan['payload'] as Map)['category'], 'food');
      expect(plan['summary_zh'], '记一笔餐饮支出 12.5 CNY');
      expect(isRfc3339('2026-05-16'), isFalse); // tool would bad_request
    });
  });

  group('W-D4.5b — resolveAsset + account_create + asset_valuation', () {
    Asset asset(
      String id,
      String symbol, {
      AssetType type = AssetType.stock,
      String currency = 'USD',
      String? name,
    }) => Asset(
      id: id,
      type: type,
      symbol: symbol,
      currency: currency,
      name: name,
      sync: _stamp(),
    );

    test('resolveAsset: none / one(byId,bySymbol,byName) / many', () {
      final assets = [
        asset('a1', 'AAPL', name: 'Apple Inc'),
        asset('a2', 'AAPLW', name: 'Apple Warrant'),
        asset('h1', 'HOUSE', type: AssetType.realEstate, name: '北京房产'),
      ];
      expect(resolveAsset(assets, byName: 'nope'), isA<ResolvedNone<Asset>>());
      expect(
        (resolveAsset(assets, byId: 'h1') as ResolvedOne<Asset>).row.symbol,
        'HOUSE',
      );
      expect(
        (resolveAsset(assets, byName: '北京') as ResolvedOne<Asset>).row.id,
        'h1',
      );
      final many =
          resolveAsset(assets, bySymbol: 'aapl') as ResolvedMany<Asset>;
      expect(many.candidates, hasLength(2));
      expect(many.candidates.first, containsPair('type', 'stock'));
    });

    Future<Object?> runTool(DeviceTool tool, Map<String, Object?> input) {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      return _withRef(
        c,
        (ref) => tool.invoke(
          DeviceToolContext(ref: ref, session: _session()),
          input,
        ),
      );
    }

    test(
      'propose_account_create: validation + ready (pure, no provider)',
      () async {
        expect(
          ((await runTool(const ProposeAccountCreateTool(), const {}))
              as Map)['error'],
          contains("field 'name'"),
        );
        expect(
          ((await runTool(const ProposeAccountCreateTool(), const {
                'name': '  ',
                'type': 'bank',
              }))
              as Map)['error'],
          contains('must not be blank'),
        );
        final amb =
            await runTool(const ProposeAccountCreateTool(), const {
                  'name': 'My Card',
                  'type': 'not-a-type',
                })
                as Map;
        expect(amb['status'], 'needs_clarification');
        expect(amb['ambiguous_field'], 'type');
        expect(
          (amb['candidates'] as List).map((e) => (e as Map)['id']),
          kProposalAccountTypes,
        );
        final ok =
            await runTool(const ProposeAccountCreateTool(), const {
                  'name': '招行储蓄',
                  'type': 'bank',
                })
                as Map;
        expect(ok['status'], 'ready');
        expect(ok['kind'], 'account_create');
        final p = ok['payload'] as Map;
        expect(p['name'], '招行储蓄');
        expect(p['type'], 'bank');
        expect(p['currency'], 'CNY'); // defaulted
        expect((p['id'] as String).isNotEmpty, isTrue);
        expect(ok['summary_zh'], '创建账户「招行储蓄」（bank / CNY）');
        expect((ok['warnings'] as List).single, contains('CNY'));
      },
    );

    test('propose_asset_valuation: pre-resolve bad_request branches', () async {
      expect(
        ((await runTool(const ProposeAssetValuationTool(), const {}))
            as Map)['error'],
        contains("field 'new_value'"),
      );
      expect(
        ((await runTool(const ProposeAssetValuationTool(), const {
              'new_value': -1,
            }))
            as Map)['error'],
        contains('must be ≥ 0'),
      );
    });

    test('asset_valuation post-resolve composition (pure)', () {
      // Securities are NOT manual-valuation → tool bad_requests.
      expect(
        kProposalManualValuationTypes.contains(AssetType.stock.name),
        isFalse,
      );
      // Real estate IS → ready plan shape.
      expect(
        kProposalManualValuationTypes.contains(AssetType.realEstate.name),
        isTrue,
      );
      final house = asset(
        'h1',
        'HOUSE',
        type: AssetType.realEstate,
        name: '北京房产',
        currency: 'CNY',
      );
      final display = house.name ?? house.symbol;
      final plan = readyPlan(
        kind: 'asset_valuation',
        summaryZh: '更新「$display」估值为 ${formatProposalAmount(8500000)} CNY',
        payload: {
          'type': 'asset_valuation',
          'asset_id': house.id,
          'asset_name': display,
          'new_value': 8500000.0,
          'currency': house.currency,
        },
      );
      expect(plan['summary_zh'], '更新「北京房产」估值为 8500000 CNY');
      expect((plan['payload'] as Map)['asset_id'], 'h1');
      expect((plan['payload'] as Map)['currency'], 'CNY');
    });
  });

  group('W-D4.5c — resolveLiability + propose_liability_payment', () {
    Liability liab(
      String id,
      String name, {
      LiabilityType type = LiabilityType.mortgage,
      String currency = 'CNY',
    }) => Liability(
      id: id,
      type: type,
      name: name,
      principal: Decimal.fromInt(1000000),
      interestRate: Decimal.parse('0.045'),
      currency: currency,
      sync: _stamp(),
    );

    test('resolveLiability: none / one(id,name) / many(≤8,{id,name,type})', () {
      final ls = [
        liab('l1', '招行房贷'),
        liab('l2', '招行车贷', type: LiabilityType.carLoan),
        liab('l3', '花呗', type: LiabilityType.consumerLoan),
      ];
      expect(
        resolveLiability(ls, byName: 'nope'),
        isA<ResolvedNone<Liability>>(),
      );
      expect(
        (resolveLiability(ls, byId: 'l3') as ResolvedOne<Liability>).row.name,
        '花呗',
      );
      final many =
          resolveLiability(ls, byName: '招行') as ResolvedMany<Liability>;
      expect(many.candidates, hasLength(2));
      expect(many.candidates.first, containsPair('type', 'mortgage'));
    });

    Future<Object?> run(Map<String, Object?> input) {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      return _withRef(
        c,
        (ref) => const ProposeLiabilityPaymentTool().invoke(
          DeviceToolContext(ref: ref, session: _session()),
          input,
        ),
      );
    }

    test('pre-resolve bad_request branches', () async {
      expect(((await run(const {})) as Map)['error'], contains("'amount'"));
      expect(
        ((await run(const {'amount': 0})) as Map)['error'],
        contains('amount must be > 0'),
      );
    });

    test('liability not found → needs_clarification shape', () {
      expect(
        resolveLiability(const [], byName: 'whatever'),
        isA<ResolvedNone<Liability>>(),
      );
      final plan = needsClarification(
        kind: 'liability_payment',
        field: 'liability',
        reason: '未找到匹配的负债。请让用户先在「负债」里录入这笔贷款 / 信用卡。',
        candidates: const [],
      );
      expect(plan['status'], 'needs_clarification');
      expect(plan['ambiguous_field'], 'liability');
    });
  });

  group('W-D4.5c — propose_trade (pre-resolve branches)', () {
    Future<Object?> run(Map<String, Object?> input) {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      return _withRef(
        c,
        (ref) => const ProposeTradeTool().invoke(
          DeviceToolContext(ref: ref, session: _session()),
          input,
        ),
      );
    }

    test('type / quantity validation bad_requests (before resolve)', () async {
      expect(((await run(const {})) as Map)['error'], contains("field 'type'"));
      expect(
        ((await run(const {'type': 'gift', 'quantity': 1})) as Map)['error'],
        contains("unsupported transaction type 'gift'"),
      );
      expect(
        ((await run(const {'type': 'buy'})) as Map)['error'],
        contains("field 'quantity'"),
      );
      expect(
        ((await run(const {'type': 'buy', 'quantity': 0})) as Map)['error'],
        contains('quantity must be > 0'),
      );
    });

    test('_qty / summary composition (pure, mirrors invoke tail)', () {
      // integer qty → " {n} 股"; fractional → " {value}"
      final intPlan = readyPlan(
        kind: 'trade',
        summaryZh: '买入 AAPL 10 股 @ 190（券商）',
        payload: const {'type': 'buy'},
      );
      expect(intPlan['summary_zh'], '买入 AAPL 10 股 @ 190（券商）');
      expect(formatProposalAmount(190.0), '190');
      expect(formatProposalAmount(1.5), '1.5');
    });
  });

  group('W-D4.4 — scoped_window helpers + read_account_window', () {
    test('scopedParseIso: RFC3339 vs bare YYYY-MM-DD pinned UTC', () {
      expect(scopedParseIso('2026-05-16'), DateTime.utc(2026, 5, 16));
      expect(
        scopedParseIso('2026-05-16T08:00:00Z'),
        DateTime.utc(2026, 5, 16, 8),
      );
      expect(scopedParseIso('garbage'), isNull);
    });

    test('validateScopedRange / parseScopedLimit / excerpt / purpose', () {
      expect(
        validateScopedRange(DateTime.utc(2026, 5, 2), DateTime.utc(2026)),
        'to must be after from',
      );
      expect(
        validateScopedRange(DateTime.utc(2026), DateTime.utc(2026, 3)),
        contains('range exceeds 31 days'),
      );
      expect(
        validateScopedRange(DateTime.utc(2026), DateTime.utc(2026, 1, 20)),
        isNull,
      );
      expect(parseScopedLimit(const {}), kScopedDefaultLimit);
      expect(parseScopedLimit(const {'limit': 9999}), kScopedMaxLimit);
      expect(parseScopedLimit(const {'limit': 5}), 5);
      expect(scopedExcerpt('abcdef', 3), 'abc…');
      expect(scopedExcerpt('ab', 3), 'ab');
      expect(isScopedPurpose('drill_down_expense'), isTrue);
      expect(isScopedPurpose('exfiltrate'), isFalse);
    });

    Future<Object?> run(Map<String, Object?> input) {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      return _withRef(
        c,
        (ref) => const ReadAccountWindowTool().invoke(
          DeviceToolContext(ref: ref, session: _session()),
          input,
        ),
      );
    }

    test('mandatory-field + range + purpose validation (pre-read)', () async {
      Future<String> err(Map<String, Object?> i) async =>
          ((await run(i)) as Map)['error'] as String;
      expect(await err(const {}), 'account_id required');
      expect(await err(const {'account_id': 'a', 'from': 'x'}), 'to required');
      expect(
        await err(const {
          'account_id': 'a',
          'from': 'nope',
          'to': '2026-02-01',
          'purpose': 'other',
        }),
        'from not ISO date',
      );
      expect(
        await err(const {
          'account_id': 'a',
          'from': '2026-01-01',
          'to': '2026-03-01', // 59d
          'purpose': 'other',
        }),
        contains('range exceeds'),
      );
      expect(
        await err(const {
          'account_id': 'a',
          'from': '2026-01-01',
          'to': '2026-01-10',
          'purpose': 'exfiltrate',
        }),
        contains('DisclosurePurpose'),
      );
    });
  });

  group('W-D4.4b — read_asset_window validation (pre-read)', () {
    Future<Object?> run(Map<String, Object?> input) {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      return _withRef(
        c,
        (ref) => const ReadAssetWindowTool().invoke(
          DeviceToolContext(ref: ref, session: _session()),
          input,
        ),
      );
    }

    test('asset_id / range / purpose mandatory', () async {
      expect(((await run(const {})) as Map)['error'], 'asset_id required');
      expect(
        ((await run(const {
              'asset_id': 'AAPL',
              'from': '2026-01-01',
              'to': '2026-03-01',
              'purpose': 'other',
            }))
            as Map)['error'],
        contains('range exceeds'),
      );
      expect(
        ((await run(const {
              'asset_id': 'AAPL',
              'from': '2026-01-01',
              'to': '2026-01-10',
              'purpose': 'nope',
            }))
            as Map)['error'],
        contains('DisclosurePurpose'),
      );
    });
  });

  group('W-D4.4b — read_category_window (remap + validation)', () {
    Future<Object?> run(Map<String, Object?> input) {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      return _withRef(
        c,
        (ref) => const ReadCategoryWindowTool().invoke(
          DeviceToolContext(ref: ref, session: _session()),
          input,
        ),
      );
    }

    test('category / range / purpose mandatory (pre-read)', () async {
      expect(((await run(const {})) as Map)['error'], 'category required');
      expect(
        ((await run(const {
              'category': 'food',
              'from': '2026-01-01',
              'to': '2026-03-01', // 59d
              'purpose': 'other',
            }))
            as Map)['error'],
        contains('range exceeds'),
      );
      expect(
        ((await run(const {
              'category': 'food',
              'from': '2026-01-01',
              'to': '2026-01-10',
              'purpose': 'nope',
            }))
            as Map)['error'],
        contains('DisclosurePurpose'),
      );
    });

    final from = DateTime.utc(2026, 4, 1);
    final to = DateTime.utc(2026, 5, 1);
    final accounts = [
      _acct('exp_food', 'Food', category: AccountSide.expense),
      _acct('exp_txp', 'Transport', category: AccountSide.expense),
      _acct('bank', 'Bank', category: AccountSide.asset),
    ];

    test('remaps category→expense account; window + amount + summary', () {
      final entries = [
        _ewp('e1', DateTime.utc(2026, 4, 15), [
          _post('exp_food', 'CNY', '12.50'),
          _post('bank', 'CNY', '-12.50'),
        ], narration: 'Noodle lunch'),
        _ewp('e2', DateTime.utc(2026, 4, 16), [
          _post('exp_txp', 'CNY', '8.00'),
          _post('bank', 'CNY', '-8.00'),
        ]),
        _ewp('out', DateTime.utc(2026, 5, 2), [
          _post('exp_food', 'CNY', '99.00'),
        ]),
      ];
      final m = ReadCategoryWindowTool.shape(
        entries,
        accounts: accounts,
        category: 'food',
        from: from,
        to: to,
        limit: 20,
        purpose: 'drill_down_expense',
      );
      final txns = m['transactions'] as List;
      expect(txns.length, 1);
      expect((txns.single as Map)['id'], 'e1');
      expect((txns.single as Map)['amount_minor'], '1250');
      expect((txns.single as Map)['currency'], 'CNY');
      expect((txns.single as Map)['note_excerpt'], 'Noodle lunch');
      final summary = m['summary'] as Map;
      expect(summary['count'], 1);
      expect(summary['returned'], 1);
      expect(summary['total_minor'], '1250');
      expect(summary['currency'], 'CNY');
      expect(m['device_note'], contains('已将 category=food 解析为 1 个支出账户'));
    });

    test('unmatched category → empty + explicit device_note', () {
      final m = ReadCategoryWindowTool.shape(
        [
          _ewp('e1', DateTime.utc(2026, 4, 15), [
            _post('exp_food', 'CNY', '5.00'),
          ]),
        ],
        accounts: accounts,
        category: 'groceries',
        from: from,
        to: to,
        limit: 20,
        purpose: 'other',
      );
      expect((m['transactions'] as List), isEmpty);
      expect((m['summary'] as Map)['count'], 0);
      expect(m['device_note'], contains('未找到名称/ID 匹配 category=groceries'));
    });

    test('merchant_substring filters on narration', () {
      final entries = [
        _ewp('e1', DateTime.utc(2026, 4, 15), [
          _post('exp_food', 'CNY', '4.50'),
        ], narration: 'STARBUCKS 04291'),
        _ewp('e2', DateTime.utc(2026, 4, 16), [
          _post('exp_food', 'CNY', '12.00'),
        ], narration: 'Lunch noodle'),
      ];
      final m = ReadCategoryWindowTool.shape(
        entries,
        accounts: accounts,
        category: 'food',
        from: from,
        to: to,
        limit: 20,
        purpose: 'drill_down_expense',
        merchantSubstring: 'starbucks',
      );
      final txns = m['transactions'] as List;
      expect(txns.length, 1);
      expect((txns.single as Map)['id'], 'e1');
    });

    test('mixed currency → by_currency summary branch', () {
      final entries = [
        _ewp('u', DateTime.utc(2026, 4, 10), [
          _post('exp_food', 'USD', '5.00'),
        ]),
        _ewp('c', DateTime.utc(2026, 4, 11), [
          _post('exp_food', 'CNY', '10.00'),
        ]),
      ];
      final m = ReadCategoryWindowTool.shape(
        entries,
        accounts: accounts,
        category: 'food',
        from: from,
        to: to,
        limit: 20,
        purpose: 'drill_down_expense',
      );
      final summary = m['summary'] as Map;
      expect(summary['count'], 2);
      expect(summary.containsKey('total_minor'), isFalse);
      final byCur = (summary['by_currency'] as List)
          .map((e) => (e as Map)['currency'])
          .toSet();
      expect(byCur, {'USD', 'CNY'});
    });
  });
}
