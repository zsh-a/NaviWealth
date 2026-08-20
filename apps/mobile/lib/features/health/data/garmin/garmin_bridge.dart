/// FRB wrapper for the Rust Garmin Connect client.
///
/// Calls generated bindings from `lifeos_native` via
/// `package:naviwealth/src/rust/api/health.dart`.
library;

import 'dart:convert' as convert;

import 'package:naviwealth/core/native/lifeos_native_runtime.dart';
import 'package:naviwealth/src/rust/api/health.dart' as rust;

/// Garmin authentication states (mirrors Rust `GarminAuthState`).
enum GarminAuthStateType {
  unauthenticated,
  pendingMfa,
  authenticated,
  refreshing,
  error,
}

/// Parsed auth state from the Rust side.
class GarminAuthState {
  const GarminAuthState._({
    required this.type,
    this.expiresAt,
    this.errorMessage,
  });

  final GarminAuthStateType type;
  final DateTime? expiresAt;
  final String? errorMessage;

  bool get canMakeRequests => type == GarminAuthStateType.authenticated;
  bool get needsMfa => type == GarminAuthStateType.pendingMfa;

  factory GarminAuthState.fromJson(Map<String, dynamic> json) {
    // Rust serializes enum variants as {"VariantName": {fields}} or
    // {"VariantName": null} for unit variants.
    final typeStr = json.keys.firstOrNull ?? 'Unauthenticated';
    final inner = json[typeStr];

    GarminAuthStateType type;
    switch (typeStr) {
      case 'Unauthenticated':
        type = GarminAuthStateType.unauthenticated;
      case 'PendingMfa':
        type = GarminAuthStateType.pendingMfa;
      case 'Authenticated':
        type = GarminAuthStateType.authenticated;
      case 'Refreshing':
        type = GarminAuthStateType.refreshing;
      case 'Error':
        type = GarminAuthStateType.error;
      default:
        type = GarminAuthStateType.unauthenticated;
    }

    DateTime? expiresAt;
    String? errorMessage;
    if (inner is Map<String, dynamic>) {
      final expiresStr = inner['expires_at'] as String?;
      if (expiresStr != null) {
        expiresAt = DateTime.tryParse(expiresStr);
      }
      errorMessage = inner['message'] as String?;
    }

    return GarminAuthState._(
      type: type,
      expiresAt: expiresAt,
      errorMessage: errorMessage,
    );
  }

  static const unauthenticated = GarminAuthState._(
    type: GarminAuthStateType.unauthenticated,
  );

  @override
  String toString() => 'GarminAuthState($type)';
}

/// Result of an auth attempt.
enum GarminAuthResultType { authenticated, mfaRequired, failed }

class GarminAuthResult {
  const GarminAuthResult({required this.type, this.errorMessage});

  final GarminAuthResultType type;
  final String? errorMessage;
}

/// Outcome of a sync operation (mirrors Rust `SyncOutcome`).
class GarminSyncOutcome {
  const GarminSyncOutcome({
    required this.provider,
    required this.from,
    required this.to,
    required this.metricsCount,
    required this.activitiesCount,
    required this.errors,
    required this.durationMs,
  });

  final String provider;
  final DateTime from;
  final DateTime to;
  final int metricsCount;
  final int activitiesCount;
  final List<String> errors;
  final int durationMs;

  bool get ok => errors.isEmpty;

