import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

import '../../core/shell/settings_route_paths.dart';
import '../../core/speech/speech_error_copy.dart';
import '../../core/speech/speech_input.dart';
import '../../core/speech/speech_recognizer.dart';
import '../../core/speech/speech_recognizer_provider.dart';
import '../../l10n/gen/app_localizations.dart';
import '../tokens/dimens_tokens.dart';
import 'app_toast.dart';

/// Reusable push-to-dictate control that only writes editable draft text.
///
/// Recognition never submits the form or invokes an AI tool. The caller's
/// [controller] remains the source of truth and the user can edit the final
/// transcript before sending or saving it.
class SpeechInputButton extends ConsumerStatefulWidget {
  const SpeechInputButton({
    super.key,
    required this.controller,
    this.enabled = true,
    this.onSpeechInput,
  });

  final TextEditingController controller;
  final bool enabled;

  /// Called after a transcript event has been written to [controller].
  /// Consumers can use this to preserve the input modality when the draft is
  /// eventually submitted. The button still never submits the draft itself.
  final VoidCallback? onSpeechInput;

  @override
  ConsumerState<SpeechInputButton> createState() => _SpeechInputButtonState();
}

enum _SpeechButtonState { idle, starting, listening, stopping }

class _SpeechInputButtonState extends ConsumerState<SpeechInputButton>
    with WidgetsBindingObserver {
  _SpeechButtonState _state = _SpeechButtonState.idle;
  SpeechInputSession? _session;
  StreamSubscription<SpeechInputEvent>? _events;
  String _baseText = '';
  bool _writingTranscript = false;

  bool get _busy => _state != _SpeechButtonState.idle;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.controller.addListener(_handleControllerChanged);
  }

  @override
  void didUpdateWidget(SpeechInputButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_handleControllerChanged);
      widget.controller.addListener(_handleControllerChanged);
    }
    if (oldWidget.enabled && !widget.enabled && _busy) {
      unawaited(_cancel());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.controller.removeListener(_handleControllerChanged);
    unawaited(_events?.cancel());
    unawaited(_session?.cancel());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_busy || state == AppLifecycleState.resumed) return;
    if (_state == _SpeechButtonState.listening) {
      unawaited(_stop());
    } else {
      unawaited(_cancel());
    }
  }

  void _handleControllerChanged() {
    if (_writingTranscript || !_busy) return;
    // User edits always win. Stop the pending/native session instead of
    // allowing a later partial result to overwrite their draft.
    unawaited(_cancel());
  }

  Future<void> _toggle() =>
      _state == _SpeechButtonState.listening ? _stop() : _start();

  Future<void> _start() async {
    if (!widget.enabled || _busy) return;
    setState(() => _state = _SpeechButtonState.starting);
    final l10n = AppLocalizations.of(context);
    try {
      final input = ref.read(speechInputProvider);
      final status = await input.status();
      if (!mounted) return;
      if (!widget.enabled || _state != _SpeechButtonState.starting) return;
      switch (status.availability) {
        case SpeechRecognizerAvailability.modelNotInstalled:
          setState(() => _state = _SpeechButtonState.idle);
          AppMessenger.show(
            context,
            ToastKind.info,
            l10n.speechInputModelMissing,
          );
          unawaited(context.push(SettingsRoutes.aiModels));
          return;
        case SpeechRecognizerAvailability.unsupported:
          setState(() => _state = _SpeechButtonState.idle);
          AppMessenger.show(
            context,
            ToastKind.warning,
            l10n.speechInputUnsupported,
          );
          return;
        case SpeechRecognizerAvailability.permissionDenied:
          // The Android provider requests RECORD_AUDIO from the explicit
          // push-to-talk action. Do not turn a first-use permission state into
          // a permanent error before the native request has run.
          break;
        case SpeechRecognizerAvailability.ready:
          break;
      }

      _baseText = widget.controller.text;
      final session = await input.start();
      if (!mounted ||
          !widget.enabled ||
          _state != _SpeechButtonState.starting) {
        await session.cancel();
        return;
      }
      _session = session;
      _events = session.events.listen(
        _applyTranscript,
        onError: (Object error, StackTrace stackTrace) {
          if (!mounted) return;
          AppMessenger.show(context, ToastKind.error, l10n.speechInputFailed);
          unawaited(_cancel());
        },
        onDone: () => unawaited(_reset()),
      );
      setState(() => _state = _SpeechButtonState.listening);
    } on SpeechRecognitionException catch (error) {
      if (!mounted || _state != _SpeechButtonState.starting) return;
      setState(() => _state = _SpeechButtonState.idle);
      final message = speechRecognitionErrorMessage(l10n, error.code);
      AppMessenger.show(context, ToastKind.error, message);
    } on Object {
      if (!mounted || _state != _SpeechButtonState.starting) return;
      setState(() => _state = _SpeechButtonState.idle);
      AppMessenger.show(context, ToastKind.error, l10n.speechInputFailed);
    }
  }

  void _applyTranscript(SpeechInputEvent event) {
    final text = switch (event) {
      SpeechInputTranscript(:final text) => text,
      SpeechInputSpeechStarted() ||
      SpeechInputSpeechStopped() ||
      SpeechInputEnded() => null,
    };
    if (text == null) return;
    if (!mounted) return;
    final separator = _baseText.isEmpty || RegExp(r'\s$').hasMatch(_baseText)
        ? ''
        : '\n';
    final nextText = '$_baseText$separator$text';
    _writingTranscript = true;
    try {
      widget.controller.value = TextEditingValue(
        text: nextText,
        selection: TextSelection.collapsed(offset: nextText.length),
      );
      widget.onSpeechInput?.call();
    } finally {
      _writingTranscript = false;
    }
  }

  Future<void> _stop() async {
    final session = _session;
    if (session == null || _state != _SpeechButtonState.listening) return;
    setState(() => _state = _SpeechButtonState.stopping);
    try {
      await session.stop();
      // A session may publish its final transcript asynchronously immediately
      // before stop completes. Yield once before detaching the listener.
      await Future<void>.delayed(Duration.zero);
    } on Object {
      if (mounted) {
        AppMessenger.show(
          context,
          ToastKind.error,
          AppLocalizations.of(context).speechInputFailed,
        );
      }
    } finally {
      await _reset();
    }
  }

  Future<void> _cancel() async {
    try {
      await _session?.cancel();
    } finally {
      await _reset();
    }
  }

  Future<void> _reset() async {
    final events = _events;
    _events = null;
    _session = null;
    if (mounted && _state != _SpeechButtonState.idle) {
      setState(() => _state = _SpeechButtonState.idle);
    }
    await events?.cancel();
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    final listening = _state == _SpeechButtonState.listening;
    final loading =
        _state == _SpeechButtonState.starting ||
        _state == _SpeechButtonState.stopping;
    final tooltip = listening
        ? l10n.speechInputStopTooltip
        : loading
        ? l10n.speechInputStartingTooltip
        : l10n.speechInputStartTooltip;
    return FTooltip(
      tipBuilder: (_, _) => Text(tooltip),
      child: FButton.icon(
        variant: listening
            ? FButtonVariant.destructive
            : FButtonVariant.secondary,
        onPress: widget.enabled && !loading ? _toggle : null,
        child: loading
            ? const SizedBox.square(
                dimension: AppIconSizes.sm,
                child: FCircularProgress(),
              )
            : Icon(listening ? FLucideIcons.square : FLucideIcons.mic),
      ),
    );
  }
}
