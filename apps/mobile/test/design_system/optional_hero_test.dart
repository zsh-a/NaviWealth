import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/design_system/design_system.dart';

void main() {
  testWidgets('OptionalHero wraps in Hero when enabled', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: OptionalHero(
            tag: 'asset-1-name',
            child: Text('Apple'),
          ),
        ),
      ),
    );
    expect(find.byType(Hero), findsOneWidget);
    expect(find.text('Apple'), findsOneWidget);
  });

  testWidgets('OptionalHero is a no-op when disabled', (tester) async {
    // Disabled mode is what the master-detail surface uses to avoid two
    // Hero widgets sharing a tag inside the same Navigator.
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Row(
            children: [
              OptionalHero(
                tag: 'asset-1-name',
                enabled: false,
                child: Text('Apple'),
              ),
              OptionalHero(
                tag: 'asset-1-name',
                enabled: false,
                child: Text('Apple'),
              ),
            ],
          ),
        ),
      ),
    );
    expect(find.byType(Hero), findsNothing);
    expect(find.text('Apple'), findsNWidgets(2));
  });
}
