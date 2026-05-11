import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/ai/contracts/contracts.dart';

void main() {
  group('ContextPack roundtrip', () {
    test('fully populated pack round-trips through JSON', () {
      final pack = _samplePack();
      final encoded = jsonEncode(pack.toJson());
      final decoded = ContextPack.fromJson(
        jsonDecode(encoded) as Map<String, Object?>,
      );

      expect(decoded.version.major, pack.version.major);
      expect(decoded.version.minor, pack.version.minor);
      expect(decoded.budget.tier, pack.budget.tier);

      expect(decoded.base.preferredCurrency, pack.base.preferredCurrency);
      expect(decoded.base.riskPreference, pack.base.riskPreference);
      expect(decoded.base.accounts.totalCount, pack.base.accounts.totalCount);
      expect(decoded.base.accounts.byKind, pack.base.accounts.byKind);
      expect(decoded.base.cashflow.trend, pack.base.cashflow.trend);
      expect(
        decoded.base.cashflow.averageOutflowMinor,
        pack.base.cashflow.averageOutflowMinor,
      );
      expect(decoded.base.fireGoal?.currency, pack.base.fireGoal?.currency);
      expect(
        decoded.base.fireGoal?.progressFraction,
        pack.base.fireGoal?.progressFraction,
      );

      expect(decoded.task.route.area, pack.task.route.area);
      expect(decoded.task.intent.capability, pack.task.intent.capability);
      expect(decoded.task.intent.risk, pack.task.intent.risk);
      expect(decoded.task.intent.label, pack.task.intent.label);
      expect(decoded.task.signals, hasLength(pack.task.signals.length));
      expect(decoded.task.signals.first.kind, pack.task.signals.first.kind);
      expect(
        decoded.task.aggregates.first.amountMinor,
        pack.task.aggregates.first.amountMinor,
      );
    });

    test('snake_case wire keys are stable', () {
      final json = _samplePack().toJson();
      // Spot-check that we never accidentally emit camelCase. The Rust
      // mirror uses serde rename_all = "snake_case" — drift between
      // sides shows up as wire incompatibility, so this is the cheapest
      // canary.
      expect(json.containsKey('version'), isTrue);
      expect(json.containsKey('base'), isTrue);
      final base = json['base']! as Map<String, Object?>;
      expect(base.containsKey('preferred_currency'), isTrue);
      expect(base.containsKey('risk_preference'), isTrue);
      final cashflow = base['cashflow']! as Map<String, Object?>;
      expect(cashflow.containsKey('months_covered'), isTrue);
      expect(cashflow.containsKey('average_inflow_minor'), isTrue);
      expect(cashflow.containsKey('average_outflow_minor'), isTrue);
      final task = json['task']! as Map<String, Object?>;
      final intent = task['intent']! as Map<String, Object?>;
      expect(intent['capability'], 'analyze');
      expect(intent['risk'], 'suggest');
    });

    test('unknown enum values fall through to safe defaults', () {
      final raw = <String, Object?>{
        'version': <String, Object?>{'major': 1, 'minor': 0},
        'base': <String, Object?>{
          'preferred_currency': 'USD',
          'risk_preference': 'extreme', // not a real value
          'accounts': <String, Object?>{
            'total_count': 0,
            'by_kind': <String, Object?>{},
          },
          'cashflow': <String, Object?>{
            'base_currency': 'USD',
            'months_covered': 0,
            'average_inflow_minor': '0',
            'average_outflow_minor': '0',
            'trend': 'sideways', // not a real value
          },
        },
        'task': <String, Object?>{
          'route': <String, Object?>{'path': '/', 'area': 'unknown'},
          'intent': <String, Object?>{
            'capability': 'time_travel', // not a real value
            'risk': 'whatever',
          },
        },
        'budget': <String, Object?>{'tier': 'unbounded'},
      };
      final pack = ContextPack.fromJson(raw);
      expect(pack.base.riskPreference, RiskPreference.moderate);
      expect(pack.base.cashflow.trend, CashflowTrend.unknown);
      expect(pack.task.intent.capability, Capability.analyze);
      expect(pack.task.intent.risk, RiskLevel.info);
      expect(pack.budget.tier, BudgetTier.standard);
    });

    test('byte caps are 4KB / 16KB / 64KB', () {
      expect(BudgetTier.small.byteCap, 4 * 1024);
      expect(BudgetTier.standard.byteCap, 16 * 1024);
      expect(BudgetTier.large.byteCap, 64 * 1024);
    });

    test('assertBudget passes when within cap', () {
      final pack = _samplePack();
      // Sample pack is ~1KB — well within standard's 16KB cap.
      expect(pack.serializedByteSize, lessThan(BudgetTier.standard.byteCap));
      expect(() => pack.assertBudget(), returnsNormally);
    });

    test('assertBudget throws when oversize for tier', () {
      // Force oversize by stuffing many signals into a small-tier pack.
      final fatTask = TaskContext(
        route: const RouteContext(path: '/expense', area: 'expense'),
        intent: const IntentHint(
          capability: Capability.analyze,
          risk: RiskLevel.info,
        ),
        signals: List<RecentSignal>.generate(
          200,
          (i) => RecentSignal(
            kind: SignalKind.spendingSpike,
            severity: SignalSeverity.warn,
            summaryZh: '触发了一条相当长的提示文案以撑大序列化体积 #$i',
          ),
          growable: false,
        ),
      );
      final pack = ContextPack(
        version: kCurrentContextPackVersion,
        base: _sampleBase(),
        task: fatTask,
        budget: PrivacyBudget.small,
      );
      expect(
        () => pack.assertBudget(),
        throwsA(isA<ContextPackOversizeException>()),
      );
    });
  });

  group('DisclosureRequest / Response roundtrip', () {
    test('request round-trips with all fields', () {
      const req = DisclosureRequest(
        requestId: 'req_42',
        purpose: DisclosurePurpose.drillDownExpense,
        fields: <LedgerField>[
          LedgerField.amount,
          LedgerField.date,
          LedgerField.category,
          LedgerField.merchantHashed,
        ],
        range: DateRange(
          fromInclusive: '2026-04-01',
          toExclusive: '2026-05-01',
        ),
        maxRows: 50,
        anonymization: AnonymizationLevel.hash,
        humanReasonZh: '查看 4 月餐饮支出明细以解释支出上升',
      );
      final encoded = jsonEncode(req.toJson());
      final decoded = DisclosureRequest.fromJson(
        jsonDecode(encoded) as Map<String, Object?>,
      );
      expect(decoded.requestId, req.requestId);
      expect(decoded.purpose, req.purpose);
      expect(decoded.fields, req.fields);
      expect(decoded.range.fromInclusive, req.range.fromInclusive);
      expect(decoded.maxRows, req.maxRows);
      expect(decoded.anonymization, req.anonymization);
      expect(decoded.humanReasonZh, req.humanReasonZh);
    });

    test('unknown LedgerField wire values are dropped, not parsed as default', () {
      final raw = <String, Object?>{
        'request_id': 'req_1',
        'purpose': 'drill_down_expense',
        'fields': <Object?>['amount', 'ssn', 'iban', 'category'],
        'range': <String, Object?>{
          'from_inclusive': '2026-04-01',
          'to_exclusive': '2026-05-01',
        },
        'max_rows': 10,
        'anonymization': 'hash',
        'human_reason_zh': '',
      };
      final req = DisclosureRequest.fromJson(raw);
      expect(req.fields, <LedgerField>[
        LedgerField.amount,
        LedgerField.category,
      ]);
    });

    test('response with rows round-trips', () {
      const resp = DisclosureResponse(
        requestId: 'req_42',
        consent: UserConsent.session,
        rows: <Map<String, Object?>>[
          <String, Object?>{
            'amount': '4500',
            'currency': 'USD',
            'date': '2026-04-15',
            'category': 'food',
          },
          <String, Object?>{
            'amount': '900',
            'currency': 'USD',
            'date': '2026-04-16',
            'category': 'food',
          },
        ],
        truncatedFrom: 87,
      );
      final encoded = jsonEncode(resp.toJson());
      final decoded = DisclosureResponse.fromJson(
        jsonDecode(encoded) as Map<String, Object?>,
      );
      expect(decoded.requestId, resp.requestId);
      expect(decoded.consent, resp.consent);
      expect(decoded.rows.length, 2);
      expect(decoded.rows[0]['amount'], '4500');
      expect(decoded.truncatedFrom, 87);
    });
  });

  group('ToolDescriptor roundtrip', () {
    test('descriptor round-trips with all axes', () {
      const desc = ToolDescriptor(
        name: 'request_disclosure',
        access: Access.read,
        risk: RiskLevel.info,
        requiresConfirmation: Confirmation.oneTap,
        allowedContextTier: BudgetTier.standard,
      );
      final decoded = ToolDescriptor.fromJson(
        jsonDecode(jsonEncode(desc.toJson())) as Map<String, Object?>,
      );
      expect(decoded.name, desc.name);
      expect(decoded.access, desc.access);
      expect(decoded.risk, desc.risk);
      expect(decoded.requiresConfirmation, desc.requiresConfirmation);
      expect(decoded.allowedContextTier, desc.allowedContextTier);
    });
  });

  group('AiTrace roundtrip', () {
    test('trace with disclosures + tool calls round-trips', () {
      const trace = AiTrace(
        requestId: 'trace_1',
        startedAtIso: '2026-05-10T10:30:00Z',
        intent: IntentHint(
          capability: Capability.analyze,
          risk: RiskLevel.suggest,
          label: 'cashflow_explain',
        ),
        backend: Backend.hybrid,
        budgetTier: BudgetTier.standard,
        routingReason: 'capability_analyze_online',
        usedCloud: true,
        usedRawLedger: true,
        totalDurationMs: 3450,
        disclosures: <DisclosureSummary>[
          DisclosureSummary(
            purpose: DisclosurePurpose.anomalyExplain,
            fieldsCount: 4,
            rowCount: 23,
            consent: UserConsent.session,
          ),
        ],
        toolCalls: <TraceToolCall>[
          TraceToolCall(name: 'query_plan', durationMs: 12, ok: true),
          TraceToolCall(
            name: 'request_disclosure',
            durationMs: 180,
            ok: true,
          ),
        ],
      );
      final decoded = AiTrace.fromJson(
        jsonDecode(jsonEncode(trace.toJson())) as Map<String, Object?>,
      );
      expect(decoded.requestId, trace.requestId);
      expect(decoded.intent.label, trace.intent.label);
      expect(decoded.backend, Backend.hybrid);
      expect(decoded.usedRawLedger, isTrue);
      expect(decoded.disclosures, hasLength(1));
      expect(decoded.disclosures.first.purpose, DisclosurePurpose.anomalyExplain);
      expect(decoded.toolCalls, hasLength(2));
      expect(decoded.toolCalls.last.name, 'request_disclosure');
    });
  });

  group('ContextPack version', () {
    test('current version is 1.0', () {
      expect(kCurrentContextPackVersion.major, 1);
      expect(kCurrentContextPackVersion.minor, 0);
    });
  });

  group('FreshnessHint (Wave 6)', () {
    test('round-trips force_refresh_read_models list', () {
      const h = FreshnessHint(
        forceRefreshReadModels: <String>[
          'monthly_spend_by_category',
          'holdings_snapshot',
        ],
      );
      final decoded = FreshnessHint.fromJson(
        jsonDecode(jsonEncode(h.toJson())) as Map<String, Object?>,
      );
      expect(decoded.forceRefreshReadModels, h.forceRefreshReadModels);
    });

    test('TaskContext omits freshness_hint when empty', () {
      const task = TaskContext(
        route: RouteContext(path: '/', area: 'home'),
        intent: IntentHint(
          capability: Capability.analyze,
          risk: RiskLevel.info,
        ),
      );
      final json = task.toJson();
      expect(json.containsKey('freshness_hint'), isFalse);
    });

    test('TaskContext emits freshness_hint when non-empty', () {
      const task = TaskContext(
        route: RouteContext(path: '/', area: 'home'),
        intent: IntentHint(
          capability: Capability.analyze,
          risk: RiskLevel.info,
        ),
        freshnessHint: FreshnessHint(
          forceRefreshReadModels: <String>['monthly_spend_by_category'],
        ),
      );
      final json = task.toJson();
      expect(json.containsKey('freshness_hint'), isTrue);
      final decoded = TaskContext.fromJson(
        jsonDecode(jsonEncode(json)) as Map<String, Object?>,
      );
      expect(
        decoded.freshnessHint?.forceRefreshReadModels,
        <String>['monthly_spend_by_category'],
      );
    });
  });

  group('AnalyticalUpload + TaskContext.analytical_uploads (Wave 10/11)', () {
    test('round-trips a list of uploads with payload JSON shape', () {
      const uploads = <AnalyticalUpload>[
        AnalyticalUpload(
          kind: 'anomaly_flag',
          id: 'expense_monthly_spike|2026-05',
          payload: <String, Object?>{
            'category': 'all_expense',
            'kind': 'monthly_spike',
            'delta_pct': 42,
            'severity': 'warn',
          },
        ),
        AnalyticalUpload(
          kind: 'recurring_pattern',
          id: 'netflix|USD',
          payload: <String, Object?>{
            'merchant_key': 'netflix',
            'cadence': 'monthly',
            'median_amount_minor': '999',
            'currency': 'USD',
            'occurrences': 3,
          },
        ),
      ];
      const task = TaskContext(
        route: RouteContext(path: '/', area: 'home'),
        intent: IntentHint(
          capability: Capability.analyze,
          risk: RiskLevel.info,
        ),
        analyticalUploads: uploads,
        deviceHlc: '00000001700000000000.0001-device',
      );
      final decoded = TaskContext.fromJson(
        jsonDecode(jsonEncode(task.toJson())) as Map<String, Object?>,
      );
      expect(decoded.analyticalUploads, hasLength(2));
      expect(decoded.analyticalUploads[0].kind, 'anomaly_flag');
      expect(decoded.analyticalUploads[0].payload['delta_pct'], 42);
      expect(decoded.analyticalUploads[1].kind, 'recurring_pattern');
      expect(decoded.analyticalUploads[1].payload['occurrences'], 3);
      expect(decoded.deviceHlc, '00000001700000000000.0001-device');
    });

    test('empty uploads + null deviceHlc are omitted from wire', () {
      const task = TaskContext(
        route: RouteContext(path: '/', area: 'home'),
        intent: IntentHint(
          capability: Capability.analyze,
          risk: RiskLevel.info,
        ),
      );
      final json = task.toJson();
      expect(json.containsKey('analytical_uploads'), isFalse);
      expect(json.containsKey('device_hlc'), isFalse);
    });
  });

  group('AiTrace stale_read_model_names (Wave 6)', () {
    test('round-trips as a JSON list under stale_read_model_names key', () {
      const trace = AiTrace(
        requestId: 't',
        startedAtIso: '2026-05-12T10:00:00.000Z',
        intent: IntentHint(
          capability: Capability.analyze,
          risk: RiskLevel.info,
        ),
        backend: Backend.hybrid,
        budgetTier: BudgetTier.standard,
        routingReason: 'test',
        usedCloud: true,
        usedRawLedger: false,
        totalDurationMs: 100,
        staleReadModelNames: <String>{
          'monthly_spend_by_category',
          'holdings_snapshot',
        },
      );
      final json = trace.toJson();
      expect(json.containsKey('stale_read_model_names'), isTrue);
      final decoded = AiTrace.fromJson(
        jsonDecode(jsonEncode(json)) as Map<String, Object?>,
      );
      expect(
        decoded.staleReadModelNames,
        <String>{'monthly_spend_by_category', 'holdings_snapshot'},
      );
      expect(decoded.staleReadModels, 2);
    });

    test('omits stale_read_model_names key when set is empty', () {
      const trace = AiTrace(
        requestId: 't',
        startedAtIso: '2026-05-12T10:00:00.000Z',
        intent: IntentHint(
          capability: Capability.analyze,
          risk: RiskLevel.info,
        ),
        backend: Backend.device,
        budgetTier: BudgetTier.small,
        routingReason: 'test',
        usedCloud: false,
        usedRawLedger: false,
        totalDurationMs: 50,
      );
      final json = trace.toJson();
      expect(json.containsKey('stale_read_model_names'), isFalse);
      expect(trace.staleReadModels, 0);
    });
  });
}

