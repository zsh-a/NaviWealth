import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';

import '../routing/router.dart';

typedef ShareIntentNavigationSink = void Function(String destinationPath);

final shareIntentNavigationSinkProvider = Provider<ShareIntentNavigationSink>(
  (_) => (_) {},
);

List<Override> appShareIntentNavigationOverrides() {
  return [
    shareIntentNavigationSinkProvider.overrideWith((ref) {
      return (destinationPath) =>
          ref.read(appRouterProvider).go(destinationPath);
    }),
  ];
}
