import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/config/app_config.dart';
import 'package:naviwealth/core/logging/app_logger.dart';
import 'package:naviwealth/core/logging/crash_reporter.dart';
import 'package:naviwealth/core/logging/providers.dart';
import 'package:naviwealth/features/shared/forms/optimistic_form_submit.dart';

void main() {
  group('runOptimisticWrite', () {
    late AppLogger logger;
    late GlobalKey<ScaffoldMessengerState> messengerKey;

    setUp(() {
      logger = AppLogger(
        environment: AppEnvironment.dev,
        crashReporter: const NoopCrashReporter(),
      );
      messengerKey = GlobalKey<ScaffoldMessengerState>();
    });

    Future<void> pumpHost(WidgetTester tester) {
      return tester.pumpWidget(
        MaterialApp(
          scaffoldMessengerKey: messengerKey,
          home: const Scaffold(body: SizedBox()),
        ),
      );
    }

    testWidgets(
      'runs the write and surfaces no snackbar on success',
      (tester) async {
        await pumpHost(tester);
        var calls = 0;
        await runOptimisticWrite(
          write: () async {
            calls += 1;
          },
          failureMessage: (_) => 'unused',
          logger: logger,
          messengerKey: messengerKey,
          retryLabel: 'Retry',
        );
        expect(calls, 1);
        await tester.pump();
        expect(find.byType(SnackBar), findsNothing);
      },
    );

    testWidgets('shows a snackbar with the failure message on error', (
      tester,
    ) async {
      await pumpHost(tester);
      await runOptimisticWrite(
        write: () async => throw StateError('boom'),
        failureMessage: (err) => 'oops: $err',
        logger: logger,
        messengerKey: messengerKey,
      );
      await tester.pump();
      expect(find.text('oops: Bad state: boom'), findsOneWidget);
    });

    testWidgets('retry action re-invokes write and dismisses on success', (
      tester,
    ) async {
      await pumpHost(tester);
      final attempts = <int>[];
      var nextResult = Completer<void>()..completeError(StateError('first'));
      Future<void> write() {
        attempts.add(attempts.length + 1);
        return nextResult.future;
      }

      await runOptimisticWrite(
        write: write,
        failureMessage: (_) => 'failed',
        logger: logger,
        messengerKey: messengerKey,
        retryLabel: 'Retry',
      );
      // Pump enough frames for the SnackBar animation to come in.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 750));
      expect(find.text('failed'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      expect(attempts, [1]);

      // Arm the next attempt to succeed before we tap retry.
      nextResult = Completer<void>()..complete();
      await tester.tap(find.byType(SnackBarAction));
      // Drain microtasks so the retry's awaited write resolves.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 750));
      expect(attempts, [1, 2]);
    });

    testWidgets('omits the retry action when retryLabel is null', (
      tester,
    ) async {
      await pumpHost(tester);
      await runOptimisticWrite(
        write: () async => throw StateError('boom'),
        failureMessage: (_) => 'no retry here',
        logger: logger,
        messengerKey: messengerKey,
      );
      await tester.pump();
      expect(find.text('no retry here'), findsOneWidget);
      expect(find.byType(SnackBarAction), findsNothing);
    });
  });

  group('OptimisticFormSubmit mixin', () {
    testWidgets(
      'pops the route synchronously and surfaces the write failure '
      'on the global messenger',
      (tester) async {
        final messengerKey = GlobalKey<ScaffoldMessengerState>();
        final logger = AppLogger(
          environment: AppEnvironment.dev,
          crashReporter: const NoopCrashReporter(),
        );
        final completer = Completer<void>();
        var didPop = false;

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              scaffoldMessengerKeyProvider.overrideWithValue(messengerKey),
              loggerProvider.overrideWithValue(logger),
            ],
            child: MaterialApp(
              scaffoldMessengerKey: messengerKey,
              home: Scaffold(
                body: Builder(
                  builder: (ctx) => Center(
                    child: TextButton(
                      onPressed: () {
                        Navigator.of(ctx).push(
                          MaterialPageRoute<void>(
                            builder: (_) => _ProbeForm(
                              onPop: () {
                                didPop = true;
                                Navigator.of(ctx).pop();
                              },
                              write: () => completer.future,
                            ),
                          ),
                        );
                      },
                      child: const Text('open'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
        expect(find.byType(_ProbeForm), findsOneWidget);

        await tester.tap(find.byKey(const Key('submit')));
        // Pump frames so the Navigator processes the pop.
        await tester.pumpAndSettle();
        expect(didPop, isTrue);
        // Form is gone, but the write is still in-flight — no snackbar yet.
        expect(find.byType(SnackBar), findsNothing);

        // Resolve the write with an error; the global messenger surfaces it.
        completer.completeError(StateError('write blew up'));
        await tester.pumpAndSettle();
        expect(find.textContaining('write blew up'), findsOneWidget);
      },
    );
  });
}

class _ProbeForm extends ConsumerStatefulWidget {
  const _ProbeForm({required this.onPop, required this.write});

  final VoidCallback onPop;
  final Future<void> Function() write;

  @override
  ConsumerState<_ProbeForm> createState() => _ProbeFormState();
}

class _ProbeFormState extends ConsumerState<_ProbeForm>
    with OptimisticFormSubmit<_ProbeForm> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('probe')),
      body: Center(
        child: ElevatedButton(
          key: const Key('submit'),
          onPressed: () {
            // Fire and forget — the mixin pops synchronously.
            unawaited(
              submitOptimistic(
                pop: widget.onPop,
                write: widget.write,
                failureMessage: (err) => 'probe failed: $err',
                retryLabel: 'Retry',
                tag: 'probe',
              ),
            );
          },
          child: const Text('save'),
        ),
      ),
    );
  }
}
