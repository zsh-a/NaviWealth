/// Route-backed detail for an Agent result surfaced by the Life hub.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:naviwealth/core/ai/agents/agent_artifact.dart';
import 'package:naviwealth/core/ai/agents/agent_artifact_access.dart';
import 'package:naviwealth/core/ai/agents/ui/agent_result_card.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/life/composition/life_route_paths.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

final lifeAgentArtifactProvider = FutureProvider.autoDispose
    .family<AgentArtifact?, String>((ref, artifactId) {
      return readActiveAgentArtifact(ref, artifactId: artifactId);
    });

class LifeAgentArtifactPage extends ConsumerWidget {
  const LifeAgentArtifactPage({super.key, required this.artifactId});

  final String artifactId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final artifactAsync = ref.watch(lifeAgentArtifactProvider(artifactId));
    final title = artifactAsync.value?.title.trim();

    return ObjectDetailScaffold(
      title: title?.isNotEmpty == true
          ? title!
          : l10n.lifeAgentArtifactDetailTitle,
      child: artifactAsync.when(
        loading: () => const Center(
          child: FCircularProgress(size: FCircularProgressSizeVariant.sm),
        ),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.s16),
            child: AppEmptyState(
              icon: FLucideIcons.circleX,
              title: l10n.commonError,
              message: userSafeErrorMessage(
                context,
                error,
                operation: 'load agent result',
              ),
              compact: true,
            ),
          ),
        ),
        data: (artifact) {
          if (artifact == null) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.s16),
                child: AppEmptyState(
                  icon: FLucideIcons.fileQuestion,
                  title: l10n.lifeAgentArtifactMissingTitle,
                  message: l10n.lifeAgentArtifactMissingBody,
                  compact: true,
                ),
              ),
            );
          }
          return ListView(
            padding: const EdgeInsets.all(AppSpacing.s16),
            children: [
              AgentArtifactDetailBody(
                artifact: artifact,
                onVisibilityChanged: () {
                  ref.invalidate(lifeAgentArtifactProvider(artifactId));
                  if (context.mounted) context.go(LifeRoutes.home);
                },
              ),
              const SizedBox(height: AppSpacing.s16),
              AgentArtifactDetailFooter(artifact: artifact),
            ],
          );
        },
      ),
    );
  }
}
