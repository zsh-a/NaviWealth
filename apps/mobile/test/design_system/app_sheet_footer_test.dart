import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/design_system/design_system.dart';

Widget _wrap({required Size size, double textScale = 1}) {
  return MaterialApp(
    theme: AppTheme.light(),
    home: FTheme(
      data: FTheme.neutral.light.desktop,
      child: MediaQuery(
        data: MediaQueryData(
          size: size,
          textScaler: TextScaler.linear(textScale),
        ),
        child: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: SizedBox(
              width: size.width,
              child: AppSheetFooter(
                cancelLabel: 'Cancel changes',
                submitLabel: 'Save changes',
                onSubmit: () {},
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('sheet footer stacks actions on compact widths', (tester) async {
    await tester.pumpWidget(_wrap(size: const Size(320, 640)));

    expect(
      find.byKey(const ValueKey<String>('app-sheet-footer.stacked')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('app-sheet-footer.horizontal')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('sheet footer keeps side-by-side actions on regular widths', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap(size: const Size(600, 800)));

    expect(
      find.byKey(const ValueKey<String>('app-sheet-footer.horizontal')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('app-sheet-footer.stacked')),
      findsNothing,
    );
  });

  testWidgets('sheet footer stacks actions for large text', (tester) async {
    await tester.pumpWidget(_wrap(size: const Size(430, 800), textScale: 1.6));

    expect(
      find.byKey(const ValueKey<String>('app-sheet-footer.stacked')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
