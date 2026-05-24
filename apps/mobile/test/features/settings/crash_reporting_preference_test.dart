import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/logging/crash_reporter.dart';
import 'package:naviwealth/core/logging/crash_reporting_preference.dart';
import 'package:naviwealth/core/logging/providers.dart';
import 'package:naviwealth/design_system/preferences/theme_preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _SpyReporter extends CrashReporter {
  final captured = <Object>[];

  @override
  void captureError(Object error, {StackTrace? stackTrace, String? hint}) {
    captured.add(error);
  }

  @override
  void captureMessage(
    String message, {
    BreadcrumbLevel level = BreadcrumbLevel.info,
  }) {}

  @override
  void recordBreadcrumb({
    required String message,
    BreadcrumbLevel level = BreadcrumbLevel.info,
    String? category,
  }) {}

  @override
  void identifyUser({String? userId}) {}
}

ProviderContainer _container(SharedPreferences prefs, CrashReporter delegate) {
  return ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      crashReporterDelegateProvider.overrideWithValue(delegate),
    ],
  );
}

void main() {
  group('crashReportingEnabledProvider', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('defaults to false (opt-in must be explicit)', () async {
      final prefs = await SharedPreferences.getInstance();
      final c = _container(prefs, _SpyReporter());
      addTearDown(c.dispose);
      expect(c.read(crashReportingEnabledProvider), isFalse);
    });

    test('persists across container disposal', () async {
      var prefs = await SharedPreferences.getInstance();
      final c = _container(prefs, _SpyReporter());
      await c.read(crashReportingEnabledProvider.notifier).setEnabled(true);
      expect(c.read(crashReportingEnabledProvider), isTrue);
      c.dispose();

      prefs = await SharedPreferences.getInstance();
      final c2 = _container(prefs, _SpyReporter());
      addTearDown(c2.dispose);
      expect(c2.read(crashReportingEnabledProvider), isTrue);
    });
  });

  group('crashReporterProvider opt-in wiring', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test(
      'reporter drops events while preference is disabled, forwards once enabled',
      () async {
        final prefs = await SharedPreferences.getInstance();
        final spy = _SpyReporter();
        final c = _container(prefs, spy);
        addTearDown(c.dispose);

        // Default = off. captureError must not reach the delegate.
        c.read(crashReporterProvider).captureError(StateError('first'));
        expect(spy.captured, isEmpty);

        // Flip the toggle on; provider re-emits so the next read sees the
        // enabled wrapper.
        await c.read(crashReportingEnabledProvider.notifier).setEnabled(true);
        c.read(crashReporterProvider).captureError(StateError('second'));
        expect(spy.captured, hasLength(1));
        expect(
          (spy.captured.single as StateError).message,
          'second',
          reason: 'only events after opt-in reach the delegate',
        );
      },
    );
  });
}
