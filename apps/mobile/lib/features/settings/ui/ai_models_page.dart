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

import '../../../core/ai/local/embedding/embedder_path_resolution.dart';
import '../../../core/ai/local/embedding/model_install_state.dart';
import '../../../core/ai/local/embedding/model_manifest.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';

class AiModelsPage extends ConsumerWidget {
  const AiModelsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bundles = ref.watch(knownModelBundlesProvider);
    final resolution = ref.watch(embedderPathResolutionProvider);
    final l10n = AppLocalizations.of(context);
    return FScaffold(
      header: FHeader.nested(
        title: Text(l10n.settingsAiModelsTitle),
        prefixes: [backHeaderAction(context)],
      ),
      childPad: false,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final padding = Breakpoints.isMobile(constraints.maxWidth)
              ? const EdgeInsets.all(AppSpacing.s16)
              : const EdgeInsets.all(AppSpacing.s24);
          return ListView(
            padding: padding,
            children: [
              _RuntimeDiagnosticsCard(resolution: resolution),
              const SizedBox(height: AppSpacing.s12),
              const _Hint(),
              const SizedBox(height: AppSpacing.s16),
              for (final bundle in bundles) ...[
                _BundleCard(bundle: bundle),
                const SizedBox(height: AppSpacing.s12),
              ],
              const SizedBox(height: AppSpacing.s16),
              const _Footnote(),
            ],
          );
        },
      ),
    );
  }
}

class _RuntimeDiagnosticsCard extends StatelessWidget {
  const _RuntimeDiagnosticsCard({required this.resolution});

  final AsyncValue<EmbedderPathResolution> resolution;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final semantic = SemanticColors.of(context);
    final colors = context.theme.colors;
    return SoftCard(
      padding: const EdgeInsets.all(AppSpacing.s12),
      child: resolution.when(
        loading: () => Row(
          children: [
            const SizedBox.square(
              dimension: 16,
              child: FCircularProgress(),
            ),
            const SizedBox(width: AppSpacing.s8),
            Text(
              l10n.settingsAiModelsCheckingRuntime,
              style: context.theme.typography.sm,
            ),
          ],
        ),
        error: (e, _) => Text(
          l10n.settingsAiModelsRuntimeCheckFailed('$e'),
          style: context.theme.typography.xs.copyWith(color: semantic.danger),
        ),
        data: (r) {
          final complete = r.isComplete;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    complete ? FLucideIcons.cpu : FLucideIcons.circleAlert,
                    size: AppIconSizes.h18,
                    color: complete ? semantic.success : semantic.warning,
                  ),
                  const SizedBox(width: AppSpacing.s8),
                  Expanded(
                    child: Text(
                      complete
                          ? l10n.settingsAiModelsRuntimeReady
                          : l10n.settingsAiModelsRuntimeStub,
                      style: context.theme.typography.sm.copyWith(
                        color: colors.foreground,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.s8),
              _RuntimeRow(
                label: l10n.settingsAiModelsModelLabel,
                value: r.modelDir.isEmpty
                    ? l10n.settingsAiModelsModelMissing
                    : '${_modelSourceLabel(l10n, r.modelSource)} · ${r.modelDir}',
              ),
              const SizedBox(height: AppSpacing.s4),
              _RuntimeRow(
                label: 'ONNX Runtime',
                value: r.ortDylibPath.isEmpty
                    ? l10n.settingsAiModelsOrtMissing
                    : '${_ortSourceLabel(l10n, r.ortSource)} · ${r.ortDylibPath}',
              ),
              const SizedBox(height: AppSpacing.s4),
              _RuntimeRow(
                label: l10n.settingsAiModelsNativeLibLabel,
                value: r.libraryPath ?? l10n.settingsAiModelsNativeLibPlatform,
              ),
            ],
          );
        },
      ),
    );
  }
}

class _RuntimeRow extends StatelessWidget {
  const _RuntimeRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 86,
          child: Text(
            label,
            style: context.theme.typography.xs2.copyWith(
              color: colors.mutedForeground,
            ),
          ),
        ),
        Expanded(
          child: SelectableText(
            value,
            style: TypographyTokens.numericCaption.copyWith(
              color: colors.foreground,
            ),
          ),
        ),
      ],
    );
  }
}

String _modelSourceLabel(
  AppLocalizations l10n,
  EmbedderModelPathSource source,
) => switch (source) {
  EmbedderModelPathSource.dartDefine => 'dart-define',
  EmbedderModelPathSource.installedBundle =>
    l10n.settingsAiModelsInstalledSource,
  EmbedderModelPathSource.missing => l10n.settingsAiModelsMissingSource,
};

String _ortSourceLabel(AppLocalizations l10n, EmbedderOrtPathSource source) =>
    switch (source) {
      EmbedderOrtPathSource.dartDefine => 'dart-define',
      EmbedderOrtPathSource.bundled => 'app bundle',
      EmbedderOrtPathSource.missing => l10n.settingsAiModelsMissingSource,
    };

class _Hint extends StatelessWidget {
  const _Hint();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SoftCard(
      padding: const EdgeInsets.all(AppSpacing.s12),
      child: Text(
        l10n.settingsAiModelsHint,
        style: context.theme.typography.sm,
      ),
    );
  }
}

