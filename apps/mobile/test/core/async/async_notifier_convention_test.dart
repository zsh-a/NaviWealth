// Verifies the conventions documented in
// `lib/core/async/async_notifier_convention.dart` actually behave as the
// docstring promises:
//   - build() runs the fetch, errors surface as AsyncError
//   - refresh() preserves the previous data while reloading
//   - mutate() routes errors through AsyncValue
//
// The tests use a tiny in-memory data source so the focus stays on the
// state-machine behavior, not on any specific feature module.

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/async/async_notifier_convention.dart';

class _Source {
  Object? failWith;
  int loads = 0;
  List<int> nextPayload = [1, 2, 3];
  Completer<void>? gate;

  Future<List<int>> load() async {
    loads += 1;
    if (gate != null) {
      await gate!.future;
    }
    if (failWith != null) {
      throw failWith!;
    }
    return List<int>.from(nextPayload);
  }
}

class _ListNotifier extends ConventionalAsyncNotifier<List<int>> {
  @override
  Future<List<int>> fetch() => ref.read(_sourceProvider).load();
}

class _NoPreviousListNotifier extends ConventionalAsyncNotifier<List<int>> {
  @override
  bool get keepPreviousOnRefresh => false;

  @override
  Future<List<int>> fetch() => ref.read(_sourceProvider).load();
}

final _sourceProvider = Provider<_Source>((_) => _Source());
final _listProvider = AsyncNotifierProvider<_ListNotifier, List<int>>(
  _ListNotifier.new,
);
final _noPreviousListProvider =
    AsyncNotifierProvider<_NoPreviousListNotifier, List<int>>(
      _NoPreviousListNotifier.new,
    );

void main() {
  test('build() resolves with the fetched payload', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final value = await container.read(_listProvider.future);
    expect(value, [1, 2, 3]);
    expect(container.read(_sourceProvider).loads, 1);
  });

  test('build() errors surface as AsyncError', () async {
    final source = _Source()..failWith = StateError('boom');
    final container = ProviderContainer(
      overrides: [_sourceProvider.overrideWithValue(source)],
    );
    addTearDown(container.dispose);

    await expectLater(
      container.read(_listProvider.future),
      throwsA(isA<StateError>()),
    );
    expect(container.read(_listProvider).hasError, isTrue);
  });

  test('refresh() keeps previous data attached during reload', () async {
    final source = _Source();
    final container = ProviderContainer(
      overrides: [_sourceProvider.overrideWithValue(source)],
    );
    addTearDown(container.dispose);

    // Initial build resolves with [1, 2, 3].
    await container.read(_listProvider.future);
    expect(container.read(_listProvider).value, [1, 2, 3]);

    // Gate the next fetch so we can observe the in-flight state.
    source
      ..nextPayload = [4, 5, 6]
      ..gate = Completer<void>();

    final notifier = container.read(_listProvider.notifier);
    final refreshing = notifier.refresh();

    // While the gated load is in flight, state is loading but previous data
    // is still attached — this is the contract refresh() exists to enforce.
    final inFlight = container.read(_listProvider);
    expect(inFlight.isLoading, isTrue);
    expect(inFlight.value, [1, 2, 3]);

    source.gate!.complete();
    await refreshing;

    expect(container.read(_listProvider).value, [4, 5, 6]);
    expect(source.loads, 2);
  });

  test(
    'refresh() routes fetch errors through AsyncError without throwing',
    () async {
      final source = _Source();
      final container = ProviderContainer(
        overrides: [_sourceProvider.overrideWithValue(source)],
      );
      addTearDown(container.dispose);

      await container.read(_listProvider.future);
      source.failWith = StateError('refresh failed');

      await container.read(_listProvider.notifier).refresh();

      final state = container.read(_listProvider);
      expect(state.hasError, isTrue);
      expect(state.error, isA<StateError>());
    },
  );

  test('refresh() can mark stale display as a full reload', () async {
    final source = _Source();
    final container = ProviderContainer(
      overrides: [_sourceProvider.overrideWithValue(source)],
    );
    addTearDown(container.dispose);

    await container.read(_noPreviousListProvider.future);
    expect(container.read(_noPreviousListProvider).value, [1, 2, 3]);

    source
      ..nextPayload = [7, 8, 9]
      ..gate = Completer<void>();

    final refreshing = container
        .read(_noPreviousListProvider.notifier)
        .refresh();

    final inFlight = container.read(_noPreviousListProvider);
    expect(inFlight.isLoading, isTrue);
    expect(inFlight.isReloading, isTrue);
    expect(inFlight.isRefreshing, isFalse);

    source.gate!.complete();
    await refreshing;

    expect(container.read(_noPreviousListProvider).value, [7, 8, 9]);
    expect(source.loads, 2);
  });

  test('mutate() routes thrown errors through AsyncError', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container.read(_listProvider.future);
    final notifier = container.read(_listProvider.notifier);

    final result = await notifier.mutate(
      () async => throw StateError('mutation failed'),
    );

    expect(result.hasError, isTrue);
    expect(result.error, isA<StateError>());
    expect(container.read(_listProvider).hasError, isTrue);
  });

  test('mutate() success replaces the data', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container.read(_listProvider.future);
    final notifier = container.read(_listProvider.notifier);

    final result = await notifier.mutate(() async => [9, 9, 9]);

    expect(result.value, [9, 9, 9]);
    expect(container.read(_listProvider).value, [9, 9, 9]);
  });
}
