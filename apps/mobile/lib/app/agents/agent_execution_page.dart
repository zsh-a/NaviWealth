import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

import '../../core/ai/agents/agent_artifact_routes.dart';
import '../../core/ai/agents/agent_execution.dart';
import '../../core/ai/agents/agent_registry.dart';
import '../../core/ai/agents/agent_run_controller.dart';
import '../../core/ai/agents/ui/agent_result_card.dart';
import '../../core/ai/contracts/contracts.dart';
import '../../core/ai/visual/visual.dart';
import '../../core/auth/current_user.dart';
import '../../core/auth/providers.dart' show domainOptInsProvider;
import '../../core/format/providers.dart';
import '../../core/shell/settings_route_paths.dart';
import '../../design_system/design_system.dart';
import '../../features/ai_chat/domain/chat_models.dart';
import '../../features/ai_chat/ui/messages/user_message_surface.dart';
import '../../features/ai_chat/ui/tools/tool_invocation_inline.dart';
import '../../l10n/gen/app_localizations.dart';
import '../agent_artifact_page.dart';

/// A read-only conversation projection of a runner-owned execution. Opening
/// or refreshing this route never creates a run, chat session or composer.
class AgentExecutionPage extends ConsumerStatefulWidget {
  const AgentExecutionPage({super.key, required this.agentId, this.runId});
  final String agentId;
  final String? runId;

  @override
  ConsumerState<AgentExecutionPage> createState() => _AgentExecutionPageState();
}

class _AgentExecutionPageState extends ConsumerState<AgentExecutionPage> {
  bool _starting = false;
  bool _stopping = false;

