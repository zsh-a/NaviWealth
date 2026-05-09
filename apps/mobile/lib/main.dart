import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import 'app/app.dart';
import 'app/bootstrap.dart';
import 'core/perf/refresh_rate.dart';

Future<void> main() async {
  await runGuarded(() async {
    final container = await bootstrap();
    // Match the GlassPerformanceMonitor budget to the device's actual
    // refresh rate. A fixed 120 fps budget on a 60 fps panel marks every
    // frame as over-budget and drives adaptiveQuality to permanently
    // downgrade — defeating the premium tier on hero surfaces.
    final fps = targetFps();
    GlassPerformanceMonitor.rasterBudget = Duration(
      microseconds: targetFrameBudgetUs(),
    );
    GlassPerformanceMonitor.sustainedFrameThreshold = fps;
    await LiquidGlassWidgets.initialize();
    runApp(
      UncontrolledProviderScope(
        container: container,
        child: const NaviWealthApp(),
      ),
    );
  });
}
