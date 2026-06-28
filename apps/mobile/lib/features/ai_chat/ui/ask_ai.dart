/// `askAi` — the single API every UI surface uses to invoke the AI.
///
/// This is the layer above [showAiSheet]: it auto-fills the bits that
/// should not vary by call site (domain from current route, source
/// from current path, default capabilities) so feature code can express
/// only what's domain-specific to it — an intent, an object, maybe a
/// prefill.
///
/// Two modes, picked by whether [intent] is supplied:
///
///  - **conversation** (`intent == null`): opens or resumes the user's
///    default chat thread, optionally with [prefill] in the composer.
///  - **invocation** (`intent != null`): builds an [AiIntentInvocation]
///    against the current ambient context and opens the invocation
///    sheet (fresh thread, fires the rendered prompt immediately).
///
/// **Domain rule.** The invocation's `domain` is read from
/// [aiContextProvider], which the outer shell keeps in sync with the
/// active route. When the user is on a shell-level route (`/login`,
/// `/settings/*`) we fall back to [DomainScope.finance] — the
/// always-on seed domain. Call sites never write `domain:` directly.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ai/intent/ai_intent_invocation.dart';
import '../../../core/auth/domain_scope.dart';
import '../state/ai_context.dart';
import 'ai_sheet.dart';

/// Open the AI surface. Pass [intent] for the object-semantic mode;
/// omit it (and optionally pass [prefill]) for a conversation.
///
/// All parameters except [intent] / [object] are optional — by default
/// `source` is the current route path, `domain` is the route's
/// owning [DomainScope] (falling back to `finance`), and `capabilities`
/// covers chat / proposal / visualization.
Future<void> askAi(
  BuildContext context,
  WidgetRef ref, {
  String? intent,
  AiObjectRef? object,
  String? objectLabel,
  Map<String, Object?> attrs = const <String, Object?>{},
  String? prefill,
  String? source,
  Set<AiCapability>? capabilities,
}) {
  if (intent == null) {
    return showAiSheet(context, prefill: prefill);
  }
  final aiCtx = ref.read(aiContextProvider);
  final domain = (aiCtx.domain ?? DomainScope.finance).wire;
  return showAiSheet(
    context,
    invocation: AiIntentInvocation(
      source: source ?? aiCtx.path,
      intent: intent,
      object: object,
      context: attrs,
      domain: domain,
      capabilities:
          capabilities ??
          const <AiCapability>{
            AiCapability.chat,
            AiCapability.proposal,
            AiCapability.visualization,
          },
    ),
    objectLabel: objectLabel,
  );
}
