import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/core/ai/agents/agent_artifact.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/finance/agents/providers.dart'
    as finance_agent_providers;
import 'package:naviwealth/features/finance/agents/weekly_wealth_review_agent.dart';
import 'package:naviwealth/features/finance/home/ui/home_page.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

void main() {
  testWidgets('renders weekly finance artifact in the home agent panel', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          finance_agent_providers.latestFinanceAgentArtifactsProvider
              .overrideWith(
                (ref) async => <AgentArtifact>[
                  AgentArtifact(
                    id: 'weekly_wealth_review:2026-07-05',
                    ownerUserId: 'user-1',
                    agentId: kWeeklyWealthReviewAgentId,
                    domain: 'finance',
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
                ],
              ),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: FTheme(
            data: FThemes.slate.light.desktop,
            child: const Scaffold(body: FinanceAgentResultsPanel()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Weekly Wealth Review'), findsOneWidget);
    expect(
      find.text('Net worth moved 2.4% with cashflow pressure.'),
      findsOneWidget,
    );
    expect(find.text('Net worth'), findsOneWidget);
    expect(find.textContaining('FinanceOS'), findsOneWidget);
  });
}
