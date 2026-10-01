import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/ai/visual/ai_pill.dart';
import '../../../../core/shell/settings_route_paths.dart';
import '../../../../design_system/design_system.dart';
import '../../../../l10n/gen/app_localizations.dart';
import '../../data/knowledge_rewrite_client.dart';

class KnowledgeRewriteAction extends ConsumerWidget {
  const KnowledgeRewriteAction({
    super.key,
    required this.onRewrite,
    this.enabled = true,
  });

  final VoidCallback onRewrite;
  final bool enabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (kIsWeb) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    final client = ref.watch(knowledgeRewriteClientProvider);
    return Align(
      alignment: Alignment.centerLeft,
      child: client == null
          ? AppQuietButton(
              label: l10n.knowledgeRewriteConfigure,
              prefix: const Icon(FLucideIcons.settings2),
              onPress: enabled
                  ? () => context.push(SettingsRoutes.aiLlm)
                  : null,
            )
          : AiPill(
              leading: const Icon(FLucideIcons.pencil, size: AppIconSizes.xs),
              label: l10n.knowledgeRewriteAction,
              onTap: enabled ? onRewrite : null,
            ),
    );
  }
}
