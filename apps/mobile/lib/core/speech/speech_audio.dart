import 'dart:typed_data';

/// Converts little-endian signed PCM16 microphone bytes to normalized mono
/// samples expected by sherpa-onnx.
Float32List pcm16BytesToFloat32(Uint8List bytes) {
  final sampleCount = bytes.length ~/ 2;
  final samples = Float32List(sampleCount);
  final data = ByteData.sublistView(bytes, 0, sampleCount * 2);
  for (var i = 0; i < sampleCount; i++) {
    samples[i] = data.getInt16(i * 2, Endian.little) / 32768.0;
  }
  return samples;
}
