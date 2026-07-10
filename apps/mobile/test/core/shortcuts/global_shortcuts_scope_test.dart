import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/shortcuts/global_shortcuts_scope.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: child,
  );
}

/// Runs [body] under a desktop platform override.
///
/// The framework's invariants check runs at the end of the test body — before
/// `tearDown` callbacks — so we restore [debugDefaultTargetPlatformOverride]
/// inside `finally` to keep tests hermetic.
Future<void> _runOnDesktop(
  Future<void> Function() body, {
  TargetPlatform platform = TargetPlatform.macOS,
}) async {
  debugDefaultTargetPlatformOverride = platform;
  try {
    await body();
  } finally {
    debugDefaultTargetPlatformOverride = null;
  }
}

enum _TopRouteKind { dirty, clean }

class _RoutePopObserver extends NavigatorObserver {
  final Map<String, int> _counts = <String, int>{};

  int countFor(String routeName) => _counts[routeName] ?? 0;

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPop(route, previousRoute);
    final name = route.settings.name;
    if (name != null) {
      _counts.update(name, (count) => count + 1, ifAbsent: () => 1);
    }
  }
}

class _ShortcutBackHarness extends StatelessWidget {
  const _ShortcutBackHarness({required this.top, required this.observer});

  final _TopRouteKind top;
  final NavigatorObserver observer;

  @override
  Widget build(BuildContext context) {
    final topName = switch (top) {
      _TopRouteKind.dirty => '/dirty',
      _TopRouteKind.clean => '/clean',
    };
    return MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      navigatorObservers: <NavigatorObserver>[observer],
      onGenerateRoute: (_) => null,
      onGenerateInitialRoutes: (_) => <Route<dynamic>>[
        MaterialPageRoute<void>(
          settings: const RouteSettings(name: '/root'),
          builder: (_) => const Scaffold(body: Text('root-sentinel')),
        ),
        MaterialPageRoute<void>(
          settings: const RouteSettings(name: '/previous'),
          builder: (_) => const Scaffold(body: Text('previous-sentinel')),
        ),
        MaterialPageRoute<void>(
          settings: RouteSettings(name: topName),
          builder: (_) => switch (top) {
            _TopRouteKind.dirty => const _DirtyPopPage(),
            _TopRouteKind.clean => const Scaffold(
              body: Focus(autofocus: true, child: Text('clean-route')),
            ),
          },
        ),
      ],
      builder: (context, child) => GlobalShortcutsScope(
        onSwitchPrimaryTab: (_) {},
        onOpenCommandPalette: (_) {},
        onToggleSidebar: () {},
        onOpenAiChat: (_) {},
        onVimGoto: (_) {},
        child: child!,
      ),
    );
  }
}

class _DirtyPopPage extends StatefulWidget {
  const _DirtyPopPage();

  @override
  State<_DirtyPopPage> createState() => _DirtyPopPageState();
}

class _DirtyPopPageState extends State<_DirtyPopPage> {
  final _controller = TextEditingController();
  var _dirty = false;
  var _confirmOpen = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_markDirty);
  }

  void _markDirty() {
    if (!_dirty && mounted) setState(() => _dirty = true);
  }

  Future<void> _onPopInvoked(bool didPop, Object? result) async {
    if (didPop || !_dirty || _confirmOpen) return;
    _confirmOpen = true;
    final discard = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Discard changes?'),
        content: const Text('Unsaved edits will be lost.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Keep Editing'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    _confirmOpen = false;
    if (discard != true || !mounted) return;
    setState(() => _dirty = false);
    await WidgetsBinding.instance.endOfFrame;
    if (mounted) Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _controller.removeListener(_markDirty);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope<Object?>(
      canPop: !_dirty,
      onPopInvokedWithResult: _onPopInvoked,
      child: Scaffold(
        body: TextField(
          key: const Key('dirty-field'),
          controller: _controller,
          autofocus: true,
        ),
      ),
    );
  }
}

