/// AI chat surface wiring.
///
/// Core and domain code call the domain-neutral `askAi(...)` seam from
/// `core/ai/composition/ask_ai.dart`. The actual bottom sheet is an
/// AI-chat feature concern and is installed here by app composition.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/misc.dart';

import '../../../core/ai/composition/ask_ai.dart';
import '../../../core/ai/intent/ai_intent_invocation.dart';
import '../ui/ai_sheet.dart';

List<Override> aiChatSurfaceOverrides() {
  return [askAiSurfaceProvider.overrideWith((ref) => _openAiChatSurface)];
}

Future<void> _openAiChatSurface(
  BuildContext context, {
  AiIntentInvocation? invocation,
  String? objectLabel,
  String? prefill,
}) {
  return showAiSheet(
    context,
    invocation: invocation,
    objectLabel: objectLabel,
    prefill: prefill,
  );
}
