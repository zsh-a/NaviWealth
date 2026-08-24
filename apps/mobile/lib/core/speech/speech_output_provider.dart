import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'speech_output.dart';
import 'speech_output_stub.dart'
    if (dart.library.io) 'system_speech_output.dart'
    as implementation;

/// The host-selected speech output capability.
///
/// Web deliberately selects the unsupported stub. Native platforms use the
/// system TTS adapter; a downloadable local TTS engine can replace this
/// provider without changing InteractionSession or Agent Runtime contracts.
final speechOutputProvider = Provider<SpeechOutput>((ref) {
  return implementation.createSpeechOutput();
});
