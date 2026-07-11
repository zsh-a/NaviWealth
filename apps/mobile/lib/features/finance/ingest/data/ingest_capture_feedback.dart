import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'ingest_capture_policy.dart';

sealed class IngestCaptureFeedback {
  const IngestCaptureFeedback();
}

final class IngestCaptureFailureFeedback extends IngestCaptureFeedback {
  const IngestCaptureFailureFeedback(this.failure);

  final IngestCaptureFailure failure;
}

enum IngestProcessingFailureCode { rejected, failed }

final class IngestProcessingFailureFeedback extends IngestCaptureFeedback {
  const IngestProcessingFailureFeedback(this.code);

  final IngestProcessingFailureCode code;
}

class IngestCaptureFeedbackEvent {
  const IngestCaptureFeedbackEvent({required this.id, required this.feedback});

  final int id;
  final IngestCaptureFeedback feedback;
}

class IngestCaptureFeedbackQueue
    extends Notifier<List<IngestCaptureFeedbackEvent>> {
  IngestCaptureFeedbackQueue({
    List<IngestCaptureFeedbackEvent> initialEvents = const [],
  }) : _initialEvents = List.unmodifiable(initialEvents);

  final List<IngestCaptureFeedbackEvent> _initialEvents;
  var _nextId = 0;

  @override
  List<IngestCaptureFeedbackEvent> build() {
    for (final event in _initialEvents) {
      if (event.id > _nextId) _nextId = event.id;
    }
    return _initialEvents;
  }

  void enqueueCaptureFailure(IngestCaptureFailure failure) {
    _enqueue(IngestCaptureFailureFeedback(failure));
  }

  void enqueueProcessingFailure(IngestProcessingFailureCode code) {
    _enqueue(IngestProcessingFailureFeedback(code));
  }

  List<IngestCaptureFeedbackEvent> drain() {
    if (state.isEmpty) return const [];
    final drained = state;
    state = const [];
    return drained;
  }

  void _enqueue(IngestCaptureFeedback feedback) {
    final event = IngestCaptureFeedbackEvent(id: ++_nextId, feedback: feedback);
    state = List.unmodifiable([...state, event]);
  }
}

final ingestCaptureFeedbackQueueProvider =
    NotifierProvider<
      IngestCaptureFeedbackQueue,
      List<IngestCaptureFeedbackEvent>
    >(IngestCaptureFeedbackQueue.new);