  factory GarminSyncOutcome.fromJson(Map<String, dynamic> json) {
    return GarminSyncOutcome(
      provider: json['provider'] as String? ?? '',
      from: DateTime.parse(json['from'] as String),
      to: DateTime.parse(json['to'] as String),
      metricsCount: json['metrics_count'] as int? ?? 0,
      activitiesCount: json['activities_count'] as int? ?? 0,
      errors:
          (json['errors'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      durationMs: json['duration_ms'] as int? ?? 0,
    );
  }
}

/// Injectable raw native surface used by [GarminBridge].
///
/// Keeping generated FRB calls behind this interface lets cold-start runtime
/// ordering be tested without loading the native library.
abstract interface class GarminNativeApi {
  Future<Object?> initialize({String? storedTokenJson, required bool isCn});
  Future<Object?> authenticate({
    required String email,
    required String password,
  });
  Future<Object?> submitMfa({required String code});
  Future<Object?> authState();
  Future<Object?> syncRange({required String from, required String to});
  Stream<rust.GarminSyncProgress> syncRangeWithProgress({
    required String from,
    required String to,
  });
  Future<void> cancelSync();
  Future<Object?> syncCursors();
  Future<void> logout();
  Future<Object?> exportSession();
}

final class FrbGarminNativeApi implements GarminNativeApi {
  const FrbGarminNativeApi();

  @override
  Future<Object?> initialize({String? storedTokenJson, required bool isCn}) =>
      rust.garminInit(storedTokenJson: storedTokenJson, isCn: isCn);

  @override
  Future<Object?> authenticate({
    required String email,
    required String password,
  }) => rust.garminAuthenticate(email: email, password: password);

  @override
  Future<Object?> submitMfa({required String code}) =>
      rust.garminSubmitMfa(code: code);

  @override
  Future<Object?> authState() => rust.garminAuthState();

  @override
  Future<Object?> syncRange({required String from, required String to}) =>
      rust.garminSyncRange(from: from, to: to);

  @override
  Stream<rust.GarminSyncProgress> syncRangeWithProgress({
    required String from,
    required String to,
  }) => rust.garminSyncRangeStream(from: from, to: to);

  @override
  Future<void> cancelSync() => rust.garminSyncCancel();

  @override
  Future<Object?> syncCursors() => rust.garminSyncCursors();

  @override
  Future<void> logout() => rust.garminLogout();

  @override
  Future<Object?> exportSession() => rust.garminExportSession();
}

/// Bridge to the Rust Garmin client.
///
/// All methods call FRB-generated async functions from
/// `package:naviwealth/src/rust/api/health.dart`.
class GarminBridge {
  GarminBridge({
    GarminNativeApi nativeApi = const FrbGarminNativeApi(),
    LifeosNativeRuntimeInitializer initRuntime = initLifeosNativeRuntime,
    String? libraryPath,
  }) : _nativeApi = nativeApi,
       _initRuntime = initRuntime,
       _libraryPath = libraryPath;

  final GarminNativeApi _nativeApi;
  final LifeosNativeRuntimeInitializer _initRuntime;
  final String? _libraryPath;
  Future<void>? _initFuture;

  /// Initialize the Garmin client.
  Future<GarminAuthState> init({
    String? storedTokenJson,
    bool isCn = true,
  }) async {
    await _ensureInitialized();
    // FRB returns String but SSE codec may auto-decode JSON.
    final result = await _nativeApi.initialize(
      storedTokenJson: storedTokenJson,
      isCn: isCn,
    );
    return _parseAuthState(result);
  }

  /// Authenticate with email/password.
  Future<GarminAuthResult> authenticate(String email, String password) async {
    await _ensureInitialized();
    final result = await _nativeApi.authenticate(
      email: email,
      password: password,
    );
    return _parseAuthResult(result);
  }

  /// Submit MFA code.
  Future<GarminAuthResult> submitMfa(String code) async {
    await _ensureInitialized();
    final result = await _nativeApi.submitMfa(code: code);
    return _parseAuthResult(result);
  }

  /// Get current auth state.
  Future<GarminAuthState> authState() async {
    await _ensureInitialized();
    final result = await _nativeApi.authState();
    return _parseAuthState(result);
  }

  /// Sync health data for a date range.
  Future<List<GarminSyncOutcome>> syncRange(DateTime from, DateTime to) async {
    await _ensureInitialized();
    final result = await _nativeApi.syncRange(
      from: from.toIso8601String().substring(0, 10),
      to: to.toIso8601String().substring(0, 10),
    );
    final list = _decodeJsonList(result);
    return list
        .map((e) => GarminSyncOutcome.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Sync health data with streaming progress events.
  ///
  /// Returns a [Stream] of [rust.GarminSyncProgress] that emits after
  /// each day completes. The stream closes on completion or cancellation.
  Stream<rust.GarminSyncProgress> syncRangeWithProgress(
    DateTime from,
    DateTime to,
  ) async* {
    await _ensureInitialized();
    yield* _nativeApi.syncRangeWithProgress(
      from: from.toIso8601String().substring(0, 10),
      to: to.toIso8601String().substring(0, 10),
    );
  }

  /// Cancel an in-progress sync.
  Future<void> cancelSync() async {
    await _ensureInitialized();
    await _nativeApi.cancelSync();
  }

  /// Get sync cursors.
  Future<Map<String, DateTime>> syncCursors() async {
    await _ensureInitialized();
    final result = await _nativeApi.syncCursors();
    final map = _decodeJsonMap(result);
    return map.map((k, v) => MapEntry(k, DateTime.parse(v as String)));
  }

  /// Logout and clear stored credentials.
  Future<void> logout() async {
    await _ensureInitialized();
    await _nativeApi.logout();
  }

  /// Export the current session JSON for persistent storage.
  ///
  /// Returns the session JSON string if authenticated, or `null`.
  Future<String?> exportSession() async {
    await _ensureInitialized();
    final result = await _nativeApi.exportSession();
    if (result == null) return null;
    // FRB may return a String or auto-decode.
    if (result is String) return result.isEmpty ? null : result;
    return result.toString();
  }

  Future<void> _ensureInitialized() {
    return _initFuture ??= _initializeRuntime();
  }

  Future<void> _initializeRuntime() async {
    try {
      await _initRuntime(libraryPath: _libraryPath);
    } on Object {
      _initFuture = null;
      rethrow;
    }
  }

  // ---------------------------------------------------------------------------
  // JSON parsing helpers
  // ---------------------------------------------------------------------------

  /// Parse auth state from Rust.
  ///
  /// Rust returns either a bare state object `{"Authenticated": {...}}`
  /// or a wrapper `{"result": ..., "state": ...}`.
  /// The `state` value may be a Map or a JSON-encoded String.
  GarminAuthState _parseAuthState(dynamic raw) {
    // Rust serde serializes unit enum variants as plain strings:
    //   "Unauthenticated", "Refreshing" (legacy compatibility only)
    // Variants with data serialize as objects:
    //   {"PendingMfa": {"session_ticket": "..."}}
    //   {"Authenticated": {"expires_at": "..."}}
    //   {"Error": {"message": "..."}}

    // Case 1: Plain string (unit variant).
    if (raw is String) {
      // Try JSON decode first — it might be a JSON string.
      final decoded = convert.jsonDecode(raw);
      if (decoded is String) {
        return _authStateFromTypeName(decoded);
      }
      if (decoded is Map) {
        return _authStateFromMap(decoded.cast<String, dynamic>());
      }
    }

    // Case 2: Already a Map (FRB SSE auto-decoded).
    if (raw is Map) {
      return _authStateFromMap(raw.cast<String, dynamic>());
    }

    return GarminAuthState.unauthenticated;
  }

  GarminAuthState _authStateFromTypeName(String typeName) {
    switch (typeName) {
      case 'Unauthenticated':
        return GarminAuthState.unauthenticated;
      case 'Refreshing':
        return const GarminAuthState._(type: GarminAuthStateType.refreshing);
      default:
        return GarminAuthState.unauthenticated;
    }
  }

  GarminAuthState _authStateFromMap(Map<String, dynamic> map) {
    // May be a bare state: {"Authenticated": {"expires_at": "..."}}
    // Or a wrapper: {"state": {"Authenticated": {...}}, "result": ...}
    final stateObj = map['state'];
    if (stateObj != null) {
      // It's a wrapper — extract the state.
      if (stateObj is Map) {
        return GarminAuthState.fromJson(stateObj.cast<String, dynamic>());
      }
      if (stateObj is String) {
        final inner = convert.jsonDecode(stateObj);
        if (inner is Map) {
          return GarminAuthState.fromJson(inner.cast<String, dynamic>());
        }
        if (inner is String) {
          return _authStateFromTypeName(inner);
        }
      }
    }
    // Bare state map.
    return GarminAuthState.fromJson(map);
  }

  /// Parse auth result from Rust.
  ///
  /// Rust returns JSON like:
  ///   `{"result": {"Authenticated": null}, "state": {"Authenticated": {...}}}`
  /// or for MFA:
  ///   `{"result": {"MfaRequired": null}, "state": {"PendingMfa": {...}}}`
  /// or failure:
  ///   `{"result": {"Failed": "message"}, "state": {"Error": {...}}}`
  GarminAuthResult _parseAuthResult(dynamic raw) {
    // Decode the top-level object.
    Map<String, dynamic> decoded;
    if (raw is Map) {
      decoded = raw.cast<String, dynamic>();
    } else if (raw is String) {
      final d = convert.jsonDecode(raw);
      if (d is Map) {
        decoded = d.cast<String, dynamic>();
      } else {
        return const GarminAuthResult(
          type: GarminAuthResultType.failed,
          errorMessage: 'unexpected response format',
        );
      }
    } else {
      return GarminAuthResult(
        type: GarminAuthResultType.failed,
        errorMessage: 'unexpected response type: ${raw.runtimeType}',
      );
    }

    // Parse "result" field — identifies the outcome.
    final resultObj = decoded['result'];
    final resultTypeName = _extractEnumTypeName(resultObj);
    if (resultTypeName != null) {
      switch (resultTypeName) {
        case 'Authenticated':
          return const GarminAuthResult(
            type: GarminAuthResultType.authenticated,
          );
        case 'MfaRequired':
          return const GarminAuthResult(type: GarminAuthResultType.mfaRequired);
        case 'Failed':
          // Extract error message from the result object.
          String? msg;
          if (resultObj is Map) {
            final inner = resultObj[resultTypeName];
            msg = inner is String ? inner : inner?.toString();
          }
          return GarminAuthResult(
            type: GarminAuthResultType.failed,
            errorMessage: msg ?? 'authentication failed',
          );
      }
    }

    // Fallback: check "state" field for success.
    final stateObj = decoded['state'];
    final stateTypeName = _extractEnumTypeName(stateObj);
    if (stateTypeName == 'Authenticated') {
      return const GarminAuthResult(type: GarminAuthResultType.authenticated);
    }

    return const GarminAuthResult(
      type: GarminAuthResultType.failed,
      errorMessage: 'unknown response',
    );
  }

  /// Extract the enum variant type name from a serde-serialized value.
  ///
  /// serde serializes:
  ///   unit variant → "TypeName" (String)
  ///   struct variant → {"TypeName": {...}} (Map)
  String? _extractEnumTypeName(dynamic value) {
    if (value is String) return value;
    if (value is Map && value.isNotEmpty) return value.keys.first as String?;
    return null;
  }

  /// Decode a JSON value into a Map.
  /// Handles both raw JSON strings and already-decoded Maps
  /// (FRB SSE codec may auto-decode JSON strings).
  Map<String, dynamic> _decodeJsonMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return value.cast<String, dynamic>();
    if (value is String) {
      final decoded = convert.jsonDecode(value);
      if (decoded is Map) return decoded.cast<String, dynamic>();
      // jsonDecode returned something unexpected (e.g. a nested string).
      // Try one more level of decoding (double-encoded JSON).
      if (decoded is String) {
        final inner = convert.jsonDecode(decoded);
        if (inner is Map) return inner.cast<String, dynamic>();
      }
      throw ArgumentError(
        'JSON decoded to ${decoded.runtimeType}, expected Map. '
        'Input: ${value.substring(0, value.length.clamp(0, 200))}',
      );
    }
    throw ArgumentError(
      'Expected String or Map, got ${value.runtimeType}: $value',
    );
  }

  /// Decode a JSON value into a List.
  List<dynamic> _decodeJsonList(dynamic value) {
    if (value is List<dynamic>) return value;
    if (value is List) return value;
    if (value is String) {
      return convert.jsonDecode(value) as List<dynamic>;
    }
    throw ArgumentError('Expected String or List, got ${value.runtimeType}');
  }
}
