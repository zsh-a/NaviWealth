import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:naviwealth/core/shell/app_go_route.dart';
import 'package:naviwealth/design_system/design_system.dart';

void main() {
  testWidgets('Flutter Material routes keep transitions and GoRouter state', (
    tester,
  ) async {
    final router = GoRouter(
      routes: [
        AppGoRoute(path: '/', builder: (_, _) => const Text('home')),
        AppGoRoute(
          path: '/record/:id',
          name: 'record',
          builder: (context, state) {
            final inherited = GoRouterState.of(context);
            return Text(
              '${inherited.pathParameters['id']}/'
              '${inherited.uri.queryParameters['mode']}/${state.extra}',
            );
          },
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      MaterialApp.router(theme: AppTheme.light(), routerConfig: router),
    );
    unawaited(router.push<void>('/record/abc?mode=edit', extra: 'prefill'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    final route = ModalRoute.of(tester.element(find.text('abc/edit/prefill')))!;
    expect(route.settings, isA<MaterialPage<void>>());
    expect(route.transitionDuration, Motion.pageTransition);
    expect(route.settings.name, 'record');
    expect(route.settings.arguments, {'id': 'abc', 'mode': 'edit'});
    await tester.pumpAndSettle();
    router.pop();
    await tester.pumpAndSettle();
    expect(find.text('home'), findsOneWidget);
  });

  testWidgets(
    'explicit pages, redirect-only routes and exit guards stay intact',
    (tester) async {
      final router = GoRouter(
        initialLocation: '/old',
        routes: [
          AppGoRoute(path: '/old', redirect: (_, _) => '/guarded'),
          AppGoRoute(path: '/', builder: (_, _) => const Text('home')),
          AppGoRoute(
            path: '/guarded',
            onExit: (_, _) => false,
            pageBuilder: (_, state) => NoTransitionPage<void>(
              key: state.pageKey,
              child: const Text('guarded'),
            ),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        MaterialApp.router(theme: AppTheme.light(), routerConfig: router),
      );
      expect(find.text('guarded'), findsOneWidget);
      expect(
        ModalRoute.of(tester.element(find.text('guarded')))!.transitionDuration,
        Duration.zero,
      );
      router.go('/');
      await tester.pumpAndSettle();
      expect(find.text('guarded'), findsOneWidget);
      expect(find.text('home'), findsNothing);
    },
  );
}
