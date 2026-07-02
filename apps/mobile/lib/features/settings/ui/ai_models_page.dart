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

import '../../../core/ai/local/embedding/embedder_diagnostics.dart';
import '../../../core/ai/local/embedding/embedder_path_resolution.dart';
import '../../../core/ai/local/embedding/model_install_state.dart';
import '../../../core/ai/local/embedding/model_manifest.dart';
import '../../../core/shell/settings_ui/settings_page_frame.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';

class AiModelsPage extends ConsumerWidget {
  const AiModelsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bundles = ref.watch(knownModelBundlesProvider);
    final resolution = ref.watch(embedderPathResolutionProvider);
    final l10n = AppLocalizations.of(context);
    return AppPageScaffold(
      title: l10n.settingsAiModelsTitle,
      childPad: false,
      child: SettingsPageFrame(
        children: [
          _RuntimeDiagnosticsCard(resolution: resolution),
          const SizedBox(height: AppSpacing.s12),
          const _ActiveEmbedderCard(),
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
      ),
    );
  }
}

class _ActiveEmbedderCard extends ConsumerWidget {
  const _ActiveEmbedderCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final diagnostics = ref.watch(embedderDiagnosticsProvider);
    final l10n = AppLocalizations.of(context);
    final colors = context.theme.colors;
    final semantic = SemanticColors.of(context);
    return SoftCard(
      padding: const EdgeInsets.all(AppSpacing.s12),
      child: diagnostics.when(
        loading: () => Row(
          children: [
            const SizedBox.square(
              dimension: AppIconSizes.xs,
              child: FCircularProgress(),
            ),
            const SizedBox(width: AppSpacing.s8),
            Text(
              l10n.settingsAiModelsActiveRuntimeLoading,
              style: context.theme.typography.body.sm,
            ),
          ],
        ),
        error: (e, _) => Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              FLucideIcons.circleAlert,
              size: AppIconSizes.h18,
              color: semantic.danger,
            ),
            const SizedBox(width: AppSpacing.s8),
            Expanded(
              child: Text(
                l10n.settingsAiModelsActiveRuntimeFailed('$e'),
                style: context.captionStyle.copyWith(color: semantic.danger),
              ),
            ),
          ],
        ),
        data: (d) {
          final isNative = d.kind == EmbedderRuntimeKind.native;
          final isStub = d.kind == EmbedderRuntimeKind.stub;
          final statusColor = isNative
              ? semantic.success
              : isStub
              ? semantic.warning
              : semantic.danger;
          final statusLabel = switch (d.kind) {
            EmbedderRuntimeKind.native =>
              l10n.settingsAiModelsActiveRuntimeNative,
            EmbedderRuntimeKind.stub => l10n.settingsAiModelsActiveRuntimeStub,
            EmbedderRuntimeKind.unknown =>
              l10n.settingsAiModelsActiveRuntimeUnknown,
          };
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    isNative ? FLucideIcons.cpu : FLucideIcons.activity,
                    size: AppIconSizes.h18,
                    color: statusColor,
                  ),
                  const SizedBox(width: AppSpacing.s8),
                  Expanded(
                    child: Text(
                      l10n.settingsAiModelsActiveRuntimeTitle,
                      style: context.labelStyle.copyWith(
                        color: colors.foreground,
                      ),
                    ),
                  ),
                  _StatusChip(text: statusLabel, color: statusColor),
                ],
              ),
              if (d.error != null) ...[
                const SizedBox(height: AppSpacing.s8),
                Text(
                  d.error!,
                  style: context.captionStyle.copyWith(color: semantic.danger),
                ),
              ],
              const SizedBox(height: AppSpacing.s10),
              _RuntimeRow(
                label: l10n.settingsAiModelsFingerprintLabel,
                value: d.fingerprint.isEmpty ? '—' : d.fingerprint,
              ),
              const SizedBox(height: AppSpacing.s4),
              _RuntimeRow(
                label: l10n.settingsAiModelsDimensionLabel,
                value: d.dimension == 0 ? '—' : '${d.dimension}',
              ),
              const SizedBox(height: AppSpacing.s12),
              Wrap(
                spacing: AppSpacing.s8,
                runSpacing: AppSpacing.s8,
                children: [
                  _MetricTile(
                    label: l10n.settingsAiModelsMemoryRowsLabel,
                    value: d.memoryCount,
                  ),
                  _MetricTile(
                    label: l10n.settingsAiModelsVectorRowsLabel,
                    value: d.vectorCount,
                  ),
                  _MetricTile(
                    label: l10n.settingsAiModelsCurrentVectorsLabel,
                    value: d.currentVectorCount,
                  ),
                  _MetricTile(
                    label: l10n.settingsAiModelsStaleVectorsLabel,
                    value: d.staleVectorCount,
                    color: d.hasStaleVectors
                        ? semantic.warning
                        : colors.mutedForeground,
                  ),
                  _MetricTile(
                    label: l10n.settingsAiModelsEventsLabel,
                    value: d.eventCount,
                  ),
                ],
              ),
              if (d.hasStaleVectors) ...[
                const SizedBox(height: AppSpacing.s8),
                Text(
                  l10n.settingsAiModelsStaleVectorsHint,
                  style: context.captionStyle.copyWith(color: semantic.warning),
                ),
              ],
              const SizedBox(height: AppSpacing.s12),
              Text(
                l10n.settingsAiModelsSourcesTitle,
                style: context.captionLabelStyle.copyWith(
                  color: colors.mutedForeground,
                ),
              ),
              const SizedBox(height: AppSpacing.s6),
              if (d.sourceStats.isEmpty)
                Text(
                  l10n.settingsAiModelsNoSources,
                  style: context.captionStyle,
                )
              else
                for (final source in d.sourceStats)
                  _SourceStatRow(source: source),
            ],
          );
        },
      ),
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({required this.label, required this.value, this.color});

  final String label;
  final int value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final valueColor = color ?? colors.foreground;
    return Container(
      constraints: const BoxConstraints(minWidth: 94),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s10,
        vertical: AppSpacing.s8,
      ),
      decoration: BoxDecoration(
        color: colors.muted,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$value',
            style: TypographyTokens.numericCaptionStrong.copyWith(
              color: valueColor,
            ),
          ),
          const SizedBox(height: AppSpacing.s2),
          Text(label, style: context.microCaptionStyle),
        ],
      ),
    );
  }
}

