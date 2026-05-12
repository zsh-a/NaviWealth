/// Wave 33 — `AiObjectCapsule`: the object-semantic AI affordance.
///
/// **What this is**: a small inline pill that, when tapped, opens an
/// AI bottom sheet pre-loaded with the object's context. The label is
/// always object-semantic ("为什么涨价" / "如何提高") sourced from
/// `intent_policy`; the §5.8 hard constraints forbid generic
/// "Ask AI" copy.
///
/// **What this is NOT**: a floating action button, a header icon, or
/// a glowing chat shortcut. Calm Intelligence: surface tone, single
/// muted sparkle, type-size body label.
library;

import 'package:flutter/material.dart';

import '../../../core/ai/intent/intent.dart';
import 'ai_bottom_sheet.dart';

class AiObjectCapsule extends StatelessWidget {
  const AiObjectCapsule({
    super.key,
    required this.source,
    required this.intent,
    required this.object,
    required this.objectLabel,
    this.context = const <String, Object?>{},
    this.fallbackLabel,
  });

  /// Trigger location tag (matches `AiIntentInvocation.source`).
  final String source;

  /// Registered intent name. Must exist in `intent_policy.dart` —
  /// the capsule label comes from `lookupIntent(intent).labelZh`.
  final String intent;

  final AiObjectRef object;

  /// Human-readable name of the object, used in the prompt template
  /// and as the bottom-sheet header subtitle.
  final String objectLabel;

  /// Extra ContextPack signals to attach to the invocation (e.g.
  /// `{'timeframe': '30d'}`).
  final Map<String, Object?> context;

  /// Override the registry-derived label. Use sparingly — usually the
  /// registry label is correct; fallback is for niche surfaces.
  final String? fallbackLabel;

  @override
  Widget build(BuildContext buildContext) {
    final descriptor = lookupIntent(intent);
    final label = fallbackLabel ?? descriptor?.labelZh ?? '展开';
    final scheme = Theme.of(buildContext).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: () => _open(buildContext),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.auto_awesome_outlined,
                size: 14,
                color: scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: Theme.of(buildContext).textTheme.bodySmall?.copyWith(
                  color: scheme.onSurface,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _open(BuildContext buildContext) {
    showAiBottomSheet(
      buildContext,
      invocation: AiIntentInvocation(
        source: source,
        intent: intent,
        object: object,
        context: context,
      ),
      objectLabel: objectLabel,
    );
  }
}
