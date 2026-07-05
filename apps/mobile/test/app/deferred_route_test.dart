import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/core/shell/deferred_route.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: child,
  );
}

void main() {
  testWidgets(
    'shows placeholder while loadLibrary is in flight, then the page',
    (tester) async {
      final completer = Completer<void>();
      await tester.pumpWidget(
        _wrap(
          DeferredRoute(
            load: () => completer.future,
            builder: (_) => const Text('loaded'),
          ),
        ),
      );

      expect(find.byType(FCircularProgress), findsOneWidget);
      expect(find.text('loaded'), findsNothing);

      completer.complete();
      await tester.pumpAndSettle();

      expect(find.byType(FCircularProgress), findsNothing);
      expect(find.text('loaded'), findsOneWidget);
    },
  );

  testWidgets('surfaces an error scaffold with a working retry', (
    tester,
  ) async {
    var attempts = 0;
    Future<void> load() {
      attempts += 1;
      if (attempts == 1) {
        return Future<void>.error(StateError('boom'));
      }
      return Future<void>.value();
    }

    await tester.pumpWidget(
      _wrap(DeferredRoute(load: load, builder: (_) => const Text('loaded'))),
    );
    await tester.pumpAndSettle();

    expect(find.text('Bad state: boom'), findsOneWidget);
    expect(find.byIcon(FLucideIcons.refreshCw), findsOneWidget);

    await tester.tap(find.byIcon(FLucideIcons.refreshCw));
    await tester.pumpAndSettle();

    expect(find.text('loaded'), findsOneWidget);
    expect(attempts, 2);
  });
}
