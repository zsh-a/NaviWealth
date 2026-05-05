import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/backup/backup_codec.dart';
import '../../../core/backup/backup_service.dart';
import '../../../core/backup/providers.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/sync/providers.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import 'file_saver.dart';

class BackupPage extends ConsumerWidget {
  const BackupPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: GlassAppBar(title: Text(l10n.settingsDataTitle)),
      body: ListView(
        padding: Spacing.pageMobile.copyWith(
          bottom: Spacing.pageMobile.bottom +
              Spacing.floatingBarClearance +
              MediaQuery.paddingOf(context).bottom,
        ),
        children: [
          LiquidGlassCard(
            layer: GlassLayer.tertiary,
            padding: EdgeInsets.zero,
            child: ListTile(
              leading: const Icon(Icons.upload_outlined),
              title: Text(l10n.backupExportTitle),
              subtitle: Text(l10n.backupExportSubtitle),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _exportBackup(context, ref),
            ),
          ),
          const SizedBox(height: Spacing.s12),
          LiquidGlassCard(
            layer: GlassLayer.tertiary,
            padding: EdgeInsets.zero,
            child: ListTile(
              leading: const Icon(Icons.download_outlined),
              title: Text(l10n.backupImportTitle),
              subtitle: Text(l10n.backupImportSubtitle),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _importBackup(context, ref),
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

    final dismiss = _showProgressSheet(context, l10n.backupExportProgress);

    try {
      final sw = Stopwatch()..start();
      final service = await ref.read(backupServiceProvider.future);
      logger.d('backup_ui: service resolved, calling exportBackup');
      final bytes = await service.exportBackup(passphrase: passphrase);
      sw.stop();
      logger.d('backup_ui: encryption done (${bytes.length} bytes, '
          '${sw.elapsedMilliseconds}ms)');

      await dismiss();
      if (!context.mounted) return;

      // Small delay to let the progress sheet fully close before showing
      // the system save dialog (needed on macOS).
      await Future<void>.delayed(const Duration(milliseconds: 300));

      final date = DateTime.now().toIso8601String().substring(0, 10);
      final fileName = 'naviwealth-backup-$date.bak';
      logger.d('backup_ui: opening save dialog for $fileName');
      final saved = await saveBackupFile(bytes, fileName);
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
      AppMessenger.show(context, ToastKind.error, e.toString());
    }
  }

  Future<void> _importBackup(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final logger = AppLogger.instance;

    // Pick backup file.
    logger.d('backup_ui: import flow started, opening file picker');
    FilePickerResult? result;
    try {
      result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['bak'],
        withData: true,
      );
    } catch (e, st) {
      logger.e('backup_ui: file picker threw', error: e, stackTrace: st);
      if (!context.mounted) return;
      AppMessenger.show(
        context,
        ToastKind.error,
        l10n.backupFilePickerError,
      );
      return;
    }
    if (result == null || result.files.isEmpty) {
      logger.d('backup_ui: import cancelled (no file selected)');
      return;
    }

    final pickedFile = result.files.first;
    logger.d('backup_ui: picked file name=${pickedFile.name} '
        'size=${pickedFile.size} hasBytes=${pickedFile.bytes != null}');
    var fileBytes = pickedFile.bytes;

    // On desktop, withData may not load bytes — fall back to reading from path.
    if (fileBytes == null && pickedFile.path != null) {
      logger.d('backup_ui: reading bytes from path=${pickedFile.path}');
      try {
        fileBytes = await File(pickedFile.path!).readAsBytes();
      } catch (e, st) {
        logger.e('backup_ui: failed to read file from path',
            error: e, stackTrace: st);
      }
    }

    if (fileBytes == null) {
      logger.w('backup_ui: no bytes available after file pick');
      if (!context.mounted) return;
      AppMessenger.show(
        context,
        ToastKind.error,
        l10n.backupFilePickerError,
      );
      return;
    }

    logger.d('backup_ui: file loaded (${fileBytes.length} bytes)');
    if (!context.mounted) return;

    // Show confirmation sheet with passphrase input.
    final passphrase = await _showRestoreConfirmSheet(context);
    if (passphrase == null || passphrase.isEmpty) {
      logger.d('backup_ui: restore cancelled (no passphrase)');
      return;
    }
    if (!context.mounted) return;

    final dismiss = _showProgressSheet(context, l10n.backupImportProgress);

    try {
      final sw = Stopwatch()..start();
      final service = await ref.read(backupServiceProvider.future);
      final scheduler = await ref.read(syncSchedulerProvider.future);
      logger.d('backup_ui: service resolved, pausing sync and restoring');

      final restoreResult = await service.restoreBackup(
        passphrase: passphrase,
        fileBytes: fileBytes,
        pauseSync: scheduler.pause,
        resumeSync: scheduler.resume,
      );
      sw.stop();
      logger.i('backup_ui: restore complete '
          '(${restoreResult.totalRows} rows, ${sw.elapsedMilliseconds}ms)');

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
      logger.w('backup_ui: restore failed — schema too new '
          '(backup=${e.backupVersion}, current=${e.currentVersion})');
      AppMessenger.show(context, ToastKind.error, l10n.backupSchemaTooNew);
    } on BackupValidationException catch (e) {
      await dismiss();
      if (!context.mounted) return;
      logger.w('backup_ui: restore failed — validation: ${e.message}');
      AppMessenger.show(context, ToastKind.error, e.message);
    } catch (e, st) {
      logger.e('backup_ui: restore failed unexpectedly',
          error: e, stackTrace: st);
      await dismiss();
      if (!context.mounted) return;
      AppMessenger.show(context, ToastKind.error, e.toString());
    }
  }

  Future<String?> _showPassphraseSheet({
    required BuildContext context,
    required String title,
    required String hint,
    required String confirmLabel,
  }) {
    return showGlassModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _PassphraseSheet(
        title: title,
        hint: hint,
        confirmLabel: confirmLabel,
      ),
    );
  }

  Future<String?> _showRestoreConfirmSheet(BuildContext context) {
    return showGlassModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _RestoreConfirmSheet(),
    );
  }

