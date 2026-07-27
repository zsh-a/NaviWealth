import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/core/ai/agents/agent_artifact.dart';
import 'package:naviwealth/core/ai/agents/agent_run_store.dart';
import 'package:naviwealth/core/ai/agents/providers.dart' as agent_providers;
import 'package:naviwealth/core/ai/agents/ui/agent_result_card.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/finance/agents/providers.dart'
    as finance_agent_providers;
import 'package:naviwealth/features/finance/agents/weekly_wealth_review_agent.dart';
import 'package:naviwealth/features/finance/home/ui/home_page.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

Widget _wrap(List<Override> overrides, {bool showPlaceholderStates = true}) {
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp(
      theme: AppTheme.light(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: FTheme(
        data: FThemes.slate.light.desktop,
        child: Scaffold(
          body: FinanceAgentResultsPanel(
            showPlaceholderStates: showPlaceholderStates,
          ),
        ),
      ),
    ),
  );
}

AgentArtifact _artifact({
  required String id,
  required String agentId,
  required AgentArtifactKind kind,
  required AgentArtifactSeverity severity,
  required String title,
  required String summary,
  required DateTime createdAt,
  List<AgentInsight> insights = const <AgentInsight>[],
}) {
  return AgentArtifact(
    id: id,
    ownerUserId: 'user-1',
    agentId: agentId,
    domain: 'finance',
    kind: kind,
    severity: severity,
    title: title,
    summary: summary,
    insights: insights,
    createdAt: createdAt,
  );
}

