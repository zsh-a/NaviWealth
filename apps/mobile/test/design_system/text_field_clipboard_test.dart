import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/app/app.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

void main() {
  var clipboard = '';
  setUp(() {
    clipboard = 'pasted meal';
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            clipboard =
                (call.arguments as Map<Object?, Object?>)['text']! as String;
            return null;
          }
          return switch (call.method) {
            'Clipboard.getData' => <String, Object>{'text': clipboard},
            'Clipboard.hasStrings' => <String, Object>{
              'value': clipboard.isNotEmpty,
            },
            _ => null,
          };
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  for (final brightness in Brightness.values) {
    for (final (locale, pasteLabel, copyLabel, cutLabel) in const [
      (Locale('en'), 'Paste', 'Copy', 'Cut'),
      (Locale('zh'), '粘贴', '复制', '剪切'),
    ]) {
      final variant = TargetPlatformVariant.only(TargetPlatform.android);
      final description = '${locale.languageCode} ${brightness.name}';

      testWidgets(
        'Android empty field supports long-press paste ($description)',
        (tester) async {
          final controller = TextEditingController();
          addTearDown(controller.dispose);
          await tester.pumpWidget(
            _wrap(
              brightness: brightness,
              locale: locale,
              child: FTextField(
                control: FTextFieldControl.managed(controller: controller),
                hint: 'Meal note',
              ),
            ),
          );
          await tester.longPress(find.byType(EditableText));
          await tester.pumpAndSettle();

          expect(tester.takeException(), isNull);
          expect(find.text(pasteLabel), findsOneWidget);
          await tester.tap(find.text(pasteLabel));
          await tester.pumpAndSettle();

          expect(tester.takeException(), isNull);
          expect(controller.text, 'pasted meal');
          expect(find.byType(ErrorWidget), findsNothing);
        },
        variant: variant,
      );

      testWidgets(
        'Android selected text supports copy, cut and paste ($description)',
        (tester) async {
          final controller = TextEditingController(text: 'meal');
          addTearDown(controller.dispose);
          await tester.pumpWidget(
            _wrap(
              brightness: brightness,
              locale: locale,
              child: FTextField.multiline(
                control: FTextFieldControl.managed(controller: controller),
              ),
            ),
          );
          await tester.longPressAt(
            tester.getTopLeft(find.byType(EditableText)) + const Offset(10, 10),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(controller.selection.textInside(controller.text), 'meal');
          await tester.tap(find.text(copyLabel));
          await tester.pumpAndSettle();
          expect(clipboard, 'meal');
          expect(controller.text, 'meal');

          await tester.longPressAt(
            tester.getTopLeft(find.byType(EditableText)) + const Offset(10, 10),
          );
          await tester.pumpAndSettle();
          await tester.tap(find.text(cutLabel));
          await tester.pumpAndSettle();
          expect(clipboard, 'meal');
          expect(controller.text, isEmpty);

          await tester.longPress(find.byType(EditableText));
          await tester.pumpAndSettle();
          await tester.tap(find.text(pasteLabel));
          await tester.pumpAndSettle();
          expect(controller.text, 'meal');
          expect(tester.takeException(), isNull);
          expect(find.byType(ErrorWidget), findsNothing);
        },
        variant: variant,
      );

      testWidgets(
        'Android form sheet keeps numeric paste interactive ($description)',
        (tester) async {
          clipboard = '42.5';
          final controller = TextEditingController();
          addTearDown(controller.dispose);
          await tester.pumpWidget(
            _wrap(
              brightness: brightness,
              locale: locale,
              child: Builder(
                builder: (context) => FButton(
                  onPress: () => showAppFormSheet<void>(
                    context: context,
                    builder: (_) => AppSheet(
                      title: 'Meal amount',
                      child: AppNumberField(
                        control: FTextFieldControl.managed(
                          controller: controller,
                        ),
                      ),
                    ),
                  ),
                  child: const Text('Open form'),
                ),
              ),
            ),
          );
          await tester.tap(find.text('Open form'));
          await tester.pumpAndSettle();
          await tester.longPress(find.byType(EditableText));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await tester.tap(find.text(pasteLabel));
          await tester.pumpAndSettle();

          expect(controller.text, '42.5');
          expect(find.text('Meal amount'), findsOneWidget);
          expect(tester.takeException(), isNull);
          expect(find.byType(ErrorWidget), findsNothing);
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpAndSettle();
        },
        variant: variant,
      );
    }
  }
}

Widget _wrap({
  required Brightness brightness,
  required Locale locale,
  required Widget child,
}) => MaterialApp(
  theme: brightness == Brightness.light ? AppTheme.light() : AppTheme.dark(),
  localizationsDelegates: NaviWealthApp.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  locale: locale,
  builder: (context, child) => FTheme(
    data: buildAppForuiTheme(brightness: brightness, touch: true),
    child: AppMessenger.init(child: child!),
  ),
  home: Scaffold(
    body: Center(child: SizedBox(width: 300, child: child)),
  ),
);
