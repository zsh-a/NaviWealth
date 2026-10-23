part of 'frb_chat_runner.dart';

Stream<Map<String, Object?>> _cancelableFrbStream(
  Stream<Map<String, Object?>> source,
  CancelToken? cancelToken,
) async* {
  if (cancelToken == null) {
    yield* source;
    return;
  }

  final iterator = StreamIterator<Map<String, Object?>>(source);
  final cancellation = _waitForCancel(cancelToken)
      .then((_) => const _FrbStreamCancelled());
  try {
    while (true) {
      if (cancelToken.isCancelled) {
        yield const <String, Object?>{'kind': kFrbChatStreamCancelledKind};
        return;
      }
      final outcome = await Future.any<_FrbStreamOutcome>([
        iterator.moveNext().then(
          (hasNext) => hasNext
              ? _FrbStreamEvent(iterator.current)
              : const _FrbStreamDone(),
        ),
        cancellation,
      ]);
      switch (outcome) {
        case _FrbStreamCancelled():
          yield const <String, Object?>{'kind': kFrbChatStreamCancelledKind};
          return;
        case _FrbStreamDone():
          return;
        case _FrbStreamEvent(:final event):
          yield event;
      }
    }
  } finally {
    await iterator.cancel();
  }
}

Future<void> _waitForCancel(CancelToken cancelToken) async {
  await cancelToken.whenCancel;
}

String _cancellationCode(CancelToken? token) {
  final reason = token?.cancelError?.error;
  return const {
        'scheduled_task_user_cancelled',
        'scheduled_task_backgrounded',
        'scheduled_task_interrupted',
        'scheduled_task_timeout',
      }.contains(reason)
      ? reason! as String
      : 'cancelled';
}

sealed class _FrbStreamOutcome {
  const _FrbStreamOutcome();
}

final class _FrbStreamEvent extends _FrbStreamOutcome {
  const _FrbStreamEvent(this.event);
  final Map<String, Object?> event;
}

final class _FrbStreamDone extends _FrbStreamOutcome {
  const _FrbStreamDone();
}

final class _FrbStreamCancelled extends _FrbStreamOutcome {
  const _FrbStreamCancelled();
}