ContextPack _samplePack() => ContextPack(
  version: kCurrentContextPackVersion,
  base: _sampleBase(),
  task: const TaskContext(
    route: RouteContext(path: '/expense', area: 'expense'),
    intent: IntentHint(
      capability: Capability.analyze,
      risk: RiskLevel.suggest,
      label: 'monthly_food_explain',
    ),
    signals: <RecentSignal>[
      RecentSignal(
        kind: SignalKind.spendingSpike,
        severity: SignalSeverity.warn,
        summaryZh: '本月餐饮支出环比 +37%',
        detailRef: 'anomaly:fr_2026_04',
      ),
    ],
    aggregates: <ScopedAggregate>[
      ScopedAggregate(
        label: 'monthly_food_spend',
        amountMinor: '128400',
        currency: 'USD',
        range: DateRange(
          fromInclusive: '2026-04-01',
          toExclusive: '2026-05-01',
        ),
        rowCount: 41,
      ),
    ],
  ),
  budget: PrivacyBudget.standard,
);

BaseContext _sampleBase() => const BaseContext(
  preferredCurrency: 'USD',
  riskPreference: RiskPreference.moderate,
  accounts: AccountSummary(
    totalCount: 9,
    byKind: <String, int>{
      'cash': 2,
      'deposit': 1,
      'security': 4,
      'crypto': 1,
      'liability': 1,
    },
  ),
  cashflow: CashflowSummary(
    baseCurrency: 'USD',
    monthsCovered: 6,
    averageInflowMinor: '850000',
    averageOutflowMinor: '420000',
    trend: CashflowTrend.improving,
  ),
  fireGoal: FireGoalSummary(
    targetMinor: '250000000',
    currency: 'USD',
    progressFraction: 0.32,
    yearsRemainingEstimate: 12.4,
  ),
);
