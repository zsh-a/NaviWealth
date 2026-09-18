import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/app/agents/scheduled_run_lifecycle.dart';

void main() {
  for (final platform in TargetPlatform.values) {
    test('$platform keeps running across focus and visibility changes', () {
      final token = CancelToken();
      final lifecycle = ScheduledRunLifecycle(token, platform: platform);
      for (final state in [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]) {
        lifecycle.didChangeAppLifecycleState(state);
        expect(token.isCancelled, isFalse);
      }
      lifecycle.dispose();
      expect(token.isCancelled, isFalse);
    });

    test('$platform applies platform policy on pause', () {
      final token = CancelToken();
      final lifecycle = ScheduledRunLifecycle(token, platform: platform);
      lifecycle.didChangeAppLifecycleState(AppLifecycleState.paused);
      final mobile =
          platform == TargetPlatform.android || platform == TargetPlatform.iOS;
      expect(token.isCancelled, mobile);
      if (mobile) {
        expect(token.cancelError?.error, 'scheduled_task_backgrounded');
        lifecycle.didChangeAppLifecycleState(AppLifecycleState.resumed);
        expect(token.isCancelled, isTrue); // Never replay a cancelled turn.
      }
      lifecycle.dispose();
    });
  }

  test('detach interrupts and never overwrites an earlier cancellation', () {
    final token = CancelToken();
    final lifecycle = ScheduledRunLifecycle(
      token,
      platform: TargetPlatform.macOS,
    );
    lifecycle.didChangeAppLifecycleState(AppLifecycleState.detached);
    expect(token.cancelError?.error, 'scheduled_task_interrupted');
    final stopped = CancelToken()..cancel('scheduled_task_user_cancelled');
    ScheduledRunLifecycle(
      stopped,
      platform: TargetPlatform.android,
    ).didChangeAppLifecycleState(AppLifecycleState.paused);
    expect(stopped.cancelError?.error, 'scheduled_task_user_cancelled');
  });

  testWidgets('attachment checks current pause and disposal removes observer', (
    tester,
  ) async {
    final binding = tester.binding;
    binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    final paused = CancelToken();
    final lifecycle = ScheduledRunLifecycle(
      paused,
      platform: TargetPlatform.iOS,
    )..attach(binding);
    expect(paused.cancelError?.error, 'scheduled_task_backgrounded');
    lifecycle.dispose();
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final token = CancelToken();
    ScheduledRunLifecycle(token, platform: TargetPlatform.android)
      ..attach(binding)
      ..dispose();
    binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    expect(token.isCancelled, isFalse);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  });
}
