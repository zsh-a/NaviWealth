import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/config/app_config.dart';
import 'package:naviwealth/core/logging/app_logger.dart';
import 'package:naviwealth/core/speech/managed_speech_recognizer.dart';
import 'package:naviwealth/core/speech/speech_diagnostics.dart';
import 'package:naviwealth/core/speech/speech_recognizer.dart';

void main() {
  test(
    'rejects concurrent recognizer instances and releases after cancel',
    () async {
      final firstDelegate = _FakeRecognizer();
      final secondDelegate = _FakeRecognizer();
      final diagnostics = SpeechDiagnosticsRecorder(
        logger: AppLogger(environment: AppEnvironment.dev),
      );
      final firstRecognizer = ManagedSpeechRecognizer(
        delegate: firstDelegate,
        diagnostics: diagnostics,
      );
      final secondRecognizer = ManagedSpeechRecognizer(
        delegate: secondDelegate,
        diagnostics: diagnostics,
      );

      final first = await firstRecognizer.start();
      await expectLater(
        secondRecognizer.start(),
        throwsA(
          isA<SpeechRecognitionException>().having(
            (error) => error.code,
            'code',
            SpeechRecognitionErrorCode.sessionBusy,
          ),
        ),
      );

      await first.cancel();
      final second = await secondRecognizer.start();
      await second.cancel();

      expect(firstDelegate.started, 1);
      expect(secondDelegate.started, 1);
      expect(diagnostics.snapshot.started, 2);
      expect(diagnostics.snapshot.cancelled, 2);
      expect(diagnostics.snapshot.failed, 1);
      expect(
        diagnostics.snapshot.lastErrorCode,
        SpeechRecognitionErrorCode.sessionBusy,
      );
    },
  );

  test(
    'records unavailable status with a stable code and no reason text',
    () async {
      final logger = AppLogger(environment: AppEnvironment.dev);
      final diagnostics = SpeechDiagnosticsRecorder(logger: logger);
      final recognizer = ManagedSpeechRecognizer(
        delegate: _FakeRecognizer(
          statusValue: const SpeechRecognizerStatus(
            SpeechRecognizerAvailability.modelNotInstalled,
            reason: 'path contains private provider detail',
          ),
        ),
        diagnostics: diagnostics,
      );

      final status = await recognizer.status();

      expect(status.isReady, isFalse);
      expect(status.errorCode, SpeechRecognitionErrorCode.modelNotInstalled);
      expect(diagnostics.snapshot.statusUnavailable, 1);
      expect(
        diagnostics.snapshot.lastStatusAvailability,
        SpeechRecognizerAvailability.modelNotInstalled,
      );
      expect(
        diagnostics.snapshot.lastStatusErrorCode,
        SpeechRecognitionErrorCode.modelNotInstalled,
      );
      final history = logger.talker.history
          .map((entry) => entry.message?.toString() ?? '')
          .join('\n');
      expect(history, isNot(contains('path contains private provider detail')));
    },
  );

  test(
    'start failure records its code and releases process ownership',
    () async {
      final failingDelegate = _FakeRecognizer(
        startError: const SpeechRecognitionException(
          SpeechRecognitionErrorCode.permissionDenied,
          'Microphone permission denied',
        ),
      );
      final diagnostics = SpeechDiagnosticsRecorder(
        logger: AppLogger(environment: AppEnvironment.dev),
      );
      final failingRecognizer = ManagedSpeechRecognizer(
        delegate: failingDelegate,
        diagnostics: diagnostics,
      );

      await expectLater(
        failingRecognizer.start(),
        throwsA(
          isA<SpeechRecognitionException>().having(
            (error) => error.code,
            'code',
            SpeechRecognitionErrorCode.permissionDenied,
          ),
        ),
      );

      expect(diagnostics.snapshot.failed, 1);
      expect(
        diagnostics.snapshot.lastErrorCode,
        SpeechRecognitionErrorCode.permissionDenied,
      );

      final succeedingDelegate = _FakeRecognizer();
      final succeedingRecognizer = ManagedSpeechRecognizer(
        delegate: succeedingDelegate,
        diagnostics: diagnostics,
      );
      final session = await succeedingRecognizer.start();
      await session.cancel();

      expect(succeedingDelegate.started, 1);
      expect(diagnostics.snapshot.started, 1);
      expect(diagnostics.snapshot.cancelled, 1);
    },
  );

  test('automatically finalizes at the maximum duration', () async {
    final delegate = _FakeRecognizer();
    final diagnostics = SpeechDiagnosticsRecorder(
      logger: AppLogger(environment: AppEnvironment.dev),
    );
    final recognizer = ManagedSpeechRecognizer(
      delegate: delegate,
      diagnostics: diagnostics,
      maxSessionDuration: const Duration(milliseconds: 10),
    );

    final session = await recognizer.start();
    final events = <SpeechRecognitionEvent>[];
    final done = Completer<void>();
    session.events.listen(events.add, onDone: done.complete);

    await done.future.timeout(const Duration(seconds: 1));

    expect(delegate.sessions.single.stopped, isTrue);
    expect(events.last.isFinal, isTrue);
    expect(diagnostics.snapshot.maxDurationStops, 1);
    expect(diagnostics.snapshot.completed, 1);

    final next = await recognizer.start();
    await next.cancel();
  });

  test('stream errors close the session and release the microphone', () async {
    final delegate = _FakeRecognizer();
    final diagnostics = SpeechDiagnosticsRecorder(
      logger: AppLogger(environment: AppEnvironment.dev),
    );
    final recognizer = ManagedSpeechRecognizer(
      delegate: delegate,
      diagnostics: diagnostics,
    );

    final session = await recognizer.start();
    final errorSeen = Completer<void>();
    session.events.listen((_) {}, onError: (Object _) => errorSeen.complete());
    delegate.sessions.single.addError(StateError('microphone interrupted'));

    await errorSeen.future.timeout(const Duration(seconds: 1));
    await Future<void>.delayed(Duration.zero);
    expect(delegate.sessions.single.cancelled, isTrue);
    expect(diagnostics.snapshot.failed, 1);

    final next = await recognizer.start();
    await next.cancel();
  });

  test(
    'native cancelled terminal event is not misclassified as completion',
    () async {
      final delegate = _FakeRecognizer();
      final diagnostics = SpeechDiagnosticsRecorder(
        logger: AppLogger(environment: AppEnvironment.dev),
      );
      final recognizer = ManagedSpeechRecognizer(
        delegate: delegate,
        diagnostics: diagnostics,
      );

      final session = await recognizer.start();
      session.events.listen((_) {});
      delegate.sessions.single.addSessionEnded(cancelled: true);
      await Future<void>.delayed(Duration.zero);

      expect(diagnostics.snapshot.cancelled, 1);
      expect(diagnostics.snapshot.completed, 0);

      final next = await recognizer.start();
      await next.cancel();
    },
  );

  test('diagnostics retain timing but never transcript text', () async {
    final logger = AppLogger(environment: AppEnvironment.dev);
    final diagnostics = SpeechDiagnosticsRecorder(logger: logger);
    final delegate = _FakeRecognizer();
    final recognizer = ManagedSpeechRecognizer(
      delegate: delegate,
      diagnostics: diagnostics,
    );

    final session = await recognizer.start();
    final events = <SpeechRecognitionEvent>[];
    session.events.listen(events.add);
    delegate.sessions.single.addCaptureStarted(
      startupDuration: const Duration(milliseconds: 480),
    );
    delegate.sessions.single.add('银行卡余额是一万元');
    await Future<void>.delayed(Duration.zero);
    await session.stop();

    expect(events, isNotEmpty);
    expect(
      diagnostics.snapshot.lastCaptureStartupLatency,
      const Duration(milliseconds: 480),
    );
    expect(diagnostics.snapshot.lastFirstPartialLatency, isNotNull);
    final history = logger.talker.history
        .map((entry) => entry.message ?? '')
        .join('\n');
    expect(history, contains('core.speech.session.capture_started'));
    expect(history, contains('core.speech.session.first_partial'));
    expect(history, isNot(contains('银行卡')));
    expect(history, isNot(contains('一万元')));
  });

  test('repeated sessions do not retain ownership or event history', () async {
    final delegate = _FakeRecognizer();
    final diagnostics = SpeechDiagnosticsRecorder(
      logger: AppLogger(environment: AppEnvironment.prod),
    );
    final recognizer = ManagedSpeechRecognizer(
      delegate: delegate,
      diagnostics: diagnostics,
    );

    for (var i = 0; i < 25; i++) {
      final session = await recognizer.start();
      delegate.sessions.last.add('第$i次');
      await session.cancel();
    }

    expect(delegate.started, 25);
    expect(diagnostics.snapshot.started, 25);
    expect(diagnostics.snapshot.cancelled, 25);
  });
}

