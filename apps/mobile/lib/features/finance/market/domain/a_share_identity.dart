/// Normalizes provider aliases for comparison without rewriting stored ids.
/// Returns null when the symbol is outside the native SDK's identity grammar.
String? tryCanonicalAShareSymbol(String symbol) {
  final value = symbol.trim().toUpperCase();
  final suffix = RegExp(r'^(\d{6})\.(SH|SS|SZ|BJ)$').firstMatch(value);
  if (suffix != null) {
    return '${suffix[1]}.${suffix[2] == 'SS' ? 'SH' : suffix[2]}';
  }
  final prefix = RegExp(r'^(SH|SZ|BJ)(\d{6})$').firstMatch(value);
  if (prefix != null) return '${prefix[2]}.${prefix[1]}';
  if (RegExp(r'^\d{6}$').hasMatch(value)) {
    if (value.startsWith('5') || value.startsWith('6')) return '$value.SH';
    if (value.startsWith('0') ||
        value.startsWith('1') ||
        value.startsWith('3')) {
      return '$value.SZ';
    }
    if (value.startsWith('4') ||
        value.startsWith('8') ||
        value.startsWith('920')) {
      return '$value.BJ';
    }
  }
  return null;
}
