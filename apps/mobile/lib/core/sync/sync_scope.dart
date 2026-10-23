import 'dart:convert';

/// The visibility boundary of one pull cursor. Switching owner or expanding
/// domain visibility must never reuse progress from a different boundary.
class SyncScope {
  SyncScope({required this.ownerUserId, required Iterable<String> domains})
    : domains = Set<String>.unmodifiable(domains);

  final String ownerUserId;
  final Set<String> domains;

  String get storageKey {
    final sorted = domains.toList()..sort();
    return base64Url.encode(utf8.encode(jsonEncode([ownerUserId, sorted])));
  }
}
