/// FRB wrapper for the Rust Garmin Connect client.
///
/// Calls generated bindings from `lifeos_native`. The actual Dart
/// bindings are produced by `flutter_rust_bridge_codegen` — this file
/// wraps them in a clean API for the rest of the app.
library;

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
    final state = json['state'] ?? json;
    if (state is! Map<String, dynamic>) {
      return GarminAuthState.unauthenticated;
    }

    // Rust serializes enum variants as {"VariantName": {fields}} or
    // {"VariantName": null} for unit variants.
    final typeStr = state.keys.firstOrNull ?? 'Unauthenticated';
    final inner = state[typeStr];

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
  const GarminAuthResult({
    required this.type,
    this.errorMessage,
  });

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
      errors: (json['errors'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      durationMs: json['duration_ms'] as int? ?? 0,
    );
  }
}

/// Bridge to the Rust Garmin client.
///
/// All methods call FRB-generated async functions. Until codegen runs,
/// they throw [UnsupportedError].
class GarminBridge {
  /// Initialize the Garmin client. Restores session if [storedTokenJson] is provided.
  Future<GarminAuthState> init({String? storedTokenJson}) async {
    // FRB-generated call:
    // final result = await garminInit(storedTokenJson);
    // return GarminAuthState.fromJson(jsonDecode(result));
    throw UnsupportedError(
      'FRB bindings not generated. Run: bash tool/build-lifeos-native.sh',
    );
  }

  /// Authenticate with email/password.
  Future<GarminAuthResult> authenticate(String email, String password) async {
    // FRB-generated call:
    // final result = await garminAuthenticate(email: email, password: password);
    // final decoded = jsonDecode(result) as Map<String, dynamic>;
    // final resultType = decoded['result'] as Map<String, dynamic>;
    // final authResult = resultType.keys.firstOrNull;
    // return GarminAuthResult(type: switch (authResult) { ... })
    throw UnsupportedError(
      'FRB bindings not generated. Run: bash tool/build-lifeos-native.sh',
    );
  }

  /// Submit MFA code.
  Future<GarminAuthResult> submitMfa(String code) async {
    // FRB-generated call:
    // final result = await garminSubmitMfa(code: code);
    // ...
    throw UnsupportedError(
      'FRB bindings not generated. Run: bash tool/build-lifeos-native.sh',
    );
  }

  /// Get current auth state.
  Future<GarminAuthState> authState() async {
    // FRB-generated call:
    // final result = await garminAuthState();
    // return GarminAuthState.fromJson(jsonDecode(result));
    throw UnsupportedError(
      'FRB bindings not generated. Run: bash tool/build-lifeos-native.sh',
    );
  }

  /// Sync health data for a date range.
  Future<List<GarminSyncOutcome>> syncRange(DateTime from, DateTime to) async {
    // FRB-generated call:
    // final result = await garminSyncRange(
    //   from: from.toIso8601String().substring(0, 10),
    //   to: to.toIso8601String().substring(0, 10),
    // );
    // final list = jsonDecode(result) as List<dynamic>;
    // return list.map((e) => GarminSyncOutcome.fromJson(e as Map<String, dynamic>)).toList();
    throw UnsupportedError(
      'FRB bindings not generated. Run: bash tool/build-lifeos-native.sh',
    );
  }

  /// Get sync cursors.
  Future<Map<String, DateTime>> syncCursors() async {
    // FRB-generated call:
    // final result = await garminSyncCursors();
    // final map = jsonDecode(result) as Map<String, dynamic>;
    // return map.map((k, v) => MapEntry(k, DateTime.parse(v as String)));
    throw UnsupportedError(
      'FRB bindings not generated. Run: bash tool/build-lifeos-native.sh',
    );
  }

  /// Logout and clear stored credentials.
  Future<void> logout() async {
    // FRB-generated call:
    // await garminLogout();
    throw UnsupportedError(
      'FRB bindings not generated. Run: bash tool/build-lifeos-native.sh',
    );
  }
}
