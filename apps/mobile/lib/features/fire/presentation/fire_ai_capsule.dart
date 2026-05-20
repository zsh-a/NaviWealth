import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ai/intent/ai_intent_invocation.dart';
import '../../../core/ai/llm_credentials/providers.dart';
import '../../ai_chat/ui/ai_object_capsule.dart';

/// Thin wrapper around [AiObjectCapsule] that hides the pill when the
/// device LLM runtime is unavailable (web builds, no profile, etc.).
/// Every FIRE-OS card that surfaces an intent uses this so capsules
/// behave consistently and don't render a no-op tap target.
class FireAiCapsule extends ConsumerWidget {
  const FireAiCapsule({
    super.key,
    required this.intent,
    required this.source,
    required this.objectLabel,
    this.objectType = 'fire_state',
    this.objectId = 'default',
    this.context = const <String, Object?>{},
  });

  final String intent;
  final String source;
  final String objectLabel;
  final String objectType;
  final String objectId;
  final Map<String, Object?> context;

  @override
  Widget build(BuildContext buildContext, WidgetRef ref) {
    if (!ref.watch(deviceLlmAvailableProvider)) {
      return const SizedBox.shrink();
    }
    return AiObjectCapsule(
      source: source,
      intent: intent,
      object: AiObjectRef(type: objectType, id: objectId),
      objectLabel: objectLabel,
      context: context,
    );
  }
}
