part of '../ingest_review_page.dart';

/// Subscribes to the capture feedback queue and drains queued events into
/// error toasts once per frame, without rebuilding the wrapped subtree.
class IngestCaptureFeedbackListener extends ConsumerStatefulWidget {
  const IngestCaptureFeedbackListener({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<IngestCaptureFeedbackListener> createState() =>
      _IngestCaptureFeedbackListenerState();
}

class _IngestCaptureFeedbackListenerState
    extends ConsumerState<IngestCaptureFeedbackListener> {
  ProviderSubscription<List<IngestCaptureFeedbackEvent>>? _subscription;
  bool _drainScheduled = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _subscription != null) return;
      _subscription = ref.listenManual(ingestCaptureFeedbackQueueProvider, (
        _,
        events,
      ) {
        if (events.isNotEmpty) _scheduleDrain();
      }, fireImmediately: true);
    });
  }

  @override
  void dispose() {
    _subscription?.close();
    super.dispose();
  }

  void _scheduleDrain() {
    if (_drainScheduled) return;
    _drainScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _drainScheduled = false;
      if (!mounted) return;
      final events = ref
          .read(ingestCaptureFeedbackQueueProvider.notifier)
          .drain();
      final l10n = AppLocalizations.of(context);
      for (final event in events) {
        AppMessenger.show(
          context,
          ToastKind.error,
          localizedIngestCaptureFeedback(l10n, event),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
