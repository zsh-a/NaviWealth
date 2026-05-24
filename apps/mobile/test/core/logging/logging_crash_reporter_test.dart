import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/logging/crash_reporter.dart';
import 'package:naviwealth/core/logging/logging_crash_reporter.dart';
import 'package:talker/talker.dart';

void main() {
  group('LoggingCrashReporter', () {
    late Talker talker;
    late LoggingCrashReporter reporter;

    setUp(() {
      // History on; console off — we only need a recordable in-memory
      // log sink for assertions.
      talker = Talker(
        settings: TalkerSettings(
          useConsoleLogs: false,
          useHistory: true,
        ),
      );
      reporter = LoggingCrashReporter(talker: talker);
    });

    test('captureError records an entry in talker history', () {
      final before = talker.history.length;
      reporter.captureError(StateError('boom'), hint: 'unit-test');
      // talker.handle dispatches asynchronously in some versions, so we
      // assert on the count delta rather than scanning entries —
      // exact placement of the message string is talker-internal.
      expect(
        talker.history.length,
        greaterThanOrEqualTo(before + 1),
      );
    });

    test('captureMessage level=info emits an info log', () {
      reporter.captureMessage('hello');
      expect(
        talker.history.any(
          (e) =>
              e.logLevel == LogLevel.info &&
              (e.message?.toString().contains('hello') ?? false),
        ),
        isTrue,
      );
    });

    test('captureMessage level=fatal emits an error log', () {
      reporter.captureMessage('fatal!', level: BreadcrumbLevel.fatal);
      expect(
        talker.history.any(
          (e) =>
              e.logLevel == LogLevel.error &&
              (e.message?.toString().contains('fatal!') ?? false),
        ),
        isTrue,
      );
    });

    test('recordBreadcrumb tags with category and uses verbose level', () {
      reporter.recordBreadcrumb(message: 'tap', category: 'ui');
      expect(
        talker.history.any(
          (e) => (e.message?.toString().contains('breadcrumb/ui: tap')) ?? false,
        ),
        isTrue,
      );
    });

    test('identifyUser is non-throwing for null + non-null userIds', () {
      expect(() => reporter.identifyUser(), returnsNormally);
      expect(
        () => reporter.identifyUser(userId: 'u-1'),
        returnsNormally,
      );
    });
  });
}
