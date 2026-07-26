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
  String? _submissionFailureMessage;

  /// Persistent, user-safe failure copy for the mounted form.
  ///
  /// Toasts remain useful for transient global feedback, but a failed commit
  /// must also stay visible beside the user's preserved input until they
  /// retry. Forms render this through [AppStatusBanner].
  String? get submissionFailureMessage => _submissionFailureMessage;

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
    AppLogOperation? diagnosticOperation,
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
          diagnosticOperation: diagnosticOperation,
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
    AppLogOperation? diagnosticOperation,
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
      diagnosticOperation: diagnosticOperation,
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
    required AppLogOperation? diagnosticOperation,
  }) async {
    // Preserve the element before any async gap. It remains safe to pass to
    // AppMessenger after navigation because the toaster lookup catches an
    // unmounted element and falls back to the cached overlay.
    final feedbackContext = context;
    final logger = ref.read(loggerProvider);
    final operation =
        diagnosticOperation ??
        logger.startOperation('form.submit', fields: {'form_type': tag});
    if (_submissionFailureMessage != null && mounted) {
      setState(() => _submissionFailureMessage = null);
    }
    onBusyChanged(true);
    dirty.busy = true;
    var committed = false;
    try {
      final result = await operation.step(
        'commit',
        commit,
        // A caller-owned operation may contain more precise child stages.
        // Keep this parent failure at debug and emit one terminal error below.
        failureLevel: diagnosticOperation == null
            ? AppLogLevel.warning
            : AppLogLevel.debug,
      );
      committed = true;
      if (!mounted) {
        operation.complete(outcome: 'committed_detached');
        return;
      }

      if (onCommitted != null) {
        try {
          onCommitted(result);
        } catch (error, stack) {
          // The local write is already durable. A receipt/undo decoration
          // failure must never make the form look retryable and duplicate it.
          logger.event(
            '${operation.name}.post_commit_callback.failed',
            operationId: operation.operationId,
            level: AppLogLevel.error,
            fields: const {
              'stage': 'post_commit_callback',
              'outcome': 'failed',
            },
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
          logger.event(
            '${operation.name}.undo_builder.failed',
            operationId: operation.operationId,
            level: AppLogLevel.error,
            fields: const {'stage': 'undo_builder', 'outcome': 'failed'},
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
      await operation.step(
        'publish_pristine_state',
        _nextFrame,
        slowThreshold: const Duration(seconds: 1),
      );
      if (!mounted || !feedbackContext.mounted) {
        operation.complete(outcome: 'committed_detached');
        return;
      }
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
      operation.complete();
    } catch (error, stack) {
      if (committed) {
        operation.complete(
          outcome: 'committed_feedback_failed',
          fields: {'error_code': diagnosticErrorCode(error)},
        );
        rethrow;
      }
      operation.fail(
        error,
        stackTrace: stack,
        stage: 'commit',
        retryable: true,
      );
      if (mounted) {
        final message = failureMessage(error);
        setState(() => _submissionFailureMessage = message);
        AppMessenger.show(
          context,
          ToastKind.error,
          message,
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
  final operation = logger.startOperation(
    'form.undo',
    fields: {'form_type': tag},
  );
  try {
    final changed = await operation.step('apply', action.call);
    if (changed) {
      AppMessenger.show(
        context, // ignore: use_build_context_synchronously -- overlay cached above
        ToastKind.success,
        successMessage,
      );
    }
    operation.complete(outcome: changed ? 'success' : 'noop');
  } catch (error, stack) {
    operation.fail(error, stackTrace: stack, stage: 'apply', retryable: true);
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
