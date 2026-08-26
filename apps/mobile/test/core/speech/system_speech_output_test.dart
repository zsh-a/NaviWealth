import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/ai/session/delivery_ledger.dart';
import 'package:naviwealth/core/ai/session/interaction_ids.dart';
import 'package:naviwealth/core/speech/speech_output.dart';
import 'package:naviwealth/core/speech/system_speech_output.dart';
import 'package:naviwealth/core/speech/system_tts_driver.dart';

void main() {
  test('starts and completes one session, then permits the next one', () async {
    final driver = _FakeSystemTtsDriver();
    final output = SystemSpeechOutput(driver: driver);

    final first = await output.speak(_request('第一段'));
    final firstEvents = <SpeechOutputEvent>[];
    final firstSubscription = first.events.listen(firstEvents.add);
    await _flush();

    driver.complete();
    await _flush();

    expect(firstEvents.whereType<SpeechOutputStarted>(), hasLength(1));
    expect(firstEvents.whereType<SpeechOutputSegmentDelivered>(), hasLength(1));
    expect(firstEvents.whereType<SpeechOutputStopped>(), hasLength(1));
    expect(
      firstEvents.whereType<SpeechOutputStopped>().single.reason,
      SpeechOutputStopReason.completed,
    );
    await firstSubscription.cancel();

    final second = await output.speak(_request('第二段'));
    await second.cancel();
    expect(driver.stopCalls, 1);
  });

  test(
    'native error emits a stable failure and releases the session',
    () async {
      final driver = _FakeSystemTtsDriver();
      final output = SystemSpeechOutput(driver: driver);
      final session = await output.speak(_request('会失败'));
      final events = <SpeechOutputEvent>[];
      final subscription = session.events.listen(events.add);
      await _flush();

      driver.fail('private native error detail');
      await _flush();

      final error = events.whereType<SpeechOutputError>().single;
      expect(error.code, SpeechOutputErrorCode.synthesisFailed);
      expect(events.whereType<SpeechOutputSegmentDelivered>(), isEmpty);
      expect(
        events.whereType<SpeechOutputStopped>().single.interrupted,
        isTrue,
      );

      await subscription.cancel();
      final next = await output.speak(_request('下一段'));
      await next.cancel();
    },
  );

  test(
    'speak Future failure is typed and does not poison the next session',
    () async {
      final driver = _FakeSystemTtsDriver()
        ..speakError = StateError('native speak failed');
      final output = SystemSpeechOutput(driver: driver);

      await expectLater(
        output.speak(_request('失败')),
        throwsA(
          isA<SpeechOutputException>().having(
            (error) => error.code,
            'code',
            SpeechOutputErrorCode.synthesisFailed,
          ),
        ),
      );

      driver.speakError = null;
      final next = await output.speak(_request('恢复'));
      await next.cancel();
    },
  );

  test('pause, resume, cancel and late callbacks are idempotent', () async {
    final driver = _FakeSystemTtsDriver();
    final output = SystemSpeechOutput(driver: driver);
    final session = await output.speak(_request('可暂停'));
    final events = <SpeechOutputEvent>[];
    final subscription = session.events.listen(events.add);
    await _flush();

    await session.pause();
    await session.pause();
    await session.resume();
    await session.resume();
    await session.cancel();
    await session.cancel();
    driver.complete();
    driver.fail('late error');
    await _flush();

    expect(events.whereType<SpeechOutputPaused>(), hasLength(1));
    expect(events.whereType<SpeechOutputResumed>(), hasLength(1));
    expect(events.whereType<SpeechOutputStopped>(), hasLength(1));
    expect(events.whereType<SpeechOutputError>(), isEmpty);
    expect(
      events.whereType<SpeechOutputStopped>().single.reason,
      SpeechOutputStopReason.interrupted,
    );
    await subscription.cancel();
  });

  test('reports an unavailable engine without leaking provider text', () async {
    final driver = _FakeSystemTtsDriver()
      ..availabilityError = StateError('private engine detail');
    final output = SystemSpeechOutput(driver: driver);

    final status = await output.status();
    expect(status.availability, SpeechOutputAvailability.unsupported);
    expect(status.errorCode, SpeechOutputErrorCode.engineUnavailable);
    expect(status.reason, 'System text-to-speech is unavailable');
    await expectLater(
      output.speak(_request('不可用')),
      throwsA(
        isA<SpeechOutputException>().having(
          (error) => error.code,
          'code',
          SpeechOutputErrorCode.engineUnavailable,
        ),
      ),
    );
  });

  test(
    'prepares the engine once and caches language setup across segments',
    () async {
      final driver = _FakeSystemTtsDriver();
      final output = SystemSpeechOutput(driver: driver);

      await output.prepare();
      await output.prepare();
      final first = await output.speak(_request('第一段。'));
      await first.cancel();
      final second = await output.speak(_request('第二段。'));
      await second.cancel();

      expect(driver.awaitSpeakCompletionCalls, 1);
      expect(driver.languages, <String>['zh-CN']);
    },
  );
}

Future<void> _flush() => Future<void>.delayed(Duration.zero);

SpeechOutputRequest _request(String text) => SpeechOutputRequest(
  stamp: const InteractionStamp(
    sessionId: SessionId('session-1'),
    turnId: TurnId('turn-1'),
    epoch: ResponseEpoch.initial(),
    sequence: 1,
  ),
  segment: OutputSegment(id: text, text: text),
);

final class _FakeSystemTtsDriver implements SystemTtsDriver {
  VoidCallback? startHandler;
  VoidCallback? completionHandler;
  VoidCallback? pauseHandler;
  VoidCallback? continueHandler;
  VoidCallback? cancelHandler;
  SystemTtsErrorHandler? errorHandler;
  Object? availabilityError;
  Object? speakError;
  Object? pauseError;
  Object? stopError;
  int stopCalls = 0;
  int awaitSpeakCompletionCalls = 0;
  final languages = <String>[];

  @override
  Future<void> awaitSpeakCompletion(bool awaitCompletion) async {
    awaitSpeakCompletionCalls++;
    final error = availabilityError;
    if (error != null) throw error;
  }

  @override
  Future<void> setLanguage(String language) async => languages.add(language);

  @override
  Future<void> speak(String text) async {
    final error = speakError;
    if (error != null) throw error;
  }

  @override
  Future<void> pause() async {
    final error = pauseError;
    if (error != null) throw error;
  }

  @override
  Future<void> stop() async {
    stopCalls++;
    final error = stopError;
    if (error != null) throw error;
  }

  @override
  void setStartHandler(VoidCallback callback) => startHandler = callback;

  @override
  void setCompletionHandler(VoidCallback callback) =>
      completionHandler = callback;

  @override
  void setPauseHandler(VoidCallback callback) => pauseHandler = callback;

  @override
  void setContinueHandler(VoidCallback callback) => continueHandler = callback;

  @override
  void setCancelHandler(VoidCallback callback) => cancelHandler = callback;

  @override
  void setErrorHandler(SystemTtsErrorHandler callback) =>
      errorHandler = callback;

  void complete() => completionHandler?.call();

  void fail(Object message) => errorHandler?.call(message);
}
