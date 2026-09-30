import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/shell/master_detail_layout.dart';
import 'package:naviwealth/core/shell/shell_preferences.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _pumpLayout(
  WidgetTester tester, {
  Map<String, Object> prefs = const {},
}) async {
  SharedPreferences.setMockInitialValues(prefs);
  final sharedPreferences = await SharedPreferences.getInstance();

  await tester.binding.setSurfaceSize(const Size(1000, 600));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(sharedPreferences),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(
          body: MasterDetailLayout(
            master: ColoredBox(key: ValueKey('master'), color: Colors.red),
            detail: ColoredBox(key: ValueKey('detail'), color: Colors.blue),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('splitter supports keyboard resizing and clamps width', (
    tester,
  ) async {
    await _pumpLayout(tester);
    final focus = tester.widget<Focus>(
      find.byKey(const ValueKey('master-detail-splitter')),
    );
    // The Focus widget owns the node below its build context.
    final node = Focus.of(
      tester.element(
        find
            .descendant(
              of: find.byKey(const ValueKey('master-detail-splitter')),
              matching: find.byType(MouseRegion),
            )
            .first,
      ),
    );
    node.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(
      tester.getSize(find.byKey(const ValueKey('master'))).width,
      kMasterPaneDefaultWidth + AppSpacing.s16,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.end);
    await tester.pump();
    expect(
      tester.getSize(find.byKey(const ValueKey('master'))).width,
      kMasterPaneMaxWidth,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.home);
    await tester.pump();
    expect(
      tester.getSize(find.byKey(const ValueKey('master'))).width,
      kMasterPaneMinWidth,
    );
    expect(focus.canRequestFocus, isTrue);
  });
  test('shouldUseMasterDetail follows the local content breakpoint', () {
    expect(MasterDetailLayout.shouldUseMasterDetail(1023), isFalse);
    expect(MasterDetailLayout.shouldUseMasterDetail(1024), isTrue);
  });

  testWidgets('uses the default master pane width', (tester) async {
    await _pumpLayout(tester);

    final masterRect = tester.getRect(find.byKey(const ValueKey('master')));
    final detailRect = tester.getRect(find.byKey(const ValueKey('detail')));

    expect(masterRect.width, kMasterPaneDefaultWidth);
    // Detail pane sits past the splitter's hit area (AppSpacing.s16 = 16dp).
    expect(detailRect.left, kMasterPaneDefaultWidth + AppSpacing.s16);
  });

  testWidgets('clamps an oversized persisted master pane width', (
    tester,
  ) async {
    await _pumpLayout(
      tester,
      prefs: const {'naviwealth.shell.master_pane_width': 900.0},
    );

    final masterRect = tester.getRect(find.byKey(const ValueKey('master')));
    expect(masterRect.width, kMasterPaneMaxWidth);
  });

  testWidgets('dragging the splitter clamps the master pane width', (
    tester,
  ) async {
    await _pumpLayout(tester);

    final splitter = find.byType(MouseRegion).last;
    await tester.drag(splitter, const Offset(500, 0));
    await tester.pumpAndSettle();

    var masterRect = tester.getRect(find.byKey(const ValueKey('master')));
    expect(masterRect.width, kMasterPaneMaxWidth);

    await tester.drag(splitter, const Offset(-500, 0));
    await tester.pumpAndSettle();

    masterRect = tester.getRect(find.byKey(const ValueKey('master')));
    expect(masterRect.width, kMasterPaneMinWidth);
  });

  testWidgets('MasterDetailEmpty renders a centered empty detail message', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(
          body: MasterDetailEmpty(
            message: 'Select an item',
            icon: Icons.account_balance_wallet_outlined,
          ),
        ),
      ),
    );

    expect(find.text('Select an item'), findsOneWidget);
    expect(find.byIcon(Icons.account_balance_wallet_outlined), findsOneWidget);
  });
}
