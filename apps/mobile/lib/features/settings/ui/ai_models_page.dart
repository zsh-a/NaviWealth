/// AI Models settings (D-1.7c).
///
/// Lets users download / verify / delete the model bundles the Rust
/// embedder needs (EmbeddingGemma weights + ONNX Runtime native lib).
/// Replaces the old `--dart-define`-driven manual setup with an
/// in-app installer; the bootstrap auto-discovery picks up installed
/// bundles next run.
///
/// Deliberately minimal UI:
///   - One card per bundle, status-driven (NotInstalled / Installing /
///     Installed / Failed)
///   - Download / Cancel / Delete buttons gated by status
///   - Per-file progress when downloading; aggregate when not
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../../core/ai/local/embedding/model_install_state.dart';
import '../../../core/ai/local/embedding/model_manifest.dart';
import '../../../design_system/design_system.dart';

class AiModelsPage extends ConsumerWidget {
  const AiModelsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bundles = ref.watch(knownModelBundlesProvider);
    return FScaffold(
      header: FHeader.nested(
        title: const Text('AI 模型'),
        prefixes: [backHeaderAction(context)],
      ),
      childPad: false,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final padding = Breakpoints.isMobile(constraints.maxWidth)
              ? const EdgeInsets.all(16)
              : const EdgeInsets.all(24);
          return ListView(
            padding: padding,
            children: [
              const _Hint(),
              const SizedBox(height: 16),
              for (final bundle in bundles) ...[
                _BundleCard(bundle: bundle),
                const SizedBox(height: 12),
              ],
              const SizedBox(height: 16),
              const _Footnote(),
            ],
          );
        },
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint();

  @override
  Widget build(BuildContext context) {
    return const SoftCard(
      padding: EdgeInsets.all(12),
      child: Text(
        'AI 记忆检索默认走轻量 stub。下载 EmbeddingGemma + ONNX Runtime 后,'
        '重启应用即可启用本地多语言句向量(768-d)。模型文件在本机保存,'
        '不上传任何远端。',
        style: TextStyle(fontSize: 13),
      ),
    );
  }
}

class _Footnote extends StatelessWidget {
  const _Footnote();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 4),
      child: Text(
        '下载完成后,请重启应用让 Memory Runtime 使用新 embedder。'
        '已有的记忆条目会在下次 indexer 周期自动用新模型重新生成 vector,'
        '原始 typed records (events/episodic/...) 保持不变。',
        style: TextStyle(fontSize: 12, color: Colors.grey),
      ),
    );
  }
}

class _BundleCard extends ConsumerWidget {
  const _BundleCard({required this.bundle});

  final ModelBundle bundle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stateAsync = ref.watch(modelInstallProvider(bundle));
    final controller = ref.read(modelInstallProvider(bundle).notifier);

    return SoftCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      bundle.displayName,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      bundle.description,
                      style:
                          const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
              ),
              _SizeBadge(bundle: bundle),
            ],
          ),
          const SizedBox(height: 12),
          stateAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: LinearProgressIndicator(),
            ),
            error: (e, _) => Text(
              '加载状态失败:$e',
              style: const TextStyle(color: Colors.redAccent, fontSize: 12),
            ),
            data: (bundleState) => _BundleBody(
              state: bundleState,
              onInstall: controller.install,
              onCancel: controller.cancel,
              onDelete: controller.delete,
            ),
          ),
        ],
      ),
    );
  }
}

class _SizeBadge extends StatelessWidget {
  const _SizeBadge({required this.bundle});
  final ModelBundle bundle;
  @override
  Widget build(BuildContext context) {
    final total = bundle.totalSizeBytes;
    if (total == null) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(_formatBytes(total),
          style: const TextStyle(fontSize: 11, color: Colors.black54)),
    );
  }
}

class _BundleBody extends StatelessWidget {
  const _BundleBody({
    required this.state,
    required this.onInstall,
    required this.onCancel,
    required this.onDelete,
  });

  final ModelBundleState state;
  final Future<void> Function() onInstall;
  final void Function() onCancel;
  final Future<void> Function() onDelete;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final file in state.files) _FileRow(file: file),
        const SizedBox(height: 12),
        Row(
          children: [
            if (state.isInstalled)
              const _StatusChip(
                text: '已安装',
                color: Colors.green,
              )
            else if (state.isInstalling)
              _StatusChip(
                text: '下载中…',
                color: Colors.blue,
                progress: state.aggregateProgress,
              )
            else if (state.files.any(
                (f) => f.status == ModelFileStatus.failed))
              const _StatusChip(text: '失败', color: Colors.redAccent)
            else
              const _StatusChip(text: '未安装', color: Colors.grey),
            const Spacer(),
            if (state.isInstalling)
              TextButton(onPressed: onCancel, child: const Text('取消'))
            else if (state.isInstalled) ...[
              TextButton(
                onPressed: () async {
                  final confirm = await _confirmDelete(context);
                  if (confirm == true) {
                    await onDelete();
                  }
                },
                child: const Text('删除'),
              ),
              TextButton(
                onPressed: () async {
                  await onDelete();
                  await onInstall();
                },
                child: const Text('重新下载'),
              ),
            ] else
              FilledButton(
                onPressed: onInstall,
                child: const Text('下载'),
              ),
          ],
        ),
      ],
    );
  }

  Future<bool?> _confirmDelete(BuildContext context) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除模型?'),
        content: const Text(
          '删除后 AI 检索会自动回到 stub embedder。重新下载需要再走一次网络。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }
}

class _FileRow extends StatelessWidget {
  const _FileRow({required this.file});
  final ModelFileState file;

  @override
  Widget build(BuildContext context) {
    final progress = file.progress;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  file.file.localName,
                  style: const TextStyle(
                    fontSize: 12,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _statusIcon(file.status),
            ],
          ),
          if (file.status == ModelFileStatus.downloading) ...[
            const SizedBox(height: 4),
            LinearProgressIndicator(
              value: progress,
              minHeight: 3,
            ),
            const SizedBox(height: 2),
            Text(
              '${_formatBytes(file.bytesDownloaded)}'
              '${file.file.sizeBytes != null ? ' / ${_formatBytes(file.file.sizeBytes!)}' : ''}',
              style: const TextStyle(fontSize: 10, color: Colors.grey),
            ),
          ],
          if (file.status == ModelFileStatus.failed && file.error != null) ...[
            const SizedBox(height: 4),
            Text(
              file.error!,
              style:
                  const TextStyle(fontSize: 10, color: Colors.redAccent),
            ),
          ],
        ],
      ),
    );
  }

  Widget _statusIcon(ModelFileStatus s) => switch (s) {
        ModelFileStatus.notInstalled => const Icon(
            Icons.download_outlined,
            size: 16,
            color: Colors.grey,
          ),
        ModelFileStatus.downloading => const SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ModelFileStatus.installed => const Icon(
            Icons.check_circle,
            size: 16,
            color: Colors.green,
          ),
        ModelFileStatus.failed => const Icon(
            Icons.error_outline,
            size: 16,
            color: Colors.redAccent,
          ),
      };
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.text, required this.color, this.progress});
  final String text;
  final Color color;
  final double? progress;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            text,
            style: TextStyle(
              fontSize: 11,
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (progress != null) ...[
            const SizedBox(width: 6),
            Text(
              '${(progress! * 100).toStringAsFixed(0)}%',
              style: TextStyle(fontSize: 11, color: color),
            ),
          ],
        ],
      ),
    );
  }
}

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
}
