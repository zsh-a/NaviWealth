import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:naviwealth/app/agent_artifact_page.dart';
import 'package:naviwealth/core/ai/agents/agent_artifact.dart';
import 'package:naviwealth/core/ai/agents/agent_artifact_routes.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

void main() {
  testWidgets('opens the route owned by an individual conclusion', (
    tester,
  ) async {
    const artifactId = 'artifact-1';
    final artifact = AgentArtifact(
      id: artifactId,
      ownerUserId: 'user-1',
      agentId: 'weekly_wealth_review',
      domain: 'finance',
      kind: AgentArtifactKind.review,
      severity: AgentArtifactSeverity.attention,
      title: 'Weekly wealth conclusion',
      summary: 'Your allocation needs review.',
      insights: const [
        AgentInsight(
          id: 'allocation',
          title: 'Allocation concentration',
          body: 'One category is above the preferred range.',
          route: '/wealth/portfolio',
        ),
      ],
      createdAt: DateTime.utc(2026, 7, 22),
    );
    final router = GoRouter(
      initialLocation: AgentArtifactRoutes.detail(artifactId),
      routes: [
        GoRoute(
          path: AgentArtifactRoutes.detailPath,
          builder: (_, state) => AgentArtifactPage(
            artifactId: state.pathParameters['artifactId']!,
          ),
        ),
        GoRoute(
          path: '/wealth/portfolio',
          builder: (_, _) => const Scaffold(body: Text('Portfolio page')),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          agentArtifactProvider(
            artifactId,
          ).overrideWith((ref) async => artifact),
        ],
        child: MaterialApp.router(
          theme: AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router,
          builder: (context, child) =>
              FTheme(data: FThemes.slate.light.desktop, child: child!),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Weekly wealth conclusion'), findsOneWidget);
    await tester.tap(find.text('Allocation concentration'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open related page'));
    await tester.pumpAndSettle();

    expect(find.text('Portfolio page'), findsOneWidget);
  });
}
