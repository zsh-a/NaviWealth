import 'package:flutter/widgets.dart';

/// Parses a persisted account color (`#RRGGBB`, `RRGGBB`, `#AARRGGBB`, or
/// `AARRGGBB`) into a Flutter [Color].
///
/// This is data decoding for user-selected account colors, not a design token.
/// UI code should still use theme, semantic, and palette tokens for app chrome.
Color? parseAccountColor(String? value) {
  if (value == null || value.isEmpty) return null;
  var hex = value.startsWith('#') ? value.substring(1) : value;
  if (hex.length == 6) hex = 'FF$hex';
  if (hex.length != 8) return null;
  final parsed = int.tryParse(hex, radix: 16);
  if (parsed == null) return null;
  return Color(parsed);
}
