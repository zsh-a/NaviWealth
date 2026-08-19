import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/core/shell/shell_chrome.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

Widget _wrap(
  Widget child, {
  ShellChromeBuilders chrome = ShellChromeBuilders.empty,
  TargetPlatform platform = TargetPlatform.android,
}) {
  return ProviderScope(
    overrides: [shellChromeBuildersProvider.overrideWith((_) => chrome)],
    child: MaterialApp(
      theme: AppTheme.light().copyWith(platform: platform),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      home: FTheme(data: FTheme.neutral.light.desktop, child: child),
    ),
  );
}

Future<void> _setSurface(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

void main() {
  group('ShellTabScaffold', () {
    testWidgets('injects shell chrome on compact viewports', (tester) async {
      await _setSurface(tester, const Size(400, 800));

      await tester.pumpWidget(
        _wrap(
          const ShellTabScaffold(title: 'Activity', child: Text('body')),
          chrome: const ShellChromeBuilders(
            leadingBuilder: _leading,
            headerActionsBuilder: _actions,
          ),
        ),
      );

      expect(find.text('Activity'), findsOneWidget);
      expect(find.byKey(const Key('shell.leading')), findsOneWidget);
      expect(find.bySemanticsLabel('Global action'), findsOneWidget);
    });

    testWidgets('leaves desktop global chrome to dock/sidebar', (tester) async {
      await _setSurface(tester, const Size(1440, 900));

      await tester.pumpWidget(
        _wrap(
          const ShellTabScaffold(title: 'Activity', child: Text('body')),
          chrome: const ShellChromeBuilders(
            leadingBuilder: _leading,
            headerActionsBuilder: _actions,
          ),
        ),
      );

      expect(find.text('Activity'), findsOneWidget);
      expect(find.byKey(const Key('shell.leading')), findsNothing);
      expect(find.bySemanticsLabel('Global action'), findsNothing);
    });

    testWidgets('keeps desktop headers to two direct actions', (tester) async {
      await _setSurface(tester, const Size(1440, 900));

      await tester.pumpWidget(
        _wrap(
          ShellTabScaffold(
            title: 'Activity',
            actions: <ShellHeaderActionSpec>[
              for (var index = 0; index < 3; index++)
                ShellHeaderActionSpec(
                  icon: FLucideIcons.circle,
                  label: 'Domain action $index',
                  onPress: () {},
                  order: index,
                ),
            ],
            child: const Text('body'),
          ),
        ),
      );

      for (var index = 0; index < 2; index++) {
        expect(find.bySemanticsLabel('Domain action $index'), findsOneWidget);
      }
      expect(find.bySemanticsLabel('Domain action 2'), findsNothing);
      expect(find.bySemanticsLabel('More actions'), findsOneWidget);

      await tester.tap(find.bySemanticsLabel('More actions'));
      await tester.pumpAndSettle();
      expect(find.text('Domain action 2'), findsOneWidget);
    });

    testWidgets('budgets combined actions and moves the rest to overflow', (
      tester,
    ) async {
      await _setSurface(tester, const Size(400, 800));
      var thirdActionSelected = false;

      await tester.pumpWidget(
        _wrap(
          ShellTabScaffold(
            title: 'Activity',
            actions: <ShellHeaderActionSpec>[
              ShellHeaderActionSpec(
                icon: FLucideIcons.plus,
                label: 'Primary action',
                onPress: () {},
              ),
              ShellHeaderActionSpec(
                icon: FLucideIcons.filter,
                label: 'Filter action',
                onPress: () {},
                order: 10,
              ),
              ShellHeaderActionSpec(
                icon: FLucideIcons.inbox,
                label: 'Third action',
                onPress: () => thirdActionSelected = true,
                order: 20,
              ),
            ],
            child: const Text('body'),
          ),
          chrome: const ShellChromeBuilders(
            leadingBuilder: _leading,
            headerActionsBuilder: _actions,
          ),
        ),
      );

      expect(find.bySemanticsLabel('Primary action'), findsOneWidget);
      expect(find.bySemanticsLabel('Filter action'), findsOneWidget);
      expect(find.bySemanticsLabel('Third action'), findsNothing);
      await tester.tap(find.bySemanticsLabel('More actions'));
      await tester.pumpAndSettle();
      expect(find.text('Third action'), findsOneWidget);
      expect(find.text('Global action'), findsOneWidget);
      await tester.tap(find.text('Third action'));
      await tester.pumpAndSettle();
      expect(thirdActionSelected, isTrue);
      expect(find.text('Third action'), findsNothing);
      await _flushTooltipDelay(tester);
    });

    testWidgets('uses an anchored overflow menu on desktop platforms', (
      tester,
    ) async {
      await _setSurface(tester, const Size(400, 800));
      var thirdActionSelected = false;

      await tester.pumpWidget(
        _wrap(
          ShellTabScaffold(
            title: 'Activity',
            actions: <ShellHeaderActionSpec>[
              ShellHeaderActionSpec(
                icon: FLucideIcons.plus,
                label: 'Primary action',
                onPress: () {},
              ),
              ShellHeaderActionSpec(
                icon: FLucideIcons.filter,
                label: 'Filter action',
                onPress: () {},
                order: 10,
              ),
              ShellHeaderActionSpec(
                icon: FLucideIcons.inbox,
                label: 'Third action',
                onPress: () => thirdActionSelected = true,
                order: 20,
              ),
            ],
            child: const Text('body'),
          ),
          chrome: const ShellChromeBuilders(
            leadingBuilder: _leading,
            headerActionsBuilder: _actions,
          ),
          platform: TargetPlatform.macOS,
        ),
      );

      await tester.tap(find.bySemanticsLabel('More actions'));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey<String>('app-adaptive-action-menu.popover')),
        findsOneWidget,
      );
      expect(find.byType(AppActionSheetList), findsNothing);
      expect(find.text('Third action'), findsOneWidget);

      await tester.tap(find.text('Third action'));
      await tester.pumpAndSettle();
      expect(thirdActionSelected, isTrue);
      expect(find.text('Third action'), findsNothing);
      await _flushTooltipDelay(tester);
    });
  });

  group('ShellCanvasScaffold', () {
    testWidgets('keeps headerless roots inside shell-owned canvas', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(const ShellCanvasScaffold(child: Text('cockpit'))),
      );

      expect(find.text('cockpit'), findsOneWidget);
      expect(find.byType(FHeader), findsNothing);
      expect(find.byType(AppCanvasScaffold), findsOneWidget);
    });
  });

  test('domain tab roots use shell-owned scaffolds', () {
    final violations = <String>[];

    for (final file in _domainTabRootFiles()) {
      final text = file.readAsStringSync();
      final usesShellScaffold =
          text.contains('ShellTabScaffold(') ||
          text.contains('ShellCanvasScaffold(');
      if (!usesShellScaffold) {
        violations.add('${_relative(file.path)}: missing shell scaffold');
      }

      for (final match in _forbiddenRootScaffold.allMatches(text)) {
        violations.add(
          '${_relative(file.path)}: uses ${match.group(1)} directly',
        );
      }
    }

    expect(
      violations,
      isEmpty,
      reason:
          'Top-level domain tab pages must route through ShellTabScaffold or '
          'ShellCanvasScaffold so compact chrome, desktop chrome handoff, '
          'and tab padding stay centralized in core/shell.',
    );
  });
}