void main() {
  group('GlobalShortcutsScope', () {
    testWidgets('digit key dispatches SwitchPrimaryTabIntent with the index', (
      tester,
    ) async {
      await _runOnDesktop(() async {
        final dispatched = <int>[];
        await tester.pumpWidget(
          _wrap(
            GlobalShortcutsScope(
              onSwitchPrimaryTab: dispatched.add,
              onOpenCommandPalette: (_) {},
              onToggleSidebar: () {},
              onOpenAiChat: (_) {},
              onVimGoto: (_) {},
              child: const Scaffold(
                body: Focus(autofocus: true, child: SizedBox()),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.sendKeyEvent(LogicalKeyboardKey.digit2);
        await tester.pumpAndSettle();

        expect(dispatched, [1]);
      });
    });

    testWidgets('Cmd+K invokes the command palette callback', (tester) async {
      await _runOnDesktop(() async {
        var called = 0;
        await tester.pumpWidget(
          _wrap(
            GlobalShortcutsScope(
              onSwitchPrimaryTab: (_) {},
              onOpenCommandPalette: (_) => called++,
              onToggleSidebar: () {},
              onOpenAiChat: (_) {},
              onVimGoto: (_) {},
              child: const Scaffold(
                body: Focus(autofocus: true, child: SizedBox()),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
        await tester.pumpAndSettle();

        expect(called, 1);
      });
    });

    testWidgets('digit keys are suppressed while a TextField has focus', (
      tester,
    ) async {
      await _runOnDesktop(() async {
        final dispatched = <int>[];
        final controller = TextEditingController();
        addTearDown(controller.dispose);
        await tester.pumpWidget(
          _wrap(
            GlobalShortcutsScope(
              onSwitchPrimaryTab: dispatched.add,
              onOpenCommandPalette: (_) {},
              onToggleSidebar: () {},
              onOpenAiChat: (_) {},
              onVimGoto: (_) {},
              child: Scaffold(
                body: Center(
                  child: TextField(controller: controller, autofocus: true),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.binding.focusManager.primaryFocus, isNotNull);

        await tester.sendKeyEvent(LogicalKeyboardKey.digit2);
        await tester.pumpAndSettle();

        expect(
          dispatched,
          isEmpty,
          reason: 'typing into a field must not switch app tabs',
        );
      });
    });

    testWidgets('Esc pops the topmost dialog', (tester) async {
      await _runOnDesktop(() async {
        final navigatorKey = GlobalKey<NavigatorState>();
        await tester.pumpWidget(
          MaterialApp(
            navigatorKey: navigatorKey,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: GlobalShortcutsScope(
              onSwitchPrimaryTab: (_) {},
              onOpenCommandPalette: (_) {},
              onToggleSidebar: () {},
              onOpenAiChat: (_) {},
              onVimGoto: (_) {},
              child: const Scaffold(body: SizedBox.expand()),
            ),
          ),
        );
        await tester.pumpAndSettle();

        unawaited(
          showDialog<void>(
            context: navigatorKey.currentContext!,
            builder: (_) => const AlertDialog(content: Text('hello')),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('hello'), findsOneWidget);

        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();

        expect(find.text('hello'), findsNothing);
      });
    });

    testWidgets('Esc respects dirty PopScope confirmation and pops once', (
      tester,
    ) async {
      await _runOnDesktop(() async {
        final observer = _RoutePopObserver();
        await tester.pumpWidget(
          _ShortcutBackHarness(top: _TopRouteKind.dirty, observer: observer),
        );
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const Key('dirty-field')),
          'keep this edit',
        );
        await tester.pump();

        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();

        expect(find.text('Discard changes?'), findsOneWidget);
        expect(observer.countFor('/dirty'), 0);

        await tester.tap(find.text('Keep Editing'));
        await tester.pumpAndSettle();
        expect(find.byType(_DirtyPopPage), findsOneWidget);
        expect(
          tester
              .widget<TextField>(find.byKey(const Key('dirty-field')))
              .controller!
              .text,
          'keep this edit',
        );

        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(find.text('Discard changes?'), findsOneWidget);
        await tester.tap(find.text('Discard'));
        await tester.pumpAndSettle();

        expect(find.byType(_DirtyPopPage), findsNothing);
        expect(find.text('previous-sentinel'), findsOneWidget);
        expect(observer.countFor('/dirty'), 1);
      });
    });

    testWidgets('Esc pops a clean route exactly once', (tester) async {
      await _runOnDesktop(() async {
        final observer = _RoutePopObserver();
        await tester.pumpWidget(
          _ShortcutBackHarness(top: _TopRouteKind.clean, observer: observer),
        );
        await tester.pumpAndSettle();

        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();

        expect(find.text('clean-route'), findsNothing);
        expect(find.text('previous-sentinel'), findsOneWidget);
        expect(observer.countFor('/clean'), 1);
      });
    });
  });

  testWidgets('is a transparent passthrough on native mobile platforms', (
    tester,
  ) async {
    // kIsWeb is a compile-time constant so we can only assert the native
    // mobile branch here. On Web the scope is always active, which is
    // covered by the desktop tests above.
    if (kIsWeb) return;

    await _runOnDesktop(platform: TargetPlatform.iOS, () async {
      final dispatched = <int>[];
      await tester.pumpWidget(
        _wrap(
          GlobalShortcutsScope(
            onSwitchPrimaryTab: dispatched.add,
            onOpenCommandPalette: (_) {},
            onToggleSidebar: () {},
            onOpenAiChat: (_) {},
            onVimGoto: (_) {},
            child: const Scaffold(
              body: Focus(autofocus: true, child: SizedBox()),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.digit2);
      await tester.pumpAndSettle();

      expect(dispatched, isEmpty);
    });
  });
}
