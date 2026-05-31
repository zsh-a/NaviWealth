/// Settings ▸ on-device AI (bring-your-own key).
///
/// Manage **multiple** provider profiles (official Anthropic, a
/// self-hosted gateway, a regional proxy, …) and switch the active one
/// with a single tap. Keys are stored in the Keychain/Keystore via
/// [llmCredentialsProvider]; the active profile drives the device
/// runtime. Native platforms only — web sees an explanatory
/// card.
///
/// The old "启用端侧 AI" opt-in switch was removed: there is
/// no cloud relay to fall back to, so the active profile *is* the
/// intent.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:uuid/uuid.dart';

import '../../../core/ai/llm_credentials/llm_connectivity.dart';
import '../../../core/ai/llm_credentials/llm_credentials.dart';
import '../../../core/ai/llm_credentials/providers.dart';
import '../../../core/ai/runtime/device/anthropic/anthropic_wire.dart'
    show kDefaultDeviceModel;
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';

class AiLlmCredentialsPage extends ConsumerStatefulWidget {
  const AiLlmCredentialsPage({super.key});

  @override
  ConsumerState<AiLlmCredentialsPage> createState() =>
      _AiLlmCredentialsPageState();
}

class _AiLlmCredentialsPageState extends ConsumerState<AiLlmCredentialsPage> {
  final _nameController = TextEditingController();
  final _keyController = TextEditingController();
  final _baseUrlController = TextEditingController();
  final _modelController = TextEditingController();
  LlmProvider _provider = LlmProvider.anthropic;

  /// `null` ⇒ editor closed. Otherwise the id being edited, or the
  /// empty string for a brand-new profile.
  String? _editingId;
  bool _saving = false;
  bool _probing = false;
  LlmProbeResult? _probeResult;

  @override
  void dispose() {
    _nameController.dispose();
    _keyController.dispose();
    _baseUrlController.dispose();
    _modelController.dispose();
    super.dispose();
  }

  void _openEditor({LlmProfile? profile}) {
    _nameController.text = profile?.name ?? '';
    _keyController.clear(); // never echo a stored key
    _baseUrlController.text = profile?.baseUrl ?? '';
    _modelController.text = profile?.model ?? '';
    setState(() {
      _editingId = profile?.id ?? '';
      _provider = profile?.provider ?? LlmProvider.anthropic;
      _probeResult = null;
    });
  }

  void _closeEditor() => setState(() {
    _editingId = null;
    _probeResult = null;
  });

  /// Build the profile the editor currently describes (typed key, or
  /// the stored key when editing and the field is left blank).
  LlmProfile _draftProfile(LlmProfile? existing) {
    final typed = _keyController.text.trim();
    return LlmProfile(
      id: existing?.id ?? 'probe',
      name: _nameController.text.trim(),
      provider: _provider,
      apiKey: typed.isNotEmpty ? typed : (existing?.apiKey ?? ''),
      baseUrl: _baseUrlController.text.trim().isEmpty
          ? null
          : _baseUrlController.text.trim(),
      model: _modelController.text.trim().isEmpty
          ? null
          : _modelController.text.trim(),
    );
  }

  Future<void> _test(LlmProfile? existing) async {
    setState(() {
      _probing = true;
      _probeResult = null;
    });
    final result = await ref
        .read(llmConnectivityProbeProvider)
        .probe(_draftProfile(existing));
    if (!mounted) return;
    setState(() {
      _probing = false;
      _probeResult = result;
    });
    _toast(switch (result.status) {
      LlmProbeStatus.ok => ToastKind.success,
      LlmProbeStatus.rateLimited ||
      LlmProbeStatus.badRequest => ToastKind.warning,
      _ => ToastKind.error,
    }, result.message);
  }

  Future<void> _save(LlmProfile? existing) async {
    final typedKey = _keyController.text.trim();
    final effectiveKey = typedKey.isNotEmpty
        ? typedKey
        : (existing?.apiKey ?? '');
    if (effectiveKey.isEmpty) {
      _toast(
        ToastKind.warning,
        AppLocalizations.of(context).aiLlmMissingApiKey,
      );
      return;
    }
    final profile = LlmProfile(
      id: existing?.id ?? const Uuid().v4(),
      name: _nameController.text.trim(),
      provider: _provider,
      apiKey: effectiveKey,
      baseUrl: _baseUrlController.text.trim().isEmpty
          ? null
          : _baseUrlController.text.trim(),
      model: _modelController.text.trim().isEmpty
          ? null
          : _modelController.text.trim(),
    );
    setState(() => _saving = true);
    await ref.read(llmCredentialsProvider.notifier).upsertProfile(profile);
    if (!mounted) return;
    setState(() {
      _saving = false;
      _editingId = null;
    });
    _toast(ToastKind.success, AppLocalizations.of(context).aiLlmSaved);
  }

