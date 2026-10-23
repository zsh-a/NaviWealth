/// Device-local permission for sending documents to the configured provider.
///
/// Chat requests use the user's native provider profile. This separate setting
/// controls Vision ingest of raw images, PDFs and emails; it does not claim to
/// redact chat context, amounts, or account names.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../design_system/preferences/theme_preferences.dart';
import 'privacy_budget.dart';

@immutable
class AiPrivacySettings {
  const AiPrivacySettings({this.allowDocumentRecognition = false});

  final bool allowDocumentRecognition;

  /// Trace classification only; the ingest gate enforces document permission.
  BudgetTier get maxBudgetTier =>
      allowDocumentRecognition ? BudgetTier.large : BudgetTier.small;

  @override
  bool operator ==(Object other) =>
      other is AiPrivacySettings &&
      other.allowDocumentRecognition == allowDocumentRecognition;

  @override
  int get hashCode => allowDocumentRecognition.hashCode;
}

class AiPrivacyController extends Notifier<AiPrivacySettings> {
  static const _documentPermissionKey = 'ai_privacy.document_recognition';

  @override
  AiPrivacySettings build() => AiPrivacySettings(
    allowDocumentRecognition:
        ref.watch(sharedPreferencesProvider).getBool(_documentPermissionKey) ??
        false,
  );

  Future<void> setAllowDocumentRecognition(bool value) async {
    final saved = await ref
        .read(sharedPreferencesProvider)
        .setBool(_documentPermissionKey, value);
    if (!saved) throw StateError('Could not save AI document permission');
    state = AiPrivacySettings(allowDocumentRecognition: value);
  }
}

final aiPrivacySettingsProvider =
    NotifierProvider<AiPrivacyController, AiPrivacySettings>(
      AiPrivacyController.new,
    );
