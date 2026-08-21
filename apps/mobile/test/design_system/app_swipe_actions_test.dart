import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

Widget _wrap(Widget child, {TextDirection direction = TextDirection.ltr}) {
  return MaterialApp(
    theme: AppTheme.light(),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: FTheme(
      data: FTheme.neutral.light.desktop,
      child: Directionality(
        textDirection: direction,
        child: Scaffold(
          body: Center(child: SizedBox(width: 320, child: child)),
        ),
      ),
    ),
  );
}

Widget _row({
  required String label,
  required VoidCallback onEdit,
  required VoidCallback onContext,
  required VoidCallback onDelete,
}) {
  return AppSwipeActions(
    leadingActions: <AppSwipeAction>[
      AppSwipeAction(
        id: 'edit-$label',
        icon: FLucideIcons.pencil,
        label: 'Edit',
        onPressed: onEdit,
      ),
      AppSwipeAction(
        id: 'context-$label',
        icon: FLucideIcons.sparkles,
        label: 'Organize',
        tone: AppSwipeActionTone.primary,
        onPressed: onContext,
      ),
    ],
    trailingActions: <AppSwipeAction>[
      AppSwipeAction(
        id: 'delete-$label',
        icon: FLucideIcons.trash2,
        label: 'Delete',
        tone: AppSwipeActionTone.danger,
        onPressed: onDelete,
      ),
    ],
    child: ColoredBox(
      color: Colors.white,
      child: SizedBox(height: 80, child: Center(child: Text(label))),
    ),
  );
}

void main() {
  testWidgets('right drag reveals commands without executing them', (
    tester,
  ) async {
    var edited = false;
    var organized = false;
    var deleted = false;
    await tester.pumpWidget(
      _wrap(
        _row(
          label: 'Knowledge row',
          onEdit: () => edited = true,
          onContext: () => organized = true,
          onDelete: () => deleted = true,
        ),
      ),
    );

    await tester.drag(find.text('Knowledge row'), const Offset(150, 0));
    await tester.pumpAndSettle();

    expect(edited, isFalse);
    expect(organized, isFalse);
    expect(deleted, isFalse);

    await tester.tap(
      find.byKey(const ValueKey<String>('app-swipe-action.edit-Knowledge row')),
    );
    await tester.pumpAndSettle();
    expect(edited, isTrue);
  });

  testWidgets('left drag reveals destructive command but requires a tap', (
    tester,
  ) async {
    var deleted = false;
    await tester.pumpWidget(
      _wrap(
        _row(
          label: 'Knowledge row',
          onEdit: () {},
          onContext: () {},
          onDelete: () => deleted = true,
        ),
      ),
    );

    await tester.drag(find.text('Knowledge row'), const Offset(-90, 0));
    await tester.pumpAndSettle();
    expect(deleted, isFalse);

    await tester.tap(
      find.byKey(
        const ValueKey<String>('app-swipe-action.delete-Knowledge row'),
      ),
    );
    await tester.pumpAndSettle();
    expect(deleted, isTrue);
  });

  testWidgets('opening another row closes the previous row', (tester) async {
    await tester.pumpWidget(
      _wrap(
        AppSwipeActionGroup(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _row(
                label: 'First',
                onEdit: () {},
                onContext: () {},
                onDelete: () {},
              ),
              const SizedBox(height: 8),
              _row(
                label: 'Second',
                onEdit: () {},
                onContext: () {},
                onDelete: () {},
              ),
            ],
          ),
        ),
      ),
    );

    await tester.drag(find.text('First'), const Offset(150, 0));
    await tester.pumpAndSettle();
    await tester.drag(find.text('Second'), const Offset(150, 0));
    await tester.pumpAndSettle();

    final firstTextCenter = tester.getCenter(find.text('First'));
    final secondTextCenter = tester.getCenter(find.text('Second'));
    expect(firstTextCenter.dx, closeTo(400, 1));
    expect(secondTextCenter.dx, greaterThan(firstTextCenter.dx + 100));
  });

  testWidgets('leading actions follow text direction', (tester) async {
    var edited = false;
    await tester.pumpWidget(
      _wrap(
        _row(
          label: 'RTL row',
          onEdit: () => edited = true,
          onContext: () {},
          onDelete: () {},
        ),
        direction: TextDirection.rtl,
      ),
    );

    await tester.drag(find.text('RTL row'), const Offset(-150, 0));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('app-swipe-action.edit-RTL row')),
    );
    await tester.pumpAndSettle();
    expect(edited, isTrue);
  });
}
