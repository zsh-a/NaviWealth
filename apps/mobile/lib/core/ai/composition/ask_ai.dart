/// `askAi` — the single API every UI surface uses to invoke the AI.
///
/// This core layer auto-fills the bits that should not vary by call site
/// (domain from current route, source from current path, default
/// capabilities) and dispatches to the app-provided [askAiSurfaceProvider].
/// The concrete chat sheet stays in `features/ai_chat/`.
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

import '../../auth/domain_scope.dart';
import '../intent/ai_intent_invocation.dart';
import 'ai_context.dart';

typedef AskAiSurface =
    Future<void> Function(
      BuildContext context, {
      AiIntentInvocation? invocation,
      String? objectLabel,
      String? prefill,
    });

Future<void> _noopAskAiSurface(
  BuildContext context, {
  AiIntentInvocation? invocation,
  String? objectLabel,
  String? prefill,
}) async {}

/// App-provided AI surface opener.
///
/// The default is a no-op so feature widgets can be rendered in isolation
/// without importing `features/ai_chat/`. Production installs the chat sheet
/// implementation from the app composition root.
final askAiSurfaceProvider = Provider<AskAiSurface>((ref) => _noopAskAiSurface);

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
  final openSurface = ref.read(askAiSurfaceProvider);
  if (intent == null) {
    return openSurface(context, prefill: prefill);
  }
  final aiCtx = ref.read(aiContextProvider);
  final domain = (aiCtx.domain ?? DomainScope.finance).wire;
  return openSurface(
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
