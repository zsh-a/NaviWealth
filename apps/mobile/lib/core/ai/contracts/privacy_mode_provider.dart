/// §5.10.5 — runtime user-facing toggle for AI privacy posture.
///
/// Post-W-D7 the chat path is device-only, so this setting now only
/// gates the cloud-Vision ingest fallback (see `ingest_privacy_gate`).
/// [maxBudgetTier] is also read by ingest to stamp the AiTrace tier.
///
///   * `amountsAllowed`  — default for new installs.
///   * `amountsBucketed` — middle posture.
///   * `amountsLocal`    — ingest layer 4 cloud Vision is refused for
///                         payloads carrying amount-bearing fields.
///
/// State is persisted via [SharedPreferences] so a setting picked on
/// device A survives a relaunch. Cross-device sync of this preference
/// is intentionally out of scope — it's a local trust decision.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../design_system/preferences/theme_preferences.dart';
import 'privacy_budget.dart';

/// Three user-visible privacy postures the §5.10.5 spec calls out.
enum AiPrivacyMode { amountsAllowed, amountsBucketed, amountsLocal }

extension AiPrivacyModeWire on AiPrivacyMode {
  String get wire => switch (this) {
    AiPrivacyMode.amountsAllowed => 'amounts_allowed',
    AiPrivacyMode.amountsBucketed => 'amounts_bucketed',
    AiPrivacyMode.amountsLocal => 'amounts_local',
  };

  static AiPrivacyMode parse(String s) => switch (s) {
    'amounts_allowed' => AiPrivacyMode.amountsAllowed,
    'amounts_bucketed' => AiPrivacyMode.amountsBucketed,
    'amounts_local' => AiPrivacyMode.amountsLocal,
    _ => AiPrivacyMode.amountsAllowed,
  };
}

@immutable
class AiPrivacySettings {
  const AiPrivacySettings({required this.mode, required this.maskAccountNames});

  final AiPrivacyMode mode;

  /// When `true`, account / institution names get redacted before
  /// they cross the privacy gate regardless of [mode]. Useful for
  /// power users who're fine with amounts going up but don't want
  /// their bank list inferred.
  final bool maskAccountNames;

  static const AiPrivacySettings defaults = AiPrivacySettings(
    mode: AiPrivacyMode.amountsAllowed,
    maskAccountNames: false,
  );

  /// PrivacyBudget tier this mode allows. Device prompt assembly and
  /// ingest traces use this as an upper bound; tools that explicitly
  /// need a smaller tier still get capped.
  BudgetTier get maxBudgetTier => switch (mode) {
    AiPrivacyMode.amountsAllowed => BudgetTier.large,
    AiPrivacyMode.amountsBucketed => BudgetTier.standard,
    AiPrivacyMode.amountsLocal => BudgetTier.small,
  };

  AiPrivacySettings copyWith({AiPrivacyMode? mode, bool? maskAccountNames}) {
    return AiPrivacySettings(
      mode: mode ?? this.mode,
      maskAccountNames: maskAccountNames ?? this.maskAccountNames,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is AiPrivacySettings &&
      other.mode == mode &&
      other.maskAccountNames == maskAccountNames;

  @override
  int get hashCode => Object.hash(mode, maskAccountNames);
}

class AiPrivacyController extends Notifier<AiPrivacySettings> {
  static const String _modeKey = 'ai_privacy.mode.v1';
  static const String _maskKey = 'ai_privacy.mask_account_names.v1';

  @override
  AiPrivacySettings build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    final modeWire = prefs.getString(_modeKey);
    final mask = prefs.getBool(_maskKey) ?? false;
    return AiPrivacySettings(
      mode: modeWire == null
          ? AiPrivacySettings.defaults.mode
          : AiPrivacyModeWire.parse(modeWire),
      maskAccountNames: mask,
    );
  }

  Future<void> setMode(AiPrivacyMode mode) async {
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.setString(_modeKey, mode.wire);
    state = state.copyWith(mode: mode);
  }

  Future<void> setMaskAccountNames(bool value) async {
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.setBool(_maskKey, value);
    state = state.copyWith(maskAccountNames: value);
  }
}

/// User's current AI-privacy posture. The command palette status badge
/// reads this; context assembly clamps to `state.maxBudgetTier`.
final aiPrivacySettingsProvider =
    NotifierProvider<AiPrivacyController, AiPrivacySettings>(
      AiPrivacyController.new,
    );

/// Has the user been shown the first-run privacy onboarding sheet?
/// Bootstrap reads this; the sheet writes `true` on dismissal.
final aiPrivacyOnboardingSeenProvider = Provider<bool>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return prefs.getBool('ai_privacy.onboarding_seen.v1') ?? false;
});

Future<void> markAiPrivacyOnboardingSeen(SharedPreferences prefs) {
  return prefs.setBool('ai_privacy.onboarding_seen.v1', true);
}
