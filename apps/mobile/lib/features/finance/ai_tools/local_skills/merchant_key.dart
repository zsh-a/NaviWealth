/// Normalised "merchant key" used by classifiers and matchers.
///
/// Goal: collapse the noisy raw description (`"STARBUCKS 04291"`,
/// `"AMAZON.COM*XB12K"`, `"星巴克咖啡北京店"`) into a stable token
/// that can be used as a hash key or alias-table lookup.
///
/// Strategy: lowercase, then return the first contiguous run of
/// letters (latin or CJK). Discards trailing transaction codes,
/// dates, location suffixes. Returns the empty string when the
/// description has no letters at all.
library;

final RegExp _firstWordRun = RegExp(r'[一-鿿]+|[a-z]+');

String merchantKey(String description) {
  final lower = description.toLowerCase();
  final match = _firstWordRun.firstMatch(lower);
  return match?.group(0) ?? '';
}
