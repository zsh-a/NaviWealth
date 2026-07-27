import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    theme: AppTheme.light(),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: FTheme(
      data: FThemes.slate.light.desktop,
      child: Scaffold(body: Center(child: child)),
    ),
  );
}

void main() {
  testWidgets('AppStatusBanner renders details and action', (tester) async {
    var pressed = false;
    await tester.pumpWidget(
      _wrap(
        AppStatusBanner(
          kind: AppStatusKind.error,
          message: 'Could not sync',
          details: 'Network unavailable',
          action: FButton(
            onPress: () => pressed = true,
            child: const Text('Retry'),
          ),
        ),
      ),
    );

    expect(find.text('Could not sync'), findsOneWidget);
    expect(find.text('Network unavailable'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(pressed, isTrue);
  });

  testWidgets('AppBadge renders compact status labels', (tester) async {
    await tester.pumpWidget(
      _wrap(
        const AppBadge(
          label: 'Active',
          tone: AppBadgeTone.success,
          size: AppBadgeSize.compact,
          icon: FLucideIcons.circleCheck,
        ),
      ),
    );

    expect(find.text('Active'), findsOneWidget);
    expect(find.byIcon(FLucideIcons.circleCheck), findsOneWidget);
  });

  testWidgets('SectionHeader keeps hierarchy neutral by default', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap(const SectionHeader(title: 'Overview')));

    final title = tester.widget<Text>(find.text('Overview'));
    final context = tester.element(find.byType(SectionHeader));
    expect(title.style?.color, context.theme.colors.foreground);
  });

  testWidgets('AppSection renders title, trailing and children', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        const AppSection.group(
          title: 'Section',
          trailing: AppBadge(label: 'New'),
          children: [Text('Body')],
        ),
      ),
    );

    expect(find.text('Section'), findsOneWidget);
    expect(find.text('New'), findsOneWidget);
    expect(find.text('Body'), findsOneWidget);
  });

  testWidgets('AppPageScaffold injects back header and actions', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        AppPageScaffold(
          title: 'Details',
          actions: [
            FHeaderAction(
              icon: const Icon(FLucideIcons.settings, key: Key('settings')),
              onPress: () {},
            ),
          ],
          child: const Text('Body'),
        ),
      ),
    );

    expect(find.text('Details'), findsOneWidget);
    expect(find.byKey(const ValueKey('app.back')), findsOneWidget);
    expect(find.byKey(const Key('settings')), findsOneWidget);
    expect(find.text('Body'), findsOneWidget);
  });

  testWidgets('AppPageScaffold accepts a custom title widget', (tester) async {
    await tester.pumpWidget(
      _wrap(
        const AppPageScaffold(
          titleWidget: Row(
            mainAxisSize: MainAxisSize.min,
            children: [Text('Custom')],
          ),
          child: Text('Body'),
        ),
      ),
    );

    expect(find.text('Custom'), findsOneWidget);
    expect(find.byKey(const ValueKey('app.back')), findsOneWidget);
  });

  testWidgets('AppFormPageScaffold uses the standard back header', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        AppFormPageScaffold(
          title: const Text('Edit'),
          actions: [
            FHeaderAction(
              icon: const Icon(FLucideIcons.trash2, key: Key('delete')),
              onPress: () {},
            ),
          ],
          child: const Text('Fields'),
        ),
      ),
    );

    expect(find.text('Edit'), findsOneWidget);
    expect(find.byKey(const ValueKey('app.back')), findsOneWidget);
    expect(find.byKey(const Key('delete')), findsOneWidget);
    expect(find.text('Fields'), findsOneWidget);
  });

  testWidgets('AppCanvasScaffold renders a headerless canvas', (tester) async {
    await tester.pumpWidget(
      _wrap(const AppCanvasScaffold(child: Text('Root'))),
    );

    expect(find.text('Root'), findsOneWidget);
    expect(find.byKey(const ValueKey('app.back')), findsNothing);
  });
}
