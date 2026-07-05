part of '../ai_models_page.dart';

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
                value: d.fingerprint.isEmpty ? '\u2014' : d.fingerprint,
              ),
              const SizedBox(height: AppSpacing.s4),
              _RuntimeRow(
                label: l10n.settingsAiModelsDimensionLabel,
                value: d.dimension == 0 ? '\u2014' : '${d.dimension}',
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
                    : '${_modelSourceLabel(l10n, r.modelSource)} \u00b7 ${r.modelDir}',
              ),
              const SizedBox(height: AppSpacing.s4),
              _RuntimeRow(
                label: 'ONNX Runtime',
                value: r.ortDylibPath.isEmpty
                    ? l10n.settingsAiModelsOrtMissing
                    : '${_ortSourceLabel(l10n, r.ortSource)} \u00b7 ${r.ortDylibPath}',
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
