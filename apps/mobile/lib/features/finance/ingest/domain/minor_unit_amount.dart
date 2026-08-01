/// Formats an integer minor-unit amount with exactly two fractional digits.
///
/// This avoids routing persisted money through binary floating point.
String formatMinorUnitAmount(int minorUnits) {
  final value = BigInt.from(minorUnits);
  return _formatMinorUnitMagnitude(value.abs(), negative: value.isNegative);
}

/// Formats the magnitude of a signed minor-unit amount.
String formatAbsoluteMinorUnitAmount(int minorUnits) {
  return _formatMinorUnitMagnitude(BigInt.from(minorUnits).abs());
}

String _formatMinorUnitMagnitude(BigInt absolute, {bool negative = false}) {
  final major = absolute ~/ BigInt.from(100);
  final minor = (absolute % BigInt.from(100)).toString().padLeft(2, '0');
  return '${negative ? '-' : ''}$major.$minor';
}

/// Parses a user-entered non-negative decimal into integer minor units.
///
/// At most two fractional digits are accepted because ingest drafts currently
/// persist currencies at a two-decimal minor-unit scale. Invalid, negative,
/// or out-of-range values return `null` instead of being rounded.
int? parseUnsignedMinorUnitAmount(String input) {
  return _parseMinorUnitAmount(input, allowNegative: false);
}

/// Parses a signed decimal into an integer minor-unit amount exactly.
///
/// A leading minus sign is supported for statement formats that classify
/// refunds or repayments by direction. Positive and negative values are
/// bounded to SQLite's signed 64-bit integer range.
int? parseMinorUnitAmount(String input) {
  return _parseMinorUnitAmount(input, allowNegative: true);
}

int? _parseMinorUnitAmount(String input, {required bool allowNegative}) {
  final value = input.trim();
  final match = RegExp(
    r'^(-?)(?:(\d+)(?:\.(\d{0,2}))?|\.(\d{1,2}))$',
  ).firstMatch(value);
  if (match == null) return null;
  final negative = match.group(1) == '-';
  if (negative && !allowNegative) return null;

  final major = BigInt.tryParse(match.group(2) ?? '0');
  final fraction = match.group(3) ?? match.group(4) ?? '';
  final minor = BigInt.from(int.tryParse(fraction.padRight(2, '0')) ?? 0);
  if (major == null) return null;

  final unsigned = major * BigInt.from(100) + minor;
  final maxSigned64 = BigInt.from(9223372036854775807);
  final minSigned64 = -maxSigned64 - BigInt.one;
  final signed = negative ? -unsigned : unsigned;
  if (signed < minSigned64 || signed > maxSigned64) return null;
  return signed.toInt();
}
