import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/haptics/haptics.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/logging/providers.dart';
import '../../../design_system/design_system.dart';

/// Holds the [ScaffoldMessenger] used by [OptimisticFormSubmit] so a
/// background-scoped failure toast can still surface after the originating
/// form has popped.
///
/// Wire this into `MaterialApp.router` via [MaterialApp.scaffoldMessengerKey];
/// otherwise [OptimisticFormSubmit.submitOptimistic] will silently log the
/// failure without any user-visible feedback.
final scaffoldMessengerKeyProvider =
    Provider<GlobalKey<ScaffoldMessengerState>>(
      (ref) => GlobalKey<ScaffoldMessengerState>(
        debugLabel: 'NaviWealthScaffoldMessenger',
      ),
    );

/// Builds the snackbar text shown when an optimistic write fails. The
/// underlying error is passed through so callers that want detail (e.g.
/// `TradeEntryException.message`) can surface it; callers that want a
/// generic line can ignore the argument.
typedef OptimisticFailureMessageBuilder = String Function(Object error);

/// "Pop-then-write" form-submit pattern (FIR-98).
///
/// Local Drift writes complete in well under 10 ms, so the
/// `setState(_busy=true) → await write() → snackbar → pop` flow shows a
/// busy state the user never has time to read but does have time to feel
/// as latency. This mixin pops the form first; the list page that takes
/// over is fed by a Riverpod stream that picks up the new row on the
/// next frame. The write runs in the background; failures surface as a
/// global snackbar with a one-tap retry.
///
/// Usage:
///
/// ```dart
/// class _MyFormState extends ConsumerState<MyForm>
///     with OptimisticFormSubmit<MyForm> {
///   Future<void> _save() async {
///     if (!_formKey.currentState!.validate()) return;
///     final repo = await ref.read(myRepoProvider.future);
///     await submitOptimistic(
///       pop: () => context.go('/things'),
///       write: () => repo.create(...),
///       failureMessage: (_) => l10n.myFormSaveFailed,
///       retryLabel: l10n.commonRetry,
///       tag: 'my-thing',
///     );
///   }
/// }
/// ```
///
/// The [write] closure must not capture [BuildContext] or this state's
/// [WidgetRef] — both can be invalidated by the pop. Resolve any async
/// providers (`ref.read(repoProvider.future)`) BEFORE calling
/// [submitOptimistic] so the closure only references local values.
mixin OptimisticFormSubmit<W extends ConsumerStatefulWidget>
    on ConsumerState<W> {
  /// Pops the form immediately, then runs [write] in the background.
  ///
  /// On failure, surfaces a [SnackBar] via [scaffoldMessengerKeyProvider]
  /// with the localized [failureMessage]. When [retryLabel] is non-null,
  /// the snackbar exposes a retry action that re-invokes [write] (no
  /// further pop). The caller is responsible for form validation before
  /// invoking this.
  ///
  /// [pop] is required so each call site can choose between
  /// `Navigator.of(context).pop()`, `context.pop()`, or
  /// `context.go('/...')` without the mixin guessing.
  Future<void> submitOptimistic({
    required VoidCallback pop,
    required Future<void> Function() write,
    required OptimisticFailureMessageBuilder failureMessage,
    String? retryLabel,
    String tag = 'form',
  }) async {
    final logger = ref.read(loggerProvider);
    final ctx = context;
    // Cache the Navigator's overlay before popping so that
    // AppMessenger.show can find it after this widget is disposed.
    AppMessenger.cacheOverlay(context);
    pop();
    await runOptimisticWrite(
      write: write,
      failureMessage: failureMessage,
      logger: logger,
      context: ctx,
      retryLabel: retryLabel,
      tag: tag,
    );
  }

  /// Convenience over [submitOptimistic]: pops to the previous route, or
  /// to [leaveFallback] when the form was deep-linked with no back stack
  /// (via [popOrGo]).
  ///
  /// Prefer this over hand-writing `pop: () => context.go(...)` so every
  /// form leaves the same way and the deep-link fallback stays a real
  /// destination (the owning list/hub) instead of `/`. [onBeforeLeave]
  /// runs synchronously just before the pop — use it for the success
  /// haptic the old `pop:` closures fired inline.
  Future<void> submitOptimisticAndLeave({
    required String leaveFallback,
    required Future<void> Function() write,
    required OptimisticFailureMessageBuilder failureMessage,
    VoidCallback? onBeforeLeave,
    String? retryLabel,
    String tag = 'form',
  }) {
    final ctx = context;
    return submitOptimistic(
      pop: () {
        onBeforeLeave?.call();
        popOrGo(ctx, fallback: leaveFallback);
      },
      write: write,
      failureMessage: failureMessage,
      retryLabel: retryLabel,
      tag: tag,
    );
  }
}

/// Internal helper that runs [write], logs, and surfaces a failure
/// snackbar. Exposed as a top-level function so the snackbar's retry
/// action can re-invoke it without recreating the mixin's host state
/// (which has typically been disposed by the pop).
@visibleForTesting
Future<void> runOptimisticWrite({
  required Future<void> Function() write,
  required OptimisticFailureMessageBuilder failureMessage,
  required AppLogger logger,
  BuildContext? context,
  String? retryLabel,
  String tag = 'form',
}) async {
  try {
    await write();
  } catch (error, stack) {
    logger.e('optimistic-$tag write failed', error: error, stackTrace: stack);
    Haptics.error();
    if (context == null) return;
    AppMessenger.show(
      context, // ignore: use_build_context_synchronously — overlay cached before pop
      ToastKind.error,
      failureMessage(error),
      duration: const Duration(seconds: 6),
      actionLabel: retryLabel,
      onAction: retryLabel == null
          ? null
          : () => runOptimisticWrite(
              write: write,
              failureMessage: failureMessage,
              logger: logger,
              context: context,
              retryLabel: retryLabel,
              tag: tag,
            ),
    );
  }
}
