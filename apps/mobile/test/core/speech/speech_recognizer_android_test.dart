import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/speech/speech_recognizer.dart';
import 'package:naviwealth/core/speech/speech_recognizer_android.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('maps Android on-device availability and permission status', () async {
    const channel = MethodChannel('test.naviwealth/speech_android.status');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'status');
      return <String, Object?>{
        'availability': 'permission_denied',
        'reason': 'Microphone permission is required',
      };
    });

    final status = await AndroidOnDeviceSpeechRecognizer(
      methodChannel: channel,
      eventStream: () => const Stream<Object?>.empty(),
    ).status();

    expect(status.availability, SpeechRecognizerAvailability.permissionDenied);
    expect(status.isReady, isFalse);
    expect(status.reason, 'Microphone permission is required');
  });

  test(
    'buffers native semantic events until the session consumer attaches',
    () async {
      const channel = MethodChannel('test.naviwealth/speech_android.events');
      final nativeEvents = StreamController<Object?>();
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      addTearDown(() async {
        messenger.setMockMethodCallHandler(channel, null);
        await nativeEvents.close();
      });

      messenger.setMockMethodCallHandler(channel, (call) async {
        switch (call.method) {
          case 'start':
            nativeEvents
              ..add(<String, Object?>{
                'type': 'speech_started',
                'started_at_ms': 1,
              })
              ..add(<String, Object?>{
                'type': 'transcript',
                'text': '记录午饭',
                'is_final': true,
              });
            await Future<void>.delayed(Duration.zero);
          case 'stop':
            nativeEvents.add(<String, Object?>{
              'type': 'ended',
              'cancelled': false,
            });
            await Future<void>.delayed(Duration.zero);
          default:
            fail('Unexpected method ${call.method}');
        }
        return null;
      });

      final session = await AndroidOnDeviceSpeechRecognizer(
        methodChannel: channel,
        eventStream: () => nativeEvents.stream,
      ).start();
      final events = <SpeechRecognitionEvent>[];
      final subscription = session.events.listen(events.add);

      await session.stop();
      await Future<void>.delayed(Duration.zero);

      expect(events, hasLength(2));
      expect(events.first.speechStarted, isTrue);
      expect(events.last.text, '记录午饭');
      expect(events.last.isFinal, isTrue);

      await subscription.cancel();
    },
  );
}
