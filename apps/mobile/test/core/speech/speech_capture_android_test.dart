import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/speech/speech_capture.dart';
import 'package:naviwealth/core/speech/speech_capture_android.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('maps native capture format and processing capabilities', () async {
    const channel = MethodChannel('test.naviwealth/audio_capture.status');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'status');
      return <String, Object?>{
        'availability': 'ready',
        'sample_rate_hz': 16000,
        'channel_count': 1,
        'encoding': 'pcm16le',
        'ring_capacity_bytes': 64000,
        'aec_available': true,
        'ns_available': true,
        'agc_available': false,
        'vad_available': true,
        'vad_mode': 'native_energy',
        'vad_frame_duration_ms': 20,
        'vad_min_speech_frames': 2,
        'vad_min_silence_frames': 20,
        'supports_barge_in': true,
        'full_duplex': true,
      };
    });

    final status = await AndroidNativeAudioCapture(
      methodChannel: channel,
      eventStream: () => const Stream<Object?>.empty(),
    ).status();

    expect(status.isReady, isTrue);
    expect(status.capabilities?.sampleRateHz, 16000);
    expect(status.capabilities?.channelCount, 1);
    expect(status.capabilities?.aecAvailable, isTrue);
    expect(status.capabilities?.automaticGainControlAvailable, isFalse);
    expect(status.capabilities?.vadAvailable, isTrue);
    expect(status.capabilities?.vadMode, 'native_energy');
    expect(status.capabilities?.vadFrameDurationMs, 20);
    expect(status.capabilities?.supportsBargeIn, isTrue);
    expect(status.capabilities?.fullDuplex, isTrue);
  });

  test('maps native VAD boundaries without exposing audio frames', () async {
    const channel = MethodChannel('test.naviwealth/audio_capture.vad');
    final nativeEvents = StreamController<Object?>();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    addTearDown(() async {
      messenger.setMockMethodCallHandler(channel, null);
      await nativeEvents.close();
    });

    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'start') {
        nativeEvents
          ..add(<String, Object?>{
            'type': 'capture_started',
            'sample_rate_hz': 16000,
            'channel_count': 1,
            'encoding': 'pcm16le',
            'ring_capacity_bytes': 64000,
            'vad_mode': 'native_energy',
            'vad_frame_duration_ms': 20,
            'vad_min_speech_frames': 2,
            'vad_min_silence_frames': 20,
          })
          ..add(<String, Object?>{
            'type': 'speech_started',
            'started_at_ms': 1000,
            'vad_mode': 'native_energy',
          })
          ..add(<String, Object?>{
            'type': 'speech_stopped',
            'stopped_at_ms': 2400,
            'duration_ms': 1400,
            'vad_mode': 'native_energy',
          });
      }
      return null;
    });

    final session = await AndroidNativeAudioCapture(
      methodChannel: channel,
      eventStream: () => nativeEvents.stream,
    ).start();
    final events = <SpeechCaptureEvent>[];
    final subscription = session.events.listen(events.add);
    await Future<void>.delayed(Duration.zero);

    expect(events, hasLength(3));
    expect(events[0], isA<SpeechCaptureStarted>());
    expect(events[1], isA<SpeechCaptureSpeechStarted>());
    expect(
      (events[1] as SpeechCaptureSpeechStarted).startedAt,
      DateTime.fromMillisecondsSinceEpoch(1000, isUtc: true),
    );
    expect(events[2], isA<SpeechCaptureSpeechStopped>());
    expect((events[2] as SpeechCaptureSpeechStopped).durationMs, 1400);
    expect((events[2] as SpeechCaptureSpeechStopped).vadMode, 'native_energy');

    await session.cancel();
    await subscription.cancel();
  });

  test('buffers lifecycle events and never exposes PCM frames', () async {
    const channel = MethodChannel('test.naviwealth/audio_capture.events');
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
          nativeEvents.add(<String, Object?>{
            'type': 'capture_started',
            'sample_rate_hz': 16000,
            'channel_count': 1,
            'encoding': 'pcm16le',
            'ring_capacity_bytes': 64000,
            'aec_available': true,
            'aec_enabled': true,
            'ns_available': true,
            'ns_enabled': true,
            'agc_available': true,
            'agc_enabled': false,
          });
        case 'stop':
          nativeEvents.add(<String, Object?>{
            'type': 'capture_stopped',
            'cancelled': false,
            'captured_bytes': 1280,
            'buffered_bytes': 1280,
            'dropped_bytes': 0,
            'read_errors': 0,
          });
        default:
          fail('Unexpected method ${call.method}');
      }
      return null;
    });

    final session = await AndroidNativeAudioCapture(
      methodChannel: channel,
      eventStream: () => nativeEvents.stream,
    ).start();
    final events = <SpeechCaptureEvent>[];
    final subscription = session.events.listen(events.add);

    await session.stop();
    await Future<void>.delayed(Duration.zero);

    expect(events, hasLength(2));
    expect(events.first, isA<SpeechCaptureStarted>());
    expect(
      (events.first as SpeechCaptureStarted).capabilities.aecEnabled,
      isTrue,
    );
    expect(events.last, isA<SpeechCaptureStopped>());
    expect((events.last as SpeechCaptureStopped).capturedBytes, 1280);
    expect((events.last as SpeechCaptureStopped).droppedBytes, 0);

    await subscription.cancel();
  });

  test('maps native recorder failure to a semantic error event', () async {
    const channel = MethodChannel('test.naviwealth/audio_capture.error');
    final nativeEvents = StreamController<Object?>();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    addTearDown(() async {
      messenger.setMockMethodCallHandler(channel, null);
      await nativeEvents.close();
    });

    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'start') {
        nativeEvents.add(<String, Object?>{
          'type': 'error',
          'code': 'recorder_unavailable',
          'message': 'AudioRecord disconnected',
        });
        nativeEvents.add(<String, Object?>{
          'type': 'capture_stopped',
          'cancelled': true,
          'captured_bytes': 0,
          'buffered_bytes': 0,
          'dropped_bytes': 0,
          'read_errors': 1,
        });
      }
      return null;
    });

    final session = await AndroidNativeAudioCapture(
      methodChannel: channel,
      eventStream: () => nativeEvents.stream,
    ).start();
    final events = <SpeechCaptureEvent>[];
    final subscription = session.events.listen(events.add);
    await Future<void>.delayed(Duration.zero);

    expect(events, hasLength(2));
    expect(events.first, isA<SpeechCaptureError>());
    expect(
      (events.first as SpeechCaptureError).code,
      SpeechCaptureErrorCode.recorderUnavailable,
    );
    expect(events.last, isA<SpeechCaptureStopped>());
    await subscription.cancel();
  });
}
