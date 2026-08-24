import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/ai/session/interaction_ids.dart';
import 'package:naviwealth/core/ai/session/output_text_segmenter.dart';

void main() {
  const epoch = ResponseEpoch.initial();

  test('emits sentence segments and flushes the final tail', () {
    final segmenter = OutputTextSegmenter();

    expect(segmenter.add('本月消费 12430 元。', epoch: epoch), hasLength(1));
    final tail = segmenter.add('其中房租 5200 元', epoch: epoch);
    expect(tail, isEmpty);

    final flushed = segmenter.flush(epoch: epoch);
    expect(flushed.single.text, '其中房租 5200 元');
    expect(flushed.single.id, 'epoch-0-segment-1');
  });

  test('splits long text at whitespace without leaking across epochs', () {
    final segmenter = OutputTextSegmenter(maxSegmentLength: 8);

    final first = segmenter.add('one two three', epoch: epoch);
    expect(first.single.text, 'one two');
    expect(segmenter.flush(epoch: epoch).single.text, ' three');

    final nextEpoch = epoch.next();
    final second = segmenter.add('新的回答。', epoch: nextEpoch);
    expect(second.single.text, '新的回答。');
    expect(segmenter.flush(epoch: nextEpoch), isEmpty);
  });
}