void main() {
  testWidgets('renders weekly finance artifact in the home agent panel', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap([
        finance_agent_providers.latestFinanceAgentResultsProvider.overrideWith(
          (ref) async => agent_providers.AgentResultBundle(
            artifacts: <AgentArtifact>[
              _artifact(
                id: 'weekly_wealth_review:2026-07-05',
                agentId: kWeeklyWealthReviewAgentId,
                kind: AgentArtifactKind.review,
                severity: AgentArtifactSeverity.attention,
                title: 'Weekly Wealth Review',
                summary: 'Net worth moved 2.4% with cashflow pressure.',
                insights: const <AgentInsight>[
                  AgentInsight(
                    title: 'Net worth',
                    body: 'Portfolio value increased this week.',
                  ),
                ],
                createdAt: DateTime.utc(2026, 7, 5),
              ),
              _artifact(
                id: 'cashflow_anomaly_review:2026-07-05',
                agentId: 'cashflow_anomaly_review',
                kind: AgentArtifactKind.alert,
                severity: AgentArtifactSeverity.warning,
                title: 'Cashflow Anomaly Review',
                summary: 'Spending moved sharply above baseline.',
                createdAt: DateTime.utc(2026, 7, 4),
              ),
            ],
            latestRuns: const <AgentRunRecord>[],
          ),
        ),
      ]),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('Cashflow Anomaly Review'), findsOneWidget);
    expect(find.text('Spending moved sharply above baseline.'), findsOneWidget);
    expect(find.text('Weekly Wealth Review'), findsNothing);
    expect(
      find.text('Net worth moved 2.4% with cashflow pressure.'),
      findsNothing,
    );
    expect(find.text('Net worth'), findsNothing);
    expect(find.byType(AgentResultCard), findsOneWidget);
    expect(find.byType(AgentCompactResultRow), findsNothing);
    expect(
      find.byKey(const ValueKey<String>('agent-result-stack')),
      findsOneWidget,
    );
    expect(
      tester.widget<AgentResultCard>(find.byType(AgentResultCard)).layout,
      AgentResultCardLayout.summary,
    );
    // Result-first surface: no domain chrome ("FinanceOS") on the home card.
    expect(find.textContaining('FinanceOS'), findsNothing);
    expect(find.text('No financial insights yet'), findsNothing);
  });

  testWidgets('renders an intentional loading state', (tester) async {
    final pending = Completer<agent_providers.AgentResultBundle>();
    addTearDown(() {
      if (!pending.isCompleted) {
        pending.complete(agent_providers.AgentResultBundle.empty);
      }
    });

    await tester.pumpWidget(
      _wrap([
        finance_agent_providers.latestFinanceAgentResultsProvider.overrideWith(
          (ref) => pending.future,
        ),
      ]),
    );
    await tester.pump();

    expect(find.text('Assistant is checking in'), findsOneWidget);
    expect(find.byType(FCircularProgress), findsOneWidget);
  });

  testWidgets('renders an empty state when no artifact or run exists', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap([
        finance_agent_providers.latestFinanceAgentResultsProvider.overrideWith(
          (ref) async => agent_providers.AgentResultBundle.empty,
        ),
      ]),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('No agent results yet'), findsOneWidget);
    expect(
      find.text('Run the agent to get a fresh readout of this domain.'),
      findsOneWidget,
    );
  });

  testWidgets('compact mode hides placeholder states on the home surface', (
    tester,
  ) async {
    final pending = Completer<agent_providers.AgentResultBundle>();
    addTearDown(() {
      if (!pending.isCompleted) {
        pending.complete(agent_providers.AgentResultBundle.empty);
      }
    });

    await tester.pumpWidget(
      _wrap([
        finance_agent_providers.latestFinanceAgentResultsProvider.overrideWith(
          (ref) => pending.future,
        ),
      ], showPlaceholderStates: false),
    );
    await tester.pump();

    expect(find.text('Loading financial insights'), findsNothing);
    expect(find.byType(AgentResultPanelStateCard), findsNothing);

    pending.complete(agent_providers.AgentResultBundle.empty);
    await tester.pumpWidget(
      _wrap([
        finance_agent_providers.latestFinanceAgentResultsProvider.overrideWith(
          (ref) async => agent_providers.AgentResultBundle.empty,
        ),
      ], showPlaceholderStates: false),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('No financial insights yet'), findsNothing);
    expect(find.byType(AgentResultPanelStateCard), findsNothing);

    await tester.pumpWidget(
      _wrap([
        finance_agent_providers.latestFinanceAgentResultsProvider.overrideWith(
          (ref) async => throw StateError('boom'),
        ),
      ], showPlaceholderStates: false),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('Financial insights could not load'), findsNothing);
    expect(find.byType(AgentResultPanelStateCard), findsNothing);
  });

  testWidgets('compact mode still renders real artifacts', (tester) async {
    await tester.pumpWidget(
      _wrap([
        finance_agent_providers.latestFinanceAgentResultsProvider.overrideWith(
          (ref) async => agent_providers.AgentResultBundle(
            artifacts: <AgentArtifact>[
              _artifact(
                id: 'weekly_wealth_review:2026-07-05',
                agentId: kWeeklyWealthReviewAgentId,
                kind: AgentArtifactKind.review,
                severity: AgentArtifactSeverity.attention,
                title: 'Weekly Wealth Review',
                summary: 'Net worth moved 2.4%.',
                createdAt: DateTime.utc(2026, 7, 5),
              ),
            ],
            latestRuns: const <AgentRunRecord>[],
          ),
        ),
      ], showPlaceholderStates: false),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('Weekly Wealth Review'), findsOneWidget);
    expect(find.byType(AgentResultCard), findsOneWidget);
  });

  testWidgets('renders latest run status when no artifact exists', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap([
        finance_agent_providers.latestFinanceAgentResultsProvider.overrideWith(
          (ref) async => agent_providers.AgentResultBundle(
            artifacts: const <AgentArtifact>[],
            latestRuns: [
              AgentRunRecord(
                id: 'run-1',
                ownerUserId: 'user-1',
                agentId: kWeeklyWealthReviewAgentId,
                agentName: 'Weekly Wealth Review',
                status: AgentRunLifecycleStatus.running,
                trigger: AgentRunTrigger.schedule,
                startedAt: DateTime.utc(2026, 7, 6),
                summary: 'Review in progress.',
              ),
            ],
          ),
        ),
      ]),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('Weekly Wealth Review'), findsOneWidget);
    expect(find.text('Running'), findsOneWidget);
    expect(find.text('Review in progress.'), findsOneWidget);
    expect(find.byType(AgentRunStatusCard), findsOneWidget);
  });

  testWidgets('compact mode still renders latest run status', (tester) async {
    await tester.pumpWidget(
      _wrap([
        finance_agent_providers.latestFinanceAgentResultsProvider.overrideWith(
          (ref) async => agent_providers.AgentResultBundle(
            artifacts: const <AgentArtifact>[],
            latestRuns: [
              AgentRunRecord(
                id: 'run-1',
                ownerUserId: 'user-1',
                agentId: kWeeklyWealthReviewAgentId,
                agentName: 'Weekly Wealth Review',
                status: AgentRunLifecycleStatus.running,
                trigger: AgentRunTrigger.schedule,
                startedAt: DateTime.utc(2026, 7, 6),
                summary: 'Review in progress.',
              ),
            ],
          ),
        ),
      ], showPlaceholderStates: false),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('Weekly Wealth Review'), findsOneWidget);
    expect(find.text('Running'), findsOneWidget);
    expect(find.byType(AgentRunStatusCard), findsOneWidget);
  });

  testWidgets('keeps older artifact body while newer run overlays', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap([
        finance_agent_providers.latestFinanceAgentResultsProvider.overrideWith(
          (ref) async => agent_providers.AgentResultBundle(
            artifacts: <AgentArtifact>[
              _artifact(
                id: 'weekly_wealth_review:2026-07-05',
                agentId: kWeeklyWealthReviewAgentId,
                kind: AgentArtifactKind.review,
                severity: AgentArtifactSeverity.attention,
                title: 'Old Wealth Review',
                summary: 'This older review should stay behind the run state.',
                createdAt: DateTime.utc(2026, 7, 5),
              ),
            ],
            latestRuns: [
              AgentRunRecord(
                id: 'run-1',
                ownerUserId: 'user-1',
                agentId: kWeeklyWealthReviewAgentId,
                agentName: 'Weekly Wealth Review',
                status: AgentRunLifecycleStatus.running,
                trigger: AgentRunTrigger.schedule,
                startedAt: DateTime.utc(2026, 7, 6),
                summary: 'Review in progress.',
              ),
            ],
          ),
        ),
      ]),
    );
    await tester.pump();
    await tester.pump();

    // Result-first: previous body remains; run is an overlay banner.
    expect(find.text('Old Wealth Review'), findsOneWidget);
    expect(
      find.text('This older review should stay behind the run state.'),
      findsOneWidget,
    );
    expect(find.text('Review in progress.'), findsOneWidget);
    expect(find.byType(AgentResultCard), findsOneWidget);
    expect(find.byType(AgentRunStatusCard), findsNothing);
  });
}
