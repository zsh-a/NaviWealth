import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/core/auth/domain_scope.dart';
import 'package:naviwealth/core/backup/backup_codec.dart';
import 'package:naviwealth/core/backup/backup_service.dart';
import 'package:naviwealth/core/backup/providers.dart';
import 'package:naviwealth/core/logging/app_logger.dart';
import 'package:naviwealth/core/shell/settings_ui/inline_setting_row.dart';
import 'package:naviwealth/core/shell/settings_ui/settings_page_frame.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/settings/data/backup/file_saver.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

typedef BackupFileSaver =
    Future<bool> Function(Uint8List bytes, String fileName);

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
    final fileBytes = pickedFile.bytes;
    logger.d('backup_ui: file loaded (${fileBytes.length} bytes)');
    if (!context.mounted) return;

    // Show confirmation sheet with passphrase input.
    final passphrase = await _showRestoreConfirmSheet(context);
    if (passphrase == null || passphrase.isEmpty) {
      logger.d('backup_ui: restore cancelled (no passphrase)');
      return;
    }
    if (!context.mounted) return;

    final dismiss = await showProgressDialog(
      context: context,
      message: l10n.backupImportProgress,
    );

    try {
      final sw = Stopwatch()..start();
      logger.d('backup_ui: service resolved, pausing sync and restoring');

      final RestoreResult restoreResult;
      if (domain case final expectedDomain?) {
        final restore = await ref.read(
          domainBackupRestoreRunnerProvider.future,
        );
        if (restore == null) {
          throw StateError('Backup service is not ready.');
        }
        restoreResult = await restore(
          passphrase: passphrase,
          fileBytes: fileBytes,
          domain: expectedDomain,
        );
      } else {
        final restore = await ref.read(backupRestoreRunnerProvider.future);
        if (restore == null) {
          throw StateError('Backup service is not ready.');
        }
        restoreResult = await restore(
          passphrase: passphrase,
          fileBytes: fileBytes,
        );
      }
      sw.stop();
      logger.i(
        'backup_ui: restore complete '
        '(${restoreResult.totalRows} rows, ${sw.elapsedMilliseconds}ms)',
      );

      await dismiss();
      if (!context.mounted) return;

      AppMessenger.show(
        context,
        ToastKind.success,
        l10n.backupImportSuccess(restoreResult.totalRows),
      );
    } on BackupAuthenticationException {
      await dismiss();
      if (!context.mounted) return;
      logger.w('backup_ui: restore failed — wrong passphrase or corrupt file');
      AppMessenger.show(context, ToastKind.error, l10n.backupWrongPassphrase);
    } on BackupSchemaTooNewException catch (e) {
      await dismiss();
      if (!context.mounted) return;
      logger.w(
        'backup_ui: restore failed — schema too new '
        '(backup=${e.backupVersion}, current=${e.currentVersion})',
      );
      AppMessenger.show(context, ToastKind.error, l10n.backupSchemaTooNew);
    } on BackupValidationException catch (e) {
      await dismiss();
      if (!context.mounted) return;
      logger.w('backup_ui: restore failed — validation: ${e.message}');
      AppMessenger.show(context, ToastKind.error, e.message);
    } catch (e, st) {
      logger.e(
        'backup_ui: restore failed unexpectedly',
        error: e,
        stackTrace: st,
      );
      await dismiss();
      if (!context.mounted) return;
      AppMessenger.show(
        context,
        ToastKind.error,
        userSafeErrorMessage(context, e, stackTrace: st),
      );
    }
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

  Future<String?> _showRestoreConfirmSheet(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return showAppFormSheet<String>(
      context: context,
      builder: (_) =>
          _RestoreConfirmSheet(title: l10n.backupConfirmRestoreTitle),
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

class _RestoreConfirmSheet extends StatefulWidget {
  const _RestoreConfirmSheet({required this.title});

  final String title;

  @override
  State<_RestoreConfirmSheet> createState() => _RestoreConfirmSheetState();
}

class _RestoreConfirmSheetState extends State<_RestoreConfirmSheet> {
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
        submitLabel: l10n.backupConfirmRestoreAction,
        cancelLabel: l10n.backupCancelAction,
        onSubmit: _submit,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.backupConfirmRestoreMessage,
            style: context.bodyCaptionStyle.copyWith(height: 1.4),
          ),
          const SizedBox(height: AppSpacing.s16),
          FTextFormField(
            control: FTextFieldControl.managed(controller: _controller),
            label: Text(l10n.backupPassphraseLabel),
            hint: l10n.backupRestorePassphraseHint,
            obscureText: true,
            autofocus: true,
          ),
        ],
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
