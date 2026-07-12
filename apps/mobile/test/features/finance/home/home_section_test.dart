import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/features/finance/home/ui/home_section.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    home: FTheme(
      data: FThemes.slate.light.desktop,
      child: Scaffold(body: child),
    ),
  );
}

void main() {
  testWidgets('HomeSection renders a consistent title and action slot', (
    tester,
  ) async {
    var tapped = false;
    await tester.pumpWidget(
      _wrap(
        HomeSection(
          title: 'Allocation',
          actionLabel: 'View all',
          onAction: () => tapped = true,
          child: const HomeSurface(child: Text('content')),
        ),
      ),
    );

    expect(find.text('Allocation'), findsOneWidget);
    expect(find.text('View all'), findsOneWidget);
    expect(find.text('content'), findsOneWidget);

    await tester.tap(find.text('View all'));
    await tester.pumpAndSettle();
    expect(tapped, isTrue);
  });
}
