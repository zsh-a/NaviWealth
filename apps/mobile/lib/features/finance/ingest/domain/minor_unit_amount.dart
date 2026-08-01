/// Formats an integer minor-unit amount with exactly two fractional digits.
///
/// This avoids routing persisted money through binary floating point.
String formatMinorUnitAmount(int minorUnits) {
  final negative = minorUnits < 0;
  final absolute = minorUnits.abs();
  final major = absolute ~/ 100;
  final minor = (absolute % 100).toString().padLeft(2, '0');
  return '${negative ? '-' : ''}$major.$minor';
}

/// Parses a user-entered non-negative decimal into integer minor units.
///
/// At most two fractional digits are accepted because ingest drafts currently
/// persist currencies at a two-decimal minor-unit scale. Invalid, negative,
/// or out-of-range values return `null` instead of being rounded.
int? parseUnsignedMinorUnitAmount(String input) {
  final value = input.trim();
  final match = RegExp(
    r'^(?:(\d+)(?:\.(\d{0,2}))?|\.(\d{1,2}))$',
  ).firstMatch(value);
  if (match == null) return null;

  final major = int.tryParse(match.group(1) ?? '0');
  final fraction = match.group(2) ?? match.group(3) ?? '';
  final minor = int.tryParse(fraction.padRight(2, '0')) ?? 0;
  if (major == null) return null;

  try {
    return major * 100 + minor;
  } on RangeError {
    return null;
  }
}
