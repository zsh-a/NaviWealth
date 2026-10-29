import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/design_system/design_system.dart';

Future<void> _pump(
  WidgetTester tester, {
  required double width,
  TextScaler textScaler = TextScaler.noScaling,
}) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(textScaler: textScaler),
        child: const Scaffold(
          body: AdaptiveSupportingPane(
            primary: SizedBox(key: ValueKey('primary'), height: 100),
            supporting: SizedBox(key: ValueKey('supporting'), height: 80),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('keeps editing state and focus across responsive layouts', (
    tester,
  ) async {
    final width = ValueNotifier(1200.0);
    addTearDown(width.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: ValueListenableBuilder<double>(
              valueListenable: width,
              builder: (context, width, _) => SizedBox(
                width: width,
                child: const AdaptiveSupportingPane(
                  primary: TextField(),
                  supporting: Text('Supporting'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.enterText(find.byType(TextField), 'Keep my draft');
    final field = tester.state<EditableTextState>(find.byType(EditableText));
    final focus = field.widget.focusNode;
    expect(focus.hasFocus, isTrue);
    width.value = 320;
    await tester.pumpAndSettle();
    expect(tester.state(find.byType(EditableText)), same(field));
    expect(find.text('Keep my draft'), findsOneWidget);
    expect(focus.hasFocus, isTrue);
    width.value = 1200;
    await tester.pumpAndSettle();
    expect(tester.state(find.byType(EditableText)), same(field));
    expect(focus.hasFocus, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('stacks in content order below the local breakpoint', (
    tester,
  ) async {
    await _pump(tester, width: 900);

    final primary = tester.getRect(find.byKey(const ValueKey('primary')));
    final supporting = tester.getRect(find.byKey(const ValueKey('supporting')));
    expect(supporting.left, primary.left);
    expect(supporting.top, greaterThan(primary.bottom));
  });

  testWidgets('uses a fixed supporting rail on a wide surface', (tester) async {
    await _pump(tester, width: 1200);

    final primary = tester.getRect(find.byKey(const ValueKey('primary')));
    final supporting = tester.getRect(find.byKey(const ValueKey('supporting')));
    expect(supporting.top, primary.top);
    expect(supporting.left, greaterThan(primary.right));
    expect(supporting.width, kAdaptiveSupportingPaneWidth);
  });

  testWidgets('large text restores a single reading flow', (tester) async {
    await _pump(tester, width: 1200, textScaler: const TextScaler.linear(2));

    final primary = tester.getRect(find.byKey(const ValueKey('primary')));
    final supporting = tester.getRect(find.byKey(const ValueKey('supporting')));
    expect(supporting.left, primary.left);
    expect(supporting.top, greaterThan(primary.bottom));
  });
}
