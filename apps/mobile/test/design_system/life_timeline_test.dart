import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/design_system/design_system.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    theme: AppTheme.light(),
    home: FTheme(
      data: FTheme.neutral.light.desktop,
      child: Scaffold(body: Center(child: child)),
    ),
  );
}

void main() {
  testWidgets('keeps row navigation and secondary action independent', (
    tester,
  ) async {
    var opens = 0;
    var actions = 0;
    await tester.pumpWidget(
      _wrap(
        SizedBox(
          width: 420,
          child: LifeTimeline(
            items: [
              LifeTimelineItem(
                id: 'signal-1',
                at: DateTime.utc(2026, 7, 22),
                title: 'Portfolio conclusion',
                subtitle: 'Allocation changed',
                icon: FLucideIcons.sparkles,
                accent: Colors.blue,
                domainLabel: 'Finance',
                onOpen: () => opens += 1,
                onAction: () => actions += 1,
                actionLabel: 'Create action from this update',
              ),
            ],
          ),
        ),
      ),
    );

    await tester.tap(find.text('Portfolio conclusion'));
    await tester.pump(const Duration(milliseconds: 150));
    expect(opens, 1);
    expect(actions, 0);

    await tester.tap(find.bySemanticsLabel('Create action from this update'));
    await tester.pump(const Duration(milliseconds: 150));
    expect(opens, 1);
    expect(actions, 1);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 150));
  });
}
