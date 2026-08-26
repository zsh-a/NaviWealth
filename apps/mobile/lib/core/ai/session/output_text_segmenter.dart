import 'delivery_ledger.dart';
import 'interaction_ids.dart';

/// Converts streamed assistant text into semantic output segments.
///
/// Segments are the boundary between generated text and delivery. They are
/// intentionally larger than token deltas so a TTS implementation can start
/// speaking at sentence boundaries without exposing string offsets across
/// Dart/native/provider boundaries.
final class OutputTextSegmenter {
  OutputTextSegmenter({
    this.maxSegmentLength = 160,
    this.firstSegmentLength = 72,
  }) : assert(maxSegmentLength > 0),
       assert(firstSegmentLength > 0);

  final int maxSegmentLength;

  /// A streamed answer should start speaking after a short clause even when
  /// the provider has not emitted a sentence terminator yet. Later segments
  /// stay larger to avoid choppy playback.
  final int firstSegmentLength;

  String _buffer = '';
  ResponseEpoch? _epoch;
  int _nextSegment = 0;

  /// Adds one provider text delta and returns any complete segments.
  List<OutputSegment> add(String delta, {required ResponseEpoch epoch}) {
    _selectEpoch(epoch);
    if (delta.isEmpty) return const <OutputSegment>[];
    _buffer += delta;
    return _drain(flush: false, epoch: epoch);
  }

  /// Flushes the current response tail when the Agent stream completes.
  List<OutputSegment> flush({required ResponseEpoch epoch}) {
    _selectEpoch(epoch);
    return _drain(flush: true, epoch: epoch);
  }

  void _selectEpoch(ResponseEpoch epoch) {
    if (_epoch == epoch) return;
    // Never carry an unspoken tail into a newer response. The old tail is
    // retained only by GeneratedText/trace, not by the delivery queue.
    _epoch = epoch;
    _buffer = '';
    _nextSegment = 0;
  }

  List<OutputSegment> _drain({
    required bool flush,
    required ResponseEpoch epoch,
  }) {
    final segments = <OutputSegment>[];
    while (_buffer.isNotEmpty) {
      final splitAt = _splitPoint(flush: flush);
      if (splitAt == null) break;
      final text = _buffer.substring(0, splitAt);
      _buffer = _buffer.substring(splitAt);
      if (text.trim().isEmpty) continue;
      segments.add(
        OutputSegment(
          id: 'epoch-${epoch.value}-segment-${_nextSegment++}',
          text: text,
        ),
      );
    }
    return List<OutputSegment>.unmodifiable(segments);
  }

  int? _splitPoint({required bool flush}) {
    if (flush) return _buffer.length;

    var boundary = -1;
    for (var index = 0; index < _buffer.length; index++) {
      if (_isSentenceBoundary(_buffer.codeUnitAt(index))) {
        boundary = index + 1;
      }
    }
    if (boundary > 0) return boundary;
    final targetLength = _nextSegment == 0
        ? (firstSegmentLength < maxSegmentLength
              ? firstSegmentLength
              : maxSegmentLength)
        : maxSegmentLength;
    if (_buffer.length < targetLength) return null;

    final limit = targetLength.clamp(1, _buffer.length);
    for (var index = limit; index > 0; index--) {
      final whitespaceAt = index - 1;
      if (whitespaceAt > 0 && _isWhitespace(_buffer.codeUnitAt(whitespaceAt))) {
        return whitespaceAt;
      }
    }
    return limit;
  }
}

bool _isSentenceBoundary(int codeUnit) => switch (codeUnit) {
  0x3002 || // 。
  0x3001 || // 、
  0xff01 || // ！
  0xff1f || // ？
  0xff0c || // ，
  0x21 || // !
  0x3f || // ?
  0x2e || // .
  0x2c || // ,
  0x3b || // ;
  0xff1b || // ；
  0x0a => true,
  _ => false,
};

bool _isWhitespace(int codeUnit) => switch (codeUnit) {
  0x09 || 0x0a || 0x0d || 0x20 => true,
  _ => false,
};
