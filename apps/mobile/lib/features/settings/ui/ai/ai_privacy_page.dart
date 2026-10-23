import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/ai/contracts/ai_privacy_settings.dart';
import '../../../../core/ai/llm_credentials/providers.dart';
import '../../../../core/shell/settings_ui/settings_page_frame.dart';
import '../../../../design_system/design_system.dart';
import '../../../../l10n/gen/app_localizations.dart';
import 'ai_provider_privacy_fields.dart';

class AiPrivacyPage extends ConsumerStatefulWidget {
  const AiPrivacyPage({super.key});

  @override
  ConsumerState<AiPrivacyPage> createState() => _AiPrivacyPageState();
}

class _AiPrivacyPageState extends ConsumerState<AiPrivacyPage> {
  bool _saving = false;
  String? _error;

  Future<void> _setPermission(bool value) async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref
          .read(aiPrivacySettingsProvider.notifier)
          .setAllowDocumentRecognition(value);
    } catch (_) {
      if (mounted) {
        setState(() => _error = AppLocalizations.of(context).commonSaveFailed);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final supported = ref.watch(deviceLlmPlatformSupportedProvider);
    return AppPageScaffold(
      title: l10n.aiPrivacyTitle,
      childPad: false,
      child: SettingsPageFrame(
        topPadding: AppSpacing.s8,
        children: [
          if (!supported)
            AppStatusBanner(
              kind: AppStatusKind.info,
              message: l10n.settingsAiNativeOnly,
              compact: true,
            )
          else ...[
            AiProviderPrivacyFields(
              allowDocumentRecognition: ref
                  .watch(aiPrivacySettingsProvider)
                  .allowDocumentRecognition,
              enabled: !_saving,
              onChanged: _setPermission,
            ),
            if (_error case final error?) ...[
              const SizedBox(height: AppSpacing.s12),
              AppStatusBanner(
                kind: AppStatusKind.error,
                message: error,
                compact: true,
              ),
            ],
          ],
        ],
      ),
    );
  }
}
