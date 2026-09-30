import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/core/auth/auth_session.dart';
import 'package:naviwealth/core/auth/providers.dart';
import 'package:naviwealth/core/forms/form_undo.dart';
import 'package:naviwealth/core/forms/form_undo_banner.dart';
import 'package:naviwealth/core/logging/providers.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

final _sessionProvider = NotifierProvider<_Session, AuthSession?>(_Session.new);

class _Session extends Notifier<AuthSession?> {
  @override
  AuthSession? build() => null;
  void login(String user) => state = AuthSession(
    accessToken: 'test',
    expiresAt: DateTime.utc(2030),
    userId: user,
    deviceId: 'device',
  );
}

FormUndoOffer _offer(String message, Future<void> Function() undo) =>
    FormUndoOffer(
      message: message,
      action: FormUndoAction(undo),
      actionLabel: 'Undo',
      successMessage: 'Undone',
      failureMessage: (_) => 'Undo failed',
      retryLabel: 'Retry',
    );

Future<ProviderContainer> _pump(WidgetTester tester) async {
  final container = ProviderContainer(
    overrides: [
      authSessionProvider.overrideWith((ref) => ref.watch(_sessionProvider)),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: FTheme(
          data: FTheme.neutral.light.desktop,
          child: const Scaffold(body: FormUndoBanner()),
        ),
      ),
    ),
  );
  return container;
}

void main() {
  testWidgets(
    'receipt survives transient feedback and expires after its undo window',
    (tester) async {
      final container = await _pump(tester);
      container
          .read(formUndoOfferProvider.notifier)
          .offer(_offer('Saved action', () async {}));
      await tester.pump();
      await tester.pump(const Duration(seconds: 6));
      expect(find.text('Saved action'), findsOneWidget);
      await tester.pump(const Duration(seconds: 55));
      expect(container.read(formUndoOfferProvider), isNull);
      expect(find.text('Saved action'), findsNothing);
    },
  );

  testWidgets(
    'failed undo remains available and the same receipt retries once',
    (tester) async {
      final container = await _pump(tester);
      var calls = 0;
      container
          .read(formUndoOfferProvider.notifier)
          .offer(
            _offer('Saved action', () async {
              if (++calls == 1) throw StateError('retry');
            }),
          );
      await tester.pump();
      final undoButton = find.descendant(
        of: find.byType(FormUndoBanner),
        matching: find.text('Undo'),
      );
      await tester.tap(undoButton);
      await tester.pumpAndSettle();
      expect(container.read(formUndoOfferProvider), isNotNull);
      expect(find.text('Undo failed'), findsOneWidget);
      await tester.tap(
        find.descendant(
          of: find.byType(FormUndoBanner),
          matching: find.text('Retry'),
        ),
      );
      await tester.pumpAndSettle();
      expect(calls, 2);
      expect(container.read(formUndoOfferProvider), isNull);
    },
  );

  testWidgets('finishing an older undo preserves a newer receipt', (
    tester,
  ) async {
    final container = await _pump(tester);
    final pending = Completer<void>();
    final offers = container.read(formUndoOfferProvider.notifier);
    final older = _offer('Older', () => pending.future);
    offers.offer(older);
    final operation = offers.run(
      tester.element(find.byType(FormUndoBanner)),
      older,
      container.read(loggerProvider),
    );
    final newer = _offer('Newer', () async {});
    offers.offer(newer);
    pending.complete();
    await operation;
    expect(container.read(formUndoOfferProvider), same(newer));
    offers.dismiss(newer);
    await tester.pumpAndSettle();
  });

  testWidgets('account changes clear callbacks from the previous session', (
    tester,
  ) async {
    final container = await _pump(tester);
    container.read(_sessionProvider.notifier).login('owner-a');
    await tester.pump();
    var calls = 0;
    final offer = _offer('Owner A', () async {
      calls++;
    });
    final offers = container.read(formUndoOfferProvider.notifier);
    offers.offer(offer);
    await tester.pump();
    container.read(_sessionProvider.notifier).login('owner-b');
    await tester.pump();
    expect(container.read(formUndoOfferProvider), isNull);
    await offers.run(
      tester.element(find.byType(FormUndoBanner)),
      offer,
      container.read(loggerProvider),
    );
    expect(calls, 0);
  });
}
