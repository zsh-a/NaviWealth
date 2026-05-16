/// §4.6 W-D1 — Settings ▸ on-device AI (bring-your-own key).
///
/// Lets the user paste their own LLM provider key. The key is stored
/// in the Keychain/Keystore via [llmCredentialsProvider]; the device
/// runtime (W-D3) is only selected when this screen's opt-in switch is
/// on. iOS/Android only — other platforms see an explanatory card and
/// keep using the cloud relay.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

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
  final _keyController = TextEditingController();
  final _baseUrlController = TextEditingController();
  bool _prefilled = false;
  bool _saving = false;

  @override
  void dispose() {
    _keyController.dispose();
    _baseUrlController.dispose();
    super.dispose();
  }

  // Prefill the base-URL field once from stored creds. The API key is
  // never echoed back — the field stays empty and only overwrites when
  // the user types something.
  void _maybePrefill(LlmCredentials? creds) {
    if (_prefilled || creds == null) return;
    _prefilled = true;
    if (creds.baseUrl != null) _baseUrlController.text = creds.baseUrl!;
  }

  Future<void> _save(LlmCredentials? current) async {
    final typedKey = _keyController.text.trim();
    final storedKey = current?.apiKey ?? '';
    final effectiveKey = typedKey.isNotEmpty ? typedKey : storedKey;
    if (effectiveKey.isEmpty) {
      _toast(ToastKind.warning, '请先填入 API Key');
      return;
    }
    final baseUrl = _baseUrlController.text.trim();
    setState(() => _saving = true);
    await ref.read(llmCredentialsProvider.notifier).save(
          LlmCredentials(
            provider: LlmProvider.anthropic,
            apiKey: effectiveKey,
            baseUrl: baseUrl.isEmpty ? null : baseUrl,
            // Saving a key for the first time does not auto-enable —
            // the user flips the switch deliberately (§11 opt-in).
            enabled: current?.enabled ?? false,
          ),
        );
    if (!mounted) return;
    setState(() => _saving = false);
    _keyController.clear();
    _toast(ToastKind.success, '已保存到设备安全存储');
  }

  Future<void> _clear() async {
    await ref.read(llmCredentialsProvider.notifier).clear();
    if (!mounted) return;
    _keyController.clear();
    _baseUrlController.clear();
    _toast(ToastKind.success, '已从设备移除');
  }

  void _toast(ToastKind kind, String msg) {
    AppMessenger.show(context, kind, msg);
  }

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
    final creds = asyncCreds.asData?.value;
    _maybePrefill(creds);
    final hasStoredKey = creds?.hasKey ?? false;

    return [
      _intro(context),
      const SizedBox(height: 12),
      SoftCard(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _label(context, '提供商'),
            const SizedBox(height: 4),
            Text(
              LlmProvider.anthropic.label,
              style: context.theme.typography.sm,
            ),
            const SizedBox(height: 16),
            _label(context, 'API Key'),
            const SizedBox(height: 6),
            FTextFormField(
              control: FTextFieldControl.managed(controller: _keyController),
              hint: hasStoredKey ? '已配置 · 留空则保持不变' : 'sk-ant-…',
              obscureText: true,
              autocorrect: false,
              enableSuggestions: false,
            ),
            const SizedBox(height: 16),
            _label(context, '自定义 Base URL（可选）'),
            const SizedBox(height: 6),
            FTextFormField(
              control:
                  FTextFieldControl.managed(controller: _baseUrlController),
              hint: 'https://api.anthropic.com',
              autocorrect: false,
              enableSuggestions: false,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: FButton(
                    onPress: _saving ? null : () => _save(creds),
                    child: Text(_saving ? '保存中…' : '保存'),
                  ),
                ),
                if (hasStoredKey) ...[
                  const SizedBox(width: 12),
                  Expanded(
                    child: FButton(
                      variant: FButtonVariant.outline,
                      onPress: _saving ? null : _clear,
                      child: const Text('移除'),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      _enableCard(context, creds, hasStoredKey),
      const SizedBox(height: 16),
      _statusLine(context, asyncCreds),
    ];
  }

  Widget _enableCard(
    BuildContext context,
    LlmCredentials? creds,
    bool hasStoredKey,
  ) {
    return SoftCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '启用端侧 AI',
                  style: context.theme.typography.sm
                      .copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  hasStoredKey
                      ? '开启后 AI 在本机直连提供商，不经过我们的服务器；'
                          '关闭则继续走云端。'
                      : '先保存 API Key 后才能启用。',
                  style: context.theme.typography.xs.copyWith(
                    color: context.theme.colors.mutedForeground,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          FSwitch(
            value: creds?.enabled ?? false,
            onChange: hasStoredKey
                ? (v) =>
                    ref.read(llmCredentialsProvider.notifier).setEnabled(v)
                : null,
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
        'Key 仅存于本设备安全存储（Keychain/Keystore），'
        '不会上传、不进云同步、不进备份。费用与限流由你的提供商账户承担。',
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
            style: context.theme.typography.sm
                .copyWith(fontWeight: FontWeight.w600),
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

  Widget _statusLine(
    BuildContext context,
    AsyncValue<LlmCredentials?> async,
  ) {
    final (text, _) = switch (async) {
      AsyncData(:final value) when value?.isUsable == true => (
          '● 已启用 · AI 将在本机直连运行',
          true,
        ),
      AsyncData(:final value) when (value?.hasKey ?? false) => (
          '○ 已保存 Key · 未启用，仍走云端',
          false,
        ),
      AsyncError() => ('读取安全存储失败', false),
      _ => ('未配置 · 使用云端 AI', false),
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
}
