import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../design_system/design_system.dart';
import '../logging/app_logger.dart';
import '../logging/providers.dart';

typedef FormFailureMessageBuilder = String Function(Object error);

/// Builds and presents Undo for a typed repository commit result.
final class FormUndoPresentation<T> {
  const FormUndoPresentation({
    required this.buildAction,
    required this.actionLabel,
    required this.successMessage,
    required this.failureMessage,
    required this.retryLabel,
  });

  final FormUndoAction Function(T result) buildAction;
  final String actionLabel;
  final String successMessage;
  final FormFailureMessageBuilder failureMessage;
  final String retryLabel;
}

/// Commit-first submission protocol for local forms.
///
/// The form remains mounted until [commit] completes. While the operation is
/// in flight, duplicate calls share the same future and [dirty] blocks every
/// dismissal path. A failed commit leaves the user's input intact; pressing
/// the form's submit button is the retry.
mixin FormSubmission<W extends ConsumerStatefulWidget> on ConsumerState<W> {
  Future<void>? _submission;

  /// Commits once, then leaves the form and shows success feedback.
  ///
  /// [onCommitted] receives the typed commit result before navigation. It is
  /// the seam for constructing a [FormUndoAction] from a repository receipt.
  Future<void> submitForm<T>({
    required FormDirtyController dirty,
    required ValueChanged<bool> onBusyChanged,
    required Future<T> Function() commit,
    required VoidCallback leave,
    required FormFailureMessageBuilder failureMessage,
    required String successMessage,
    void Function(T result)? onCommitted,
    FormUndoPresentation<T>? undo,
    String tag = 'form',
  }) {
    final current = _submission;
    if (current != null) return current;

    late final Future<void> operation;
    operation =
        _runSubmission(
          dirty: dirty,
          onBusyChanged: onBusyChanged,
          commit: commit,
          leave: leave,
          failureMessage: failureMessage,
          successMessage: successMessage,
          onCommitted: onCommitted,
          undo: undo,
          tag: tag,
        ).whenComplete(() {
          if (identical(_submission, operation)) _submission = null;
        });
    _submission = operation;
    return operation;
  }

  /// [submitForm] with the app's standard back-stack/deep-link behavior.
  Future<void> submitFormAndLeave<T>({
    required FormDirtyController dirty,
    required ValueChanged<bool> onBusyChanged,
    required String leaveFallback,
    required Future<T> Function() commit,
    required FormFailureMessageBuilder failureMessage,
    required String successMessage,
    void Function(T result)? onCommitted,
    FormUndoPresentation<T>? undo,
    String tag = 'form',
  }) {
    return submitForm<T>(
      dirty: dirty,
      onBusyChanged: onBusyChanged,
      commit: commit,
      leave: () => popOrGo(context, fallback: leaveFallback),
      failureMessage: failureMessage,
      successMessage: successMessage,
      onCommitted: onCommitted,
      undo: undo,
      tag: tag,
    );
  }

  Future<void> _runSubmission<T>({
    required FormDirtyController dirty,
    required ValueChanged<bool> onBusyChanged,
    required Future<T> Function() commit,
    required VoidCallback leave,
    required FormFailureMessageBuilder failureMessage,
    required String successMessage,
    required void Function(T result)? onCommitted,
    required FormUndoPresentation<T>? undo,
    required String tag,
  }) async {
    // Preserve the element before any async gap. It remains safe to pass to
    // AppMessenger after navigation because the toaster lookup catches an
    // unmounted element and falls back to the cached overlay.
    final feedbackContext = context;
    final logger = ref.read(loggerProvider);
    onBusyChanged(true);
    dirty.busy = true;
    var committed = false;
    try {
      final result = await commit();
      committed = true;
      if (!mounted) return;

      if (onCommitted != null) {
        try {
          onCommitted(result);
        } catch (error, stack) {
          // The local write is already durable. A receipt/undo decoration
          // failure must never make the form look retryable and duplicate it.
          logger.e(
            'form-$tag post-commit callback failed',
            error: error,
            stackTrace: stack,
          );
        }
      }

      FormUndoAction? undoAction;
      if (undo != null) {
        try {
          undoAction = undo.buildAction(result);
        } catch (error, stack) {
          logger.e(
            'form-$tag undo builder failed',
            error: error,
            stackTrace: stack,
          );
        }
      }

      dirty.markPristine();
      dirty.busy = false;
      onBusyChanged(false);
      // PopScope reads canPop during build. Give FormDirtyGuard one frame to
      // publish the pristine/non-busy state before asking Navigator to pop.
      await _nextFrame();
      if (!mounted || !feedbackContext.mounted) return;
      AppMessenger.cacheOverlay(feedbackContext);
      leave();
      AppMessenger.show(
        feedbackContext,
        ToastKind.success,
        successMessage,
        actionLabel: undoAction == null ? null : undo!.actionLabel,
        onAction: undoAction == null
            ? null
            : () => unawaited(
                runFormUndoWithFeedback(
                  context: feedbackContext,
                  action: undoAction!,
                  logger: logger,
                  successMessage: undo!.successMessage,
                  failureMessage: undo.failureMessage,
                  retryLabel: undo.retryLabel,
                  tag: tag,
                ),
              ),
      );
    } catch (error, stack) {
      if (committed) rethrow;
      logger.e('form-$tag commit failed', error: error, stackTrace: stack);
      if (mounted) {
        AppMessenger.show(
          context,
          ToastKind.error,
          failureMessage(error),
          duration: const Duration(seconds: 6),
        );
      }
    } finally {
      dirty.busy = false;
      if (mounted) onBusyChanged(false);
    }
  }
}

