/// Riverpod wiring for [BackgroundScheduler]. Conditional impl —
/// native uses workmanager, web/desktop is a no-op.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'background_scheduler.dart';
import 'background_scheduler_factory.dart';

final backgroundSchedulerProvider = Provider<BackgroundScheduler>(
  (ref) => createBackgroundScheduler(),
);
