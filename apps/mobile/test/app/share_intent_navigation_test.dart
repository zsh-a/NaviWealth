import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:naviwealth/app/router.dart';
import 'package:naviwealth/app/share_intent_navigation.dart';
import 'package:naviwealth/features/finance/composition/finance_route_paths.dart';
import 'package:naviwealth/features/knowledge/composition/knowledge_route_paths.dart';

void main() {
  test('share intent navigation sink delegates destinations to app router', () {
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(path: '/', builder: (_, _) => const SizedBox.shrink()),
        GoRoute(
          path: FinanceRoutes.activityIngest,
          builder: (_, _) => const SizedBox.shrink(),
        ),
        GoRoute(
          path: KnowledgeRoutes.inbox,
          builder: (_, _) => const SizedBox.shrink(),
        ),
      ],
    );
    addTearDown(router.dispose);

    final c = ProviderContainer(
      overrides: [
        appRouterProvider.overrideWithValue(router),
        ...appShareIntentNavigationOverrides(),
      ],
    );
    addTearDown(c.dispose);

    final sink = c.read(shareIntentNavigationSinkProvider);

    sink(FinanceRoutes.activityIngest);
    expect(
      router.routeInformationProvider.value.uri.path,
      FinanceRoutes.activityIngest,
    );

    sink(KnowledgeRoutes.inbox);
    expect(
      router.routeInformationProvider.value.uri.path,
      KnowledgeRoutes.inbox,
    );
  });
}
