import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'app/bootstrap.dart';
import 'design_system/design_system.dart';

Future<void> main() async {
  final boot = await bootstrap();
  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(boot.sharedPreferences),
      ],
      child: const NaviWealthApp(),
    ),
  );
}