class _FakeRecognizer implements SpeechRecognizer {
  _FakeRecognizer({
    this.startError,
    this.statusValue = const SpeechRecognizerStatus(
      SpeechRecognizerAvailability.ready,
    ),
  });

  final sessions = <_FakeSession>[];
  Object? startError;
  final SpeechRecognizerStatus statusValue;
  var started = 0;

  @override
  Future<SpeechRecognizerStatus> status() async => statusValue;

  @override
  Future<SpeechRecognitionSession> start() async {
    final error = startError;
    startError = null;
    if (error != null) throw error;
    started++;
    final session = _FakeSession();
    sessions.add(session);
    return session;
  }
}

class _FakeSession implements SpeechRecognitionSession {
  final _events = StreamController<SpeechRecognitionEvent>.broadcast();
  bool stopped = false;
  bool cancelled = false;

  void add(String text) {
    if (_events.isClosed) return;
    _events.add(SpeechRecognitionEvent(text: text, isFinal: false));
  }

  void addCaptureStarted({required Duration startupDuration}) {
    if (_events.isClosed) return;
    _events.add(
      SpeechRecognitionEvent(
        text: '',
        isFinal: false,
        captureStarted: true,
        captureStartupDuration: startupDuration,
      ),
    );
  }

  void addSessionEnded({required bool cancelled}) {
    if (_events.isClosed) return;
    _events
      ..add(
        SpeechRecognitionEvent(
          text: '',
          isFinal: false,
          sessionEnded: true,
          cancelled: cancelled,
        ),
      )
      ..close();
  }

  void addError(Object error) {
    if (_events.isClosed) return;
    _events.addError(error, StackTrace.current);
  }

  @override
  Stream<SpeechRecognitionEvent> get events => _events.stream;

  @override
  Future<void> cancel() async {
    cancelled = true;
    if (!_events.isClosed) await _events.close();
  }

  @override
  Future<void> stop() async {
    stopped = true;
    if (_events.isClosed) return;
    _events.add(const SpeechRecognitionEvent(text: '最终文本', isFinal: true));
    await _events.close();
  }
}
