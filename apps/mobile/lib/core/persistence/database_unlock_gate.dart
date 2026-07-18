import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../design_system/design_system.dart';
import '../../l10n/gen/app_localizations.dart';
import 'database_encryption.dart';
import 'providers.dart';

class DatabaseUnlockGate extends ConsumerStatefulWidget {
  const DatabaseUnlockGate({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<DatabaseUnlockGate> createState() => _DatabaseUnlockGateState();
}

class _DatabaseUnlockGateState extends ConsumerState<DatabaseUnlockGate> {
  bool _resetting = false;

  @override
  Widget build(BuildContext context) {
    final database = ref.watch(appDatabaseProvider);
    return switch (database) {
      AsyncData() => widget.child,
      AsyncLoading() => const _DatabaseLoadingSurface(),
      AsyncError(:final error) => _DatabaseFailureSurface(
        error: error,
        resetting: _resetting,
        onRetry: () => ref.invalidate(appDatabaseProvider),
        onReset: _canReset(error) ? _reset : null,
      ),
    };
  }

  bool _canReset(Object error) =>
      error is DatabaseEncryptionException &&
      switch (error.code) {
        DatabaseEncryptionFailureCode.keyMissing ||
        DatabaseEncryptionFailureCode.invalidKey ||
        DatabaseEncryptionFailureCode.unlockFailed => true,
        DatabaseEncryptionFailureCode.cipherUnavailable ||
        DatabaseEncryptionFailureCode.migrationFailed => false,
      };

  Future<void> _reset() async {
    if (_resetting) return;
    final l10n = AppLocalizations.of(context);
    final confirmed = await showConfirmDialog(
      context: context,
      title: Text(l10n.databaseRecoveryResetConfirmTitle),
      body: Text(l10n.databaseRecoveryResetConfirmBody),
      confirmLabel: l10n.databaseRecoveryResetConfirmAction,
      cancelLabel: l10n.commonCancel,
      destructive: true,
      icon: FLucideIcons.databaseZap,
    );
    if (confirmed != true || !mounted) return;

    setState(() => _resetting = true);
    try {
      await ref
          .read(databaseRecoveryControllerProvider)
          .resetLocalEncryptedData();
    } on Object {
      if (!mounted) return;
      AppMessenger.show(
        context,
        ToastKind.error,
        l10n.databaseRecoveryResetFailed,
      );
    } finally {
      if (mounted) setState(() => _resetting = false);
    }
  }
}

class _DatabaseLoadingSurface extends StatelessWidget {
  const _DatabaseLoadingSurface();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ColoredBox(
      color: context.theme.colors.background,
      child: SafeArea(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const FCircularProgress(),
              const SizedBox(height: AppSpacing.s16),
              Text(l10n.databaseUnlockLoading, style: context.bodyCaptionStyle),
            ],
          ),
        ),
      ),
    );
  }
}

class _DatabaseFailureSurface extends StatelessWidget {
  const _DatabaseFailureSurface({
    required this.error,
    required this.resetting,
    required this.onRetry,
    this.onReset,
  });

  final Object error;
  final bool resetting;
  final VoidCallback onRetry;
  final FutureOr<void> Function()? onReset;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final presentation = _presentation(l10n, error);
    return ColoredBox(
      color: context.theme.colors.background,
      child: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: AppEmptyState.error(
              icon: FLucideIcons.databaseZap,
              title: presentation.title,
              message: presentation.message,
              action: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FButton(
                    onPress: resetting ? null : onRetry,
                    child: Text(l10n.databaseRecoveryRetry),
                  ),
                  if (onReset != null) ...[
                    const SizedBox(height: AppSpacing.s8),
                    AppQuietButton(
                      tone: AppQuietButtonTone.danger,
                      label: l10n.databaseRecoveryResetAction,
                      busy: resetting,
                      busyLabel: l10n.databaseRecoveryResetting,
                      onPress: resetting
                          ? null
                          : () => unawaited(Future<void>.sync(onReset!)),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  ({String title, String message}) _presentation(
    AppLocalizations l10n,
    Object error,
  ) {
    if (error is! DatabaseEncryptionException) {
      return (
        title: l10n.databaseRecoveryUnavailableTitle,
        message: l10n.databaseRecoveryUnavailableMessage,
      );
    }
    return switch (error.code) {
      DatabaseEncryptionFailureCode.keyMissing => (
        title: l10n.databaseRecoveryTitle,
        message: l10n.databaseRecoveryMissingKeyMessage,
      ),
      DatabaseEncryptionFailureCode.invalidKey => (
        title: l10n.databaseRecoveryTitle,
        message: l10n.databaseRecoveryInvalidKeyMessage,
      ),
      DatabaseEncryptionFailureCode.unlockFailed => (
        title: l10n.databaseRecoveryTitle,
        message: l10n.databaseRecoveryUnlockFailedMessage,
      ),
      DatabaseEncryptionFailureCode.migrationFailed => (
        title: l10n.databaseRecoveryMigrationTitle,
        message: l10n.databaseRecoveryMigrationMessage,
      ),
      DatabaseEncryptionFailureCode.cipherUnavailable => (
        title: l10n.databaseRecoveryUnavailableTitle,
        message: l10n.databaseRecoveryUnavailableMessage,
      ),
    };
  }
}
