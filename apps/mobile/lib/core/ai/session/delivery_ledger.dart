import 'interaction_ids.dart';

/// One semantic output unit. The first implementation tracks whole segments
/// rather than string offsets, because Dart/Rust/TTS boundary indices are not
/// interchangeable for Unicode text.
final class OutputSegment {
  const OutputSegment({required this.id, required this.text});

  final String id;
  final String text;
}

/// Records what an output channel actually delivered to the user.
///
/// Generated assistant text lives on [InteractionState]. The ledger only
/// records queued segments and completed delivery acknowledgements. This
/// distinction prevents undelivered TTS text from being fed into the next
/// model turn.
final class DeliveryLedger {
  DeliveryLedger._({
    required List<OutputSegment> segments,
    required Set<String> deliveredSegmentIds,
  }) : segments = List<OutputSegment>.unmodifiable(segments),
       deliveredSegmentIds = Set<String>.unmodifiable(deliveredSegmentIds);

  factory DeliveryLedger.empty() => DeliveryLedger._(
    segments: const <OutputSegment>[],
    deliveredSegmentIds: const <String>{},
  );

  final List<OutputSegment> segments;
  final Set<String> deliveredSegmentIds;

  DeliveryLedger queue(OutputSegment segment) {
    if (segment.id.trim().isEmpty || _indexOf(segment.id) != -1) return this;
    return DeliveryLedger._(
      segments: <OutputSegment>[...segments, segment],
      deliveredSegmentIds: deliveredSegmentIds,
    );
  }

  DeliveryLedger markDelivered(String segmentId) {
    if (_indexOf(segmentId) == -1 || deliveredSegmentIds.contains(segmentId)) {
      return this;
    }
    return DeliveryLedger._(
      segments: segments,
      deliveredSegmentIds: <String>{...deliveredSegmentIds, segmentId},
    );
  }

  bool isDelivered(String segmentId) => deliveredSegmentIds.contains(segmentId);

  String get deliveredText => _text(onlyDelivered: true);

  String get queuedText => _text(onlyDelivered: false);

  ContextProjection project({
    required ResponseEpoch epoch,
    required bool interrupted,
  }) => ContextProjection(
    epoch: epoch,
    deliveredText: deliveredText,
    interrupted: interrupted,
  );

  int _indexOf(String id) => segments.indexWhere((segment) => segment.id == id);

  String _text({required bool onlyDelivered}) => segments
      .where(
        (segment) => !onlyDelivered || deliveredSegmentIds.contains(segment.id),
      )
      .map((segment) => segment.text)
      .join();
}

/// The safe assistant prefix exposed to the next interaction turn.
final class ContextProjection {
  const ContextProjection({
    required this.epoch,
    required this.deliveredText,
    required this.interrupted,
  });

  final ResponseEpoch epoch;
  final String deliveredText;
  final bool interrupted;

  Map<String, Object?> toJson() => <String, Object?>{
    'response_epoch': epoch.value,
    'delivered_text': deliveredText,
    'interrupted': interrupted,
  };
}
