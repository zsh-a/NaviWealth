part of '../ai_models_page.dart';

class _BundleCard extends ConsumerWidget {
  const _BundleCard({required this.bundle});

  final ModelBundle bundle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stateAsync = ref.watch(modelInstallProvider(bundle));
    final controller = ref.read(modelInstallProvider(bundle).notifier);
    final l10n = AppLocalizations.of(context);
    final colors = context.theme.colors;

    return SoftCard.flat(
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
            error: (error, _) => AppEmptyState.error(
              title: l10n.commonLoadFailed,
              message: userSafeErrorMessage(
                context,
                error,
                operation: 'load model bundle state',
              ),
              retryLabel: l10n.commonRetry,
              onRetry: () => ref.invalidate(modelInstallProvider(bundle)),
              compact: true,
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
    final status = context.appTheme.status;
    final colors = context.theme.colors;
    if (state.isInstalled) {
      return _StatusChip(
        text: l10n.settingsAiModelsStatusInstalled,
        color: status.success.fg,
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
        color: status.danger.fg,
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
    final status = context.appTheme.status;
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
                color: status.danger.fg,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _statusIcon(BuildContext context, ModelFileStatus s) {
    final colors = context.theme.colors;
    final status = context.appTheme.status;
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
        color: status.success.fg,
      ),
      ModelFileStatus.failed => Icon(
        FLucideIcons.circleAlert,
        size: AppIconSizes.sm,
        color: status.danger.fg,
      ),
    };
  }
}
