import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Foreground time for date-sensitive views. Resumes immediately after sleep;
/// minute ticks also bring newly due records into already open lists.
final currentTimeProvider = NotifierProvider.autoDispose<CurrentTime, DateTime>(
  CurrentTime.new,
);

class CurrentTime extends Notifier<DateTime> {
  CurrentTime({DateTime Function()? now}) : _now = now ?? DateTime.now;

  final DateTime Function() _now;
  @override
  DateTime build() {
    final timer = Timer.periodic(const Duration(minutes: 1), (_) => refresh());
    final listener = AppLifecycleListener(onResume: refresh);
    ref.onDispose(() {
      timer.cancel();
      listener.dispose();
    });
    return _now();
  }

  void refresh() => state = _now();
}

final currentLocalDayProvider = Provider.autoDispose<DateTime>((ref) {
  return ref.watch(
    currentTimeProvider.select((time) {
      final local = time.toLocal();
      return DateTime(local.year, local.month, local.day);
    }),
  );
});
