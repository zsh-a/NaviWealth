import 'secure_key_store.dart';

/// In-memory implementation used by tests and as a deliberate fallback
/// when no platform-secure store is available.
///
/// Never use this for storing the production DB key — secrets disappear
/// on process exit and live in the heap unencrypted.
class InMemoryKeyStore implements SecureKeyStore {
  InMemoryKeyStore([Map<String, String>? seed]) : _data = {...?seed};

  final Map<String, String> _data;

  @override
  Future<String?> read(String key) async => _data[key];

  @override
  Future<void> write(String key, String value) async {
    _data[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    _data.remove(key);
  }

  @override
  Future<bool> contains(String key) async => _data.containsKey(key);
}
