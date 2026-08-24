import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/ai/local/embedding/model_install_paths.dart';
import 'package:naviwealth/core/ai/local/embedding/model_manifest.dart';
import 'package:naviwealth/core/speech/speech_recognizer.dart';
import 'package:naviwealth/core/speech/speech_recognizer_sherpa_android.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final paths = ModelInstallPaths.unsafeForDir(
    Directory('/test/support/ai-models'),
  );

  test(
    'reports ready only when the local Zipformer bundle is complete',
    () async {
      final recognizer = AndroidSherpaSpeechRecognizer(
        resolvePaths: () async => paths,
        isBundleComplete: (_, bundle) async {
          expect(bundle.id, streamingZipformerLargeCtcZhBundle().id);
          return true;
        },
        eventStream: () => const Stream<Object?>.empty(),
      );

      final status = await recognizer.status();

      expect(status.availability, SpeechRecognizerAvailability.ready);
      expect(status.isReady, isTrue);
    },
  );

  test('reports modelNotInstalled and does not invoke native start', () async {
    const channel = MethodChannel('test.naviwealth/sherpa_android.missing');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    var startCalls = 0;
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'start') startCalls++;
      return null;
    });

    final recognizer = AndroidSherpaSpeechRecognizer(
      resolvePaths: () async => paths,
      methodChannel: channel,
      isBundleComplete: (_, _) async => false,
      eventStream: () => const Stream<Object?>.empty(),
    );

    final status = await recognizer.status();
    expect(status.availability, SpeechRecognizerAvailability.modelNotInstalled);
    await expectLater(
      recognizer.start(),
      throwsA(
        isA<SpeechRecognitionException>().having(
          (error) => error.code,
          'code',
          SpeechRecognitionErrorCode.modelNotInstalled,
        ),
      ),
    );
    expect(startCalls, 0);
  });

  test(
    'passes the model directory and replays native semantic events',
    () async {
      const channel = MethodChannel('test.naviwealth/sherpa_android.events');
      final nativeEvents = StreamController<Object?>();
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final calls = <MethodCall>[];
      addTearDown(() async {
        messenger.setMockMethodCallHandler(channel, null);
        await nativeEvents.close();
      });

      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        if (call.method == 'start') {
          // Emit before the consumer attaches. The adapter must retain semantic
          // events until the Interaction/managed session subscribes.
          nativeEvents
            ..add(<String, Object?>{
              'type': 'speech_started',
              'started_at_ms': 1234,
            })
            ..add(<String, Object?>{
              'type': 'transcript',
              'text': '记录午饭',
              'is_final': false,
            })
            ..add(<String, Object?>{
              'type': 'transcript',
              'text': '记录午饭三十八元',
              'is_final': true,
            })
            ..add(<String, Object?>{
              'type': 'capture_stopped',
              'cancelled': false,
            });
          await Future<void>.delayed(Duration.zero);
        }
        return null;
      });

      final session = await AndroidSherpaSpeechRecognizer(
        resolvePaths: () async => paths,
        methodChannel: channel,
        eventStream: () => nativeEvents.stream,
        isBundleComplete: (_, _) async => true,
      ).start();

      final events = await session.events.toList();

      expect(events, hasLength(3));
      expect(events[0].speechStarted, isTrue);
      expect(
        events[0].startedAt,
        DateTime.fromMillisecondsSinceEpoch(1234, isUtc: true),
      );
      expect(events[1].text, '记录午饭');
      expect(events[1].isFinal, isFalse);
      expect(events[2].text, '记录午饭三十八元');
      expect(events[2].isFinal, isTrue);

      final startCall = calls.singleWhere((call) => call.method == 'start');
      expect(
        (startCall.arguments as Map<Object?, Object?>)['model_directory'],
        '${paths.rootDir.path}/${streamingZipformerLargeCtcZhBundle().id}',
      );
    },
  );
}
