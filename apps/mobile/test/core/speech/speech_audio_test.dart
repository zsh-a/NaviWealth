import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/speech/speech_audio.dart';

void main() {
  test('converts little-endian PCM16 to normalized float samples', () {
    final input = Uint8List.fromList(<int>[
      0x00, 0x80, // -32768
      0x00, 0x00, // 0
      0xff, 0x7f, // 32767
    ]);

    final samples = pcm16BytesToFloat32(input);

    expect(samples, hasLength(3));
    expect(samples[0], -1.0);
    expect(samples[1], 0.0);
    expect(samples[2], closeTo(0.999969, 0.000001));
  });

  test('ignores a trailing incomplete PCM byte', () {
    final samples = pcm16BytesToFloat32(Uint8List.fromList(<int>[1, 0, 7]));
    expect(samples, hasLength(1));
  });
}
