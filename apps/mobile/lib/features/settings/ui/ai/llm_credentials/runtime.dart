part of '../ai_llm_credentials_page.dart';

mixin _AiLlmCredentialsRuntimeMixin on _AiLlmCredentialsPageStateBase {
  Future<void> _checkRuntime() async {
    final l10n = AppLocalizations.of(context);
    final runtime = ref.read(
      agentRuntimeProfileTurnBindingProvider(_settingsRuntimeBindingKey),
    );
    if (runtime == null) {
      _toast(ToastKind.warning, l10n.aiLlmRuntimeCheckNoProfile);
      return;
    }

    setState(() {
      _runtimeChecking = true;
      _runtimeResult = null;
      _proposalApplyResult = null;
      _runtimeError = null;
    });
    try {
      final result = await runtime.run(
        messages: <Map<String, Object?>>[
          <String, Object?>{
            'role': 'user',
            'content': l10n.aiLlmRuntimeCheckPrompt,
          },
        ],
        metadata: const <String, Object?>{'purpose': 'runtime_check'},
        maxEffectSteps: 0,
      );
      if (!mounted) return;
      setState(() {
        _runtimeChecking = false;
        _runtimeResult = result;
      });
      final status = result.step['status']?.toString() ?? 'unknown';
      _toast(ToastKind.success, l10n.aiLlmRuntimeCheckSucceeded(status));
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _runtimeChecking = false;
        _runtimeError = error;
      });
      _toast(
        ToastKind.error,
        userSafeErrorMessage(context, error, operation: 'check AI runtime'),
      );
    }
  }

  Future<void> _applyRuntimeProposal() async {
    final l10n = AppLocalizations.of(context);
    final step = _runtimeResult?.step;
    if (step == null) return;
    final plan = agentRuntimeTerminalReadyProposal(step);
    if (plan == null) return;

    final confirmed = await showConfirmDialog(
      context: context,
      title: Text(l10n.aiLlmRuntimeProposalConfirmTitle),
      body: Text(l10n.aiLlmRuntimeProposalConfirmBody(plan.summaryZh)),
      confirmLabel: l10n.aiLlmRuntimeProposalApply,
      cancelLabel: l10n.commonCancel,
      destructive: false,
    );
    if (confirmed != true) return;

    setState(() {
      _proposalApplying = true;
      _proposalApplyResult = null;
    });
    try {
      final bridge = await ref.read(agentRuntimeProposalBridgeProvider.future);
      final result = await bridge.applyTerminalReadyProposal(step);
      if (!mounted) return;
      setState(() {
        _proposalApplying = false;
        _proposalApplyResult = result;
      });
      final status = result['status']?.toString() ?? 'unknown';
      _toast(ToastKind.success, l10n.aiLlmRuntimeProposalApplied(status));
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _proposalApplying = false;
        _proposalApplyResult = <String, Object?>{
          'status': 'errored',
          'error': '$error',
        };
      });
      _toast(
        ToastKind.error,
        userSafeErrorMessage(
          context,
          error,
          operation: 'apply AI runtime proposal',
        ),
      );
    }
  }

  Widget _runtimeCheckCard(
    BuildContext context,
    AgentRuntimeProfileTurnBinding? runtime,
  ) {
    final l10n = AppLocalizations.of(context);
    final available = runtime != null;
    final status = _runtimeResult?.step['status']?.toString();
    final response = _runtimeResult?.llmResponse['content']?.toString();
    final proposal = _runtimeResult == null
        ? null
        : agentRuntimeTerminalReadyProposal(_runtimeResult!.step);
    return SoftCard(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.s16,
        AppSpacing.s14,
        AppSpacing.s16,
        AppSpacing.s16,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l10n.aiLlmRuntimeCheckTitle, style: context.labelStyle),
          const SizedBox(height: AppSpacing.s6),
          Text(
            available
                ? l10n.aiLlmRuntimeCheckReady
                : l10n.aiLlmRuntimeCheckNoProfile,
            style: context.captionStyle,
          ),
          const SizedBox(height: AppSpacing.s12),
          FButton(
            variant: FButtonVariant.outline,
            onPress: !available || _runtimeChecking ? null : _checkRuntime,
            child: Text(
              _runtimeChecking
                  ? l10n.aiLlmRuntimeCheckRunning
                  : l10n.aiLlmRuntimeCheckAction,
            ),
          ),
          if (status != null || _runtimeError != null) ...[
            const SizedBox(height: AppSpacing.s10),
            Text(
              status != null
                  ? l10n.aiLlmRuntimeCheckStatus(status)
                  : l10n.aiLlmRuntimeCheckFailed('$_runtimeError'),
              style: context.captionStyle.copyWith(
                color: status != null
                    ? context.theme.colors.primary
                    : context.theme.colors.destructive,
              ),
            ),
          ],
          if (response != null && response.trim().isNotEmpty) ...[
            const SizedBox(height: AppSpacing.s6),
            Text(
              response.trim(),
              style: context.bodyCaptionStyle,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          if (proposal != null) ...[
            const SizedBox(height: AppSpacing.s12),
            _runtimeProposalCard(context, proposal),
          ],
        ],
      ),
    );
  }

  Widget _runtimeProposalCard(BuildContext context, ReadyProposalPlan plan) {
    final l10n = AppLocalizations.of(context);
    final applyStatus = _proposalApplyResult?['status']?.toString();
    final error = _proposalApplyResult?['error']?.toString();
    return Container(
      padding: const EdgeInsets.all(AppSpacing.s12),
      decoration: BoxDecoration(
        color: context.theme.colors.muted,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: context.theme.colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                FLucideIcons.fileCheck2,
                size: AppIconSizes.h18,
                color: context.theme.colors.foreground,
              ),
              const SizedBox(width: AppSpacing.s8),
              Expanded(
                child: Text(
                  l10n.aiLlmRuntimeProposalTitle(plan.kind),
                  style: context.captionLabelStyle,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s6),
          Text(plan.summaryZh, style: context.bodyCaptionStyle),
          if (plan.warnings.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.s8),
            for (final warning in plan.warnings)
              Text(
                l10n.aiLlmRuntimeProposalWarning(warning),
                style: context.captionStyle.copyWith(
                  color: context.theme.colors.mutedForeground,
                ),
              ),
          ],
          const SizedBox(height: AppSpacing.s10),
          FButton(
            variant: FButtonVariant.primary,
            onPress: _proposalApplying ? null : _applyRuntimeProposal,
            prefix: const Icon(FLucideIcons.check, size: AppIconSizes.xs),
            child: Text(
              _proposalApplying
                  ? l10n.aiLlmRuntimeProposalApplying
                  : l10n.aiLlmRuntimeProposalApply,
            ),
          ),
          if (applyStatus != null) ...[
            const SizedBox(height: AppSpacing.s8),
            Text(
              error == null
                  ? l10n.aiLlmRuntimeProposalStatus(applyStatus)
                  : l10n.aiLlmRuntimeProposalFailed(error),
              style: context.captionStyle.copyWith(
                color: error == null
                    ? context.theme.colors.primary
                    : context.theme.colors.destructive,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
