import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/app/domain_packs.dart';
import 'package:naviwealth/core/lifeos/domain_pack.dart';
import 'package:naviwealth/core/notifications/notification_preferences.dart';
import 'package:naviwealth/core/notifications/notification_service.dart';
import 'package:naviwealth/core/notifications/providers.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/health/data/health_notification_preferences.dart';
import 'package:naviwealth/features/settings/ui/notification_settings_page.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

ProviderContainer _container(SharedPreferences prefs) {
  return ProviderContainer(
    overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
  );
}

void main() {
  group('notification preferences', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test(
      'default app notifications and briefing notifications to on',
      () async {
        final prefs = await SharedPreferences.getInstance();
        final c = _container(prefs);
        addTearDown(c.dispose);

        expect(c.read(notificationsEnabledProvider), isTrue);
        expect(c.read(healthBriefingNotificationsEnabledProvider), isTrue);
      },
    );

    test('persist app-level and briefing-level toggles', () async {
      var prefs = await SharedPreferences.getInstance();
      final c = _container(prefs);

      await c.read(notificationsEnabledProvider.notifier).setEnabled(false);
      await c
          .read(healthBriefingNotificationsEnabledProvider.notifier)
          .setEnabled(false);
      c.dispose();

      prefs = await SharedPreferences.getInstance();
      final c2 = _container(prefs);
      addTearDown(c2.dispose);

      expect(c2.read(notificationsEnabledProvider), isFalse);
      expect(c2.read(healthBriefingNotificationsEnabledProvider), isFalse);
    });

    testWidgets('settings page renders permission state and toggles', (
      tester,
    ) async {
      final prefs = await SharedPreferences.getInstance();
      late ProviderContainer container;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            notificationServiceProvider.overrideWithValue(
              const _FakeNotificationService(available: true, granted: true),
            ),
            activeDomainPacksProvider.overrideWithValue([kHealthPack]),
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Consumer(
              builder: (context, ref, _) {
                container = ProviderScope.containerOf(context, listen: false);
                return const NotificationSettingsPage();
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Notifications'), findsOneWidget);
      expect(find.text('System notifications are allowed.'), findsOneWidget);
      expect(find.text('Allow app notifications'), findsOneWidget);
      expect(find.text('Morning Briefing'), findsOneWidget);

      await tester.tap(find.byType(FSwitch).first);
      await tester.pumpAndSettle();

      expect(container.read(notificationsEnabledProvider), isFalse);
      expect(
        find.text(
          'Turn on app notifications to run the daily briefing reminder.',
        ),
        findsOneWidget,
      );
    });
  });
}

class _FakeNotificationService implements NotificationService {
  const _FakeNotificationService({
    required this.available,
    required this.granted,
  });

  final bool available;
  final bool granted;

  @override
  Stream<String> get payloads => const Stream<String>.empty();

  @override
  Future<String?> initialPayload() async => null;

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<bool> hasPermissions() async => granted;

  @override
  Future<bool> requestPermissions() async => granted;

  @override
  Future<void> showNow({
    required int id,
    required String title,
    required String body,
    required NotificationChannelSpec channel,
    String? payload,
  }) async {}

  @override
  Future<void> cancel(int id) async {}
}
