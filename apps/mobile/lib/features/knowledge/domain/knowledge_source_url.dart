/// Canonical KnowledgeOS source URL handling.
library;

const int _knowledgeSourceUrlMaxChars = 4096;

/// Returns a stable HTTP(S) source URL, or `null` when [raw] is not a safe
/// external source. Bare hosts are treated as HTTPS for low-friction capture.
/// Fragments are dropped because they do not identify a different document.
String? normalizeKnowledgeSourceUrl(String? raw) {
  var value = raw?.trim() ?? '';
  if (value.isEmpty || value.length > _knowledgeSourceUrlMaxChars) return null;
  if (value.contains(RegExp(r'\s'))) return null;
  if (!value.contains('://')) value = 'https://$value';

  try {
    final uri = Uri.tryParse(value);
    if (uri == null ||
        !uri.hasAuthority ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      return null;
    }
    final scheme = uri.scheme.toLowerCase();
    if (scheme != 'http' && scheme != 'https') return null;
    final host = uri.host.toLowerCase().replaceFirst(RegExp(r'\.$'), '');
    if (host.isEmpty || host.contains(RegExp(r'\s'))) return null;
    final hasDefaultPort =
        (scheme == 'http' && uri.hasPort && uri.port == 80) ||
        (scheme == 'https' && uri.hasPort && uri.port == 443);
    final normalized = uri
        .replace(
          scheme: scheme,
          host: host,
          port: hasDefaultPort ? null : (uri.hasPort ? uri.port : null),
          path: uri.path == '/' ? '' : uri.path,
          fragment: '',
        )
        .toString();
    return normalized.endsWith('#')
        ? normalized.substring(0, normalized.length - 1)
        : normalized;
  } on FormatException {
    return null;
  }
}

Uri? parseKnowledgeSourceUrl(String? raw) {
  final normalized = normalizeKnowledgeSourceUrl(raw);
  return normalized == null ? null : Uri.parse(normalized);
}

String knowledgeSourceHost(Uri uri) =>
    uri.host.replaceFirst(RegExp(r'^www\.', caseSensitive: false), '');
