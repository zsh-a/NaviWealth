/// User-facing AI privacy posture wire enum.
///
/// Kept separate from `privacy_mode_provider.dart` so contract tools can read
/// the enum without importing Flutter / Riverpod provider code.
library;

/// Three user-visible privacy postures the section 5.10.5 spec calls out.
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
