import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/app/agents/daily_navigator_agent.dart';
import 'package:naviwealth/app/agents/daily_navigator_synthesizer.dart';
import 'package:naviwealth/core/ai/agents/agent.dart';
import 'package:naviwealth/core/ai/agents/agent_artifact_store.dart';
import 'package:naviwealth/core/ai/agents/agent_finding_store.dart';
import 'package:naviwealth/core/ai/attention/attention_store.dart';
import 'package:naviwealth/core/ai/contracts/source_identity.dart';
import 'package:naviwealth/core/auth/domain_scope.dart';
import 'package:naviwealth/core/lifeos/life_context.dart';
import 'package:naviwealth/core/lifeos/life_signal.dart';
import 'package:naviwealth/core/lifeos/personal_profile/personal_profile_snapshot.dart';
import 'package:naviwealth/core/persistence/app_database.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

import '../../core/persistence/test_database.dart';

const _owner = 'daily-navigator-owner';
final _now = DateTime.utc(2026, 8, 23, 8);

class _CountingSynthesizer implements DailyNavigatorSynthesizer {
  int calls = 0;

  @override
  Future<DailyNavigatorOutput> synthesize({
    required LifeContextSnapshot context,
    required DailyNavigatorDecision decision,
    required AppLocalizations l10n,
  }) async {
    calls += 1;
    return const DailyNavigatorOutput(
      summary: 'Protect recovery; no financial reaction is needed.',
      recommendation: 'Review the recovery evidence.',
    );
  }
}

LifeEvent _signal({
  required String id,
  required DomainScope domain,
  required LifeEventTemplate template,
  LifeSignalPriority priority = LifeSignalPriority.high,
  bool withEvidence = true,
}) => LifeEvent(
  id: id,
  at: _now,
  domain: domain,
  template: template,
  params: switch (template) {
    LifeEventTemplate.financeBudgetPressure => const <String>[
      'over_budget',
      '2026-08',
    ],
    LifeEventTemplate.executionBlocked => const <String>['2'],
    LifeEventTemplate.recoveryAlert => const <String>['strained', '42'],
    _ => const <String>['1'],
  },
  routePath: '/${domain.wire}',
  priority: priority,
  evidence: withEvidence
      ? <SourceIdentity>[
          SourceIdentity(
            domain: domain,
            rowFamily: '${domain.wire}:fixture',
            rowId: id,
            fingerprint: '$id-v1',
          ),
        ]
      : const <SourceIdentity>[],
);

LifeContextSnapshot _context({
  required Set<DomainScope> activeDomains,
  required List<LifeContextDomainState> states,
}) => LifeContextSnapshot(
  ownerUserId: _owner,
  generatedAt: _now,
  profile: PersonalProfileSnapshot(asOf: _now, facts: const []),
  activeDomains: activeDomains,
  domainStates: states,
  recentChanges: const [],
  relevantHistory: const [],
);

LifeContextDomainState _state({
  required DomainScope domain,
  required LifeContextFreshness freshness,
  required List<LifeEvent> signals,
}) => LifeContextDomainState(
  domain: domain,
  freshness: freshness,
  evaluatedSourceFamilies: <String>{'${domain.wire}:fixture'},
  signals: signals,
  latestObservedAt: _now,
);

