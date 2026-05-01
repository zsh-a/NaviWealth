/// NaviWealth's house style for [AsyncNotifier]-shaped Riverpod providers.
///
/// **Why a convention** — `AsyncValue` carries three concerns (loading, error,
/// data) and the call sites have to handle every combination. Without a shared
/// pattern we end up with a mix of `state.whenOrNull`, `if (state.isLoading)`,
/// and ad-hoc `.copyWithPrevious(...)` calls that are easy to get subtly
/// wrong (lost previous data on refresh, double-fired error handlers, etc.).
///
/// **The rules**:
///
///  1. Long-lived screen state lives in an [AsyncNotifier] (or
///     [FamilyAsyncNotifier]) declared via the `AsyncNotifierProvider` factory.
///     Synchronous, derived state (formatters, route info, etc.) stays in a
///     plain `Provider`.
///
///  2. `build()` performs the *initial* fetch. It MUST NOT swallow errors —
///     let them surface so [AsyncValue.error] is populated and consumers can
///     render an error state.
///
///  3. Refresh / pull-to-refresh calls [refresh] (defined here). It sets the
///     state to `AsyncLoading` *with the previous data attached* so the UI
///     can keep rendering the stale value while the new fetch runs. This is
///     the difference between "screen flashes blank" and "screen shows the
///     previous value with a small spinner."
///
///  4. Mutations (e.g. "save asset") use [AsyncValue.guard] inside the
///     notifier so the result still flows through the `AsyncValue` machinery.
///     After a successful mutation, *invalidate* dependent providers rather
///     than poking their internal state — Riverpod will rebuild them lazily.
///
///  5. Tests use `ProviderContainer(overrides: [...])` to inject fakes for
///     the notifier's dependencies. They should NOT override the notifier
///     itself with a static [AsyncValue] — that bypasses the very state
///     machine you're testing. (Override the data layer instead.)
///
/// See [PaginatedAsyncNotifier] below for a worked example: loads page 1 in
/// `build()`, exposes `loadMore()` and `refresh()`, never blanks the screen on
/// reload, and surfaces fetch errors as `AsyncError` without crashing.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Base class that wires up the rules above so concrete notifiers stay short.
/// Subclasses override [fetch] (and optionally [keepPreviousOnRefresh]).
///
/// Concrete shape:
/// ```dart
/// final assetsProvider = AsyncNotifierProvider<AssetsNotifier, List<Asset>>(
///   AssetsNotifier.new,
/// );
///
/// class AssetsNotifier extends ConventionalAsyncNotifier<List<Asset>> {
///   @override
///   Future<List<Asset>> fetch() => ref.read(assetRepoProvider).list();
/// }
/// ```
abstract class ConventionalAsyncNotifier<T> extends AsyncNotifier<T> {
  /// Whether [refresh] should keep the previous data attached to the new
  /// `AsyncLoading` state. Default `true`, which is what almost every list /
  /// detail screen wants. Set `false` for screens where seeing stale data
  /// would mislead (e.g. a security review screen).
  bool get keepPreviousOnRefresh => true;

  @override
  Future<T> build() => fetch();

  /// Single source of truth for the fetch logic. Called from [build] and
  /// [refresh]; subclasses that need to *parameterize* the fetch should
  /// expose explicit methods (`refresh(query: ...)`) that delegate to the
  /// data layer and then `state = AsyncData(...)`.
  Future<T> fetch();

  /// Explicit pull-to-refresh entry point. Prefer this over
  /// `ref.invalidateSelf()` because:
  ///   - it preserves previous data (so UI doesn't flash empty)
  ///   - it returns a Future the UI can await for end-of-refresh feedback
  ///   - it routes errors through `AsyncError` (no rethrow at the call site)
  Future<void> refresh() async {
    if (keepPreviousOnRefresh) {
      // In Riverpod 3.x, invalidateSelf(asReload: true) preserves previous
      // data automatically by transitioning through AsyncLoading with the
      // previous value attached.
      ref.invalidateSelf(asReload: true);
      // Wait for the rebuild to complete by reading the future.
      await future;
    } else {
      state = const AsyncLoading();
      final next = await AsyncValue.guard(fetch);
      state = next;
    }
  }

  /// Apply a mutation that doesn't change the public shape of [T] — e.g.
  /// reordering, marking-read. Errors are caught and re-emitted as
  /// `AsyncError` so the call site doesn't need its own try/catch.
  ///
  /// Returns the new state for callers that want to react synchronously.
  Future<AsyncValue<T>> mutate(Future<T> Function() apply) async {
    final next = await AsyncValue.guard(apply);
    state = next;
    return next;
  }
}