Future<void> _nextFrame() {
  final completer = Completer<void>();
  WidgetsBinding.instance.addPostFrameCallback((_) => completer.complete());
  WidgetsBinding.instance.scheduleFrame();
  return completer.future;
}

/// A one-shot, retryable undo operation.
///
/// Concurrent calls share one operation. Once it succeeds, future calls are
/// permanent no-ops. A failure clears the in-flight state so the exact same
/// atomic callback can be retried.
final class FormUndoAction {
  FormUndoAction(Future<void> Function() undo) : _undo = undo;

  final Future<void> Function() _undo;
  Future<bool>? _inFlight;
  bool _completed = false;

  bool get completed => _completed;

  Future<bool> call() {
    if (_completed) return Future<bool>.value(false);
    final current = _inFlight;
    if (current != null) return current;

    late final Future<bool> operation;
    operation = _undo()
        .then((_) {
          _completed = true;
          return true;
        })
        .whenComplete(() {
          if (identical(_inFlight, operation)) _inFlight = null;
        });
    _inFlight = operation;
    return operation;
  }
}

/// Runs [action] and reports its localized result through [AppMessenger].
Future<void> runFormUndoWithFeedback({
  required BuildContext context,
  required FormUndoAction action,
  required AppLogger logger,
  required String successMessage,
  required FormFailureMessageBuilder failureMessage,
  required String retryLabel,
  String tag = 'form',
}) async {
  AppMessenger.cacheOverlay(context);
  try {
    final changed = await action();
    if (changed) {
      AppMessenger.show(
        context, // ignore: use_build_context_synchronously -- overlay cached above
        ToastKind.success,
        successMessage,
      );
    }
  } catch (error, stack) {
    logger.e('form-$tag undo failed', error: error, stackTrace: stack);
    AppMessenger.show(
      context, // ignore: use_build_context_synchronously -- overlay cached above
      ToastKind.error,
      failureMessage(error),
      duration: const Duration(seconds: 6),
      actionLabel: retryLabel,
      onAction: () => unawaited(
        runFormUndoWithFeedback(
          context: context,
          action: action,
          logger: logger,
          successMessage: successMessage,
          failureMessage: failureMessage,
          retryLabel: retryLabel,
          tag: tag,
        ),
      ),
    );
  }
}
