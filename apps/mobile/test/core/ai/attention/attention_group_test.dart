import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/core/ai/attention/attention_item.dart';
import 'package:naviwealth/core/ai/attention/ui/attention_group.dart';
import 'package:naviwealth/core/auth/domain_scope.dart';
import 'package:naviwealth/design_system/design_system.dart';

void main() {
  testWidgets('shows concrete rows and progressively discloses evidence', (
    tester,
  ) async {
    var opened = 0;
    const items = <AttentionItem>[
      AttentionItem(
        id: 'blocked-1',
        domain: DomainScope.execution,
        headline: 'Prepare quarterly review',
        rationale: 'Blocked · Due',
        severity: AttentionItemSeverity.warning,
        facts: <AttentionFact>[
          AttentionFact(label: 'Status', value: 'Blocked'),
          AttentionFact(label: 'Due', value: 'Aug 23'),
        ],
        evidence: <AttentionEvidence>[
          AttentionEvidence(
            label: 'Action',
            detail: 'Waiting for the final statement.',
          ),
        ],
        route: '/execution/action/blocked-1',
      ),
      AttentionItem(
        id: 'project-1',
        domain: DomainScope.execution,
        headline: 'Launch retirement plan',
        rationale: 'Missing next action',
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: FTheme(
          data: FTheme.neutral.light.desktop,
          child: Scaffold(
            body: Builder(
              builder: (context) => AttentionGroup(
                title: 'Needs attention',
                items: items,
                onOpen: (item) => showAttentionItemSheet(
                  context: context,
                  item: item,
                  evidenceTitle: 'Evidence',
                  actionLabel: 'Open related page',
                  onAction: () => opened++,
                ),
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('Needs attention'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('Prepare quarterly review'), findsOneWidget);
    expect(find.text('Blocked · Due'), findsOneWidget);

    await tester.tap(find.text('Prepare quarterly review'));
    await tester.pumpAndSettle();

    expect(find.text('Evidence'), findsOneWidget);
    expect(find.text('Waiting for the final statement.'), findsOneWidget);
    expect(find.text('Status'), findsOneWidget);
    expect(find.text('Blocked'), findsWidgets);

    await tester.tap(find.text('Open related page'));
    await tester.pumpAndSettle();

    expect(opened, 1);
    expect(find.text('Evidence'), findsNothing);
  });
}
