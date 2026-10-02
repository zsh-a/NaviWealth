import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/core/auth/domain_scope.dart';
import 'package:naviwealth/core/backup/backup_codec.dart';
import 'package:naviwealth/core/backup/backup_service.dart';
import 'package:naviwealth/core/backup/providers.dart';
import 'package:naviwealth/core/forms/forms.dart';
import 'package:naviwealth/core/logging/app_logger.dart';
import 'package:naviwealth/core/shell/settings_ui/inline_setting_row.dart';
import 'package:naviwealth/core/shell/settings_ui/settings_page_frame.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/settings/data/backup/file_saver.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

typedef BackupFileSaver = Future<bool> Function(
  Uint8List bytes,
  String fileName,
);

final backupFileSaverProvider = Provider<BackupFileSaver>(
  (ref) => saveBackupFile,
);

class PickedBackupFile {
  const PickedBackupFile({required this.name, required this.bytes});

  final String name;
  final Uint8List bytes;

  int get size => bytes.length;
}

typedef BackupRestoreFilePicker = Future<PickedBackupFile?> Function();

final backupRestoreFilePickerProvider = Provider<BackupRestoreFilePicker>((
  ref,
) {
  return () async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['bak'],
    );
    if (file == null) return null;
    return PickedBackupFile(name: file.name, bytes: await file.readAsBytes());
  };
});

class BackupPage extends ConsumerWidget {
  const BackupPage({super.key, this.domain});

