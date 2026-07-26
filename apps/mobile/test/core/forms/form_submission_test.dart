import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/config/app_config.dart';
import 'package:naviwealth/core/forms/form_dirty_guard.dart';
import 'package:naviwealth/core/forms/form_submission.dart';
import 'package:naviwealth/core/logging/app_logger.dart';
import 'package:naviwealth/core/logging/crash_reporter.dart';
import 'package:naviwealth/core/logging/providers.dart';
import 'package:naviwealth/design_system/design_system.dart';

void main() {
  late AppLogger logger;

  setUp(() {
    logger = AppLogger(
      environment: AppEnvironment.dev,
      crashReporter: const NoopCrashReporter(),
    );
  });

  group('FormSubmission', () {
    testWidgets(
      'coalesces submits, blocks back, and leaves only after commit',
      (tester) async {
        final commit = Completer<String>();
        final events = <String>[];

        await _pumpProbe(
          tester,
          logger: logger,
          commit: () {
            events.add('commit-started');
            return commit.future;
          },
          onCommitted: (receipt) => events.add('receipt:$receipt'),
          onLeave: () => events.add('leave'),
        );

        final state = tester.state<_ProbeFormState>(find.byType(_ProbeForm));
        final first = state.submit();
        final second = state.submit();
        expect(identical(first, second), isTrue);
        expect(events, ['commit-started']);
        expect(state.busy, isTrue);
        expect(state.dirty.busy, isTrue);

        await tester.binding.handlePopRoute();
        await tester.pump();
        expect(find.byType(_ProbeForm), findsOneWidget);

        commit.complete('r-1');
        await tester.pump();
        await tester.pump();
        await first;
        await tester.pumpAndSettle();

        expect(events, ['commit-started', 'receipt:r-1', 'leave']);
        expect(find.byType(_ProbeForm), findsNothing);
        expect(find.text('Saved'), findsOneWidget);
        final logs = logger.talker.history
            .map((entry) => entry.message ?? '')
            .join('\n');
        expect(logs, contains('form.submit.stage.completed'));
        expect(logs, contains('form.submit.completed'));
        await tester.pump(const Duration(seconds: 4));
      },
    );

    testWidgets('failure keeps input and Save retries the same form', (
      tester,
    ) async {
      var attempts = 0;
      final events = <String>[];
      await _pumpProbe(
        tester,
        logger: logger,
        commit: () async {
          attempts += 1;
          if (attempts == 1) throw StateError('disk full');
          return 'r-2';
        },
        onCommitted: (_) {},
        onLeave: () => events.add('leave'),
      );

      await tester.tap(find.byKey(const Key('submit')));
      await tester.pump();

      final state = tester.state<_ProbeFormState>(find.byType(_ProbeForm));
      expect(find.byType(_ProbeForm), findsOneWidget);
      expect(find.text('draft input'), findsOneWidget);
      expect(find.text('Could not save: Bad state: disk full'), findsOneWidget);
      expect(state.busy, isFalse);
      expect(state.dirty.busy, isFalse);
      expect(state.dirty.isDirty, isTrue);
      expect(
        state.submissionFailureMessage,
        'Could not save: Bad state: disk full',
      );
      expect(events, isEmpty);

      await tester.tap(find.byKey(const Key('submit')));
      await tester.pump();
      await tester.pump();
      await tester.pumpAndSettle();
      expect(attempts, 2);
      expect(events, ['leave']);
      expect(find.byType(_ProbeForm), findsNothing);
      await tester.pump(const Duration(seconds: 7));
    });

    testWidgets('typed receipt builds one Undo action after commit and leave', (
      tester,
    ) async {
      final events = <String>[];
      var undoCalls = 0;
      await _pumpProbe(
        tester,
        logger: logger,
        commit: () async {
          events.add('commit');
          return 'receipt-1';
        },
        onCommitted: (receipt) => events.add('committed:$receipt'),
        onLeave: () => events.add('leave'),
        undo: FormUndoPresentation<String>(
          buildAction: (receipt) {
            events.add('build:$receipt');
            return FormUndoAction(() async {
              undoCalls += 1;
              events.add('undo');
            });
          },
          actionLabel: 'Undo',
          successMessage: 'Change undone',
          failureMessage: (_) => 'Could not undo',
          retryLabel: 'Retry',
        ),
      );

      await tester.tap(find.byKey(const Key('submit')));
      await tester.pump();
      await tester.pump();
      await tester.pumpAndSettle();

      expect(events, [
        'commit',
        'committed:receipt-1',
        'build:receipt-1',
        'leave',
      ]);
      expect(find.text('Undo'), findsOneWidget);

      await tester.tap(find.text('Undo'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(events.last, 'undo');
      expect(undoCalls, 1);
      expect(find.text('Change undone'), findsOneWidget);
      await tester.pump(const Duration(seconds: 7));
    });
  });

  group('FormUndoAction', () {
    test('shares one operation and becomes a permanent no-op', () async {
      final completer = Completer<void>();
      var calls = 0;
      final action = FormUndoAction(() {
        calls += 1;
        return completer.future;
      });

      final first = action();
      final second = action();
      expect(identical(first, second), isTrue);
      expect(calls, 1);

      completer.complete();
      expect(await first, isTrue);
      expect(await second, isTrue);
      expect(action.completed, isTrue);
      expect(await action(), isFalse);
      expect(calls, 1);
    });

    test('clears a failure so the same callback can be retried', () async {
      var calls = 0;
      final action = FormUndoAction(() async {
        calls += 1;
        if (calls == 1) throw StateError('first failed');
      });

      await expectLater(action(), throwsStateError);
      expect(action.completed, isFalse);
      expect(await action(), isTrue);
      expect(action.completed, isTrue);
      expect(calls, 2);
    });

    testWidgets('feedback helper localizes failure and retry success', (
      tester,
    ) async {
      var calls = 0;
      final action = FormUndoAction(() async {
        calls += 1;
        if (calls == 1) throw StateError('undo failed');
      });
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => AppMessenger.init(child: child!),
          home: const Scaffold(body: SizedBox(key: Key('anchor'))),
        ),
      );
      final context = tester.element(find.byKey(const Key('anchor')));

      await runFormUndoWithFeedback(
        context: context,
        action: action,
        logger: logger,
        successMessage: 'Change undone',
        failureMessage: (_) => 'Could not undo',
        retryLabel: 'Retry',
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Could not undo'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);

      await tester.tap(find.text('Retry'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Change undone'), findsOneWidget);
      expect(calls, 2);
      final logs = logger.talker.history
          .map((entry) => entry.message ?? '')
          .join('\n');
      expect(logs, contains('form.undo.failed'));
      expect(logs, contains('form.undo.completed'));
      await tester.pump(const Duration(seconds: 7));
    });
  });
}

Future<void> _pumpProbe(
  WidgetTester tester, {
  required AppLogger logger,
  required Future<String> Function() commit,
  required ValueChanged<String> onCommitted,
  required VoidCallback onLeave,
  FormUndoPresentation<String>? undo,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [loggerProvider.overrideWithValue(logger)],
      child: MaterialApp(
        builder: (context, child) => AppMessenger.init(child: child!),
        home: Builder(
          builder: (homeContext) => Scaffold(
            body: TextButton(
              onPressed: () {
                Navigator.of(homeContext).push(
                  MaterialPageRoute<void>(
                    builder: (_) => _ProbeForm(
                      commit: commit,
                      onCommitted: onCommitted,
                      onLeave: onLeave,
                      undo: undo,
                    ),
                  ),
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

class _ProbeForm extends ConsumerStatefulWidget {
  const _ProbeForm({
    required this.commit,
    required this.onCommitted,
    required this.onLeave,
    this.undo,
  });

  final Future<String> Function() commit;
  final ValueChanged<String> onCommitted;
  final VoidCallback onLeave;
  final FormUndoPresentation<String>? undo;

  @override
  ConsumerState<_ProbeForm> createState() => _ProbeFormState();
}

class _ProbeFormState extends ConsumerState<_ProbeForm>
    with FormSubmission<_ProbeForm>, FormDirtyGuard<_ProbeForm> {
  final controller = TextEditingController(text: 'draft input');
  bool busy = false;

  @override
  String get leaveFallback => '/';

  @override
  void initState() {
    super.initState();
    dirty.bindTextControllers([controller]);
    dirty.markDirty();
  }

  Future<void> submit() {
    return submitForm<String>(
      dirty: dirty,
      onBusyChanged: (value) {
        if (mounted && busy != value) setState(() => busy = value);
      },
      commit: widget.commit,
      onCommitted: widget.onCommitted,
      leave: () {
        widget.onLeave();
        Navigator.of(context).pop();
      },
      failureMessage: (error) => 'Could not save: $error',
      successMessage: 'Saved',
      undo: widget.undo,
      tag: 'probe',
    );
  }

  @override
  Widget build(BuildContext context) {
    return guardedScope(
      child: Scaffold(
        body: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextField(controller: controller),
            ElevatedButton(
              key: const Key('submit'),
              onPressed: busy ? null : submit,
              child: Text(busy ? 'Saving' : 'Save'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }
}
