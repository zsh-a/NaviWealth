import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
        child: FScaffold(
          childPad: false,
          resizeToAvoidBottomInset: false,
          child: Material(color: Colors.transparent, child: child),
        ),
      ),
    ),
  );
}

Future<void> _pressModified(
  WidgetTester tester, {
  required LogicalKeyboardKey modifier,
  required LogicalKeyboardKey trigger,
}) async {
  await tester.sendKeyDownEvent(modifier);
  await tester.sendKeyEvent(trigger);
  await tester.sendKeyUpEvent(modifier);
  await tester.pump();
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
      moreOrLessEquals(
        size.height - keyboardInset - AppSpacing.s12,
        epsilon: 1,
      ),
    );
  });

  testWidgets('centers wide forms and actions in a readable column', (
    tester,
  ) async {
    const size = Size(1280, 900);
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      _wrap(
        keyboardInset: 0,
        const AppFormScaffoldBody(
          action: SizedBox(
            key: Key('wide-form-action'),
            width: double.infinity,
            height: 48,
          ),
          children: [
            SizedBox(
              key: Key('wide-form-field'),
              width: double.infinity,
              height: 48,
            ),
          ],
        ),
      ),
    );

    for (final key in ['wide-form-field', 'wide-form-action']) {
      final finder = find.byKey(Key(key));
      expect(tester.getSize(finder).width, AdaptiveMaxWidth.narrow);
      expect(tester.getCenter(finder).dx, size.width / 2);
    }
  });

  testWidgets('Meta/Ctrl Enter and numpad Enter invoke submit', (tester) async {
    var submissions = 0;
    await tester.pumpWidget(
      _wrap(
        keyboardInset: 0,
        AppFormScaffoldBody(
          onSubmit: () => submissions++,
          action: const SizedBox(height: 48, child: Text('Save')),
          children: const [
            Focus(
              autofocus: true,
              child: SizedBox(height: 48, child: Text('Field')),
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    for (final modifier in [
      LogicalKeyboardKey.metaLeft,
      LogicalKeyboardKey.controlLeft,
    ]) {
      for (final trigger in [
        LogicalKeyboardKey.enter,
        LogicalKeyboardKey.numpadEnter,
      ]) {
        await _pressModified(tester, modifier: modifier, trigger: trigger);
      }
    }

    expect(submissions, 4);
  });

  testWidgets('submit shortcut scope preserves descendant autofocus', (
    tester,
  ) async {
    final fieldFocus = FocusNode();
    addTearDown(fieldFocus.dispose);
    await tester.pumpWidget(
      _wrap(
        keyboardInset: 0,
        AppFormScaffoldBody(
          onSubmit: () {},
          action: const SizedBox(height: 48, child: Text('Save')),
          children: [TextField(autofocus: true, focusNode: fieldFocus)],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(fieldFocus.hasPrimaryFocus, isTrue);
  });

  testWidgets('holding modified Enter does not repeat submit', (tester) async {
    var submissions = 0;
    await tester.pumpWidget(
      _wrap(
        keyboardInset: 0,
        AppFormScaffoldBody(
          onSubmit: () => submissions++,
          action: const SizedBox(height: 48, child: Text('Save')),
          children: const [Focus(autofocus: true, child: SizedBox(height: 48))],
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(submissions, 1);

    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(submissions, 1);

    await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  });

  testWidgets(
    'ordinary Enter is unbound and propagates from a multiline field',
    (tester) async {
      final controller = TextEditingController(text: 'First line');
      addTearDown(controller.dispose);
      var submissions = 0;
      var ancestorCalls = 0;
      await tester.pumpWidget(
        _wrap(
          keyboardInset: 0,
          CallbackShortcuts(
            bindings: <ShortcutActivator, VoidCallback>{
              const SingleActivator(LogicalKeyboardKey.enter): () =>
                  ancestorCalls++,
            },
            child: AppFormScaffoldBody(
              onSubmit: () => submissions++,
              action: const SizedBox(height: 48, child: Text('Save')),
              children: [
                TextField(
                  controller: controller,
                  autofocus: true,
                  maxLines: null,
                  textInputAction: TextInputAction.newline,
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField)).textInputAction,
        TextInputAction.newline,
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();

      expect(submissions, 0);
      expect(ancestorCalls, 1);
      expect(tester.binding.focusManager.primaryFocus, isNotNull);
    },
  );

  testWidgets('null onSubmit leaves modified Enter for an ancestor', (
    tester,
  ) async {
    var ancestorCalls = 0;
    await tester.pumpWidget(
      _wrap(
        keyboardInset: 0,
        CallbackShortcuts(
          bindings: <ShortcutActivator, VoidCallback>{
            const SingleActivator(
              LogicalKeyboardKey.enter,
              control: true,
            ): () =>
                ancestorCalls++,
          },
          child: const AppFormScaffoldBody(
            action: SizedBox(height: 48, child: Text('Save')),
            children: [TextField(autofocus: true)],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _pressModified(
      tester,
      modifier: LogicalKeyboardKey.controlLeft,
      trigger: LogicalKeyboardKey.enter,
    );

    expect(ancestorCalls, 1);
  });

  testWidgets('onSubmit transitions preserve descendant focus and state', (
    tester,
  ) async {
    final onSubmit = ValueNotifier<VoidCallback?>(null);
    final fieldFocus = FocusNode();
    var probeInits = 0;
    addTearDown(onSubmit.dispose);
    addTearDown(fieldFocus.dispose);
    await tester.pumpWidget(
      _wrap(
        keyboardInset: 0,
        ValueListenableBuilder<VoidCallback?>(
          valueListenable: onSubmit,
          builder: (context, submit, _) => AppFormScaffoldBody(
            onSubmit: submit,
            action: const SizedBox(height: 48, child: Text('Save')),
            children: [
              TextField(autofocus: true, focusNode: fieldFocus),
              _StatefulProbe(onInit: () => probeInits++),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(fieldFocus.hasPrimaryFocus, isTrue);
    expect(probeInits, 1);

    await tester.tap(find.text('probe-0'));
    await tester.pump();
    expect(find.text('probe-1'), findsOneWidget);

    onSubmit.value = () {};
    await tester.pump();
    expect(fieldFocus.hasPrimaryFocus, isTrue);
    expect(probeInits, 1);
    expect(find.text('probe-1'), findsOneWidget);

    onSubmit.value = null;
    await tester.pump();
    expect(fieldFocus.hasPrimaryFocus, isTrue);
    expect(probeInits, 1);
    expect(find.text('probe-1'), findsOneWidget);
  });

  testWidgets('Tab and Shift+Tab traverse fields then the pinned action', (
    tester,
  ) async {
    final first = FocusNode();
    final second = FocusNode();
    final action = FocusNode();
    addTearDown(first.dispose);
    addTearDown(second.dispose);
    addTearDown(action.dispose);
    await tester.pumpWidget(
      _wrap(
        keyboardInset: 0,
        AppFormScaffoldBody(
          action: TextButton(
            focusNode: action,
            onPressed: () {},
            child: const Text('Save'),
          ),
          children: [
            TextButton(
              autofocus: true,
              focusNode: first,
              onPressed: () {},
              child: const Text('First'),
            ),
            TextButton(
              focusNode: second,
              onPressed: () {},
              child: const Text('Second'),
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(first.hasPrimaryFocus, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(second.hasPrimaryFocus, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(action.hasPrimaryFocus, isTrue);

    await _pressModified(
      tester,
      modifier: LogicalKeyboardKey.shiftLeft,
      trigger: LogicalKeyboardKey.tab,
    );
    expect(second.hasPrimaryFocus, isTrue);

    await _pressModified(
      tester,
      modifier: LogicalKeyboardKey.shiftLeft,
      trigger: LogicalKeyboardKey.tab,
    );
    expect(first.hasPrimaryFocus, isTrue);
  });
}

class _StatefulProbe extends StatefulWidget {
  const _StatefulProbe({required this.onInit});

  final VoidCallback onInit;

  @override
  State<_StatefulProbe> createState() => _StatefulProbeState();
}

class _StatefulProbeState extends State<_StatefulProbe> {
  var _value = 0;

  @override
  void initState() {
    super.initState();
    widget.onInit();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => setState(() => _value += 1),
      child: Text('probe-$_value'),
    );
  }
}
