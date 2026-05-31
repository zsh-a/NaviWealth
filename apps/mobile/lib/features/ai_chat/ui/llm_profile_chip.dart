/// A compact "current LLM profile" capsule shown directly above the
/// composer.
///
/// The device-LLM runtime is the only AI path (no cloud
/// relay), and the user can have several `LlmProfile`s saved in
/// settings. Before this chip there was no UI indication of which
/// profile is actually answering — so a Claude / GPT swap silently
/// landed in conversations without a hint. The chip:
///
///  - hides itself when no active profile is configured (the chat
///    surface will already surface its own "set up an AI key" CTA),
///  - shows the profile's [LlmProfile.displayName] otherwise,
///  - taps through to the AI LLM credentials settings page so the
///    user can swap profiles without leaving the chat to dig through
///    menus.
library;

import 'package:flutter/widgets.dart';
import '../../../design_system/design_system.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

import '../../../app/route_paths.dart';
import '../../../core/ai/llm_credentials/providers.dart';
import '../../../core/ai/visual/visual.dart';
import '../../../l10n/gen/app_localizations.dart';

class LlmProfileChip extends ConsumerWidget {
  const LlmProfileChip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final creds = ref.watch(llmCredentialsProvider).asData?.value;
    final active = creds?.active;
    if (active == null) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.s12, AppSpacing.s6, AppSpacing.s12, 0),
      child: Align(
        alignment: Alignment.centerLeft,
        child: FTooltip(
          tipBuilder: (_, _) => Text(l10n.aiChatProfileChipTooltip),
          child: AiPill(
            leading: const AiSparkle(size: 12),
            label: active.displayName,
            onTap: () => context.go(AppRoutes.settingsAiLlm),
          ),
        ),
      ),
    );
  }
}
