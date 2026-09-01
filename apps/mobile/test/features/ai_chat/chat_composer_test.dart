import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/core/ai/llm_credentials/llm_credentials.dart';
import 'package:naviwealth/core/ai/llm_credentials/providers.dart';
import 'package:naviwealth/core/speech/speech_recognizer.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/ai_chat/state/chat_controller.dart';
import 'package:naviwealth/features/ai_chat/ui/chat_composer.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late SharedPreferences preferences;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    preferences = await SharedPreferences.getInstance();
  });

  testWidgets('idle composer uses localized copy and sends non-empty text', (
    tester,
  ) async {
    final sent = <String>[];
    var cancelled = 0;

    await _pumpComposer(
      tester,
      preferences: preferences,
      locale: const Locale('en'),
      isStreaming: false,
      onSend: sent.add,
      onCancel: () => cancelled++,
    );

    expect(
      find.text('Ask NaviWealth about finance, knowledge, health, or plans'),
      findsOneWidget,
    );

    await tester.tap(find.byIcon(FLucideIcons.arrowUp));
    await tester.pump(const Duration(milliseconds: 120));
    expect(sent, isEmpty);

    await tester.enterText(find.byType(EditableText), 'Summarize my month');
    await tester.pump();
    await tester.tap(find.byIcon(FLucideIcons.arrowUp));
    await tester.pump(const Duration(milliseconds: 120));

    expect(sent, <String>['Summarize my month']);
    expect(find.text('Summarize my month'), findsNothing);
    expect(cancelled, 0);
  });

  testWidgets('streaming composer disables input and exposes stop action', (
    tester,
  ) async {
    final sent = <String>[];
    var cancelled = 0;

    await _pumpComposer(
      tester,
      preferences: preferences,
      locale: const Locale('zh'),
      isStreaming: true,
      initialText: 'ignored draft',
      onSend: sent.add,
      onCancel: () => cancelled++,
    );

    expect(find.text('正在生成回答…'), findsOneWidget);

    final editable = tester.widget<EditableText>(find.byType(EditableText));
    expect(editable.readOnly, isTrue);

    await tester.tap(find.byIcon(FLucideIcons.square));
    await tester.pump(const Duration(milliseconds: 120));

    expect(cancelled, 1);
    expect(sent, isEmpty);
  });

  testWidgets('missing model profile exposes setup before sending', (
    tester,
  ) async {
    await _pumpComposer(
      tester,
      preferences: preferences,
      locale: const Locale('zh'),
      isStreaming: false,
      sessionId: 'session-1',
      credentials: const LlmCredentials(),
      onSend: (_) {},
      onCancel: () {},
    );
    await tester.pumpAndSettle();

    expect(find.text('添加模型服务商'), findsOneWidget);
  });

  testWidgets('voice preparation remains cancellable while busy', (
    tester,
  ) async {
    var cancelled = 0;

    await _pumpComposer(
      tester,
      preferences: preferences,
      locale: const Locale('en'),
      isStreaming: false,
      onSend: (_) {},
      onCancel: () {},
      useInteractionVoice: true,
      voiceStarting: true,
      voicePhase: VoiceLifecyclePhase.preparing,
      onCancelVoice: () async => cancelled++,
    );

    expect(find.text('Preparing microphone…'), findsOneWidget);
    expect(find.byIcon(FLucideIcons.x), findsOneWidget);

    await tester.tap(find.byIcon(FLucideIcons.x));
    await tester.pump(const Duration(milliseconds: 120));

    expect(cancelled, 1);
  });

  testWidgets('ready startup state explains that the microphone is next', (
    tester,
  ) async {
    await _pumpComposer(
      tester,
      preferences: preferences,
      locale: const Locale('en'),
      isStreaming: false,
      onSend: (_) {},
      onCancel: () {},
      useInteractionVoice: true,
      voiceStarting: true,
      voicePhase: VoiceLifecyclePhase.ready,
      onCancelVoice: () async {},
    );

    expect(
      find.text('Recognition is ready; starting microphone…'),
      findsOneWidget,
    );
  });

  testWidgets('voice error exposes an inline retry action', (tester) async {
    var retried = 0;

    await _pumpComposer(
      tester,
      preferences: preferences,
      locale: const Locale('en'),
      isStreaming: false,
      onSend: (_) {},
      onCancel: () {},
      useInteractionVoice: true,
      voicePhase: VoiceLifecyclePhase.error,
      voiceErrorCode: SpeechRecognitionErrorCode.runtimeUnavailable,
      onVoiceRetry: () async => retried++,
    );

    expect(
      find.text('The on-device speech recognition service is unavailable'),
      findsOneWidget,
    );
    expect(find.text('Retry'), findsOneWidget);

    await tester.tap(find.text('Retry'));
    await tester.pump(const Duration(milliseconds: 120));

    expect(retried, 1);
  });

  testWidgets('voice listener can switch to text and preserve its transcript', (
    tester,
  ) async {
    var switched = 0;

    await _pumpComposer(
      tester,
      preferences: preferences,
      locale: const Locale('en'),
      isStreaming: false,
      onSend: (_) {},
      onCancel: () {},
      useInteractionVoice: true,
      voiceActive: true,
      voicePhase: VoiceLifecyclePhase.listening,
      voiceTranscript: 'Check my balance',
      onVoiceSwitchToText: () async => switched++,
    );

    expect(find.byIcon(FLucideIcons.keyboard), findsOneWidget);

    await tester.tap(find.byIcon(FLucideIcons.keyboard));
    await tester.pump(const Duration(milliseconds: 120));

    expect(switched, 1);
    expect(
      tester.widget<EditableText>(find.byType(EditableText)).controller.text,
      'Check my balance',
    );
  });
}