  Future<void> _retry() async {
    if (_starting) return;
    setState(() => _starting = true);
    try {
      final controller = await ref.read(agentRunControllerProvider.future);
      final record = await controller.startRunById(widget.agentId);
      if (!mounted) return;
      context.pushReplacement(
        SettingsRoutes.agentExecution(widget.agentId, runId: record.id),
      );
    } on Object catch (error) {
      if (mounted) {
        AppMessenger.show(
          context,
          ToastKind.error,
          userSafeErrorMessage(context, error, operation: 'run agent'),
        );
      }
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  Future<void> _stop(AgentExecution execution) async {
    setState(() => _stopping = true);
    try {
      final owner = await ref.read(currentUserIdProvider)();
      if (!mounted) return;
      ref.read(agentExecutionControlsProvider).cancel(owner, execution.runId);
    } finally {
      if (mounted) setState(() => _stopping = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final key = (agentId: widget.agentId, runId: widget.runId);
    final value = ref.watch(agentExecutionProvider(key));
    // Never paint retained AsyncData while account/domain dependencies reload.
    final domains = ref.watch(domainOptInsProvider);
    final owner = ref.watch(activeUserIdProvider);
    final loading = value.isLoading || domains.isLoading;
    final execution = loading || owner == null ? null : value.asData?.value;
    return ObjectDetailScaffold(
      title: execution?.title ?? l10n.agentExecutionTitle,
      child: loading
          ? const Center(child: FCircularProgress())
          : value.hasError
          ? Center(
              child: AppEmptyState.error(
                title: l10n.commonError,
                message: l10n.agentExecutionError('execution_failed'),
                retryLabel: l10n.commonRetry,
                onRetry: () => ref.invalidate(agentExecutionProvider(key)),
              ),
            )
          : execution == null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.s24),
                child: Text(l10n.agentExecutionMissing),
              ),
            )
          : _timeline(context, execution),
    );
  }

  Widget _timeline(BuildContext context, AgentExecution execution) {
    final l10n = AppLocalizations.of(context);
    final canRetry = ref
        .watch(agentRegistryProvider)
        .any((a) => a.id == execution.agentId);
    final elapsed = (execution.finishedAt ?? DateTime.now().toUtc()).difference(
      execution.startedAt,
    );
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: AdaptiveMaxWidth.narrow),
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.s16),
          children: [
            Text(
              context.formatters(ref).dateTime(execution.startedAt.toLocal()),
              style: AiType.meta(context),
            ),
            const SizedBox(height: AppSpacing.s12),
            UserMessageSurface(text: execution.instructions),
            const SizedBox(height: AppSpacing.s24),
            Semantics(
              liveRegion: true,
              child: Text(
                '${l10n.agentExecutionStatus(execution.running ? execution.phase : execution.status)} · ${_duration(elapsed.inMilliseconds)}',
                style: AiType.meta(context),
              ),
            ),
            const SizedBox(height: AppSpacing.s12),
            for (final step in execution.steps) _step(context, execution, step),
            if (execution.summary case final summary?) ...[
              const SizedBox(height: AppSpacing.s16),
              AiMarkdown(text: summary, baseStyle: AiType.readingBody(context)),
            ],
            if (execution.errorCode case final code?) ...[
              const SizedBox(height: AppSpacing.s16),
              Text(l10n.agentExecutionError(code), style: AiType.body(context)),
            ],
            const SizedBox(height: AppSpacing.s24),
            if (execution.running) ...[
              Text(l10n.agentExecutionHint, style: AiType.meta(context)),
              const SizedBox(height: AppSpacing.s12),
            ],
            Wrap(
              spacing: AppSpacing.s8,
              runSpacing: AppSpacing.s8,
              children: [
                if (execution.running)
                  AppQuietButton(
                    label: l10n.agentExecutionStop,
                    busy: _stopping,
                    onPress: _stopping ? null : () => _stop(execution),
                    prefix: const Icon(
                      FLucideIcons.square,
                      size: AppIconSizes.xs,
                    ),
                  )
                else if (canRetry)
                  AppQuietButton(
                    label: l10n.agentSettingsRunNow,
                    busy: _starting,
                    onPress: _starting ? null : _retry,
                    prefix: const Icon(
                      FLucideIcons.rotateCw,
                      size: AppIconSizes.xs,
                    ),
                  ),
                if (!execution.running)
                  AppQuietButton(
                    label: l10n.agentExecutionDiagnostics,
                    onPress: () => context.push(
                      SettingsRoutes.aiTransparencyDetail(execution.traceId),
                    ),
                    prefix: const Icon(
                      FLucideIcons.activity,
                      size: AppIconSizes.xs,
                    ),
                  ),
              ],
            ),
            if (execution.artifactId case final id?)
              _ExecutionResultActions(
                artifactId: id,
                traceId: execution.traceId,
              ),
          ],
        ),
      ),
    );
  }

  Widget _step(BuildContext context, AgentExecution execution, AiSpan step) {
    final l10n = AppLocalizations.of(context);
    final active =
        execution.running && execution.activeStepIds.contains(step.id);
    final status = active
        ? 'running'
        : switch (step.status) {
            AiSpanStatus.ok => 'completed',
            AiSpanStatus.error => 'failed',
            AiSpanStatus.cancelled => 'cancelled',
          };
    final duration = active
        ? DateTime.now()
                  .toUtc()
                  .difference(execution.startedAt)
                  .inMilliseconds -
              step.startOffsetMs
        : step.durationMs;
    final label =
        '${l10n.agentExecutionStatus(status)} · ${_duration(duration)}';
    if (step.kind == AiSpanKind.tool) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ToolInvocationInline(
            key: ValueKey(step.id),
            invocation: ToolInvocation(
              id: step.id,
              name: step.name.replaceFirst('tool:', ''),
              input: const {},
              status: active
                  ? ToolInvocationStatus.pendingResult
                  : ToolInvocationStatus.completed,
            ),
            statusLabel: label,
            isError: step.status == AiSpanStatus.error,
            isCancelled: step.status == AiSpanStatus.cancelled,
            allowDebug: false,
          ),
          if (step.status == AiSpanStatus.error && step.errorCode != null)
            Padding(
              padding: const EdgeInsets.only(
                left: AppSpacing.s24,
                bottom: AppSpacing.s8,
              ),
              child: Text(
                l10n.agentExecutionError(step.errorCode!),
                style: AiType.meta(context),
              ),
            ),
        ],
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.s6),
      child: Text(
        '${l10n.agentExecutionModel} · $label',
        style: AiType.meta(context),
      ),
    );
  }
}

String _duration(int milliseconds) =>
    '${(milliseconds.clamp(0, 86400000) / 1000).toStringAsFixed(1)}s';

class _ExecutionResultActions extends ConsumerWidget {
  const _ExecutionResultActions({
    required this.artifactId,
    required this.traceId,
  });
  final String artifactId, traceId;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(agentArtifactProvider(artifactId));
    final artifact = value.isLoading ? null : value.asData?.value;
    if (artifact == null || artifact.traceId != traceId) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.s16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AgentArtifactDetailFooter(artifact: artifact),
          AppQuietButton(
            label: AppLocalizations.of(context).agentSettingsViewResult,
            onPress: () =>
                context.push(AgentArtifactRoutes.detail(artifact.id)),
          ),
        ],
      ),
    );
  }
}