  final DomainScope? domain;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);

    return AppPageScaffold(
      title: domain == null
          ? l10n.settingsDataTitle
          : l10n.backupDomainPageTitle(_domainLabel(domain!)),
      childPad: false,
      child: SettingsPageFrame(
        bottomPadding: AppSpacing.s64,
        children: [
          if (kIsWeb) ...[
            AppStatusBanner(
              kind: AppStatusKind.info,
              icon: FLucideIcons.shieldCheck,
              message: l10n.backupWebSecurityWarning,
            ),
            const SizedBox(height: AppSpacing.s12),
          ],
          AppGroupedSurface(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.s4),
            child: Column(
              children: [
                InlineLinkRow(
                  icon: FLucideIcons.upload,
                  label: l10n.backupExportTitle,
                  subtitle: l10n.backupExportSubtitle,
                  onTap: () => _exportBackup(context, ref),
                ),
                const AppGradientDivider(),
                InlineLinkRow(
                  icon: FLucideIcons.download,
                  label: l10n.backupImportTitle,
                  subtitle: l10n.backupImportSubtitle,
                  onTap: () => _importBackup(context, ref),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _exportBackup(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final logger = AppLogger.instance;

    logger.d('backup_ui: export flow started');
    final passphrase = await _showPassphraseSheet(
      context: context,
      title: l10n.backupExportTitle,
      hint: l10n.backupPassphraseHint,
      confirmLabel: l10n.backupExportAction,
    );
    if (passphrase == null || passphrase.isEmpty) {
      logger.d('backup_ui: export cancelled (no passphrase)');
      return;
    }
    if (!context.mounted) return;

    final dismiss = await showProgressDialog(
      context: context,
      message: l10n.backupExportProgress,
    );

    try {
      final sw = Stopwatch()..start();
      final Uint8List bytes;
      if (domain == null) {
        final exporter = await ref.read(backupExportRunnerProvider.future);
        if (exporter == null) {
          throw StateError('Backup service is not ready.');
        }
        bytes = await exporter(passphrase: passphrase);
      } else {
        final exporter = await ref.read(
          domainBackupExportRunnerProvider.future,
        );
        if (exporter == null) {
          throw StateError('Backup service is not ready.');
        }
        bytes = await exporter(passphrase: passphrase, domain: domain!);
      }
      logger.d('backup_ui: exporter resolved, calling exportBackup');
      sw.stop();
      logger.d(
        'backup_ui: encryption done (${bytes.length} bytes, '
        '${sw.elapsedMilliseconds}ms)',
      );

      await dismiss();
      if (!context.mounted) return;

      // Small delay to let the progress sheet fully close before showing
      // the system save dialog (needed on macOS).
      await Future<void>.delayed(const Duration(milliseconds: 300));

      final date = DateTime.now().toIso8601String().substring(0, 10);
      final suffix = domain == null ? '' : '-${domain!.wire}';
      final fileName = 'naviwealth-backup$suffix-$date.bak';
      logger.d('backup_ui: opening save dialog for $fileName');
      final saved = await ref.read(backupFileSaverProvider)(bytes, fileName);
      logger.d('backup_ui: saveBackupFile returned $saved');

      if (!context.mounted || !saved) {
        logger.d('backup_ui: export cancelled (save dialog dismissed)');
        return;
      }
      logger.i('backup_ui: export saved successfully ($fileName)');
      AppMessenger.show(context, ToastKind.success, l10n.backupExportSuccess);
    } on BackupAuthenticationException {
      await dismiss();
      if (!context.mounted) return;
      logger.w('backup_ui: export failed — authentication error');
      AppMessenger.show(context, ToastKind.error, l10n.backupWrongPassphrase);
    } catch (e, st) {
      logger.e('backup_ui: export failed', error: e, stackTrace: st);
      await dismiss();
      if (!context.mounted) return;
      AppMessenger.show(
        context,
        ToastKind.error,
        userSafeErrorMessage(context, e, stackTrace: st),
      );
    }
  }

  Future<void> _importBackup(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final logger = AppLogger.instance;

    // Pick backup file.
    logger.d('backup_ui: import flow started, opening file picker');
    PickedBackupFile? pickedFile;
    try {
      pickedFile = await ref.read(backupRestoreFilePickerProvider)();
    } catch (e, st) {
      logger.e('backup_ui: file picker threw', error: e, stackTrace: st);
      if (!context.mounted) return;
      AppMessenger.show(context, ToastKind.error, l10n.backupFilePickerError);
      return;
    }
    if (pickedFile == null) {
      logger.d('backup_ui: import cancelled (no file selected)');
      return;
    }

    logger.d(
      'backup_ui: picked file name=${pickedFile.name} size=${pickedFile.size}',
    );

    if (!context.mounted) return;

    await showGuardedFormSheet<RestoreResult>(
      context: context,
      builder: (_, dirty) =>
          _RestoreConfirmSheet(file: pickedFile!, domain: domain, dirty: dirty),
    );
  }

  Future<String?> _showPassphraseSheet({
    required BuildContext context,
    required String title,
    required String hint,
    required String confirmLabel,
  }) {
    return showAppFormSheet<String>(
      context: context,
      builder: (_) => _PassphraseSheet(
        title: title,
        hint: hint,
        confirmLabel: confirmLabel,
      ),
    );
  }
}

String _domainLabel(DomainScope scope) => switch (scope) {
  DomainScope.finance => 'FinanceOS',
  DomainScope.health => 'HealthOS',
  DomainScope.knowledge => 'KnowledgeOS',
  DomainScope.execution => 'ExecutionOS',
};

// ---------------------------------------------------------------------------
// Private sheet widgets
// ---------------------------------------------------------------------------

class _PassphraseSheet extends StatefulWidget {
  const _PassphraseSheet({
    required this.title,
    required this.hint,
    required this.confirmLabel,
  });

  final String title;
  final String hint;
  final String confirmLabel;

  @override
  State<_PassphraseSheet> createState() => _PassphraseSheetState();
}

class _PassphraseSheetState extends State<_PassphraseSheet> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AppSheet(
      title: widget.title,
      footer: AppSheetFooter(
        submitLabel: widget.confirmLabel,
        cancelLabel: l10n.backupCancelAction,
        onSubmit: _submit,
      ),
      child: FTextFormField(
        control: FTextFieldControl.managed(controller: _controller),
        label: Text(l10n.backupPassphraseLabel),
        hint: widget.hint,
        obscureText: true,
        autofocus: true,
      ),
    );
  }

  void _submit() {
    final l10n = AppLocalizations.of(context);
    if (_controller.text.isEmpty) {
      AppMessenger.show(
        context,
        ToastKind.error,
        l10n.backupPassphraseRequired,
      );
      return;
    }
    Navigator.of(context).pop(_controller.text);
  }
}

class _RestoreConfirmSheet extends ConsumerStatefulWidget {
  const _RestoreConfirmSheet({
    required this.file,
    required this.domain,
    required this.dirty,
  });
  final PickedBackupFile file;
  final DomainScope? domain;
  final FormDirtyController dirty;
  @override
  ConsumerState<_RestoreConfirmSheet> createState() =>
      _RestoreConfirmSheetState();
}

class _RestoreConfirmSheetState extends ConsumerState<_RestoreConfirmSheet>
    with FormSubmission<_RestoreConfirmSheet> {
  final _controller = TextEditingController();
  PreparedBackup? _prepared;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String _failure(Object error) {
    final l10n = AppLocalizations.of(context);
    return switch (error) {
      BackupAuthenticationException() => l10n.backupWrongPassphrase,
      BackupSchemaTooNewException() => l10n.backupSchemaTooNew,
      BackupValidationException() => l10n.backupArchiveInvalid,
      _ => userSafeErrorMessage(context, error),
    };
  }

  Future<void> _prepare() async {
    if (_busy) return;
    final l10n = AppLocalizations.of(context);
    final passphrase = _controller.text;
    if (passphrase.isEmpty) {
      setState(() => _error = l10n.backupPassphraseRequired);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    widget.dirty.busy = true;
    FocusScope.of(context).unfocus();
    try {
      final prepare = await ref.read(backupPrepareRestoreRunnerProvider.future);
      if (prepare == null) throw StateError('Backup service is not ready');
      final prepared = await prepare(
        passphrase: passphrase,
        fileBytes: widget.file.bytes,
        expectedDomain: widget.domain,
      );
      if (!mounted) return;
      setState(() => _prepared = prepared);
      // The decrypted archive stays in memory for confirmation and retry.
      _controller.clear();
    } catch (error) {
      if (mounted) setState(() => _error = _failure(error));
    } finally {
      widget.dirty.busy = false;
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restore() async {
    final prepared = _prepared;
    if (_busy || prepared == null) return;
    final l10n = AppLocalizations.of(context);
    await submitForm<RestoreResult>(
      dirty: widget.dirty,
      onBusyChanged: (value) => setState(() => _busy = value),
      commit: () async {
        final restore = await ref.read(
          backupApplyPreparedRestoreRunnerProvider.future,
        );
        if (restore == null) throw StateError('Backup service is not ready');
        return restore(prepared);
      },
      leave: () => Navigator.of(context).pop(prepared.summary),
      failureMessage: _failure,
      successMessage: l10n.backupImportSuccess(prepared.summary.totalRows),
      showFailureToast: false,
      tag: 'backup-restore',
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final prepared = _prepared;
    return AppSheet(
      title: l10n.backupConfirmRestoreTitle,
      footer: AppSheetFooter(
        submitKey: const Key('backup-restore-submit'),
        submitLabel: _busy
            ? prepared == null
                  ? l10n.backupInspectProgress
                  : l10n.backupImportProgress
            : prepared == null
            ? l10n.backupInspectAction
            : l10n.backupConfirmRestoreAction,
        cancelLabel: l10n.backupCancelAction,
        busy: _busy,
        destructive: prepared != null,
        onSubmit: prepared == null ? _prepare : _restore,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.file.name, style: context.labelStyle),
          const SizedBox(height: AppSpacing.s4),
          Text(
            l10n.backupSelectedFileSize((widget.file.size / 1024).ceil()),
            style: context.captionStyle,
          ),
          const SizedBox(height: AppSpacing.s12),
          if (prepared == null) ...[
            Text(l10n.backupInspectHint, style: context.bodyCaptionStyle),
            const SizedBox(height: AppSpacing.s16),
            FTextFormField(
              key: const Key('backup-restore-passphrase'),
              control: FTextFieldControl.managed(controller: _controller),
              label: Text(l10n.backupPassphraseLabel),
              hint: l10n.backupRestorePassphraseHint,
              enabled: !_busy,
              obscureText: true,
              autofocus: true,
              onSubmit: (_) => _prepare(),
            ),
          ] else ...[
            AppMetadataStrip(
              children: [
                AppMetadataItem(
                  label: l10n.backupArchiveScope,
                  value: prepared.summary.archiveDomain == null
                      ? l10n.backupFullScope
                      : _domainLabel(prepared.summary.archiveDomain!),
                ),
                AppMetadataItem(
                  label: l10n.backupArchiveDate,
                  value: MaterialLocalizations.of(context)
                      .formatMediumDate(prepared.createdAt.toLocal()),
                ),
                AppMetadataItem(
                  label: l10n.backupArchiveRows,
                  value: prepared.summary.totalRows.toString(),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.s16),
            AppStatusBanner(
              kind: AppStatusKind.warning,
              message: l10n.backupRestoreScopeWarning(
                prepared.summary.archiveDomain == null
                    ? l10n.backupFullScope
                    : _domainLabel(prepared.summary.archiveDomain!),
              ),
            ),
          ],
          if (_error ?? submissionFailureMessage case final message?) ...[
            const SizedBox(height: AppSpacing.s12),
            AppStatusBanner(
              kind: AppStatusKind.error,
              message: message,
              compact: true,
            ),
          ],
        ],
      ),
    );
  }
}
