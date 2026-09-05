import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/ai/composition/assistant_route_paths.dart';
import '../../../../core/ai/llm_credentials/providers.dart';
import '../../../../core/shell/settings_route_paths.dart';
import '../../../../core/shell/settings_ui/inline_setting_row.dart';
import '../../../../core/shell/settings_ui/settings_page_frame.dart';
import '../../../../design_system/design_system.dart';
import '../../../../l10n/gen/app_localizations.dart';

/// One navigable home for device AI configuration.
///
/// The settings overview exposes this single concept instead of making users
/// distinguish providers, models, agents, privacy, and traces at the root.
class AiSettingsHubPage extends ConsumerWidget {
  const AiSettingsHubPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final supported = ref.watch(deviceLlmPlatformSupportedProvider);
    return AppPageScaffold(
      title: l10n.settingsAiHubTitle,
      childPad: false,
      child: SettingsPageFrame(
        children: [
          if (supported)
            AppSection.group(
              title: l10n.settingsAiHubRuntimeSection,
              children: [
                InlineLinkRow(
                  icon: FLucideIcons.key,
                  label: l10n.settingsAiLlmTitle,
                  subtitle: l10n.settingsAiLlmSubtitle,
                  onTap: () => context.pushNamed(SettingsRouteNames.aiLlm),
                ),
                const AppGroupedDivider(),
                InlineLinkRow(
                  icon: FLucideIcons.download,
                  label: l10n.settingsAiModelsTitle,
                  subtitle: l10n.settingsAiModelsSubtitle,
                  onTap: () => context.pushNamed(SettingsRouteNames.aiModels),
                ),
              ],
            ),
          if (!supported)
            AppStatusBanner(
              kind: AppStatusKind.info,
              message: l10n.settingsAiNativeOnly,
              compact: true,
            ),
          const SizedBox(height: AppSpacing.s20),
          AppSection.group(
            title: l10n.settingsAiHubTrustSection,
            children: [
              InlineLinkRow(
                icon: FLucideIcons.brain,
                label: l10n.personalMemoryTitle,
                subtitle: l10n.personalMemorySubtitle,
                onTap: () =>
                    context.pushNamed(SettingsRouteNames.personalMemory),
              ),
              const AppGroupedDivider(),
              InlineLinkRow(
                icon: FLucideIcons.lock,
                label: l10n.settingsAiPrivacyTitle,
                subtitle: l10n.settingsAiPrivacySubtitle,
                onTap: () => context.pushNamed(SettingsRouteNames.aiPrivacy),
              ),
              const AppGroupedDivider(),
              InlineLinkRow(
                icon: FLucideIcons.history,
                label: l10n.settingsAiHistoryTitle,
                subtitle: l10n.settingsAiHistorySubtitle,
                onTap: () => context.pushNamed(AssistantRouteNames.home),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
