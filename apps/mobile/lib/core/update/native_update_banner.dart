import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../design_system/design_system.dart';
import '../../l10n/gen/app_localizations.dart';
import '../notifications/notification_preferences.dart';
import '../notifications/providers.dart';
import 'native_update.dart';
import 'native_update_errors.dart';
import 'native_update_installer.dart';

/// Android GitHub self-update prompt.
///
/// The update is downloaded inside the app, verified by SHA-256 in Dart and
/// by package/signature/version checks in the Android bridge, then handed to
/// Android's package installer for the final user confirmation.
final class NativeUpdateBanner extends ConsumerStatefulWidget {
  const NativeUpdateBanner({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<NativeUpdateBanner> createState() => _NativeUpdateBannerState();
}

final class _NativeUpdateBannerState extends ConsumerState<NativeUpdateBanner>
    with WidgetsBindingObserver {
  bool _updating = false;
  int _receivedBytes = 0;
  int _totalBytes = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    ref.listenManual<AsyncValue<NativeUpdateState>>(
      nativeUpdateStateProvider,
      (_, next) => unawaited(_syncNotification(next.value)),
    );
    ref.listenManual<bool>(notificationsEnabledProvider, (_, enabled) {
      if (enabled) {
        unawaited(_syncNotification(ref.read(nativeUpdateStateProvider).value));
      } else {
        unawaited(_clearNotification());
      }
    });
    // `listenManual` intentionally does not fire immediately in initState.
    // Sync once after the first frame as well, covering a provider that was
    // already resolved before this banner was mounted.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(_syncNotification(ref.read(nativeUpdateStateProvider).value));
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.invalidate(packageInfoProvider);
      ref.invalidate(nativeUpdateCheckProvider(false));
      ref.invalidate(nativeUpdateStateProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    final asyncState = ref.watch(nativeUpdateStateProvider);
    final state = asyncState.value;
    if (state == null || !state.shouldShow || state.manifest == null) {
      return widget.child;
    }

    final l10n = AppLocalizations.of(context);
    final colors = context.theme.colors;
    final manifest = state.manifest!;
    final progress = _progress;
    return Stack(
      children: [
        widget.child,
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: SafeArea(
            top: false,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: colors.foreground,
                boxShadow: AppShadow.banner,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.s16,
                  vertical: AppSpacing.s12,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Icon(FLucideIcons.download, color: colors.background),
                        const SizedBox(width: AppSpacing.s12),
                        Expanded(
                          child: Text(
                            l10n.nativeUpdateAvailable(state.latestVersion),
                            style: context.theme.typography.body.sm.copyWith(
                              color: colors.background,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (manifest.releaseNotes.isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.s8),
                      for (final note in manifest.releaseNotes)
                        Padding(
                          padding: const EdgeInsets.only(left: AppSpacing.s28),
                          child: Text(
                            '• $note',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: context.theme.typography.body.xs.copyWith(
                              color: colors.background.withValues(alpha: 0.8),
                            ),
                          ),
                        ),
                    ],
                    if (_updating) ...[
                      const SizedBox(height: AppSpacing.s8),
                      _ProgressBar(
                        progress: progress,
                        foreground: colors.background,
                        background: colors.background.withValues(alpha: 0.2),
                      ),
                      const SizedBox(height: AppSpacing.s4),
                      Text(
                        l10n.nativeUpdateDownloading(_progressPercent),
                        textAlign: TextAlign.end,
                        style: context.theme.typography.body.xs.copyWith(
                          color: colors.background.withValues(alpha: 0.8),
                        ),
                      ),
                    ],
                    const SizedBox(height: AppSpacing.s8),
                    Wrap(
                      alignment: WrapAlignment.end,
                      spacing: AppSpacing.s8,
                      runSpacing: AppSpacing.s8,
                      children: [
                        if (!state.requiredUpdate && !_updating)
                          FButton(
                            variant: FButtonVariant.ghost,
                            onPress: () => _dismiss(state),
                            child: Text(l10n.nativeUpdateDismiss),
                          ),
                        FButton(
                          variant: FButtonVariant.outline,
                          onPress: _updating
                              ? null
                              : () => unawaited(_startUpdate(state)),
                          child: Text(
                            _updating
                                ? l10n.nativeUpdateDownloading(_progressPercent)
                                : l10n.nativeUpdateApply,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  double? get _progress {
    if (_totalBytes <= 0 || _receivedBytes < 0) return null;
    return (_receivedBytes / _totalBytes).clamp(0, 1).toDouble();
  }

  int get _progressPercent => ((_progress ?? 0) * 100).round();

  Future<void> _syncNotification(NativeUpdateState? state) async {
    if (!mounted) return;
    final service = ref.read(notificationServiceProvider);
    const controller = NativeUpdateNotificationController();
    try {
      if (!ref.read(notificationsEnabledProvider)) {
        await controller.clear(service);
        return;
      }
      final l10n = AppLocalizations.of(context);
      await controller.showIfNeeded(
        state: state ?? NativeUpdateState.hidden,
        service: service,
        preferences: ref.read(sharedPreferencesProvider),
        title: l10n.nativeUpdateNotificationTitle,
        body: state == null
            ? ''
            : l10n.nativeUpdateNotificationBody(state.latestVersion),
      );
    } on Object {
      // Notification delivery is best-effort. The in-app update banner must
      // remain usable when the OS has revoked permission or the plugin fails.
    }
  }

  Future<void> _clearNotification() async {
    try {
      await const NativeUpdateNotificationController().clear(
        ref.read(notificationServiceProvider),
      );
    } on Object {
      // Best-effort cleanup only.
    }
  }

  Future<void> _dismiss(NativeUpdateState state) async {
    final versionKey = state.versionKey;
    if (versionKey.isEmpty) return;
    await ref
        .read(sharedPreferencesProvider)
        .setString(kNativeUpdateDismissedVersionKey, versionKey);
    ref.invalidate(nativeUpdateStateProvider);
  }

  Future<void> _startUpdate(NativeUpdateState state) async {
    final manifest = state.manifest;
    if (manifest == null || _updating) return;
    setState(() {
      _updating = true;
      _receivedBytes = 0;
      _totalBytes = manifest.sizeBytes ?? 0;
    });

    try {
      final installer = ref.read(nativeUpdateInstallerProvider);
      if (!await installer.canInstallPackages()) {
        await installer.openInstallSettings();
        if (mounted) {
          AppMessenger.show(
            context,
            ToastKind.info,
            AppLocalizations.of(context).nativeUpdateInstallPermission,
          );
        }
        return;
      }

      await ref
          .read(nativeUpdateServiceProvider)
          .downloadAndInstall(
            manifest,
            onProgress: (received, total) {
              if (!mounted) return;
              setState(() {
                _receivedBytes = received;
                _totalBytes = total > 0 ? total : _totalBytes;
              });
            },
          );
      if (mounted) {
        AppMessenger.show(
          context,
          ToastKind.info,
          AppLocalizations.of(context).nativeUpdateInstallStarted,
        );
      }
    } on NativeUpdateException catch (error) {
      if (mounted) _showFailure(error.failure);
    } on Object {
      if (mounted) _showFailure(NativeUpdateFailure.download);
    } finally {
      if (mounted) {
        setState(() {
          _updating = false;
        });
      }
    }
  }

  void _showFailure(NativeUpdateFailure failure) {
    final l10n = AppLocalizations.of(context);
    final message = switch (failure) {
      NativeUpdateFailure.installPermission =>
        l10n.nativeUpdateInstallPermission,
      NativeUpdateFailure.integrity => l10n.nativeUpdateVerificationFailed,
      NativeUpdateFailure.packageMismatch => l10n.nativeUpdatePackageMismatch,
      NativeUpdateFailure.install => l10n.nativeUpdateInstallFailed,
      NativeUpdateFailure.download ||
      NativeUpdateFailure.unsupported => l10n.nativeUpdateDownloadFailed,
    };
    AppMessenger.show(context, ToastKind.error, message);
  }
}

final class _ProgressBar extends StatelessWidget {
  const _ProgressBar({
    required this.progress,
    required this.foreground,
    required this.background,
  });

  final double? progress;
  final Color foreground;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: SizedBox(
        height: 4,
        child: DecoratedBox(
          decoration: BoxDecoration(color: background),
          child: Align(
            alignment: Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: progress ?? 0,
              child: ColoredBox(color: foreground),
            ),
          ),
        ),
      ),
    );
  }
}
