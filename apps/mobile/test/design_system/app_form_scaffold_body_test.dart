import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/design_system/design_system.dart';

Widget _wrap(Widget child, {required double keyboardInset}) {
  return MaterialApp(
    theme: AppTheme.light(),
    home: FTheme(
      data: FThemes.slate.light.desktop,
      child: MediaQuery(
        data: MediaQueryData(
          viewInsets: EdgeInsets.only(bottom: keyboardInset),
        ),
        child: FScaffold(childPad: false, child: child),
      ),
    ),
  );
}

void main() {
  testWidgets('AppFormScaffoldBody pins its action above the keyboard', (
    tester,
  ) async {
    const size = Size(390, 844);
    const keyboardInset = 320.0;
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      _wrap(
        keyboardInset: keyboardInset,
        const AppFormScaffoldBody(
          action: SizedBox(
            key: Key('form-action'),
            height: 48,
            child: Text('Save'),
          ),
          children: [SizedBox(height: 700, child: Text('Fields'))],
        ),
      ),
    );

    expect(find.byKey(const Key('form-action')), findsOneWidget);
    expect(
      tester.getBottomLeft(find.byKey(const Key('form-action'))).dy,
      lessThan(size.height - keyboardInset),
    );
  });
}
