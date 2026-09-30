import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../design_system/design_system.dart';
import '../auth/providers.dart';
import '../logging/app_logger.dart';

typedef FormFailureMessageBuilder = String Function(Object error);

/// A short-lived business receipt. Repository callbacks own conflict checks;
/// presentation never fabricates an undo for operations without a receipt.
final class FormUndoOffer {
  FormUndoOffer({
    required this.message,
    required this.action,
    required this.actionLabel,
    required this.successMessage,
    required this.failureMessage,
    required this.retryLabel,
    this.tag = 'form',
  }) : expiresAt = DateTime.now().add(const Duration(seconds: 60));

  final String message;
  final FormUndoAction action;
  final String actionLabel;
  final String successMessage;
  final FormFailureMessageBuilder failureMessage;
  final String retryLabel;
  final String tag;
  final DateTime expiresAt;

  bool get available => !action.completed && DateTime.now().isBefore(expiresAt);
}

final formUndoOfferProvider = NotifierProvider<FormUndoOffers, FormUndoOffer?>(
  FormUndoOffers.new,
);

/// Survives page navigation, expires automatically, and clears on account
/// changes. This is session UI state; durable AI undo keeps its own store.
class FormUndoOffers extends Notifier<FormUndoOffer?> {
  Timer? _expiry;

  @override
  FormUndoOffer? build() {
    ref.watch(authSessionProvider.select((session) => session?.userId));
    _expiry?.cancel();
    ref.onDispose(() => _expiry?.cancel());
    return null;
  }

  void offer(FormUndoOffer value) {
    _expiry?.cancel();
    state = value;
    _expiry = Timer(
      value.expiresAt.difference(DateTime.now()),
      () => dismiss(value),
    );
  }

  void dismiss(FormUndoOffer value) {
    if (!identical(state, value)) return;
    _expiry?.cancel();
    state = null;
  }

  Future<String?> run(
    BuildContext context,
    FormUndoOffer value,
    AppLogger logger,
  ) async {
    if (!identical(state, value) || !value.available) return null;
    String? errorMessage;
    await runFormUndoWithFeedback(
      context: context,
      action: value.action,
      logger: logger,
      successMessage: value.successMessage,
      failureMessage: value.failureMessage,
      retryLabel: value.retryLabel,
      tag: value.tag,
      onFailure: (message) => errorMessage = message,
      onRetry: () => unawaited(run(context, value, logger)),
    );
    if (ref.mounted && value.action.completed) dismiss(value);
    return errorMessage;
  }
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
  ValueChanged<String>? onFailure,
  VoidCallback? onRetry,
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
    onFailure?.call(failureMessage(error));
    AppMessenger.show(
      context, // ignore: use_build_context_synchronously -- overlay cached above
      ToastKind.error,
      failureMessage(error),
      duration: const Duration(seconds: 6),
      actionLabel: retryLabel,
      onAction:
          onRetry ??
          () => unawaited(
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
