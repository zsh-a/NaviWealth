/// Conditional-import factory for [BackgroundScheduler].
library;

export 'background_scheduler_stub.dart'
    if (dart.library.io) 'background_scheduler_io.dart';
