import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/ai_chat/domain/chat_models.dart';
import 'package:naviwealth/features/ai_chat/ui/tools/tool_invocation_card.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

ToolInvocation _withEvidence(List<Map<String, Object?>> anchors) =>
    ToolInvocation(
      id: 't1',
      name: 'get_wheel_lifecycle',
      input: const <String, Object?>{},
      output: <String, Object?>{
        'cycles': const <Object?>[],
        'evidence': anchors,
      },
    );

GoRouter _router(String? navigatedTo) {
  final root = GlobalKey<NavigatorState>();
  return GoRouter(
    navigatorKey: root,
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) =>
            Scaffold(body: ToolInvocationCard(invocation: _captured!)),
      ),
      GoRoute(path: '/wealth/assets/:id', builder: (_, _) => const _Probe()),
      GoRoute(
        path: '/wealth/liabilities/:id',
        builder: (_, _) => const _Probe(),
      ),
      GoRoute(path: '/activity/entry/:id', builder: (_, _) => const _Probe()),
      GoRoute(path: '/plan/income', builder: (_, _) => const _Probe()),
    ],
    redirect: (_, state) {
      navigatedTo;
      return null;
    },
  );
}

ToolInvocation? _captured;

class _Probe extends StatelessWidget {
  const _Probe();
  @override
  Widget build(BuildContext context) => const Scaffold(body: SizedBox.shrink());
}

Future<void> _pump(
  WidgetTester tester,
  ToolInvocation invocation, {
  GoRouter? router,
}) async {
  _captured = invocation;
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp.router(
        theme: AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en', 'US'),
        builder: (context, child) => FAccessibilityScope(
          data: const FAccessibility(
            accessibleNavigation: false,
            motion: FAccessibilityMotion.disabled,
            focusHighlight: false,
          ),
          child: FTheme(
            data: FTheme.neutral.light.desktop,
            child: child!,
          ),
        ),
        routerConfig: router ?? _router(null),
      ),
    ),
  );
  // Bounded pumps; pumpAndSettle hangs on any active animations.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  testWidgets('renders evidence chips for known entity_tables', (tester) async {
    final invocation = _withEvidence([
      <String, Object?>{
        'entity_table': 'assets',
        'entity_id': 'a_1',
        'label': 'Apple Inc.',
      },
      <String, Object?>{
        'entity_table': 'options_trade_journal',
        'entity_id': 'tj_5',
      },
    ]);
    await _pump(tester, invocation);

    // Anchor-provided label wins over the templated chip text.
    expect(find.text('Apple Inc.'), findsOneWidget);
    // The trade-journal anchor has no label, so the chip falls back to
    // the templated "Trade tj_5" form (id <= 8 chars stays unshortened).
    expect(find.textContaining('tj_5'), findsOneWidget);
  });

  testWidgets('drops anchors with unknown entity_tables', (tester) async {
    final invocation = _withEvidence([
      <String, Object?>{
        'entity_table': 'mystery',
        'entity_id': 'm_1',
        'label': 'Unknown',
      },
      <String, Object?>{
        'entity_table': 'assets',
        'entity_id': 'a_known',
        'label': 'Known asset',
      },
    ]);
    await _pump(tester, invocation);

    expect(find.text('Unknown'), findsNothing);
    expect(find.text('Known asset'), findsOneWidget);
  });

  testWidgets('renders cross-domain evidence with the source label', (
    tester,
  ) async {
    final invocation = _withEvidence([
      <String, Object?>{
        'entity_table': 'knowledge_decisions',
        'entity_id': 'decision-1',
        'label': 'Keep the current allocation',
      },
      <String, Object?>{
        'entity_table': 'execution_actions',
        'entity_id': 'action-1',
        'label': 'Review the decision',
      },
    ]);
    await _pump(tester, invocation);

    expect(find.text('Keep the current allocation'), findsOneWidget);
    expect(find.text('Review the decision'), findsOneWidget);
  });

  testWidgets('falls back to legacy heuristic when no evidence array', (
    tester,
  ) async {
    // No evidence array; a bare `account_id` in the output triggers
    // the legacy walk so older tools keep their chip.
    const invocation = ToolInvocation(
      id: 't2',
      name: 'list_payment_accounts',
      input: <String, Object?>{},
      output: <String, Object?>{
        'accounts': [
          <String, Object?>{'account_id': 'a_legacy'},
        ],
      },
    );
    await _pump(tester, invocation);

    expect(find.textContaining('a_legacy'), findsOneWidget);
  });

  testWidgets('renders chip for journal_entries anchor', (tester) async {
    final invocation = _withEvidence([
      <String, Object?>{
        'entity_table': 'journal_entries',
        'entity_id': 'je_42',
      },
    ]);
    await _pump(tester, invocation);
    expect(find.textContaining('je_42'), findsOneWidget);
  });

  testWidgets('handles empty evidence array without crashing', (tester) async {
    final invocation = _withEvidence(const []);
    await _pump(tester, invocation);
    // No chips, but the card itself is still mounted.
    expect(find.byType(ToolInvocationCard), findsOneWidget);
  });
}