  /// Shows a non-dismissable progress indicator and returns a callback
  /// that dismisses it. Uses [showGeneralDialog] instead of
  /// [showModalBottomSheet] because GoRouter's navigator takes over the
  /// root navigator — popping a sheet from there removes the underlying
  /// page. [showGeneralDialog] creates its own Navigator scope, so
  /// `Navigator.of(context).pop()` only dismisses the dialog.
  Future<void> Function() _showProgressSheet(
    BuildContext context,
    String message,
  ) {
    final completer = Completer<VoidCallback>();
    showGeneralDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierLabel: 'backup-progress',
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (ctx, _, _) => _ProgressSheet(
        message: message,
        onReady: (dismiss) {
          if (!completer.isCompleted) completer.complete(dismiss);
        },
      ),
    );
    return () async {
      final dismiss = await completer.future;
      dismiss();
    };
  }
}

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
    final viewInsets = MediaQuery.viewInsetsOf(context);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          Spacing.s16,
          0,
          Spacing.s16,
          Spacing.s16 + viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.title,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: Spacing.s16),
            AppTextField(
              label: l10n.backupPassphraseLabel,
              hint: widget.hint,
              controller: _controller,
              obscureText: true,
              autofocus: true,
            ),
            const SizedBox(height: Spacing.s16),
            Row(
              children: [
                Expanded(
                  child: AppButton.secondary(
                    label: l10n.backupCancelAction,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
                const SizedBox(width: Spacing.s12),
                Expanded(
                  child: AppButton.primary(
                    label: widget.confirmLabel,
                    onPressed: _submit,
                  ),
                ),
              ],
            ),
          ],
        ),
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
  const _RestoreConfirmSheet();

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
    final viewInsets = MediaQuery.viewInsetsOf(context);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          Spacing.s16,
          0,
          Spacing.s16,
          Spacing.s16 + viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.backupConfirmRestoreTitle,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: Spacing.s8),
            Text(
              l10n.backupConfirmRestoreMessage,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: Spacing.s16),
            AppTextField(
              label: l10n.backupPassphraseLabel,
              hint: l10n.backupRestorePassphraseHint,
              controller: _controller,
              obscureText: true,
              autofocus: true,
            ),
            const SizedBox(height: Spacing.s16),
            Row(
              children: [
                Expanded(
                  child: AppButton.secondary(
                    label: l10n.backupCancelAction,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
                const SizedBox(width: Spacing.s12),
                Expanded(
                  child: AppButton.primary(
                    label: l10n.backupConfirmRestoreAction,
                    onPressed: _submit,
                  ),
                ),
              ],
            ),
          ],
        ),
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

class _ProgressSheet extends StatefulWidget {
  const _ProgressSheet({required this.message, required this.onReady});

  final String message;

  /// Called once the sheet's State is mounted with a dismiss callback that
  /// pops the route from the sheet's own Navigator context.
  final ValueChanged<VoidCallback> onReady;

  @override
  State<_ProgressSheet> createState() => _ProgressSheetState();
}

class _ProgressSheetState extends State<_ProgressSheet> {
  @override
  void initState() {
    super.initState();
    // Deliver the dismiss callback once we're safely mounted.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onReady(_dismiss);
    });
  }

  void _dismiss() {
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.bottomCenter,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            Spacing.s16,
            0,
            Spacing.s16,
            Spacing.s24,
          ),
          child: Row(
            children: [
              const CircularProgressIndicator(),
              const SizedBox(width: Spacing.s16),
              Expanded(
                child: Text(
                  widget.message,
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