  Future<void> _activate(String id) async {
    await ref.read(llmCredentialsProvider.notifier).setActive(id);
    if (!mounted) return;
    _toast(ToastKind.success, AppLocalizations.of(context).aiLlmSwitched);
  }

  Future<void> _delete(LlmProfile profile) async {
    await ref.read(llmCredentialsProvider.notifier).removeProfile(profile.id);
    if (!mounted) return;
    if (_editingId == profile.id) _closeEditor();
    _toast(ToastKind.success, AppLocalizations.of(context).aiLlmRemoved);
  }

  void _toast(ToastKind kind, String msg) =>
      AppMessenger.show(context, kind, msg);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final supported = ref.watch(deviceLlmPlatformSupportedProvider);
    final asyncCreds = ref.watch(llmCredentialsProvider);
    final creds = asyncCreds.asData?.value ?? const LlmCredentials();
    final profiles = creds.profiles;
    final editing = _editingId != null;
    final existing = editing
        ? profiles
              .where((p) => p.id == _editingId)
              .cast<LlmProfile?>()
              .firstWhere((_) => true, orElse: () => null)
        : null;
    return FScaffold(
      header: FHeader.nested(
        title: Text(l10n.settingsAiLlmTitle),
        prefixes: [backHeaderAction(context)],
      ),
      childPad: false,
      resizeToAvoidBottomInset: false,
      child: !supported
          ? ListView(
              padding: const EdgeInsets.fromLTRB(AppSpacing.s16, AppSpacing.s8, AppSpacing.s16, AppSpacing.s24),
              children: [_unsupportedCard(context)],
            )
          : editing
          ? AppFormScaffoldBody(
              padding: const EdgeInsets.fromLTRB(AppSpacing.s16, AppSpacing.s8, AppSpacing.s16, AppSpacing.s16),
              action: _editorActions(context, existing),
              children: _supportedBody(
                context,
                asyncCreds: asyncCreds,
                profiles: profiles,
                existing: existing,
                includeEditorActions: false,
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(AppSpacing.s16, AppSpacing.s8, AppSpacing.s16, AppSpacing.s24),
              children: _supportedBody(
                context,
                asyncCreds: asyncCreds,
                profiles: profiles,
                existing: null,
              ),
            ),
    );
  }

