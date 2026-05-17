/// §4.6 W-D1 / Wave 46 — Settings ▸ on-device AI (bring-your-own key).
///
/// Manage **multiple** provider profiles (official Anthropic, a
/// self-hosted gateway, a regional proxy, …) and switch the active one
/// with a single tap. Keys are stored in the Keychain/Keystore via
/// [llmCredentialsProvider]; the active profile drives the device
/// runtime (W-D3). Native platforms only — web sees an explanatory
/// card.
///
/// The old "启用端侧 AI" opt-in switch was removed: post-W-D7 there is
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
import '../../../design_system/design_system.dart';

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
      _toast(ToastKind.warning, '请先填入 API Key');
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
    _toast(ToastKind.success, '已保存到设备安全存储');
  }

  Future<void> _activate(String id) async {
    await ref.read(llmCredentialsProvider.notifier).setActive(id);
    if (!mounted) return;
    _toast(ToastKind.success, '已切换');
  }

  Future<void> _delete(LlmProfile profile) async {
    await ref.read(llmCredentialsProvider.notifier).removeProfile(profile.id);
    if (!mounted) return;
    if (_editingId == profile.id) _closeEditor();
    _toast(ToastKind.success, '已从设备移除');
  }

  void _toast(ToastKind kind, String msg) =>
      AppMessenger.show(context, kind, msg);

  @override
  Widget build(BuildContext context) {
    final supported = ref.watch(deviceLlmPlatformSupportedProvider);
    return FScaffold(
      header: FHeader.nested(
        title: const Text('端侧 AI · 自带 Key'),
        prefixes: [backHeaderAction(context)],
      ),
      childPad: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: supported
            ? _supportedBody(context)
            : [_unsupportedCard(context)],
      ),
    );
  }

  List<Widget> _supportedBody(BuildContext context) {
    final asyncCreds = ref.watch(llmCredentialsProvider);
    final creds = asyncCreds.asData?.value ?? const LlmCredentials();
    final profiles = creds.profiles;

    return [
      _intro(context),
      const SizedBox(height: 12),
      if (profiles.isEmpty && _editingId == null)
        SoftCard(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
          child: Text(
            '还没有 Provider。添加一个 API Key 即可让 AI 在本机直连运行。',
            style: context.theme.typography.sm.copyWith(
              color: context.theme.colors.mutedForeground,
            ),
          ),
        )
      else
        for (final p in profiles) ...[
          _profileCard(context, p, isActive: p.id == creds.activeId),
          const SizedBox(height: 10),
        ],
      if (_editingId != null) ...[
        const SizedBox(height: 2),
        _editorCard(
          context,
          profiles
              .where((p) => p.id == _editingId)
              .cast<LlmProfile?>()
              .firstWhere((_) => true, orElse: () => null),
        ),
      ] else ...[
        const SizedBox(height: 4),
        FButton(
          variant: FButtonVariant.outline,
          onPress: () => _openEditor(),
          child: const Text('添加 Provider'),
        ),
      ],
      const SizedBox(height: 16),
      _statusLine(context, asyncCreds),
    ];
  }

  Widget _profileCard(
    BuildContext context,
    LlmProfile p, {
    required bool isActive,
  }) {
    final colors = context.theme.colors;
    final meta = <String>[
      p.provider.label,
      _hostOf(p),
      if (p.model != null && p.model!.isNotEmpty) p.model!,
    ].join(' · ');
    final card = SoftCard(
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
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
                    const SizedBox(width: 8),
                    if (isActive)
                      _tag(context, '使用中', colors.primary)
                    else
                      Text(
                        '点按切换',
                        style: context.theme.typography.xs.copyWith(
                          color: colors.mutedForeground,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 3),
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
          const SizedBox(width: 6),
          _iconAction(context, FIcons.pencil, () => _openEditor(profile: p)),
          _iconAction(context, FIcons.trash2, () => _delete(p)),
        ],
      ),
    );
    if (!isActive) return card;
    // SoftCard exposes no border slot — wrap to mark the active one.
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: colors.primary.withValues(alpha: 0.45),
          width: 1.5,
        ),
      ),
      child: card,
    );
  }

  Widget _editorCard(BuildContext context, LlmProfile? existing) {
    final hasStoredKey = existing?.hasKey ?? false;
    return SoftCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            existing == null ? '添加 Provider' : '编辑 Provider',
            style: context.theme.typography.sm.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 14),
          _label(context, '名称（可选）'),
          const SizedBox(height: 6),
          FTextFormField(
            control: FTextFieldControl.managed(controller: _nameController),
            hint: 'Anthropic 官方 / 公司网关 …',
            autocorrect: false,
            enableSuggestions: false,
          ),
          const SizedBox(height: 16),
          _label(context, '提供商'),
          const SizedBox(height: 4),
          FSelect<LlmProvider>(
            items: {for (final p in LlmProvider.values) _providerLabel(p): p},
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
          const SizedBox(height: 16),
          _label(context, 'API Key'),
          const SizedBox(height: 6),
          FTextFormField(
            control: FTextFieldControl.managed(controller: _keyController),
            hint: hasStoredKey ? '已配置 · 留空则保持不变' : _keyHint(_provider),
            obscureText: true,
            autocorrect: false,
            enableSuggestions: false,
          ),
          const SizedBox(height: 16),
          _label(context, '自定义 Base URL（可选）'),
          const SizedBox(height: 6),
          FTextFormField(
            control: FTextFieldControl.managed(controller: _baseUrlController),
            hint: _baseUrlHint(_provider),
            autocorrect: false,
            enableSuggestions: false,
          ),
          const SizedBox(height: 16),
          _label(context, '模型（可选，留空用默认）'),
          const SizedBox(height: 6),
          FTextFormField(
            control: FTextFieldControl.managed(controller: _modelController),
            hint: _modelHint(_provider),
            autocorrect: false,
            enableSuggestions: false,
          ),
          const SizedBox(height: 18),
          FButton(
            variant: FButtonVariant.outline,
            onPress: (_probing || _saving) ? null : () => _test(existing),
            child: Text(_probing ? '测试中…' : '测试连通性'),
          ),
          if (_probeResult != null) ...[
            const SizedBox(height: 8),
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
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: FButton(
                  onPress: _saving ? null : () => _save(existing),
                  child: Text(_saving ? '保存中…' : '保存'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FButton(
                  variant: FButtonVariant.outline,
                  onPress: _saving ? null : _closeEditor,
                  child: const Text('取消'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _intro(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Text(
        '使用你自己的 LLM API Key，让 AI 在本机直连提供商运行。'
        '可保存多个 Provider 并随时切换。Key 仅存于本设备安全存储'
        '（Keychain/Keystore），不会上传、不进云同步、不进备份。'
        '费用与限流由你的提供商账户承担。',
        style: context.theme.typography.sm.copyWith(
          color: context.theme.colors.mutedForeground,
        ),
      ),
    );
  }

  Widget _unsupportedCard(BuildContext context) {
    return SoftCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '当前平台不支持端侧直连',
            style: context.theme.typography.sm.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '自带 Key 的端侧 AI 在原生平台'
            '（iOS / Android / macOS / Windows / Linux）可用'
            '（需要系统级安全存储）。Web 继续使用云端 AI。',
            style: context.theme.typography.xs.copyWith(
              color: context.theme.colors.mutedForeground,
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusLine(BuildContext context, AsyncValue<LlmCredentials?> async) {
    final text = switch (async) {
      AsyncData(:final value) when value?.isUsable == true =>
        '● 使用中：${value!.active!.displayName} · 本机直连运行',
      AsyncData(:final value) when (value?.profiles.isNotEmpty ?? false) =>
        '○ 已保存 Provider，但未选择可用项',
      AsyncError() => '读取安全存储失败',
      _ => '未配置 · 当前无可用端侧 AI',
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
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.14),
      borderRadius: BorderRadius.circular(6),
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
      padding: const EdgeInsets.all(8),
      child: Icon(icon, size: 18, color: context.theme.colors.mutedForeground),
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

  String _providerLabel(LlmProvider provider) => switch (provider) {
    LlmProvider.anthropic => '${provider.label}（Anthropic Messages 协议）',
    LlmProvider.openai => '${provider.label}（Chat Completions 协议）',
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
    LlmProvider.anthropic => 'claude-sonnet-4-6',
    LlmProvider.openai => 'gpt-4o-mini',
  };
}
