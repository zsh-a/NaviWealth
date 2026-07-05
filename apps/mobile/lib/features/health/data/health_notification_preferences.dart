import 'package:flutter_riverpod/legacy.dart';

import '../../../core/notifications/notification_preferences.dart';
import '../../../design_system/preferences/theme_preferences.dart';

const String kHealthBriefingNotificationsEnabledKey =
    'lifeos.notifications.health.briefing.enabled';

final healthBriefingNotificationsEnabledProvider =
    StateNotifierProvider<SharedBoolPreferenceController, bool>((ref) {
      return SharedBoolPreferenceController(
        ref.watch(sharedPreferencesProvider),
        key: kHealthBriefingNotificationsEnabledKey,
        defaultValue: true,
      );
    });
