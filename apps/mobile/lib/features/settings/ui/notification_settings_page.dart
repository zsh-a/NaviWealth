import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../../core/notifications/notification_preferences.dart';
import '../../../core/notifications/providers.dart';
import '../../../core/shell/settings_ui/inline_setting_row.dart';
import '../../../core/shell/settings_ui/settings_page_frame.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../health/data/health_notification_preferences.dart';
import '../../health/data/morning_briefing_preferences.dart';

final _notificationPermissionSnapshotProvider =
    FutureProvider.autoDispose<_NotificationPermissionSnapshot>((ref) async {
      final service = ref.watch(notificationServiceProvider);
      final available = await service.isAvailable();
      if (!available) {
        return const _NotificationPermissionSnapshot(
          available: false,
          granted: false,
        );
      }
      return _NotificationPermissionSnapshot(
        available: true,
        granted: await service.hasPermissions(),
      );
    });

class NotificationSettingsPage extends ConsumerWidget {
  const NotificationSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final notificationsEnabled = ref.watch(notificationsEnabledProvider);
    final briefingEnabled = ref.watch(
      healthBriefingNotificationsEnabledProvider,
    );
    final hour = ref.watch(morningBriefingHourProvider);
    final hourLabel = hour.toString().padLeft(2, '0');

    return AppPageScaffold(
      title: l10n.settingsNotificationsTitle,
      childPad: false,
      child: SettingsPageFrame(
        children: [
          const _NotificationPermissionBanner(),
          const SizedBox(height: AppSpacing.s16),
          SoftCard(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.s4),
            child: Column(
              children: [
                InlineSwitchRow(
                  icon: FLucideIcons.bell,
                  label: l10n.settingsNotificationsMasterTitle,
                  subtitle: l10n.settingsNotificationsMasterSubtitle,
                  value: notificationsEnabled,
                  onChanged: (next) => ref
                      .read(notificationsEnabledProvider.notifier)
                      .setEnabled(next),
                ),
                const AppGradientDivider(),
                InlineSwitchRow(
                  icon: FLucideIcons.sunrise,
                  label: l10n.settingsNotificationsHealthBriefingTitle,
                  subtitle: notificationsEnabled
                      ? l10n.settingsNotificationsHealthBriefingSubtitle(
                          hourLabel,
                        )
                      : l10n.settingsNotificationsHealthBriefingBlockedSubtitle,
                  value: notificationsEnabled && briefingEnabled,
                  enabled: notificationsEnabled,
                  onChanged: (next) => ref
                      .read(healthBriefingNotificationsEnabledProvider.notifier)
                      .setEnabled(next),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NotificationPermissionBanner extends ConsumerStatefulWidget {
  const _NotificationPermissionBanner();

  @override
  ConsumerState<_NotificationPermissionBanner> createState() =>
      _NotificationPermissionBannerState();
}

class _NotificationPermissionBannerState
    extends ConsumerState<_NotificationPermissionBanner> {
  bool _requesting = false;

  Future<void> _request() async {
    if (_requesting) return;
    setState(() => _requesting = true);
    try {
      final service = ref.read(notificationServiceProvider);
      if (await service.isAvailable()) {
        await service.requestPermissions();
      }
      ref.invalidate(_notificationPermissionSnapshotProvider);
    } finally {
      if (mounted) setState(() => _requesting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final snapshot = ref.watch(_notificationPermissionSnapshotProvider);

    return snapshot.when(
      loading: () => AppStatusBanner(
        kind: AppStatusKind.neutral,
        message: l10n.settingsNotificationsPermissionChecking,
      ),
      error: (error, _) => AppStatusBanner(
        kind: AppStatusKind.error,
        message: l10n.settingsNotificationsPermissionFailed('$error'),
        action: FButton(
          variant: FButtonVariant.outline,
          onPress: () =>
              ref.invalidate(_notificationPermissionSnapshotProvider),
          child: Text(l10n.commonRetry),
        ),
      ),
      data: (status) {
        if (!status.available) {
          return AppStatusBanner(
            kind: AppStatusKind.neutral,
            message: l10n.settingsNotificationsPermissionUnavailable,
          );
        }
        if (status.granted) {
          return AppStatusBanner(
            kind: AppStatusKind.success,
            message: l10n.settingsNotificationsPermissionGranted,
          );
        }
        return AppStatusBanner(
          kind: AppStatusKind.warning,
          message: l10n.settingsNotificationsPermissionDenied,
          action: FButton(
            variant: FButtonVariant.outline,
            onPress: _requesting ? null : _request,
            child: Text(
              _requesting
                  ? l10n.settingsNotificationsPermissionRequesting
                  : l10n.settingsNotificationsPermissionRequest,
            ),
          ),
        );
      },
    );
  }
}

class _NotificationPermissionSnapshot {
  const _NotificationPermissionSnapshot({
    required this.available,
    required this.granted,
  });

  final bool available;
  final bool granted;
}
