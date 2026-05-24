import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/logging/crash_reporting_preference.dart';
import 'package:naviwealth/core/logging/logging_crash_reporter.dart';
import 'package:naviwealth/core/logging/providers.dart';
import 'package:naviwealth/design_system/preferences/theme_preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'debug crash reporter can share talker without a provider cycle',
    () async {
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          crashReporterDelegateProvider.overrideWith(
            (ref) => LoggingCrashReporter(talker: ref.watch(talkerProvider)),
          ),
        ],
      );
      addTearDown(container.dispose);

      await container
          .read(crashReportingEnabledProvider.notifier)
          .setEnabled(true);

      final logger = container.read(loggerProvider);
      expect(logger.talker, same(container.read(talkerProvider)));
      expect(
        () => logger.e('debug crash path', error: StateError('boom')),
        returnsNormally,
      );
    },
  );
}