  List<Widget> _supportedBody(
    BuildContext context, {
    required AsyncValue<LlmCredentials?> asyncCreds,
    required List<LlmProfile> profiles,
    required LlmProfile? existing,
    bool includeEditorActions = true,
  }) {
    final l10n = AppLocalizations.of(context);
    final creds = asyncCreds.asData?.value ?? const LlmCredentials();

    return [
      _intro(context),
      const SizedBox(height: AppSpacing.s12),
      if (profiles.isEmpty && _editingId == null)
        SoftCard(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s16, vertical: 18),
          child: Text(
            l10n.aiLlmEmpty,
            style: context.theme.typography.sm.copyWith(
              color: context.theme.colors.mutedForeground,
            ),
          ),
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
          onPress: () => _openEditor(),
          child: Text(l10n.aiLlmAddProvider),
        ),
      ],
      const SizedBox(height: AppSpacing.s16),
      _statusLine(context, asyncCreds, l10n),
    ];
  }

  Widget _profileCard(
    BuildContext context,
    LlmProfile p, {
    required bool isActive,
  }) {
    final l10n = AppLocalizations.of(context);
    final colors = context.theme.colors;
    final meta = <String>[
      p.provider.label,
      _hostOf(p),
      if (p.model != null && p.model!.isNotEmpty) p.model!,
    ].join(' · ');
    final card = SoftCard(
      padding: const EdgeInsets.fromLTRB(AppSpacing.s16, AppSpacing.s12, AppSpacing.s12, AppSpacing.s12),
      onPress: isActive ? null : () => _activate(p.id),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        p.displayName,
                        style: context.theme.typography.sm.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.s8),
                    if (isActive)
                      _tag(context, l10n.aiLlmActiveTag, colors.primary)
                    else
                      Text(
                        l10n.aiLlmTapToSwitch,
                        style: context.theme.typography.xs.copyWith(
                          color: colors.mutedForeground,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: AppSpacing.s4),
                Text(
                  meta,
                  style: context.theme.typography.xs.copyWith(
                    color: colors.mutedForeground,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.s6),
          _iconAction(
            context,
            FLucideIcons.pencil,
            () => _openEditor(profile: p),
          ),
          _iconAction(context, FLucideIcons.trash2, () => _delete(p)),
        ],
      ),
    );
    if (!isActive) return card;
    // SoftCard exposes no border slot — wrap to mark the active one.
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(
          color: colors.primary.withValues(alpha: AppOpacity.disabled),
          width: 1.5,
        ),
      ),
      child: card,
    );
  }

  Widget _editorCard(
    BuildContext context,
    LlmProfile? existing, {
    bool includeActions = true,
  }) {
    final l10n = AppLocalizations.of(context);
    final hasStoredKey = existing?.hasKey ?? false;
    return SoftCard(
      padding: const EdgeInsets.fromLTRB(AppSpacing.s16, AppSpacing.s14, AppSpacing.s16, AppSpacing.s16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            existing == null ? l10n.aiLlmAddProvider : l10n.aiLlmEditProvider,
            style: context.theme.typography.sm.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppSpacing.s14),
          _label(context, l10n.aiLlmNameLabel),
          const SizedBox(height: AppSpacing.s6),
          FTextFormField(
            control: FTextFieldControl.managed(controller: _nameController),
            hint: l10n.aiLlmNameHint,
            autocorrect: false,
            enableSuggestions: false,
          ),
          const SizedBox(height: AppSpacing.s16),
          _label(context, l10n.aiLlmProviderLabel),
          const SizedBox(height: AppSpacing.s4),
          FSelect<LlmProvider>(
            items: {
              for (final p in LlmProvider.values) _providerLabel(l10n, p): p,
            },
            control: FSelectControl<LlmProvider>.managed(
              initial: _provider,
              onChange: (value) {
                if (value == null) return;
                setState(() {
                  _provider = value;
                  _probeResult = null;
                });
              },
            ),
          ),
          const SizedBox(height: AppSpacing.s16),
          _label(context, 'API Key'),
          const SizedBox(height: AppSpacing.s6),
          FTextFormField(
            control: FTextFieldControl.managed(controller: _keyController),
            hint: hasStoredKey ? l10n.aiLlmStoredKeyHint : _keyHint(_provider),
            obscureText: true,
            autocorrect: false,
            enableSuggestions: false,
          ),
          const SizedBox(height: AppSpacing.s16),
          _label(context, l10n.aiLlmBaseUrlLabel),
          const SizedBox(height: AppSpacing.s6),
          FTextFormField(
            control: FTextFieldControl.managed(controller: _baseUrlController),
            hint: _baseUrlHint(_provider),
            autocorrect: false,
            enableSuggestions: false,
          ),
          const SizedBox(height: AppSpacing.s16),
          _label(context, l10n.aiLlmModelLabel),
          const SizedBox(height: AppSpacing.s6),
          FTextFormField(
            control: FTextFieldControl.managed(controller: _modelController),
            hint: _modelHint(_provider),
            autocorrect: false,
            enableSuggestions: false,
          ),
          const SizedBox(height: AppSpacing.s20),
          FButton(
            variant: FButtonVariant.outline,
            onPress: (_probing || _saving) ? null : () => _test(existing),
            child: Text(
              _probing ? l10n.aiLlmTesting : l10n.aiLlmTestConnectivity,
            ),
          ),
          if (_probeResult != null) ...[
            const SizedBox(height: AppSpacing.s8),
            Text(
              '${_probeResult!.ok ? '● ' : (_probeResult!.reachedProvider ? '◐ ' : '○ ')}'
              '${_probeResult!.message}',
              style: context.theme.typography.xs.copyWith(
                color: _probeResult!.ok
                    ? context.theme.colors.primary
                    : _probeResult!.reachedProvider
                    ? context.theme.colors.foreground
                    : context.theme.colors.destructive,
              ),
            ),
          ],
          if (includeActions) ...[
            const SizedBox(height: AppSpacing.s14),
            _editorActions(context, existing),
          ],
        ],
      ),
    );
  }

  Widget _editorActions(BuildContext context, LlmProfile? existing) {
    final l10n = AppLocalizations.of(context);
    return Row(
      children: [
        Expanded(
          child: FButton(
            onPress: _saving ? null : () => _save(existing),
            child: Text(_saving ? l10n.aiLlmSaving : l10n.commonSave),
          ),
        ),
        const SizedBox(width: AppSpacing.s12),
        Expanded(
          child: FButton(
            variant: FButtonVariant.outline,
            onPress: _saving ? null : _closeEditor,
            child: Text(l10n.commonCancel),
          ),
        ),
      ],
    );
  }

  Widget _intro(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.s4),
      child: Text(
        l10n.aiLlmIntro,
        style: context.theme.typography.sm.copyWith(
          color: context.theme.colors.mutedForeground,
        ),
      ),
    );
  }

  Widget _unsupportedCard(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SoftCard(
      padding: const EdgeInsets.fromLTRB(AppSpacing.s16, AppSpacing.s14, AppSpacing.s16, AppSpacing.s16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.aiLlmUnsupportedTitle,
            style: context.theme.typography.sm.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppSpacing.s6),
          Text(
            l10n.aiLlmUnsupportedBody,
            style: context.theme.typography.xs.copyWith(
              color: context.theme.colors.mutedForeground,
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusLine(
    BuildContext context,
    AsyncValue<LlmCredentials?> async,
    AppLocalizations l10n,
  ) {
    final text = switch (async) {
      AsyncData(:final value) when value?.isUsable == true =>
        '● ${l10n.aiLlmStatusActive(value!.active!.displayName)}',
      AsyncData(:final value) when (value?.profiles.isNotEmpty ?? false) =>
        '○ ${l10n.aiLlmStatusSavedNoActive}',
      AsyncError() => l10n.aiLlmStatusReadFailed,
      _ => l10n.aiLlmStatusNotConfigured,
    };
    return Text(
      text,
      style: context.theme.typography.xs.copyWith(
        color: context.theme.colors.mutedForeground,
      ),
    );
  }

  Widget _label(BuildContext context, String text) => Text(
    text,
    style: context.theme.typography.xs.copyWith(
      color: context.theme.colors.mutedForeground,
      fontWeight: FontWeight.w600,
    ),
  );

  Widget _tag(BuildContext context, String text, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: AppSpacing.s2),
    decoration: BoxDecoration(
      color: color.withValues(alpha: AppOpacity.medium),
      borderRadius: BorderRadius.circular(AppRadius.xs),
    ),
    child: Text(
      text,
      style: context.theme.typography.xs.copyWith(
        color: color,
        fontWeight: FontWeight.w600,
      ),
    ),
  );

  Widget _iconAction(
    BuildContext context,
    IconData icon,
    VoidCallback onPress,
  ) => FTappable(
    onPress: onPress,
    child: Padding(
      padding: const EdgeInsets.all(AppSpacing.s8),
      child: Icon(icon, size: AppIconSizes.h18, color: context.theme.colors.mutedForeground),
    ),
  );

  String _hostOf(LlmProfile profile) {
    final url = profile.baseUrl;
    if (url == null || url.trim().isEmpty) {
      return switch (profile.provider) {
        LlmProvider.anthropic => 'api.anthropic.com',
        LlmProvider.openai => 'api.openai.com',
      };
    }
    final u = Uri.tryParse(url.trim());
    if (u != null && u.host.isNotEmpty) return u.host;
    return url.trim();
  }

  String _providerLabel(AppLocalizations l10n, LlmProvider provider) =>
      switch (provider) {
        LlmProvider.anthropic => l10n.aiLlmAnthropicProtocol(provider.label),
        LlmProvider.openai => l10n.aiLlmOpenAiProtocol(provider.label),
      };

  String _keyHint(LlmProvider provider) => switch (provider) {
    LlmProvider.anthropic => 'sk-ant-…',
    LlmProvider.openai => 'sk-…',
  };

  String _baseUrlHint(LlmProvider provider) => switch (provider) {
    LlmProvider.anthropic => 'https://api.anthropic.com',
    LlmProvider.openai => 'https://api.openai.com',
  };

  String _modelHint(LlmProvider provider) => switch (provider) {
    LlmProvider.anthropic => kDefaultDeviceModel,
    LlmProvider.openai => 'gpt-4o-mini',
  };
}