class _Footnote extends StatelessWidget {
  const _Footnote();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s4),
      child: Text(
        l10n.settingsAiModelsFootnote,
        style: context.theme.typography.xs.copyWith(
          color: context.theme.colors.mutedForeground,
        ),
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
    final l10n = AppLocalizations.of(context);
    final semantic = SemanticColors.of(context);
    final colors = context.theme.colors;

    return SoftCard(
      padding: const EdgeInsets.all(AppSpacing.s16),
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
                      style: context.theme.typography.sm.copyWith(
                        color: colors.foreground,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.s2),
                    Text(
                      bundle.description,
                      style: context.theme.typography.xs.copyWith(
                        color: colors.mutedForeground,
                      ),
                    ),
                  ],
                ),
              ),
              _SizeBadge(bundle: bundle),
            ],
          ),
          const SizedBox(height: AppSpacing.s12),
          stateAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpacing.s8),
              child: LinearProgressIndicator(),
            ),
            error: (e, _) => Text(
              l10n.settingsAiModelsStateLoadFailed('$e'),
              style: context.theme.typography.xs.copyWith(
                color: semantic.danger,
              ),
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
    final colors = context.theme.colors;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s8,
        vertical: AppSpacing.s4,
      ),
      decoration: BoxDecoration(
        color: colors.foreground.withValues(alpha: AppOpacity.faint),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Text(
        _formatBytes(total),
        style: context.theme.typography.xs2.copyWith(
          color: colors.mutedForeground,
          fontWeight: FontWeight.w600,
        ),
      ),
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
    final l10n = AppLocalizations.of(context);
    final semantic = SemanticColors.of(context);
    final colors = context.theme.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final file in state.files) _FileRow(file: file),
        const SizedBox(height: AppSpacing.s12),
        Row(
          children: [
            if (state.isInstalled)
              _StatusChip(
                text: l10n.settingsAiModelsStatusInstalled,
                color: semantic.success,
              )
            else if (state.isInstalling)
              _StatusChip(
                text: l10n.settingsAiModelsStatusDownloading,
                color: colors.primary,
                progress: state.aggregateProgress,
              )
            else if (state.files.any((f) => f.status == ModelFileStatus.failed))
              _StatusChip(
                text: l10n.settingsAiModelsStatusFailed,
                color: semantic.danger,
              )
            else
              _StatusChip(
                text: l10n.settingsAiModelsStatusNotInstalled,
                color: colors.mutedForeground,
              ),
            const Spacer(),
            if (state.isInstalling)
              TextButton(
                onPressed: onCancel,
                child: Text(l10n.settingsAiModelsCancel),
              )
            else if (state.isInstalled) ...[
              TextButton(
                onPressed: () async {
                  final confirm = await _confirmDelete(context);
                  if (confirm == true) {
                    await onDelete();
                  }
                },
                child: Text(l10n.settingsAiModelsDelete),
              ),
              TextButton(
                onPressed: () async {
                  await onDelete();
                  await onInstall();
                },
                child: Text(l10n.settingsAiModelsRedownload),
              ),
            ] else
              FilledButton(
                onPressed: onInstall,
                child: Text(l10n.settingsAiModelsDownload),
              ),
          ],
        ),
      ],
    );
  }

  Future<bool?> _confirmDelete(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return showConfirmDialog(
      context: context,
      title: Text(l10n.settingsAiModelsDeleteTitle),
      body: Text(l10n.settingsAiModelsDeleteBody),
      confirmLabel: l10n.settingsAiModelsDelete,
      cancelLabel: l10n.settingsAiModelsCancel,
      destructive: true,
    );
  }
}

class _FileRow extends StatelessWidget {
  const _FileRow({required this.file});
  final ModelFileState file;

  @override
  Widget build(BuildContext context) {
    final progress = file.progress;
    final colors = context.theme.colors;
    final semantic = SemanticColors.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.s4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  file.file.localName,
                  style: TypographyTokens.numericCaption.copyWith(
                    color: colors.foreground,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.s8),
              _statusIcon(context, file.status),
            ],
          ),
          if (file.status == ModelFileStatus.downloading) ...[
            const SizedBox(height: AppSpacing.s4),
            LinearProgressIndicator(value: progress, minHeight: 3),
            const SizedBox(height: AppSpacing.s2),
            Text(
              '${_formatBytes(file.bytesDownloaded)}'
              '${file.file.sizeBytes != null ? ' / ${_formatBytes(file.file.sizeBytes!)}' : ''}',
              style: context.theme.typography.xs2.copyWith(
                color: colors.mutedForeground,
              ),
            ),
          ],
          if (file.status == ModelFileStatus.failed && file.error != null) ...[
            const SizedBox(height: AppSpacing.s4),
            Text(
              file.error!,
              style: context.theme.typography.xs2.copyWith(
                color: semantic.danger,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _statusIcon(BuildContext context, ModelFileStatus s) {
    final colors = context.theme.colors;
    final semantic = SemanticColors.of(context);
    return switch (s) {
      ModelFileStatus.notInstalled => Icon(
        FLucideIcons.download,
        size: AppIconSizes.sm,
        color: colors.mutedForeground,
      ),
      ModelFileStatus.downloading => const SizedBox(
        width: 12,
        height: 12,
        child: FCircularProgress(),
      ),
      ModelFileStatus.installed => Icon(
        FLucideIcons.circleCheck,
        size: AppIconSizes.sm,
        color: semantic.success,
      ),
      ModelFileStatus.failed => Icon(
        FLucideIcons.circleAlert,
        size: AppIconSizes.sm,
        color: semantic.danger,
      ),
    };
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.text, required this.color, this.progress});
  final String text;
  final Color color;
  final double? progress;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s8 + AppSpacing.s2,
        vertical: AppSpacing.s4,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: AppOpacity.medium),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            text,
            style: context.theme.typography.xs2.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (progress != null) ...[
            const SizedBox(width: AppSpacing.s6),
            Text(
              '${(progress! * 100).toStringAsFixed(0)}%',
              style: context.theme.typography.xs2.copyWith(color: color),
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