void main() {
  test(
    'stays silent before synthesis when no material signal exists',
    () async {
      final db = makeTestDatabase();
      addTearDown(db.close);
      final synthesizer = _CountingSynthesizer();
      final context = _context(
        activeDomains: const <DomainScope>{DomainScope.finance},
        states: <LifeContextDomainState>[
          _state(
            domain: DomainScope.finance,
            freshness: LifeContextFreshness.fresh,
            signals: <LifeEvent>[
              _signal(
                id: 'normal-finance',
                domain: DomainScope.finance,
                template: LifeEventTemplate.financeDaySummary,
                priority: LifeSignalPriority.normal,
              ),
            ],
          ),
        ],
      );

      final result = await _run(
        db: db,
        context: context,
        synthesizer: synthesizer,
      );

      expect(result.status, AgentRunStatus.skipped);
      expect(synthesizer.calls, 0);
    },
  );

  test('stale high-priority input never reaches synthesis', () async {
    final db = makeTestDatabase();
    addTearDown(db.close);
    final synthesizer = _CountingSynthesizer();
    final context = _context(
      activeDomains: const <DomainScope>{DomainScope.health},
      states: <LifeContextDomainState>[
        _state(
          domain: DomainScope.health,
          freshness: LifeContextFreshness.stale,
          signals: <LifeEvent>[
            _signal(
              id: 'stale-recovery',
              domain: DomainScope.health,
              template: LifeEventTemplate.recoveryAlert,
            ),
          ],
        ),
      ],
    );

    final result = await _run(
      db: db,
      context: context,
      synthesizer: synthesizer,
    );

    expect(result.status, AgentRunStatus.skipped);
    expect(synthesizer.calls, 0);
  });

  test('persists one routed, evidence-backed cross-domain artifact', () async {
    final db = makeTestDatabase();
    addTearDown(db.close);
    final synthesizer = _CountingSynthesizer();
    final context = _context(
      activeDomains: const <DomainScope>{
        DomainScope.finance,
        DomainScope.health,
        DomainScope.execution,
      },
      states: <LifeContextDomainState>[
        _state(
          domain: DomainScope.finance,
          freshness: LifeContextFreshness.fresh,
          signals: <LifeEvent>[
            _signal(
              id: 'budget',
              domain: DomainScope.finance,
              template: LifeEventTemplate.financeBudgetPressure,
            ),
          ],
        ),
        _state(
          domain: DomainScope.health,
          freshness: LifeContextFreshness.fresh,
          signals: <LifeEvent>[
            _signal(
              id: 'recovery',
              domain: DomainScope.health,
              template: LifeEventTemplate.recoveryAlert,
            ),
          ],
        ),
        _state(
          domain: DomainScope.execution,
          freshness: LifeContextFreshness.fresh,
          signals: <LifeEvent>[
            _signal(
              id: 'blocked',
              domain: DomainScope.execution,
              template: LifeEventTemplate.executionBlocked,
            ),
          ],
        ),
      ],
    );

    final result = await _run(
      db: db,
      context: context,
      synthesizer: synthesizer,
    );
    final artifact = await SqliteAgentArtifactStore(db: db)
        .read(result.artifactId!);

    expect(result.status, AgentRunStatus.completed);
    expect(synthesizer.calls, 1);
    expect(artifact, isNotNull);
    expect(artifact!.insights, hasLength(3));
    expect(artifact.evidence, hasLength(3));
    expect(artifact.evidence.every((item) => item.route != null), isTrue);
    expect(artifact.actions, hasLength(1));
    expect(
      artifact.actions.single.payload,
      containsPair('life_context_fingerprint', context.fingerprint),
    );
    expect(
      artifact.actions.single.payload['attention_decision_id'],
      isNotEmpty,
    );
    expect(artifact.memoryId, isNull);
  });

  test('unchanged finding suppresses repeated synthesis', () async {
    final db = makeTestDatabase();
    addTearDown(db.close);
    final synthesizer = _CountingSynthesizer();
    final context = _context(
      activeDomains: const <DomainScope>{DomainScope.health},
      states: <LifeContextDomainState>[
        _state(
          domain: DomainScope.health,
          freshness: LifeContextFreshness.fresh,
          signals: <LifeEvent>[
            _signal(
              id: 'recovery',
              domain: DomainScope.health,
              template: LifeEventTemplate.recoveryAlert,
            ),
          ],
        ),
      ],
    );

    final first = await _run(
      db: db,
      context: context,
      synthesizer: synthesizer,
    );
    final second = await _run(
      db: db,
      context: context,
      synthesizer: synthesizer,
      finishedAt: _now.add(const Duration(minutes: 5)),
    );

    expect(first.status, AgentRunStatus.completed);
    expect(second.status, AgentRunStatus.skipped);
    expect(synthesizer.calls, 1);
  });

  test('inactive-domain signal is excluded by the deterministic gate', () {
    final context = _context(
      activeDomains: const <DomainScope>{DomainScope.finance},
      states: <LifeContextDomainState>[
        _state(
          domain: DomainScope.execution,
          freshness: LifeContextFreshness.fresh,
          signals: <LifeEvent>[
            _signal(
              id: 'inactive-inbox',
              domain: DomainScope.execution,
              template: LifeEventTemplate.executionDue,
            ),
          ],
        ),
      ],
    );

    expect(evaluateDailyNavigatorContext(context), isNull);
  });
}

Future<AgentRunResult> _run({
  required AppDatabase db,
  required LifeContextSnapshot context,
  required _CountingSynthesizer synthesizer,
  DateTime? finishedAt,
}) {
  return DailyNavigatorAgent.synthesizeAndPersist(
    context: context,
    ownerUserId: _owner,
    startedAt: _now,
    finishedAt: finishedAt ?? _now.add(const Duration(seconds: 1)),
    synthesizer: synthesizer,
    findingStore: SqliteAgentFindingStore(db: db),
    attentionService: AttentionDecisionService(
      store: SqliteAttentionDecisionStore(db: db),
    ),
    notificationsAllowed: false,
    artifactStore: SqliteAgentArtifactStore(db: db),
    resolveRoute: (family, rowId) => '/source/$family/$rowId',
    l10n: lookupAppLocalizations(const Locale('en')),
  );
}
