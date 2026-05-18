import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/app/route_paths.dart';
import 'package:naviwealth/core/ai/local/skills/drift_query_plan_executor.dart';
import 'package:naviwealth/core/ai/local/skills/query_plan_executor.dart';
import 'package:naviwealth/core/command_palette/command_palette.dart';
import 'package:naviwealth/core/command_palette/command_palette_dialog.dart'
    show resetCommandPaletteForTest;
import 'package:naviwealth/l10n/gen/app_localizations.dart';

Widget _wrap(Widget child) {
  return ProviderScope(
    overrides: [
      // The palette dialog watches the live Drift executor; tests don't
      // have a real database so plug in the in-memory variant with no
      // fixtures — enough to keep AskAiResultPane's pipeline alive
      // without crashing.
      driftQueryPlanExecutorProvider.overrideWithValue(
        InMemoryQueryPlanExecutor(transactions: const []),
      ),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: child,
    ),
  );
}

void main() {
  group('CommandPaletteEntry.matches', () {
    test('empty query matches everything', () {
      final entry = CommandPaletteEntry(
        id: 'x',
        label: 'Go to Assets',
        icon: Icons.dashboard,
        run: (_) {},
      );
      expect(entry.matches(''), isTrue);
    });

    test('label substring is case-insensitive', () {
      final entry = CommandPaletteEntry(
        id: 'x',
        label: 'Go to Assets',
        icon: Icons.dashboard,
        run: (_) {},
      );
      expect(entry.matches('asset'), isTrue);
      expect(entry.matches('ASSET'), isFalse, reason: 'caller normalises');
      expect(entry.matches('xyz'), isFalse);
    });

    test('keywords are also searched', () {
      final entry = CommandPaletteEntry(
        id: 'x',
        label: 'Go to Assets',
        icon: Icons.dashboard,
        keywords: const [AppRoutes.accounts, '资产'],
        run: (_) {},
      );
      expect(entry.matches(AppRoutes.accounts), isTrue);
      expect(entry.matches('资产'), isTrue);
    });
  });

  group('showCommandPalette', () {
    setUp(resetCommandPaletteForTest);
    tearDown(resetCommandPaletteForTest);

    testWidgets('opens with search field focused and lists all commands', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          Builder(
            builder: (ctx) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => showCommandPalette(
                    ctx,
                    commands: <CommandPaletteEntry>[
                      CommandPaletteEntry(
                        id: 'one',
                        label: 'First command',
                        icon: Icons.bolt,
                        run: (_) {},
                      ),
                      CommandPaletteEntry(
                        id: 'two',
                        label: 'Second command',
                        icon: Icons.bolt,
                        run: (_) {},
                      ),
                    ],
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('First command'), findsOneWidget);
      expect(find.text('Second command'), findsOneWidget);

      final TextField field = tester.widget<TextField>(find.byType(TextField));
      expect(field.autofocus, isTrue);
    });

    testWidgets('typing filters the list', (tester) async {
      await tester.pumpWidget(
        _wrap(
          Builder(
            builder: (ctx) => Scaffold(
              body: ElevatedButton(
                onPressed: () => showCommandPalette(
                  ctx,
                  commands: <CommandPaletteEntry>[
                    CommandPaletteEntry(
                      id: 'assets',
                      label: 'Go to Assets',
                      icon: Icons.bolt,
                      run: (_) {},
                    ),
                    CommandPaletteEntry(
                      id: 'expenses',
                      label: 'Go to Expenses',
                      icon: Icons.bolt,
                      run: (_) {},
                    ),
                  ],
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'expense');
      await tester.pumpAndSettle();

      expect(find.text('Go to Expenses'), findsOneWidget);
      expect(find.text('Go to Assets'), findsNothing);
    });

    testWidgets('Enter invokes the selected command and closes the dialog', (
      tester,
    ) async {
      var ran = 0;
      await tester.pumpWidget(
        _wrap(
          Builder(
            builder: (ctx) => Scaffold(
              body: ElevatedButton(
                onPressed: () => showCommandPalette(
                  ctx,
                  commands: <CommandPaletteEntry>[
                    CommandPaletteEntry(
                      id: 'first',
                      label: 'First command',
                      icon: Icons.bolt,
                      run: (_) => ran++,
                    ),
                  ],
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(ran, 1);
      expect(find.text('First command'), findsNothing);
    });

    testWidgets('ArrowDown moves selection so Enter invokes the next entry', (
      tester,
    ) async {
      final invoked = <String>[];
      await tester.pumpWidget(
        _wrap(
          Builder(
            builder: (ctx) => Scaffold(
              body: ElevatedButton(
                onPressed: () => showCommandPalette(
                  ctx,
                  commands: <CommandPaletteEntry>[
                    CommandPaletteEntry(
                      id: 'one',
                      label: 'First command',
                      icon: Icons.bolt,
                      run: (_) => invoked.add('one'),
                    ),
                    CommandPaletteEntry(
                      id: 'two',
                      label: 'Second command',
                      icon: Icons.bolt,
                      run: (_) => invoked.add('two'),
                    ),
                  ],
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(invoked, ['two']);
    });

    testWidgets('Esc dismisses the palette without running any command', (
      tester,
    ) async {
      var ran = 0;
      await tester.pumpWidget(
        _wrap(
          Builder(
            builder: (ctx) => Scaffold(
              body: ElevatedButton(
                onPressed: () => showCommandPalette(
                  ctx,
                  commands: <CommandPaletteEntry>[
                    CommandPaletteEntry(
                      id: 'one',
                      label: 'First command',
                      icon: Icons.bolt,
                      run: (_) => ran++,
                    ),
                  ],
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('First command'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(find.text('First command'), findsNothing);
      expect(ran, 0);
    });

    testWidgets('a second invocation while the palette is open is a no-op', (
      tester,
    ) async {
      final commands = <CommandPaletteEntry>[
        CommandPaletteEntry(
          id: 'one',
          label: 'First command',
          icon: Icons.bolt,
          run: (_) {},
        ),
      ];
      await tester.pumpWidget(
        _wrap(
          Builder(
            builder: (ctx) => Scaffold(
              body: ElevatedButton(
                onPressed: () {
                  showCommandPalette(ctx, commands: commands);
                  showCommandPalette(ctx, commands: commands);
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('First command'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('shows empty-state message when no command matches', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          Builder(
            builder: (ctx) => Scaffold(
              body: ElevatedButton(
                onPressed: () => showCommandPalette(
                  ctx,
                  commands: <CommandPaletteEntry>[
                    CommandPaletteEntry(
                      id: 'one',
                      label: 'First command',
                      icon: Icons.bolt,
                      run: (_) {},
                    ),
                  ],
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'zzznothing');
      await tester.pumpAndSettle();

      expect(find.text('First command'), findsNothing);
      // Empty-state copy from app_en.arb.
      expect(find.text('No commands match your search'), findsOneWidget);
    });
  });

  group('defaultCommandPaletteEntries', () {
    testWidgets('exposes navigation + quick-action commands with stable ids', (
      tester,
    ) async {
      late List<CommandPaletteEntry> entries;
      await tester.pumpWidget(
        _wrap(
          Builder(
            builder: (ctx) {
              entries = defaultCommandPaletteEntries(AppLocalizations.of(ctx));
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      final ids = entries.map((e) => e.id).toSet();
      expect(
        ids,
        containsAll(<String>[
          'nav.home',
          'nav.activity',
          'nav.accounts',
          'nav.expenses',
          'nav.cashflow',
          'nav.cashflow.recurring',
          'nav.income',
          'nav.analytics',
          'nav.fire',
          'nav.rebalance',
          'nav.settings',
          'action.newTrade',
          'action.newDividend',
          'action.corporateAction',
          'action.newExpense',
          'action.rebalance.targetAllocation',
          'action.openAi',
          'action.shortcutHelp',
        ]),
      );
      expect(entries.length, ids.length, reason: 'command ids must be unique');
    });
  });
}
