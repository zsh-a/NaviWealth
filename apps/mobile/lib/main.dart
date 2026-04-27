import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'app/bootstrap.dart';

Future<void> main() async {
  await runGuarded(() async {
    final container = await bootstrap();
    runApp(
      UncontrolledProviderScope(
        container: container,
        child: const NaviWealthApp(),
      ),
    );
  });
}
