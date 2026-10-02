import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/design_system/widgets/app_soft_glass_light.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

Widget _harness({
  required VoidCallback Function(BuildContext) open,
  bool reduceMotion = false,
  Brightness brightness = Brightness.light,
  bool touch = false,
}) => MaterialApp(
  theme: brightness == Brightness.light ? AppTheme.light() : AppTheme.dark(),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(disableAnimations: reduceMotion),
    child: child!,
  ),
  home: FTheme(
    data: buildAppForuiTheme(brightness: brightness, touch: touch),
    child: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: FButton(onPress: open(context), child: const Text('Open')),
        ),
      ),
    ),
  ),
);

void main() {
  for (final brightness in Brightness.values) {
    testWidgets('wide form has no backdrop filters ($brightness)', (
      tester,
    ) async {
      tester.view
        ..physicalSize = const Size(1200, 900)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      var builds = 0;
      await tester.pumpWidget(
        _harness(
          brightness: brightness,
          open: (context) =>
              () => showAppFormSheet<void>(
                context: context,
                builder: (_) {
                  builds++;
                  return const AppSheet(
                    title: 'Edit record',
                    footer: SizedBox(height: 48),
                    child: SizedBox(height: 300, child: Text('Form content')),
                  );
                },
              ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pump();
      // Check the moving surface too, not just the settled final frame.
      for (var frame = 0; frame < 8; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
        expect(find.byType(BackdropFilter), findsNothing);
      }
      expect(builds, 1);
      final form = find.byKey(const ValueKey('app-sheet.surface'));
      expect(tester.widget(form), isA<AppOverlaySurface>());
      final background = tester.widget<DecoratedBox>(
        find.descendant(of: form, matching: find.byType(DecoratedBox)).first,
      );
      expect((background.decoration as BoxDecoration).color!.a, 1);
      await tester.tapAt(const Offset(4, 4));
      await tester.pumpAndSettle();
      expect(find.text('Form content'), findsNothing);
    });
  }

  testWidgets('phone form keeps blur out of the moving content', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(390, 844)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      _harness(
        touch: true,
        open: (context) =>
            () => showAppFormSheet<void>(
              context: context,
              builder: (_) => const AppSheet(
                title: 'Phone form',
                footer: SizedBox(height: 48),
                child: SizedBox(height: 200),
              ),
            ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 32));
    final surface = find.byKey(const ValueKey('app-sheet.surface'));
    expect(tester.widget(surface), isA<AppOverlaySurface>());
    expect(
      find.descendant(of: surface, matching: find.byType(BackdropFilter)),
      findsNothing,
    );
    expect(
      find.descendant(of: surface, matching: find.byType(AppSoftGlassLight)),
      findsNothing,
    );
    await tester.pumpAndSettle();
    expect(find.byType(AppSheetDragHandle), findsOneWidget);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  testWidgets('Android form guards back and drag and avoids the keyboard', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(390, 844)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final dirty = FormDirtyController();
    addTearDown(dirty.dispose);
    var confirmations = 0;
    await tester.pumpWidget(
      _harness(
        touch: true,
        open: (context) =>
            () => showAppFormSheet<void>(
              context: context,
              dirtyGuard: dirty,
              confirmDismiss: () async {
                confirmations++;
                return false;
              },
              builder: (_) => const AppSheet(
                title: 'Android form',
                footer: SizedBox(key: Key('android-footer'), height: 48),
                child: SizedBox(height: 400),
              ),
            ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    dirty.markDirty();
    final formContext = tester.element(find.byType(AppSheet));
    expect(ModalRoute.of(formContext)!.isCurrent, isTrue);
    expect(
      ModalRoute.of(formContext)!.popDisposition,
      RoutePopDisposition.doNotPop,
    );
    dirty.busy = true;
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(confirmations, 0);
    dirty.busy = false;
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(confirmations, 1);
    expect(find.text('Android form'), findsOneWidget);
    await tester.fling(
      find.byType(AppSheetDragHandle),
      const Offset(0, 400),
      1200,
    );
    await tester.pumpAndSettle();
    expect(confirmations, 2);
    expect(find.text('Android form'), findsOneWidget);
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pumpAndSettle();
    expect(
      tester.getRect(find.byKey(const Key('android-footer'))).bottom,
      lessThanOrEqualTo(544),
    );
    dirty.markPristine();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Android form'), findsNothing);
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  testWidgets('confirmation animates a color scrim without filtering page', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(
        open: (context) =>
            () => showConfirmDialog(
              context: context,
              title: const Text('Confirm change'),
              confirmLabel: 'Confirm',
              cancelLabel: 'Cancel',
            ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 32));
    expect(find.byType(BackdropFilter), findsNothing);
    final scrim = tester.widget<AnimatedModalBarrier>(
      find.byType(AnimatedModalBarrier),
    );
    expect(scrim.color.value!.a, greaterThan(0));
    expect(scrim.dismissible, isTrue);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
  });

  testWidgets('content dialog builds its body once during reduced motion', (
    tester,
  ) async {
    var builds = 0;
    await tester.pumpWidget(
      _harness(
        reduceMotion: true,
        open: (context) =>
            () => showAppContentDialog<void>(
              context: context,
              child: AppOverlaySurface(
                child: Builder(
                  builder: (_) {
                    builds++;
                    return const SizedBox(width: 300, height: 200);
                  },
                ),
              ),
            ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    expect(find.byType(BackdropFilter), findsNothing);
    expect(builds, 1);
    expect(tester.hasRunningAnimations, isFalse);
    await tester.tapAt(const Offset(4, 4));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 100));
  });
}
