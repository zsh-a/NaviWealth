/// Route-backed detail page for a persisted Agent result.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

import '../core/ai/agents/agent_artifact.dart';
import '../core/ai/agents/agent_artifact_access.dart';
import '../core/ai/agents/ui/agent_result_card.dart';
import '../design_system/design_system.dart';
import '../l10n/gen/app_localizations.dart';
import 'routing/route_paths.dart';

final agentArtifactProvider = FutureProvider.autoDispose
    .family<AgentArtifact?, String>((ref, artifactId) {
      return readActiveAgentArtifact(ref, artifactId: artifactId);
    });

class AgentArtifactPage extends ConsumerWidget {
  const AgentArtifactPage({super.key, required this.artifactId});

  final String artifactId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final artifactAsync = ref.watch(agentArtifactProvider(artifactId));
    final title = artifactAsync.value?.title.trim();

    return ObjectDetailScaffold(
      title: title?.isNotEmpty == true ? title! : l10n.agentArtifactDetailTitle,
      child: artifactAsync.when(
        loading: () => const Center(
          child: FCircularProgress(size: FCircularProgressSizeVariant.sm),
        ),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.s16),
            child: AppEmptyState.error(
              title: l10n.commonError,
              message: userSafeErrorMessage(
                context,
                error,
                operation: 'load agent result',
              ),
              compact: true,
              retryLabel: l10n.commonRetry,
              onRetry: () => ref.invalidate(agentArtifactProvider(artifactId)),
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
                  title: l10n.agentArtifactMissingTitle,
                  message: l10n.agentArtifactMissingBody,
                  compact: true,
                  action: FButton(
                    variant: FButtonVariant.outline,
                    onPress: () => Navigator.of(context).maybePop(),
                    child: Text(l10n.commonClose),
                  ),
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
                  ref.invalidate(agentArtifactProvider(artifactId));
                  if (!context.mounted) return;
                  if (context.canPop()) {
                    context.pop();
                  } else {
                    context.go(AppRoutes.life);
                  }
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
