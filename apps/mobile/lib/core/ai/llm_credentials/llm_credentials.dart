/// W-D1 / Wave 46 — user-supplied LLM credentials for the on-device AI
/// runtime (§4.6.1 decision 1).
///
/// The Phase 5 device runtime calls the LLM provider **directly** with
/// a key the user pastes in Settings. Wave 46 generalises the single
/// slot into **multiple named profiles + one active selection** so the
/// user can keep e.g. an official Anthropic key, a self-hosted
/// gateway, and a regional proxy side by side and switch between them.
///
/// Persisted only through [LlmCredentialStore] (Keychain/Keystore),
/// never via OpLog / cloud sync / plaintext backup — same trust class
/// as the SQLCipher DB key.
///
/// **The opt-in `enabled` switch was removed in Wave 46.** It only
/// made sense while a cloud relay existed to fall back to; W-D7
/// deleted that. The active profile *is* the intent: a saved+active
/// profile with a key → device AI runs; otherwise the turn surfaces
/// `device_unavailable`.
library;

import 'dart:convert';

/// Which provider wire dialect the device adapter speaks. Most
/// "providers" users actually want (official Anthropic, OpenAI,
/// OpenRouter, DeepSeek-compatible endpoints, a self-hosted relay, a
/// regional gateway) are reachable via a custom base URL and the chosen
/// wire dialect.
/// Unknown values soft-fall to [LlmProvider.anthropic] on decode.
enum LlmProvider {
  anthropic,
  openai;

  String get wire => switch (this) {
    LlmProvider.anthropic => 'anthropic',
    LlmProvider.openai => 'openai',
  };

  static LlmProvider parse(String? s) => switch (s) {
    'anthropic' => LlmProvider.anthropic,
    'openai' => LlmProvider.openai,
    _ => LlmProvider.anthropic,
  };

  /// Human label for the settings UI.
  String get label => switch (this) {
    LlmProvider.anthropic => 'Anthropic 兼容',
    LlmProvider.openai => 'OpenAI 兼容',
  };
}

/// One named provider configuration. `id` is stable for the lifetime
/// of the profile so the active selection survives edits.
class LlmProfile {
  const LlmProfile({
    required this.id,
    required this.name,
    required this.provider,
    required this.apiKey,
    this.baseUrl,
    this.model,
  });

  final String id;

  /// Free-form user label ("Anthropic 官方", "公司网关", …). Falls back
  /// to the provider label when blank.
  final String name;

  final LlmProvider provider;

  /// The user's own provider API key. Billing + rate limits are on the
  /// user's account (§11: this is what removes the key-custody veto).
  final String apiKey;

  /// Optional custom endpoint (self-hosted relay / regional gateway).
  /// `null` ⇒ provider default base URL.
  final String? baseUrl;

  /// Optional model override. `null` ⇒ the adapter's default model.
  final String? model;

  bool get hasKey => apiKey.trim().isNotEmpty;

  String get displayName =>
      name.trim().isNotEmpty ? name.trim() : provider.label;

  LlmProfile copyWith({
    String? name,
    LlmProvider? provider,
    String? apiKey,
    String? baseUrl,
    bool clearBaseUrl = false,
    String? model,
    bool clearModel = false,
  }) => LlmProfile(
    id: id,
    name: name ?? this.name,
    provider: provider ?? this.provider,
    apiKey: apiKey ?? this.apiKey,
    baseUrl: clearBaseUrl ? null : (baseUrl ?? this.baseUrl),
    model: clearModel ? null : (model ?? this.model),
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'name': name,
    'provider': provider.wire,
    'api_key': apiKey,
    if (baseUrl != null && baseUrl!.isNotEmpty) 'base_url': baseUrl,
    if (model != null && model!.isNotEmpty) 'model': model,
  };

