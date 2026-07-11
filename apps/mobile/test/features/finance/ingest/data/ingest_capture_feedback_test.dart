import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/features/finance/ingest/data/ingest_capture_feedback.dart';
import 'package:naviwealth/features/finance/ingest/data/ingest_capture_policy.dart';

void main() {
  test('feedback queue preserves every event and drains atomically', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final queue = container.read(ingestCaptureFeedbackQueueProvider.notifier);

    queue
      ..enqueueCaptureFailure(
        const IngestCaptureFailure(IngestCaptureFailureCode.tooLarge),
      )
      ..enqueueProcessingFailure(IngestProcessingFailureCode.rejected)
      ..enqueueProcessingFailure(IngestProcessingFailureCode.failed);

    expect(
      container
          .read(ingestCaptureFeedbackQueueProvider)
          .map((event) => event.id),
      [1, 2, 3],
    );
    final drained = queue.drain();
    expect(drained.map((event) => event.id), [1, 2, 3]);
    expect(container.read(ingestCaptureFeedbackQueueProvider), isEmpty);

    queue.enqueueCaptureFailure(
      const IngestCaptureFailure(IngestCaptureFailureCode.empty),
    );
    expect(container.read(ingestCaptureFeedbackQueueProvider).single.id, 4);
  });

  test('initial events advance the unique event id', () {
    final container = ProviderContainer(
      overrides: [
        ingestCaptureFeedbackQueueProvider.overrideWith(
          () => IngestCaptureFeedbackQueue(
            initialEvents: const [
              IngestCaptureFeedbackEvent(
                id: 7,
                feedback: IngestProcessingFailureFeedback(
                  IngestProcessingFailureCode.failed,
                ),
              ),
            ],
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    final queue = container.read(ingestCaptureFeedbackQueueProvider.notifier);

    queue.enqueueProcessingFailure(IngestProcessingFailureCode.rejected);

    expect(container.read(ingestCaptureFeedbackQueueProvider).last.id, 8);
  });
}
