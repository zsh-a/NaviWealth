import 'dart:convert';

import '../../../core/security/secure_key_store.dart';

/// Owner-scoped GitHub secrets. Browser hosts deliberately use session memory.
///
/// One secure document contains an owner's randomly identified credentials, so
/// reset can delete every token without enumerating platform-secure storage.
/// Every instance shares the write queue, including fresh reset-cleanup hosts.
class BcrGithubCredentials {
  BcrGithubCredentials(this._store, {bool persistent = true})
    : _persistent = persistent;

  static const _prefix = 'naviwealth.knowledge.github.v1.';
  static final _sessions = <String, Map<String, String>>{};
  static Future<void> _pending = Future<void>.value();

  final SecureKeyStore _store;
  final bool _persistent;

  Future<String?> read(String owner, String credentialId) => _serial(() async {
    _validateIdentity(owner);
    _validateIdentity(credentialId);
    return (await _readOwner(owner))[credentialId];
  });

  Future<void> write(String owner, String credentialId, String token) =>
      _serial(() async {
        _validateIdentity(owner);
        _validateIdentity(credentialId);
        _validateToken(token);
        final next = await _readOwner(owner);
        next[credentialId] = token;
        await _saveOwner(owner, next);
      });

  Future<void> delete(String owner, String credentialId) => _serial(() async {
    _validateIdentity(owner);
    _validateIdentity(credentialId);
    final next = await _readOwner(owner);
    if (next.remove(credentialId) != null) await _saveOwner(owner, next);
  });

  /// Explicit cleanup may remove an unreadable document without guessing data.
  Future<void> clearOwner(String owner) => _serial(() async {
    _validateIdentity(owner);
    if (!_persistent) {
      _sessions.remove(owner);
      return;
    }
    try {
      await _store.delete(_key(owner));
    } catch (_) {
      // Platform failures can include stored values; never propagate them.
      throw StateError('GitHub credentials could not be removed.');
    }
  });

  Future<Map<String, String>> _readOwner(String owner) async {
    if (!_persistent) return Map.of(_sessions[owner] ?? const {});
    final String? raw;
    try {
      raw = await _store.read(_key(owner));
    } catch (_) {
      throw StateError('GitHub credentials could not be read.');
    }
    if (raw == null) return <String, String>{};
    try {
      final document = jsonDecode(raw);
      if (document is! Map<String, dynamic> || document['version'] != 1) {
        throw const FormatException();
      }
      final tokens = document['tokens'];
      if (tokens is! Map<String, dynamic>) throw const FormatException();
      final result = <String, String>{};
      for (final entry in tokens.entries) {
        _validateIdentity(entry.key);
        final token = entry.value;
        if (token is! String) throw const FormatException();
        _validateToken(token);
        result[entry.key] = token;
      }
      return result;
    } catch (_) {
      // JSON errors include source text by default, which would expose tokens.
      throw const FormatException('GitHub credentials are unavailable.');
    }
  }

  Future<void> _saveOwner(String owner, Map<String, String> next) async {
    if (!_persistent) {
      if (next.isEmpty) {
        _sessions.remove(owner);
      } else {
        _sessions[owner] = Map.unmodifiable(next);
      }
      return;
    }
    try {
      if (next.isEmpty) {
        await _store.delete(_key(owner));
      } else {
        await _store.write(
          _key(owner),
          jsonEncode({'version': 1, 'tokens': next}),
        );
      }
    } catch (_) {
      throw StateError('GitHub credentials could not be saved.');
    }
  }

  static String _key(String owner) =>
      '$_prefix${base64Url.encode(utf8.encode(owner)).replaceAll('=', '')}';

  static Future<T> _serial<T>(Future<T> Function() action) {
    final operation = _pending.then<T>((_) => action());
    // One failed operation must not prevent cleanup or subsequent repairs.
    _pending = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return operation;
  }

  static void _validateIdentity(String value) {
    if (value.trim().isEmpty) {
      throw const FormatException('Invalid GitHub credential identity.');
    }
  }

  static void _validateToken(String value) {
    if (value.trim().isEmpty ||
        value.contains(RegExp(r'[\r\n\u0085\u2028\u2029]'))) {
      throw const FormatException('Invalid GitHub credentials.');
    }
  }

  @override
  String toString() => 'BcrGithubCredentials(persistent: $_persistent)';
}
