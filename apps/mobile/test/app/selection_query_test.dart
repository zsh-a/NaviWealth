import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:naviwealth/app/routing/route_paths.dart';
import 'package:naviwealth/core/shell/selection_query.dart';

GoRouter _router(String initialLocation) {
  return GoRouter(
    initialLocation: initialLocation,
    routes: [GoRoute(path: AppRoutes.wealth, builder: (_, _) => const _Host())],
  );
}

class _Host extends StatelessWidget {
  const _Host();

  @override
  Widget build(BuildContext context) {
    final selected = selectedQueryOf(context);
    return MaterialApp(
      home: Scaffold(
        body: Column(
          children: [
            Text(selected ?? 'none'),
            TextButton(
              onPressed: () {
                replaceSelectedQuery(
                  context,
                  path: AppRoutes.wealth,
                  selected: 'asset-2',
                );
              },
              child: const Text('select'),
            ),
            TextButton(
              onPressed: () {
                replaceSelectedQuery(
                  context,
                  path: AppRoutes.wealth,
                  selected: null,
                );
              },
              child: const Text('clear'),
            ),
          ],
        ),
      ),
    );
  }
}

String _location(GoRouter router) {
  return router.routeInformationProvider.value.uri.toString();
}

void main() {
  testWidgets('selectedQueryOf reads the selected query parameter', (
    tester,
  ) async {
    final router = _router('${AppRoutes.wealth}?selected=asset-1');
    addTearDown(router.dispose);

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    expect(find.text('asset-1'), findsOneWidget);
  });

  testWidgets('empty selected query is treated as no selection', (
    tester,
  ) async {
    final router = _router('${AppRoutes.wealth}?selected=');
    addTearDown(router.dispose);

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    expect(find.text('none'), findsOneWidget);
  });

  testWidgets('replaceSelectedQuery preserves unrelated query parameters', (
    tester,
  ) async {
    final router = _router('${AppRoutes.wealth}?range=1y&selected=asset-1');
    addTearDown(router.dispose);

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    await tester.tap(find.text('select'));
    await tester.pumpAndSettle();

    expect(_location(router), '${AppRoutes.wealth}?range=1y&selected=asset-2');
  });

  testWidgets(
    'replaceSelectedQuery removes selected without dropping filters',
    (tester) async {
      final router = _router('${AppRoutes.wealth}?range=1y&selected=asset-1');
      addTearDown(router.dispose);

      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();

      await tester.tap(find.text('clear'));
      await tester.pumpAndSettle();

      expect(_location(router), '${AppRoutes.wealth}?range=1y');
    },
  );
}
