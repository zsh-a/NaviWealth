import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderListenable;
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/features/finance/data/repositories/providers.dart';

void main() {
  test(
    'accountsStreamProvider stops a stale build after seed disposal',
    () => _disposeDuringSeed(accountsStreamProvider),
  );

  test(
    'allAccountsStreamProvider stops a stale build after seed disposal',
    () => _disposeDuringSeed(allAccountsStreamProvider),
  );
}

Future<void> _disposeDuringSeed<T>(
  ProviderListenable<AsyncValue<T>> provider,
) async {
  final seedStarted = Completer<void>();
  final seedGate = Completer<void>();
  final container = ProviderContainer(
    overrides: [
      systemAccountsSeedProvider.overrideWith((ref) {
        seedStarted.complete();
        return seedGate.future;
      }),
    ],
  );
  addTearDown(container.dispose);

  final subscription = container.listen(provider, (_, _) {});
  addTearDown(subscription.close);

  await seedStarted.future;
  subscription.close();
  // Auto-dispose runs after the current provider notification cycle. Let it
  // finish before releasing the awaited seed, which simulates a page leaving
  // while account initialization is still in flight.
  await pumpEventQueue();

  seedGate.complete();
  await pumpEventQueue();
}
