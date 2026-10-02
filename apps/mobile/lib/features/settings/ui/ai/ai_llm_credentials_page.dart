/// Settings page for native, bring-your-own-key LLM profiles.
///
/// Users can keep multiple provider profiles and switch the active one. Keys
/// are stored through [llmCredentialsProvider]; web builds show an explanatory
/// unsupported-state card because there is no web AI runtime.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:uuid/uuid.dart';

import '../../../../app/agent_runtime/bindings/agent_runtime_profile_turn_binding.dart';
import '../../../../app/agent_runtime/proposals/agent_runtime_proposal_bridge.dart';
import '../../../../core/ai/composition/proposal_plan.dart';
import '../../../../core/ai/llm_credentials/llm_connectivity.dart';
import '../../../../core/ai/llm_credentials/llm_credentials.dart';
import '../../../../core/ai/llm_credentials/providers.dart';
import '../../../../core/forms/forms.dart';
import '../../../../core/shell/settings_route_paths.dart';
import '../../../../core/shell/settings_ui/settings_page_frame.dart';
import '../../../../design_system/design_system.dart';
import '../../../../l10n/gen/app_localizations.dart';

part 'llm_credentials/editor.dart';
part 'llm_credentials/profile_cards.dart';
part 'llm_credentials/runtime.dart';

const _settingsRuntimeBindingKey = (
  agentId: kSettingsLlmRuntimeCheckAgentId,
  domain: 'settings',
  surface: 'settings_ai_llm',
);

class AiLlmCredentialsPage extends ConsumerStatefulWidget {
  const AiLlmCredentialsPage({super.key});

  @override
  ConsumerState<AiLlmCredentialsPage> createState() =>
      _AiLlmCredentialsPageState();
}

abstract class _AiLlmCredentialsPageStateBase
    extends ConsumerState<AiLlmCredentialsPage>
    with
        FormSubmission<AiLlmCredentialsPage>,
        FormDirtyGuard<AiLlmCredentialsPage> {
  @override
  String get leaveFallback => SettingsRoutes.ai;

  @override
  void initState() {
    super.initState();
    dirty.bindTextControllers([
      _nameController,
      _keyController,
      _baseUrlController,
      _modelController,
    ]);
  }

  final _nameController = TextEditingController();
  final _keyController = TextEditingController();
  final _baseUrlController = TextEditingController();
  final _modelController = TextEditingController();
  LlmProfile? _editingProfile;
  String? _probeError;
  LlmProvider _provider = LlmProvider.anthropic;

  /// `null` means editor closed. Empty string means a brand-new profile.
  String? _editingId;
  bool _saving = false;
  bool _probing = false;
  bool _runtimeChecking = false;
  bool _proposalApplying = false;
  LlmProbeResult? _probeResult;
  AgentRuntimeProfileTurnResult? _runtimeResult;
  Map<String, Object?>? _proposalApplyResult;
  Object? _runtimeError;

  @override
  void dispose() {
    _nameController.dispose();
    _keyController.dispose();
    _baseUrlController.dispose();
    _modelController.dispose();
    super.dispose();
  }

  void _toast(ToastKind kind, String msg) =>
      AppMessenger.show(context, kind, msg);

  void _openEditor({LlmProfile? profile});

  Future<void> _activate(String id);

  Future<void> _delete(LlmProfile profile);

  Widget _label(BuildContext context, String text);
}