  static LlmProfile? tryFromJson(Object? raw) {
    if (raw is! Map) return null;
    final apiKey = raw['api_key'];
    if (apiKey is! String) return null;
    final id = raw['id'];
    final name = raw['name'];
    final baseUrl = raw['base_url'];
    final model = raw['model'];
    return LlmProfile(
      id: id is String && id.isNotEmpty
          ? id
          : DateTime.now().microsecondsSinceEpoch.toString(),
      name: name is String ? name : '',
      provider: LlmProvider.parse(raw['provider'] as String?),
      apiKey: apiKey,
      baseUrl: baseUrl is String && baseUrl.isNotEmpty ? baseUrl : null,
      model: model is String && model.isNotEmpty ? model : null,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is LlmProfile &&
      other.id == id &&
      other.name == name &&
      other.provider == provider &&
      other.apiKey == apiKey &&
      other.baseUrl == baseUrl &&
      other.model == model;

  @override
  int get hashCode => Object.hash(id, name, provider, apiKey, baseUrl, model);
}

/// The full credential set: every saved [LlmProfile] plus which one is
/// active. Stored as a single JSON value in one secure-storage slot.
class LlmCredentials {
  const LlmCredentials({this.profiles = const <LlmProfile>[], this.activeId});

  final List<LlmProfile> profiles;

  /// Id of the active profile, or `null` when none is selected.
  final String? activeId;

  /// The active profile, or `null` if [activeId] is unset / dangling.
  LlmProfile? get active {
    final id = activeId;
    if (id == null) return null;
    for (final p in profiles) {
      if (p.id == id) return p;
    }
    return null;
  }

  /// Usable when the active profile exists and carries a key. The
  /// native-platform gate lives in `deviceLlmAvailableProvider`.
  bool get isUsable => active?.hasKey ?? false;

  bool get isEmpty => profiles.isEmpty;

  LlmCredentials copyWith({List<LlmProfile>? profiles, Object? activeId}) =>
      LlmCredentials(
        profiles: profiles ?? this.profiles,
        activeId: activeId == _unset ? this.activeId : activeId as String?,
      );

  static const Object _unset = Object();

  /// Insert or replace [profile] by id. A brand-new profile becomes
  /// active automatically (so adding your first/only key just works);
  /// editing an existing profile leaves the active selection alone.
  LlmCredentials upsert(LlmProfile profile) {
    final idx = profiles.indexWhere((p) => p.id == profile.id);
    final next = List<LlmProfile>.of(profiles);
    final isNew = idx < 0;
    if (isNew) {
      next.add(profile);
    } else {
      next[idx] = profile;
    }
    return LlmCredentials(
      profiles: next,
      activeId: (isNew && activeId == null) ? profile.id : activeId,
    );
  }

  /// Drop the profile with [id]. If it was active, the active
  /// selection moves to the first remaining profile (or `null`).
  LlmCredentials remove(String id) {
    final next = profiles.where((p) => p.id != id).toList(growable: false);
    final nextActive = activeId != id
        ? activeId
        : (next.isEmpty ? null : next.first.id);
    return LlmCredentials(profiles: next, activeId: nextActive);
  }

  LlmCredentials withActive(String id) {
    if (!profiles.any((p) => p.id == id)) return this;
    return LlmCredentials(profiles: profiles, activeId: id);
  }

  /// Compact JSON for the single secure-storage slot. `v:2` is the
  /// multi-profile shape; [decode] still understands the `v:1`
  /// single-key blob for a one-time migration.
  String encode() => jsonEncode(<String, Object?>{
    'v': 2,
    if (activeId != null) 'active_id': activeId,
    'profiles': profiles.map((p) => p.toJson()).toList(growable: false),
  });

  /// Throws [FormatException] on malformed input so [LlmCredentialStore]
  /// can drop a corrupt entry and fall back to "no credentials".
  ///
  /// Migration: a legacy `{provider, api_key, base_url, enabled}` blob
  /// becomes a single profile. It is made active regardless of the old
  /// `enabled` flag — post-W-D7 there is no cloud to fall back to, so a
  /// saved key the user bothered to enter should just work.
  static LlmCredentials decode(String raw) {
    final dynamic parsed = jsonDecode(raw);
    if (parsed is! Map<String, dynamic>) {
      throw const FormatException('llm credentials: not a JSON object');
    }
    final rawProfiles = parsed['profiles'];
    if (rawProfiles is List) {
      final profiles = <LlmProfile>[];
      for (final e in rawProfiles) {
        final p = LlmProfile.tryFromJson(e);
        if (p != null) profiles.add(p);
      }
      final activeId = parsed['active_id'];
      final id = activeId is String && profiles.any((p) => p.id == activeId)
          ? activeId
          : (profiles.isEmpty ? null : profiles.first.id);
      return LlmCredentials(profiles: profiles, activeId: id);
    }
    // Legacy single-key shape.
    final apiKey = parsed['api_key'];
    if (apiKey is! String) {
      throw const FormatException('llm credentials: missing api_key');
    }
    final baseUrl = parsed['base_url'];
    final migrated = LlmProfile(
      id: 'migrated',
      name: '',
      provider: LlmProvider.parse(parsed['provider'] as String?),
      apiKey: apiKey,
      baseUrl: baseUrl is String && baseUrl.isNotEmpty ? baseUrl : null,
    );
    return LlmCredentials(
      profiles: <LlmProfile>[migrated],
      activeId: migrated.id,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is LlmCredentials &&
      other.activeId == activeId &&
      _listEq(other.profiles, profiles);

  @override
  int get hashCode => Object.hash(activeId, Object.hashAll(profiles));

  static bool _listEq(List<LlmProfile> a, List<LlmProfile> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
