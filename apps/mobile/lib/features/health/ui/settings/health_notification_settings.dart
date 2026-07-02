import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../../../core/notifications/notification_preferences.dart';
import '../../../../core/shell/settings_ui/inline_setting_row.dart';
import '../../../../l10n/gen/app_localizations.dart';
import '../../data/health_notification_preferences.dart';
import '../../data/morning_briefing_preferences.dart';

List<Widget> healthNotificationSettings() => const <Widget>[
  HealthBriefingNotificationSettingRow(),
];

class HealthBriefingNotificationSettingRow extends ConsumerWidget {
  const HealthBriefingNotificationSettingRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final notificationsEnabled = ref.watch(notificationsEnabledProvider);
    final briefingEnabled = ref.watch(
      healthBriefingNotificationsEnabledProvider,
    );
    final hour = ref.watch(morningBriefingHourProvider);
    final hourLabel = hour.toString().padLeft(2, '0');

    return InlineSwitchRow(
      icon: FLucideIcons.sunrise,
      label: l10n.settingsNotificationsHealthBriefingTitle,
      subtitle: notificationsEnabled
          ? l10n.settingsNotificationsHealthBriefingSubtitle(hourLabel)
          : l10n.settingsNotificationsHealthBriefingBlockedSubtitle,
      value: notificationsEnabled && briefingEnabled,
      enabled: notificationsEnabled,
      onChanged: (next) => ref
          .read(healthBriefingNotificationsEnabledProvider.notifier)
          .setEnabled(next),
    );
  }
}
