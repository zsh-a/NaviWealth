/// `AiObjectCapsule`: the object-semantic AI affordance.
///
/// Now backed by [AiPill] + [AiSparkle] primitives
/// so capsules everywhere look identical. Adding a new capsule never
/// touches sizing / color / typography; it just supplies the
/// invocation.
///
/// §5.8 hard constraint: label text comes from the active intent catalog,
/// not free-form. No generic assistant label / glow / chat icon. Domain is
/// auto-derived from the current route via [askAi]; capsules never
/// hard-code which OS they live in.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../composition/ask_ai.dart';
import '../intent/intent.dart';
import 'ai_pill.dart';
import 'ai_sparkle.dart';

class AiObjectCapsule extends ConsumerWidget {
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
  Widget build(BuildContext buildContext, WidgetRef ref) {
    final descriptor = ref.watch(intentCatalogProvider).lookup(intent);
    final l10n = AppLocalizations.of(buildContext);
    final label =
        fallbackLabel ??
        (descriptor == null
            ? l10n.aiCapsuleExpandFallback
            : localizedIntentLabel(l10n, descriptor));
    return AiPill(
      leading: const AiSparkle(),
      label: label,
      onTap: () => _open(buildContext, ref),
    );
  }

  void _open(BuildContext buildContext, WidgetRef ref) {
    // §5.10 Layer 2 — merge surrounding scope chips into the
    // invocation context. Explicit per-capsule context wins on key
    // collision so call sites can override what the scope advertises.
    final scopeContext = AiContextChipScope.contextMapOf(buildContext);
    final mergedContext = <String, Object?>{...scopeContext, ...context};
    askAi(
      buildContext,
      ref,
      source: source,
      intent: intent,
      object: object,
      objectLabel: objectLabel,
      attrs: mergedContext,
    );
  }
}
