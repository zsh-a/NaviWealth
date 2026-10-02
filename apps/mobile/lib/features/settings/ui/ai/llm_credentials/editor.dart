part of '../ai_llm_credentials_page.dart';

mixin _AiLlmCredentialsEditorMixin on _AiLlmCredentialsPageStateBase {
  @override
  void _openEditor({LlmProfile? profile}) async {
    if (_saving || _probing) return;
    if (!await confirmDiscardIfDirty(context, dirty) || !mounted) return;
    _nameController.text = profile?.name ?? '';
    _keyController.clear();
    _baseUrlController.text = profile?.baseUrl ?? '';
    _modelController.text = profile?.model ?? '';
    setState(() {
      _editingId = profile?.id ?? '';
      _editingProfile = profile;
      _probeError = null;
      _provider = profile?.provider ?? LlmProvider.anthropic;
      _probeResult = null;
    });
    dirty.snapshotBaseline();
  }

  void _closeEditor() async {
    if (_saving || _probing) return;
    if (!await confirmDiscardIfDirty(context, dirty) || !mounted) return;
    _finishEditor();
  }

  void _finishEditor() {
    dirty.markPristine();
    _keyController.clear();
    setState(() {
      _editingId = null;
      _editingProfile = null;
      _probeResult = null;
      _probeError = null;
    });
    dirty.snapshotBaseline();
  }

  void _setSaving(bool value) {
    if (mounted) setState(() => _saving = value);
  }

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
    if (_saving || _probing) return;
    final draft = _draftProfile(existing);
    setState(() {
      _probing = true;
      _probeResult = null;
      _probeError = null;
    });
    dirty.busy = true;
    try {
      final result = await ref.read(llmConnectivityProbeProvider).probe(draft);
      if (!mounted) return;
      setState(() => _probeResult = result);
      _toast(switch (result.status) {
        LlmProbeStatus.ok => ToastKind.success,
        LlmProbeStatus.rateLimited ||
        LlmProbeStatus.badRequest => ToastKind.warning,
        _ => ToastKind.error,
      }, result.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _probeError = AppLocalizations.of(context).commonLoadFailed,
        );
      }
    } finally {
      dirty.busy = false;
      if (mounted) setState(() => _probing = false);
    }
  }

  Future<void> _save(LlmProfile? existing) async {
    if (_saving || _probing) return;
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
    final l10n = AppLocalizations.of(context);
    await submitForm<void>(
      dirty: dirty,
      onBusyChanged: _setSaving,
      commit: () =>
          ref.read(llmCredentialsProvider.notifier).upsertProfile(profile),
      leave: _finishEditor,
      failureMessage: (_) => l10n.commonSaveFailed,
      successMessage: l10n.aiLlmSaved,
      showFailureToast: false,
      tag: 'llm-profile',
    );
  }

  @override
  Future<void> _activate(String id) async {
    if (_saving || _editingId != null) return;
    final l10n = AppLocalizations.of(context);
    await submitForm<void>(
      dirty: dirty,
      onBusyChanged: _setSaving,
      commit: () => ref.read(llmCredentialsProvider.notifier).setActive(id),
      leave: () {},
      failureMessage: (_) => l10n.commonSaveFailed,
      successMessage: l10n.aiLlmSwitched,
      tag: 'llm-profile-activate',
    );
  }

  @override
  Future<void> _delete(LlmProfile profile) async {
    if (_saving || _editingId != null) return;
    final l10n = AppLocalizations.of(context);
    final confirm = await showConfirmDialog(
      context: context,
      title: Text(l10n.aiLlmDeleteTitle),
      body: Text(l10n.aiLlmDeleteBody(profile.displayName)),
      confirmLabel: l10n.commonDelete,
      cancelLabel: l10n.commonCancel,
      destructive: true,
    );
    if (confirm != true || !mounted || _saving) return;
    await submitForm<void>(
      dirty: dirty,
      onBusyChanged: _setSaving,
      commit: () =>
          ref.read(llmCredentialsProvider.notifier).removeProfile(profile.id),
      leave: () {},
      failureMessage: (_) => l10n.commonDeleteFailed,
      successMessage: l10n.aiLlmRemoved,
      tag: 'llm-profile-delete',
    );
  }

  Widget _editorCard(
    BuildContext context,
    LlmProfile? existing, {
    bool includeActions = true,
  }) {
    final l10n = AppLocalizations.of(context);
    final hasStoredKey = existing?.hasKey ?? false;
    return SoftCard.flat(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.s16,
        AppSpacing.s14,
        AppSpacing.s16,
        AppSpacing.s16,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            existing == null ? l10n.aiLlmAddProvider : l10n.aiLlmEditProvider,
            style: context.labelStyle,
          ),
          const SizedBox(height: AppSpacing.s14),
          _label(context, l10n.aiLlmNameLabel),
          const SizedBox(height: AppSpacing.s6),
          FTextFormField(
            enabled: !_saving && !_probing,
            key: const Key('llm-profile-name'),
            control: FTextFieldControl.managed(controller: _nameController),
            hint: l10n.aiLlmNameHint,
            autocorrect: false,
            enableSuggestions: false,
          ),
          const SizedBox(height: AppSpacing.s16),
          _label(context, l10n.aiLlmProviderLabel),
          const SizedBox(height: AppSpacing.s4),
          FSelect<LlmProvider>(
            key: ValueKey(_editingId),
            enabled: !_saving && !_probing,
            items: {
              for (final p in LlmProvider.values) _providerLabel(l10n, p): p,
            },
            control: FSelectControl<LlmProvider>.managed(
              initial: _provider,
              onChange: (value) {
                if (value == null) return;
                setState(() {
                  _provider = value;
                  dirty.markDirty();
                  _probeResult = null;
                });
              },
            ),
          ),
          const SizedBox(height: AppSpacing.s16),
          _label(context, 'API Key'),
          const SizedBox(height: AppSpacing.s6),
          FTextFormField(
            enabled: !_saving && !_probing,
            key: const Key('llm-profile-key'),
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
            enabled: !_saving && !_probing,
            control: FTextFieldControl.managed(controller: _baseUrlController),
            hint: _baseUrlHint(_provider),
            autocorrect: false,
            enableSuggestions: false,
          ),
          const SizedBox(height: AppSpacing.s16),
          _label(context, l10n.aiLlmModelLabel),
          const SizedBox(height: AppSpacing.s6),
          FTextFormField(
            enabled: !_saving && !_probing,
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
          if (_probeError != null) ...[
            const SizedBox(height: AppSpacing.s8),
            AppStatusBanner(
              kind: AppStatusKind.error,
              message: _probeError!,
              compact: true,
            ),
          ],
          if (_probeResult != null) ...[
            const SizedBox(height: AppSpacing.s8),
            Text(
              '${_probePrefix(_probeResult!)}${_probeResult!.message}',
              style: context.captionStyle.copyWith(
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
          child: AppBusyButton(
            label: l10n.commonSave,
            busyLabel: l10n.aiLlmSaving,
            busy: _saving,
            onPress: _saving || _probing
                ? null
                : () => unawaited(_save(existing)),
          ),
        ),
        const SizedBox(width: AppSpacing.s12),
        Expanded(
          child: FButton(
            variant: FButtonVariant.outline,
            onPress: _saving || _probing ? null : _closeEditor,
            child: Text(l10n.commonCancel),
          ),
        ),
      ],
    );
  }

  String _providerLabel(AppLocalizations l10n, LlmProvider provider) =>
      switch (provider) {
        LlmProvider.anthropic => l10n.aiLlmAnthropicProtocol(provider.label),
        LlmProvider.openai => l10n.aiLlmOpenAiProtocol(provider.label),
      };

  String _keyHint(LlmProvider provider) => switch (provider) {
    LlmProvider.anthropic => 'sk-ant-\u2026',
    LlmProvider.openai => 'sk-\u2026',
  };

  String _baseUrlHint(LlmProvider provider) => switch (provider) {
    LlmProvider.anthropic => 'https://api.anthropic.com',
    LlmProvider.openai => 'https://api.openai.com',
  };

  String _modelHint(LlmProvider provider) => switch (provider) {
    LlmProvider.anthropic => kDefaultDeviceModel,
    LlmProvider.openai => 'gpt-4o-mini',
  };

  String _probePrefix(LlmProbeResult result) {
    if (result.ok) return '\u25cf ';
    if (result.reachedProvider) return '\u25d0 ';
    return '\u25cb ';
  }
}
