/// Wave 33 — `AiIntentInvocation`: the single entry point for *all*
/// AI surfaces.
///
/// Every site that triggers AI — capsule, command palette, home insight
/// tap, future voice / drag-to-AI — **must** construct an
/// [AiIntentInvocation] and route through [showAiBottomSheet]. Direct
/// `Navigator.push(ChatPage(...))` style is forbidden by the §5.8
/// hard-constraint checklist.
///
/// The invocation captures *intent semantics* (what does the user want?
/// what object are they looking at?) rather than UI specifics (where
/// does the answer render?). Surface choice (bottom sheet vs full
/// chat) is decided downstream from [capabilities] + viewport.
library;

class AiIntentInvocation {
  const AiIntentInvocation({
    required this.source,
    required this.intent,
    this.object,
    this.context = const <String, Object?>{},
    this.suggestedPrompt,
    this.capabilities = const <AiCapability>{
      AiCapability.chat,
      AiCapability.proposal,
      AiCapability.visualization,
    },
  });

  /// Free-form tag for the trigger location — `'expense_detail'`,
  /// `'home_insight_card'`, `'command_palette'`. Used for AiTrace
  /// attribution and for analytics.
  final String source;

  /// Registered intent name (see `intent_policy.dart`). Off-registry
  /// invocations fall back to [suggestedPrompt] but emit a dev assert.
  final String intent;

  /// Optional business object being asked about. Mostly required —
  /// only abstract intents like "generic_help" can omit it.
  final AiObjectRef? object;

  /// Extra ContextPack signals attached to this invocation (e.g.
  /// `timeframe: '30d'`, related account ids). Forwarded to the cloud
  /// in ContextPack.task.invocation_context (Wave 33+).
  final Map<String, Object?> context;

  /// Override copy used when the registered intent's `promptTemplate`
  /// can't be filled (missing object, intent off-registry). Plain
  /// Chinese is fine.
  final String? suggestedPrompt;

  /// Capabilities the *surface* may need. The bottom sheet shell uses
  /// this to gate UI affordances (don't reserve viz space if the
  /// intent never asks for charts).
  final Set<AiCapability> capabilities;

  /// Serialised form for AiTrace — local-only, never crosses the wire
  /// unaltered. Keys are stable so the transparency page can render.
  Map<String, Object?> toTraceJson() => <String, Object?>{
    'source': source,
    'intent': intent,
    if (object != null) ...{
      'object_type': object!.type,
      'object_id': object!.id,
    },
    if (context.isNotEmpty) 'context_keys': context.keys.toList(),
  };
}

class AiObjectRef {
  const AiObjectRef({required this.type, required this.id});

  /// Stable type discriminator: `'expense'`, `'account'`, `'asset'`,
  /// `'liability'`, `'fire_plan'`, `'insight'`, `'recurring_pattern'`,
  /// etc. The registry uses this to validate intent×object pairs.
  final String type;

  /// Domain id (expense.id / account.id / insight composite key).
  final String id;

  @override
  bool operator ==(Object other) =>
      other is AiObjectRef && other.type == type && other.id == id;

  @override
  int get hashCode => Object.hash(type, id);

  @override
  String toString() => '$type:$id';
}

/// Which capabilities a surface is willing to host. Lets the shell
/// reserve / collapse space deterministically.
enum AiCapability {
  /// Streaming text answer (the always-on default).
  chat,
  /// Inline `propose_*` cards (CloudProposal / LocalProposal).
  proposal,
  /// Domain-specific visualisations (Wave 34 renderers).
  visualization,
  /// Reserved for Wave 36+ voice follow-up button.
  voiceFollowup,
}
