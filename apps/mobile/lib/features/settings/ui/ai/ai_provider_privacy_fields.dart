import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../../../../core/shell/settings_ui/inline_setting_row.dart';
import '../../../../design_system/design_system.dart';
import '../../../../l10n/gen/app_localizations.dart';

/// The same provider disclosure and document permission in setup and Settings.
/// Hosts own persistence so profile edits can keep the choice in their draft.
class AiProviderPrivacyFields extends StatelessWidget {
  const AiProviderPrivacyFields({
    super.key,
    required this.allowDocumentRecognition,
    required this.onChanged,
    this.enabled = true,
  });

  final bool allowDocumentRecognition;
  final ValueChanged<bool> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(l10n.aiPrivacyIntro, style: context.bodyCaptionStyle),
        const SizedBox(height: AppSpacing.s8),
        InlineSwitchRow(
          icon: FLucideIcons.fileScan,
          label: l10n.aiPrivacyDocumentRecognitionLabel,
          value: allowDocumentRecognition,
          enabled: enabled,
          onChanged: onChanged,
        ),
        Text(
          l10n.aiPrivacyDocumentRecognitionDescription,
          style: context.captionStyle,
        ),
      ],
    );
  }
}
