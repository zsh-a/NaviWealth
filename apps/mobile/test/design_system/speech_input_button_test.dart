import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/core/speech/speech_recognizer.dart';
import 'package:naviwealth/core/speech/speech_recognizer_provider.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

void main() {
  testWidgets('dictation updates draft and never submits it', (tester) async {
    final recognizer = _FakeSpeechRecognizer();
    final controller = TextEditingController(text: 'Existing note');
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [speechRecognizerProvider.overrideWithValue(recognizer)],
        child: MaterialApp(
          theme: AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: SpeechInputButton(controller: controller)),
        ),
      ),
    );

    await tester.tap(find.byIcon(FLucideIcons.mic));
    await tester.pump();
    expect(find.byIcon(FLucideIcons.square), findsOneWidget);

    recognizer.session.add('今天完成了月度复盘');
    await tester.pump();
    expect(controller.text, 'Existing note\n今天完成了月度复盘');

    await tester.tap(find.byIcon(FLucideIcons.square));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(recognizer.session.stopped, isTrue);
    expect(controller.text, 'Existing note\n今天完成了月度复盘，并制定了明日计划');
    expect(find.byIcon(FLucideIcons.mic), findsOneWidget);
  });

  testWidgets('cancels a pending session when input becomes disabled', (
    tester,
  ) async {
    final recognizer = _DeferredSpeechRecognizer();
    final controller = TextEditingController();
    final enabled = ValueNotifier<bool>(true);
    addTearDown(controller.dispose);
    addTearDown(enabled.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [speechRecognizerProvider.overrideWithValue(recognizer)],
        child: MaterialApp(
          theme: AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: ValueListenableBuilder<bool>(
              valueListenable: enabled,
              builder: (_, value, _) =>
                  SpeechInputButton(controller: controller, enabled: value),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byIcon(FLucideIcons.mic));
    await tester.pump();
    enabled.value = false;
    await tester.pump();

    recognizer.completeStart();
    await tester.pump();
    await tester.pump();

    expect(recognizer.session.cancelled, isTrue);
    expect(find.byIcon(FLucideIcons.square), findsNothing);
    await tester.pump(const Duration(milliseconds: 200));
  });

  testWidgets('user edits cancel dictation and are never overwritten', (
    tester,
  ) async {
    final recognizer = _FakeSpeechRecognizer();
    final controller = TextEditingController(text: '原始内容');
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [speechRecognizerProvider.overrideWithValue(recognizer)],
        child: MaterialApp(
          theme: AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: SpeechInputButton(controller: controller)),
        ),
      ),
    );

    await tester.tap(find.byIcon(FLucideIcons.mic));
    await tester.pump();
    recognizer.session.add('语音草稿');
    await tester.pump();
    expect(controller.text, '原始内容\n语音草稿');

    controller.text = '用户手动修改';
    await tester.pump();
    await tester.pump();
    recognizer.session.add('迟到的识别结果');
    await tester.pump();

    expect(recognizer.session.cancelled, isTrue);
    expect(controller.text, '用户手动修改');
    expect(find.byIcon(FLucideIcons.mic), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 200));
  });

  testWidgets('background transition finalizes an active session', (
    tester,
  ) async {
    final recognizer = _FakeSpeechRecognizer();
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [speechRecognizerProvider.overrideWithValue(recognizer)],
        child: MaterialApp(
          theme: AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: SpeechInputButton(controller: controller)),
        ),
      ),
    );

    await tester.tap(find.byIcon(FLucideIcons.mic));
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump(const Duration(milliseconds: 200));

    expect(recognizer.session.stopped, isTrue);
    expect(controller.text, '今天完成了月度复盘，并制定了明日计划');
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byIcon(FLucideIcons.mic), findsOneWidget);
  });
}

class _FakeSpeechRecognizer implements SpeechRecognizer {
  final session = _FakeSpeechSession();

  @override
  Future<SpeechRecognizerStatus> status() async =>
      const SpeechRecognizerStatus(SpeechRecognizerAvailability.ready);

  @override
  Future<SpeechRecognitionSession> start() async => session;
}

class _FakeSpeechSession implements SpeechRecognitionSession {
  final _events = StreamController<SpeechRecognitionEvent>.broadcast();
  bool stopped = false;
  bool cancelled = false;

  void add(String text) {
    if (_events.isClosed) return;
    _events.add(SpeechRecognitionEvent(text: text, isFinal: false));
  }

  @override
  Stream<SpeechRecognitionEvent> get events => _events.stream;

  @override
  Future<void> cancel() async {
    cancelled = true;
    if (!_events.isClosed) unawaited(_events.close());
  }

  @override
  Future<void> stop() async {
    stopped = true;
    if (_events.isClosed) return;
    _events.add(
      const SpeechRecognitionEvent(text: '今天完成了月度复盘，并制定了明日计划', isFinal: true),
    );
    unawaited(_events.close());
  }
}

class _DeferredSpeechRecognizer implements SpeechRecognizer {
  final session = _FakeSpeechSession();
  final _start = Completer<SpeechRecognitionSession>();

  void completeStart() => _start.complete(session);

  @override
  Future<SpeechRecognizerStatus> status() async =>
      const SpeechRecognizerStatus(SpeechRecognizerAvailability.ready);

  @override
  Future<SpeechRecognitionSession> start() => _start.future;
}
