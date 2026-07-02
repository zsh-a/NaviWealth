import 'package:flutter_riverpod/misc.dart';

import '../features/finance/composition/finance_route_paths.dart';
import '../features/ingest/data/share_intent_navigation.dart';
import '../features/knowledge/composition/knowledge_route_paths.dart';
import 'router.dart';

List<Override> appShareIntentNavigationOverrides() {
  return [
    shareIntentNavigationSinkProvider.overrideWith((ref) {
      return (destination) {
        final location = switch (destination) {
          ShareIntentDestination.financeIngest => FinanceRoutes.activityIngest,
          ShareIntentDestination.knowledgeInbox => KnowledgeRoutes.inbox,
        };
        ref.read(appRouterProvider).go(location);
      };
    }),
  ];
}
