import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';

/// Run-scoped host policy, independent of routes and window focus.
/// Desktop processes may continue while hidden. Mobile hosts currently have
/// no background execution lease, so a real pause must fail closed.
class ScheduledRunLifecycle with WidgetsBindingObserver {
  ScheduledRunLifecycle(this.cancel, {required this.platform});

  final CancelToken cancel;
  final TargetPlatform platform;
  WidgetsBinding? _binding;

  void attach(WidgetsBinding binding) {
    _binding = binding;
    binding.addObserver(this);
    // A run can finish preparing after the app has already paused. Detached
    // is also Flutter's initial state; only a subsequent detach is terminal.
    if (binding.lifecycleState == AppLifecycleState.paused) {
      didChangeAppLifecycleState(AppLifecycleState.paused);
    }
  }

  void dispose() {
    _binding?.removeObserver(this);
    _binding = null;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.detached) {
      cancel.cancel('scheduled_task_interrupted');
    } else if (state == AppLifecycleState.paused &&
        (platform == TargetPlatform.android ||
            platform == TargetPlatform.iOS)) {
      cancel.cancel('scheduled_task_backgrounded');
    }
  }
}