class _SourceStatRow extends StatelessWidget {
  const _SourceStatRow({required this.source});

  final EmbedderSourceStats source;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.s2),
      child: Row(
        children: [
          Expanded(
            child: Text(
              source.source,
              overflow: TextOverflow.ellipsis,
              style: TypographyTokens.numericCaption.copyWith(
                color: colors.foreground,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.s8),
          Text(
            '${source.vectors}/${source.memories}',
            style: TypographyTokens.numericCaption.copyWith(
              color: colors.mutedForeground,
            ),
          ),
        ],
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
              dimension: AppIconSizes.xs,
              child: FCircularProgress(),
            ),
            const SizedBox(width: AppSpacing.s8),
            Text(
              l10n.settingsAiModelsCheckingRuntime,
              style: context.theme.typography.body.sm,
            ),
          ],
        ),
        error: (e, _) => Text(
          l10n.settingsAiModelsRuntimeCheckFailed('$e'),
          style: context.captionStyle.copyWith(color: semantic.danger),
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
                      style: context.labelStyle.copyWith(
                        color: colors.foreground,
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
          width: AppControlWidths.runtimeLabel,
          child: Text(label, style: context.microCaptionStyle),
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
        style: context.theme.typography.body.sm,
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
      child: Text(l10n.settingsAiModelsFootnote, style: context.captionStyle),
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
                      style: context.labelStyle.copyWith(
                        color: colors.foreground,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.s2),
                    Text(bundle.description, style: context.captionStyle),
                  ],
                ),
              ),
              if (bundle.totalSizeBytes case final total?)
                AppBadge(
                  label: _formatBytes(total),
                  size: AppBadgeSize.compact,
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.s12),
          stateAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpacing.s8),
              child: FProgress(),
            ),
            error: (e, _) => Text(
              l10n.settingsAiModelsStateLoadFailed('$e'),
              style: context.captionStyle.copyWith(color: semantic.danger),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final file in state.files) _FileRow(file: file),
        const SizedBox(height: AppSpacing.s12),
        Wrap(
          spacing: AppSpacing.s8,
          runSpacing: AppSpacing.s8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _BundleStatusChip(state: state),
            if (state.isInstalling)
              FButton(
                onPress: onCancel,
                variant: FButtonVariant.outline,
                child: Text(l10n.settingsAiModelsCancel),
              )
            else if (state.isInstalled) ...[
              FButton(
                onPress: () async {
                  final confirm = await _confirmDelete(context);
                  if (confirm == true) await onDelete();
                },
                variant: FButtonVariant.outline,
                child: Text(l10n.settingsAiModelsDelete),
              ),
              FButton(
                onPress: () async {
                  await onDelete();
                  await onInstall();
                },
                variant: FButtonVariant.outline,
                child: Text(l10n.settingsAiModelsRedownload),
              ),
            ] else
              FButton(
                onPress: onInstall,
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

class _BundleStatusChip extends StatelessWidget {
  const _BundleStatusChip({required this.state});

  final ModelBundleState state;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final semantic = SemanticColors.of(context);
    final colors = context.theme.colors;
    if (state.isInstalled) {
      return _StatusChip(
        text: l10n.settingsAiModelsStatusInstalled,
        color: semantic.success,
      );
    }
    if (state.isInstalling) {
      return _StatusChip(
        text: l10n.settingsAiModelsStatusDownloading,
        color: colors.primary,
        progress: state.aggregateProgress,
      );
    }
    if (state.files.any((f) => f.status == ModelFileStatus.failed)) {
      return _StatusChip(
        text: l10n.settingsAiModelsStatusFailed,
        color: semantic.danger,
      );
    }
    return _StatusChip(
      text: l10n.settingsAiModelsStatusNotInstalled,
      color: colors.mutedForeground,
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
            FDeterminateProgress(
              value: progress!,
              style: FDeterminateProgressStyle(
                constraints: const BoxConstraints.tightFor(height: 3),
                trackDecoration: ShapeDecoration(
                  shape: RoundedSuperellipseBorder(
                    borderRadius: context.theme.style.borderRadius.pill,
                  ),
                  color: context.theme.colors.muted,
                ),
                fillDecoration: ShapeDecoration(
                  shape: RoundedSuperellipseBorder(
                    borderRadius: context.theme.style.borderRadius.pill,
                  ),
                  color: context.theme.colors.primary,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.s2),
            Text(
              '${_formatBytes(file.bytesDownloaded)}'
              '${file.file.sizeBytes != null ? ' / ${_formatBytes(file.file.sizeBytes!)}' : ''}',
              style: context.microCaptionStyle,
            ),
          ],
          if (file.status == ModelFileStatus.failed && file.error != null) ...[
            const SizedBox(height: AppSpacing.s4),
            Text(
              file.error!,
              style: context.theme.typography.body.xs2.copyWith(
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
        width: AppSpacing.s12,
        height: AppSpacing.s12,
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
            style: context.theme.typography.body.xs2.copyWith(color: color),
          ),
          if (progress != null) ...[
            const SizedBox(width: AppSpacing.s6),
            Text(
              '${(progress! * 100).toStringAsFixed(0)}%',
              style: context.theme.typography.body.xs2.copyWith(color: color),
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