Future<void> _pumpComposer(
  WidgetTester tester, {
  required SharedPreferences preferences,
  required Locale locale,
  required bool isStreaming,
  required ValueChanged<String> onSend,
  required VoidCallback onCancel,
  String? sessionId,
  LlmCredentials? credentials,
  String? initialText,
  bool useInteractionVoice = false,
  bool voiceStarting = false,
  bool voiceActive = false,
  VoiceLifecyclePhase voicePhase = VoiceLifecyclePhase.idle,
  String voiceTranscript = '',
  SpeechRecognitionErrorCode? voiceErrorCode,
  Future<void> Function()? onCancelVoice,
  Future<void> Function()? onVoiceRetry,
  Future<void> Function()? onVoiceSwitchToText,
}) {
  return tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        if (credentials != null)
          llmCredentialsProvider.overrideWith(
            () => _FakeCredentialsNotifier(credentials),
          ),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: locale,
        builder: (context, child) => FAccessibilityScope(
          data: const FAccessibility(
            accessibleNavigation: false,
            motion: FAccessibilityMotion.disabled,
            focusHighlight: false,
          ),
          child: child!,
        ),
        home: Scaffold(
          body: FTheme(
            data: FTheme.neutral.light.desktop,
            child: Align(
              alignment: Alignment.bottomCenter,
              child: ExcludeSemantics(
                child: ChatComposer(
                  isStreaming: isStreaming,
                  sessionId: sessionId,
                  initialText: initialText,
                  onSend: onSend,
                  onCancel: onCancel,
                  isVoiceActive: voiceActive,
                  canStartVoice: true,
                  onStartVoice: useInteractionVoice ? () async {} : null,
                  onStopVoice: useInteractionVoice ? () async {} : null,
                  onCancelVoice: useInteractionVoice
                      ? (onCancelVoice ?? () async {})
                      : null,
                  onVoiceRetry: useInteractionVoice ? onVoiceRetry : null,
                  onVoiceSwitchToText: useInteractionVoice
                      ? onVoiceSwitchToText
                      : null,
                  voiceStarting: voiceStarting,
                  voiceCapsuleVisible:
                      useInteractionVoice && (voiceStarting || voiceActive),
                  voicePhase: voicePhase,
                  voiceTranscript: voiceTranscript,
                  voiceErrorCode: voiceErrorCode,
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

final class _FakeCredentialsNotifier extends LlmCredentialsNotifier {
  _FakeCredentialsNotifier(this._credentials);

  final LlmCredentials _credentials;

  @override
  Future<LlmCredentials?> fetch() async => _credentials;
}
