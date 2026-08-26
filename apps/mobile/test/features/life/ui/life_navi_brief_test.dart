import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/core/ai/agents/agent_artifact.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/life/ui/life_navi_brief.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

Widget _wrap(Widget child) {
  return ProviderScope(
    child: MaterialApp(
      theme: AppTheme.light(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: FTheme(
        data: FTheme.neutral.light.desktop,
        child: FScaffold(childPad: false, child: child),
      ),
    ),
  );
}

AgentArtifact _artifact() => AgentArtifact(
  id: 'daily-navigator:one',
  ownerUserId: 'user-1',
  agentId: 'daily_navigator',
  domain: 'life',
  kind: AgentArtifactKind.briefing,
  severity: AgentArtifactSeverity.attention,
  title: 'Some items need priority attention',
  summary: 'A cross-domain summary grounded in fresh signals.',
  insights: const [
    AgentInsight(
      title: 'Execution',
      body: 'One action needs a decision today.',
      severity: AgentArtifactSeverity.attention,
    ),
  ],
  evidence: const [
    AgentEvidenceRef(type: 'life_signal_source', id: 'exec:action-1'),
    AgentEvidenceRef(type: 'life_signal_source', id: 'fin:budget-1'),
  ],
  createdAt: DateTime.utc(2026, 8, 26, 8),
);

void main() {
  testWidgets('renders one evidence-backed daily brief inside the hero', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(LifeNaviBrief(artifactAsync: AsyncValue.data(_artifact()))),
    );
    await tester.pumpAndSettle();

    expect(find.text('Briefing'), findsOneWidget);
    expect(
      find.text('A cross-domain summary grounded in fresh signals.'),
      findsOneWidget,
    );
    expect(find.text('2 sources'), findsOneWidget);
    expect(find.text('Review'), findsOneWidget);
    expect(find.text('Ask'), findsOneWidget);
  });

  testWidgets('stays quiet when no persisted brief is available', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(const LifeNaviBrief(artifactAsync: AsyncValue.data(null))),
    );
    await tester.pumpAndSettle();

    expect(find.text('Briefing'), findsNothing);
    expect(find.byType(SkeletonBox), findsNothing);
  });
}