class _AiLlmCredentialsPageState extends _AiLlmCredentialsPageStateBase
    with
        _AiLlmCredentialsEditorMixin,
        _AiLlmCredentialsRuntimeMixin,
        _AiLlmCredentialsProfileCardsMixin {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final supported = ref.watch(deviceLlmPlatformSupportedProvider);
    final asyncCreds = ref.watch(llmCredentialsProvider);
    final runtime = ref.watch(
      agentRuntimeProfileTurnBindingProvider(_settingsRuntimeBindingKey),
    );
    final creds = asyncCreds.asData?.value ?? const LlmCredentials();
    final profiles = creds.profiles;
    final editing = _editingId != null;
    final existing = _editingProfile;
    return guardedScope(
      alwaysHandleBack: true,
      child: AppFormPageScaffold(
        title: Text(l10n.settingsAiLlmTitle),
        confirmLeave: handleBackIntent,
        child: !supported
            ? SettingsPageFrame(
                topPadding: AppSpacing.s8,
                children: [_unsupportedCard(context)],
              )
            : editing
            ? AppFormScaffoldBody(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.s16,
                  AppSpacing.s8,
                  AppSpacing.s16,
                  AppSpacing.s16,
                ),
                action: _editorActions(context, existing),
                children: _supportedBody(
                  context,
                  asyncCreds: asyncCreds,
                  profiles: profiles,
                  existing: existing,
                  runtime: runtime,
                  includeEditorActions: false,
                ),
              )
            : SettingsPageFrame(
                topPadding: AppSpacing.s8,
                children: _supportedBody(
                  context,
                  asyncCreds: asyncCreds,
                  profiles: profiles,
                  existing: null,
                  runtime: runtime,
                ),
              ),
      ),
    );
  }

  List<Widget> _supportedBody(
    BuildContext context, {
    required AsyncValue<LlmCredentials?> asyncCreds,
    required List<LlmProfile> profiles,
    required LlmProfile? existing,
    required AgentRuntimeProfileTurnBinding? runtime,
    bool includeEditorActions = true,
  }) {
    final l10n = AppLocalizations.of(context);
    final creds = asyncCreds.asData?.value ?? const LlmCredentials();

    if (!asyncCreds.hasValue && _editingId == null) {
      return [
        asyncCreds.when(
          loading: () => const SkeletonBox(height: 120),
          error: (error, stack) => kDefaultError(
            context,
            error,
            stack,
            onRetry: () => ref.invalidate(llmCredentialsProvider),
          ),
          data: (_) => const SizedBox.shrink(),
        ),
      ];
    }
    if (_editingId != null) {
      return [
        if (submissionFailureMessage != null) ...[
          AppStatusBanner(
            kind: AppStatusKind.error,
            message: submissionFailureMessage!,
            compact: true,
          ),
          const SizedBox(height: AppSpacing.s12),
        ],
        _editorCard(context, existing, includeActions: includeEditorActions),
      ];
    }
    return [
      if (submissionFailureMessage != null) ...[
        AppStatusBanner(
          kind: AppStatusKind.error,
          message: submissionFailureMessage!,
          compact: true,
        ),
        const SizedBox(height: AppSpacing.s12),
      ],
      _intro(context),
      const SizedBox(height: AppSpacing.s12),
      if (profiles.isEmpty && _editingId == null)
        SoftCard.flat(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.s16,
            vertical: AppSpacing.s20,
          ),
          child: Text(l10n.aiLlmEmpty, style: context.bodyCaptionStyle),
        )
      else
        for (final p in profiles) ...[
          _profileCard(context, p, isActive: p.id == creds.activeId),
          const SizedBox(height: AppSpacing.s10),
        ],
      if (_editingId != null) ...[
        const SizedBox(height: AppSpacing.s2),
        _editorCard(context, existing, includeActions: includeEditorActions),
      ] else ...[
        const SizedBox(height: AppSpacing.s4),
        FButton(
          variant: FButtonVariant.outline,
          onPress: _saving || !asyncCreds.hasValue ? null : () => _openEditor(),
          child: Text(l10n.aiLlmAddProvider),
        ),
      ],
      const SizedBox(height: AppSpacing.s16),
      _runtimeCheckCard(context, runtime),
      const SizedBox(height: AppSpacing.s16),
      _statusLine(context, asyncCreds, l10n),
    ];
  }
}
