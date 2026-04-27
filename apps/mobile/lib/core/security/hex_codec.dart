import 'dart:typed_data';

const _hexAlphabet = '0123456789abcdef';

String hexEncode(List<int> bytes) {
  final out = StringBuffer();
  for (final b in bytes) {
    out.write(_hexAlphabet[(b >> 4) & 0xf]);
    out.write(_hexAlphabet[b & 0xf]);
  }
  return out.toString();
}

Uint8List hexDecode(String hex) {
  if (hex.length.isOdd) {
    throw const FormatException('Hex string must have even length');
  }
  final out = Uint8List(hex.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    out[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return out;
}