Future<void> _flushTooltipDelay(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pumpAndSettle();
}

Widget _leading(BuildContext context, WidgetRef ref) {
  return const Text('domain', key: Key('shell.leading'));
}

List<ShellHeaderActionSpec> _actions(BuildContext context, WidgetRef ref) {
  return <ShellHeaderActionSpec>[
    ShellHeaderActionSpec(
      icon: FLucideIcons.circle,
      label: 'Global action',
      onPress: () {},
      order: 100,
    ),
  ];
}

final _forbiddenRootScaffold = RegExp(
  r'\b(AppPageScaffold|AppCanvasScaffold|DomainTabScaffold|FScaffold)\s*\(',
);

List<File> _domainTabRootFiles() {
  final root = _appRoot();
  return <String>[
    'lib/features/finance/home/ui/home_page.dart',
    'lib/features/finance/activity/ui/activity_page.dart',
    'lib/features/finance/ui/wealth/wealth_hub_page.dart',
    'lib/features/finance/ui/plan_hub_page.dart',
    'lib/features/health/ui/health_today_page.dart',
    'lib/features/health/ui/health_trend_page.dart',
    'lib/features/knowledge/ui/knowledge_inbox_page.dart',
    'lib/features/knowledge/ui/knowledge_library_page.dart',
    'lib/features/knowledge/ui/knowledge_review_page.dart',
    'lib/features/execution/ui/execution_today_page.dart',
    'lib/features/execution/ui/execution_commitments_page.dart',
    'lib/features/execution/ui/execution_review_page.dart',
  ].map((path) => File('${root.path}/$path')).toList(growable: false);
}

Directory _appRoot() {
  var current = Directory.current.absolute;
  while (true) {
    if (File('${current.path}/pubspec.yaml').existsSync() &&
        Directory('${current.path}/lib').existsSync() &&
        Directory('${current.path}/test').existsSync()) {
      return current;
    }
    final parent = current.parent;
    if (parent.path == current.path) {
      throw StateError('Could not locate apps/mobile root');
    }
    current = parent;
  }
}

String _relative(String path) {
  final root = _appRoot().path;
  if (path.startsWith('$root/')) return path.substring(root.length + 1);
  return path;
}
