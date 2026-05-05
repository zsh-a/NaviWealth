import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import 'app/app.dart';
import 'app/bootstrap.dart';

Future<void> main() async {
  await runGuarded(() async {
    final container = await bootstrap();
    GlassPerformanceMonitor.rasterBudget = const Duration(microseconds: 8333); // 120 fps
    GlassPerformanceMonitor.sustainedFrameThreshold = 120; // 120 fps
    await LiquidGlassWidgets.initialize();
    runApp(
      UncontrolledProviderScope(
        container: container,
        child: const NaviWealthApp(),
      ),
    );
  });
}
