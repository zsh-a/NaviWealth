import 'dart:async';
import 'dart:developer' as dev;
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/backup/backup_codec.dart';
import '../../../core/backup/backup_service.dart';
import '../../../core/backup/providers.dart';
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
    final passphrase = await _showPassphraseSheet(
      context: context,
      title: l10n.backupExportTitle,
      hint: l10n.backupPassphraseHint,
      confirmLabel: l10n.backupExportAction,
    );
    if (passphrase == null || passphrase.isEmpty) return;
    if (!context.mounted) return;

    final dismiss = _showProgressSheet(context, l10n.backupExportProgress);

    try {
      final service = await ref.read(backupServiceProvider.future);
      final bytes = await service.exportBackup(passphrase: passphrase);
      dev.log('Export complete: ${bytes.length} bytes');

      dismiss();
      if (!context.mounted) return;

      // Small delay to let the progress sheet fully close before showing
      // the system save dialog (needed on macOS).
      await Future<void>.delayed(const Duration(milliseconds: 200));

      final date = DateTime.now().toIso8601String().substring(0, 10);
      final fileName = 'naviwealth-backup-$date.bak';
      dev.log('Opening save dialog for: $fileName');
      final saved = await saveBackupFile(bytes, fileName);
      dev.log('saveBackupFile returned: $saved');

      if (!context.mounted || !saved) return;
      AppMessenger.show(context, ToastKind.success, l10n.backupExportSuccess);
    } on BackupAuthenticationException {
      dismiss();
      if (!context.mounted) return;
      AppMessenger.show(context, ToastKind.error, l10n.backupWrongPassphrase);
    } catch (e, st) {
      dev.log('Export failed', error: e, stackTrace: st);
      dismiss();
      if (!context.mounted) return;
      AppMessenger.show(context, ToastKind.error, e.toString());
    }
  }

  Future<void> _importBackup(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);

    // Pick backup file.
    dev.log('Import: opening file picker');
    FilePickerResult? result;
    try {
      result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['bak'],
        withData: true,
      );
    } catch (e, st) {
      dev.log('Import: file picker threw', error: e, stackTrace: st);
      if (!context.mounted) return;
      AppMessenger.show(
        context,
        ToastKind.error,
        l10n.backupFilePickerError,
      );
      return;
    }
    if (result == null || result.files.isEmpty) {
      dev.log('Import: user cancelled or no files');
      return;
    }

    final pickedFile = result.files.first;
    dev.log('Import: picked file name=${pickedFile.name} '
        'path=${pickedFile.path} size=${pickedFile.size} '
        'bytes=${pickedFile.bytes?.length}');
    var fileBytes = pickedFile.bytes;

    // On desktop, withData may not load bytes — fall back to reading from path.
    if (fileBytes == null && pickedFile.path != null) {
      try {
        fileBytes = await File(pickedFile.path!).readAsBytes();
      } catch (_) {}
    }

    if (fileBytes == null) {
      if (!context.mounted) return;
      AppMessenger.show(
        context,
        ToastKind.error,
        l10n.backupFilePickerError,
      );
      return;
    }

    if (!context.mounted) return;

    // Show confirmation sheet with passphrase input.
    final passphrase = await _showRestoreConfirmSheet(context);
    if (passphrase == null || passphrase.isEmpty) return;
    if (!context.mounted) return;

    final dismiss = _showProgressSheet(context, l10n.backupImportProgress);

    try {
      final service = await ref.read(backupServiceProvider.future);
      final scheduler = await ref.read(syncSchedulerProvider.future);

      final restoreResult = await service.restoreBackup(
        passphrase: passphrase,
        fileBytes: fileBytes,
        pauseSync: scheduler.pause,
        resumeSync: scheduler.resume,
      );

      dismiss();
      if (!context.mounted) return;

      AppMessenger.show(
        context,
        ToastKind.success,
        l10n.backupImportSuccess(restoreResult.totalRows),
      );
    } on BackupAuthenticationException {
      dismiss();
      if (!context.mounted) return;
      AppMessenger.show(context, ToastKind.error, l10n.backupWrongPassphrase);
    } on BackupSchemaTooNewException {
      dismiss();
      if (!context.mounted) return;
      AppMessenger.show(context, ToastKind.error, l10n.backupSchemaTooNew);
    } on BackupValidationException catch (e) {
      dismiss();
      if (!context.mounted) return;
      AppMessenger.show(context, ToastKind.error, e.message);
    } catch (e) {
      dismiss();
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

  /// Shows a non-dismissable progress sheet and returns a callback that
  /// dismisses it from the sheet's own navigator context (avoids the
  /// root-navigator `_debugLocked` assertion).
  VoidCallback _showProgressSheet(BuildContext context, String message) {
    final completer = Completer<VoidCallback>();
    showGlassModalBottomSheet<void>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      builder: (_) => _ProgressSheet(
        message: message,
        onReady: (dismiss) {
          if (!completer.isCompleted) completer.complete(dismiss);
        },
      ),
    );
    // The dismiss callback will be available once the sheet's State mounts.
    return () {
      completer.future.then((dismiss) => dismiss());
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
    return SafeArea(
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
    );
  }
}
