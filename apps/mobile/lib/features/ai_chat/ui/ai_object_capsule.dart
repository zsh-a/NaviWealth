/// Wave 33 — `AiObjectCapsule`: the object-semantic AI affordance.
///
/// Wave 36 refactor — now backed by [AiPill] + [AiSparkle] primitives
/// so capsules everywhere look identical. Adding a new capsule never
/// touches sizing / color / typography; it just supplies the
/// invocation.
///
/// §5.8 hard constraint: label text comes from `intent_policy.dart`,
/// not free-form. No "Ask AI" / glow / generic chat icon.
library;

import 'package:flutter/widgets.dart';

import '../../../core/ai/intent/intent.dart';
import '../../../core/ai/visual/visual.dart';
import '../../../l10n/gen/app_localizations.dart';
import 'ai_sheet.dart';

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

  final String source;
  final String intent;
  final AiObjectRef object;
  final String objectLabel;
  final Map<String, Object?> context;
  final String? fallbackLabel;

  @override
  Widget build(BuildContext buildContext) {
    final descriptor = lookupIntent(intent);
    final label =
        fallbackLabel ??
        descriptor?.labelZh ??
        AppLocalizations.of(buildContext).aiCapsuleExpandFallback;
    return AiPill(
      leading: const AiSparkle(),
      label: label,
      onTap: () => _open(buildContext),
    );
  }

  void _open(BuildContext buildContext) {
    // §5.10 Layer 2 — merge surrounding scope chips into the
    // invocation context. Explicit per-capsule context wins on key
    // collision so call sites can override what the scope advertises.
    final scopeContext = AiContextChipScope.contextMapOf(buildContext);
    final mergedContext = <String, Object?>{
      ...scopeContext,
      ...context,
    };
    showAiSheet(
      buildContext,
      invocation: AiIntentInvocation(
        source: source,
        intent: intent,
        object: object,
        context: mergedContext,
      ),
      objectLabel: objectLabel,
    );
  }
}
