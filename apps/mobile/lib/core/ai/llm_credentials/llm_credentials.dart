/// W-D1 — user-supplied LLM credentials for the on-device AI runtime
/// (§4.6.1 decision 1).
///
/// The Phase 5 device runtime calls the LLM provider **directly** with
/// a key the user pastes in Settings. This is the in-memory shape; it
/// is persisted only through [LlmCredentialStore] (Keychain/Keystore),
/// never via OpLog / cloud sync / plaintext backup — same trust class
/// as the SQLCipher DB key.
library;

import 'dart:convert';

/// Which provider wire dialect the device adapter speaks. Only
/// Anthropic is implemented in Phase 5 (W-D2); the enum exists so
/// adding an OpenAI-compatible gateway later is a wire-additive change
/// rather than a schema change. Unknown values soft-fall to
/// [LlmProvider.anthropic] on decode.
enum LlmProvider {
  anthropic;

  String get wire => switch (this) {
    LlmProvider.anthropic => 'anthropic',
  };

  static LlmProvider parse(String? s) => switch (s) {
    'anthropic' => LlmProvider.anthropic,
    _ => LlmProvider.anthropic,
  };

  /// Human label for the settings UI.
  String get label => switch (this) {
    LlmProvider.anthropic => 'Anthropic (Claude)',
  };
}

class LlmCredentials {
  const LlmCredentials({
    required this.provider,
    required this.apiKey,
    this.baseUrl,
    this.enabled = false,
  });

  final LlmProvider provider;

  /// The user's own provider API key. Billing + rate limits are on the
  /// user's account (§11: this is what removes the key-custody veto).
  final String apiKey;

  /// Optional custom endpoint (self-hosted relay / regional gateway).
  /// `null` ⇒ provider default base URL.
  final String? baseUrl;

  /// Opt-in switch (§4.6.1, §11 "端侧 LLM 必须 opt-in"). Default `false`
  /// so installing the app or even pasting a key never silently changes
  /// routing — the device runtime is only picked when this is `true`.
  final bool enabled;

  /// A key is usable only if it's actually present *and* the user has
  /// opted in. [RuntimeRegistry.pickFor] (W-D3) gates on this plus the
  /// native-platform check.
  bool get isUsable => enabled && apiKey.trim().isNotEmpty;

  bool get hasKey => apiKey.trim().isNotEmpty;

  LlmCredentials copyWith({
    LlmProvider? provider,
    String? apiKey,
    String? baseUrl,
    bool clearBaseUrl = false,
    bool? enabled,
  }) {
    return LlmCredentials(
      provider: provider ?? this.provider,
      apiKey: apiKey ?? this.apiKey,
      baseUrl: clearBaseUrl ? null : (baseUrl ?? this.baseUrl),
      enabled: enabled ?? this.enabled,
    );
  }

  /// Compact JSON for the single secure-storage slot. snake_case to
  /// match the rest of the AI wire conventions (§10), even though this
  /// value never leaves the device.
  String encode() => jsonEncode({
    'provider': provider.wire,
    'api_key': apiKey,
    if (baseUrl != null && baseUrl!.isNotEmpty) 'base_url': baseUrl,
    'enabled': enabled,
  });

  /// Throws [FormatException] on malformed input so [LlmCredentialStore]
  /// can drop a corrupt entry and fall back to "no credentials".
  static LlmCredentials decode(String raw) {
    final dynamic parsed = jsonDecode(raw);
    if (parsed is! Map<String, dynamic>) {
      throw const FormatException('llm credentials: not a JSON object');
    }
    final apiKey = parsed['api_key'];
    if (apiKey is! String) {
      throw const FormatException('llm credentials: missing api_key');
    }
    final baseUrl = parsed['base_url'];
    return LlmCredentials(
      provider: LlmProvider.parse(parsed['provider'] as String?),
      apiKey: apiKey,
      baseUrl: baseUrl is String && baseUrl.isNotEmpty ? baseUrl : null,
      enabled: parsed['enabled'] == true,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is LlmCredentials &&
      other.provider == provider &&
      other.apiKey == apiKey &&
      other.baseUrl == baseUrl &&
      other.enabled == enabled;

  @override
  int get hashCode => Object.hash(provider, apiKey, baseUrl, enabled);
}
