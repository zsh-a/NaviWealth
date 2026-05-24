import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/logging/crash_reporter.dart';
import 'package:naviwealth/core/logging/crash_reporting_preference.dart';

class _SpyReporter extends CrashReporter {
  final captured = <String>[];
  final breadcrumbs = <String>[];
  final messages = <String>[];
  String? identifiedUser;
  bool identifyCalled = false;

  @override
  void captureError(Object error, {StackTrace? stackTrace, String? hint}) {
    captured.add('${error.runtimeType}:${error.toString()}');
  }

  @override
  void captureMessage(
    String message, {
    BreadcrumbLevel level = BreadcrumbLevel.info,
  }) {
    messages.add(message);
  }

  @override
  void recordBreadcrumb({
    required String message,
    BreadcrumbLevel level = BreadcrumbLevel.info,
    String? category,
  }) {
    breadcrumbs.add(message);
  }

  @override
  void identifyUser({String? userId}) {
    identifyCalled = true;
    identifiedUser = userId;
  }
}

void main() {
  group('OptInCrashReporter', () {
    late _SpyReporter spy;
    late OptInCrashReporter wrapper;

    setUp(() {
      spy = _SpyReporter();
      wrapper = OptInCrashReporter(delegate: spy, enabled: false);
    });

    test('drops every event when disabled', () {
      wrapper.captureError(StateError('boom'));
      wrapper.captureMessage('hello');
      wrapper.recordBreadcrumb(message: 'crumb');
      wrapper.identifyUser(userId: 'u-1');

      expect(spy.captured, isEmpty);
      expect(spy.messages, isEmpty);
      expect(spy.breadcrumbs, isEmpty);
      expect(spy.identifyCalled, isFalse);
    });

    test('forwards every event when enabled', () {
      wrapper.enabled = true;
      wrapper.captureError(StateError('boom'));
      wrapper.captureMessage('hello');
      wrapper.recordBreadcrumb(message: 'crumb');
      wrapper.identifyUser(userId: 'u-1');

      expect(spy.captured, hasLength(1));
      expect(spy.messages, ['hello']);
      expect(spy.breadcrumbs, ['crumb']);
      expect(spy.identifyCalled, isTrue);
      expect(spy.identifiedUser, 'u-1');
    });

    test('runtime toggle takes effect on the next call', () {
      wrapper.enabled = true;
      wrapper.captureMessage('first');
      wrapper.enabled = false;
      wrapper.captureMessage('second');
      wrapper.enabled = true;
      wrapper.captureMessage('third');

      expect(spy.messages, ['first', 'third']);
    });

    test('default state is disabled — opt-in must be explicit', () {
      expect(wrapper.enabled, isFalse);
    });
  });
}
