/// Intent registry (governance for intent strings).
///
/// Without a registry the codebase ends up with 50 intent strings, half
/// of them dead. Mirror the `tool_policy.rs` pattern: descriptors are a
/// static const list, validated at startup, with code review enforcing
/// "new capsule → new intent → new entry here".
///
/// Each descriptor declares which object types the intent applies to
/// and which prompt template to render. Capsules + invocation surfaces
/// look up the descriptor at trigger time to derive the rendered
/// prompt; off-registry intents fall back to the caller's
/// `suggestedPrompt` and `assert(false)` in dev.
library;

import '../../../l10n/gen/app_localizations.dart';
import 'ai_intent_invocation.dart';

class IntentCopy {
  const IntentCopy({required this.label, required this.promptTemplate});

  final String label;
  final String promptTemplate;
}

typedef IntentCopyResolver = IntentCopy Function(IntentDescriptor desc);

IntentCopy fallbackIntentCopy(IntentDescriptor desc) =>
    IntentCopy(label: desc.name, promptTemplate: 'Analyze {{object_label}}.');

IntentCopyResolver localizedIntentCopyResolver(AppLocalizations l10n) {
  return (desc) => switch (desc.name) {
    'explain_change' => IntentCopy(
      label: l10n.aiIntentExplainChangeLabel,
      promptTemplate: l10n.aiIntentExplainChangePrompt(
        _objectLabelToken,
        _timeframeToken,
      ),
    ),
    'summarize_account' => IntentCopy(
      label: l10n.aiIntentSummarizeAccountLabel,
      promptTemplate: l10n.aiIntentSummarizeAccountPrompt(
        _objectLabelToken,
        _timeframeToken,
      ),
    ),
    'stress_test_plan' => IntentCopy(
      label: l10n.aiIntentStressTestPlanLabel,
      promptTemplate: l10n.aiIntentStressTestPlanPrompt(_objectLabelToken),
    ),
    'compare_period' => IntentCopy(
      label: l10n.aiIntentComparePeriodLabel,
      promptTemplate: l10n.aiIntentComparePeriodPrompt(_objectLabelToken),
    ),
    'explain_insight' => IntentCopy(
      label: l10n.aiIntentExplainInsightLabel,
      promptTemplate: l10n.aiIntentExplainInsightPrompt(_objectLabelToken),
    ),
    'explain_chart' => IntentCopy(
      label: l10n.aiIntentExplainChartLabel,
      promptTemplate: l10n.aiIntentExplainChartPrompt(
        _objectLabelToken,
        _timeframeToken,
      ),
    ),
    'transactions.explainSelection' => IntentCopy(
      label: l10n.aiIntentTransactionsExplainSelectionLabel,
      promptTemplate: l10n.aiIntentTransactionsExplainSelectionPrompt(
        _objectLabelToken,
      ),
    ),
    'explain_fire_state' => IntentCopy(
      label: l10n.aiIntentExplainFireStateLabel,
      promptTemplate: l10n.aiIntentExplainFireStatePrompt(_objectLabelToken),
    ),
    'review_cash_bucket' => IntentCopy(
      label: l10n.aiIntentReviewCashBucketLabel,
      promptTemplate: l10n.aiIntentReviewCashBucketPrompt(_objectLabelToken),
    ),
    'simulate_fire_change' => IntentCopy(
      label: l10n.aiIntentSimulateFireChangeLabel,
      promptTemplate: l10n.aiIntentSimulateFireChangePrompt(_objectLabelToken),
    ),
    'explain_stress_test' => IntentCopy(
      label: l10n.aiIntentExplainStressTestLabel,
      promptTemplate: l10n.aiIntentExplainStressTestPrompt(_objectLabelToken),
    ),
    'suggest_fire_actions' => IntentCopy(
      label: l10n.aiIntentSuggestFireActionsLabel,
      promptTemplate: l10n.aiIntentSuggestFireActionsPrompt,
    ),
    _ => fallbackIntentCopy(desc),
  };
}

String localizedIntentLabel(AppLocalizations l10n, IntentDescriptor? desc) =>
    desc == null ? 'AI' : localizedIntentCopyResolver(l10n)(desc).label;

const String _objectLabelToken = '{{object_label}}';
const String _timeframeToken = '{{timeframe}}';
const String _currencyToken = '{{currency}}';

class IntentDescriptor {
  const IntentDescriptor({
    required this.name,
    required this.allowedObjectTypes,
    required this.preferredCapabilities,
    this.preferredReadModels = const <String>[],
    this.requiresExplicitConfirmation = false,
    this.domain = 'finance',
    this.allowedDomains = const <String>{},
  });

  /// Stable identifier — `'explain_change'`, never renamed.
  final String name;

  /// Home LifeOS domain this intent belongs to (trace attribution +
  /// the default surface). Phase D-1.3 default `finance`.
  final String domain;

  /// Extra domains this intent is *also* valid in, beyond [domain]. Set
  /// this for genuinely cross-cutting intents (e.g. a "correlate spend ×
  /// sleep" intent valid from both a finance and a health surface) so a
  /// trigger on either domain's page is accepted. Empty = single-domain
  /// (just [domain]). The effective set is [domains].
  final Set<String> allowedDomains;

  /// Which `AiObjectRef.type` values may use this intent. Empty set
  /// means "object-less / abstract intent".
  final Set<String> allowedObjectTypes;

  /// Hint to the bottom sheet shell about what affordances to render.
  /// The shell may add `chat` regardless.
  final Set<AiCapability> preferredCapabilities;

  /// Read models this intent typically consults. Kept as a lightweight
  /// hint for context preparation and future freshness diagnostics;
  /// empty means no hint.
  final List<String> preferredReadModels;

  /// §5.10.6 — irreversible-operation guard. When `true`, surfaces that
  /// could trigger this intent (command palette overlay, inline capsule
  /// auto-actions) **must not** execute it without an explicit
  /// confirmation sheet. The rule is enforced at the call site (command
  /// palette / capsule dispatcher); AI surfaces never short-circuit a
  /// transfer / order / delete via natural language.
  ///
  /// Reach for this on any intent whose side effect is not safely
  /// undoable through [DriftUndoStack]: external API calls, cross-account
  /// transfers, account deletion, broker order placement.
  final bool requiresExplicitConfirmation;

  /// Full set of domains this intent may be triggered from = [domain]
  /// plus [allowedDomains]. Single-domain intents resolve to `{domain}`.
  Set<String> get domains => <String>{domain, ...allowedDomains};
}

/// Whether [desc] may be triggered from [domain]. Cross-domain intents
/// (those declaring [IntentDescriptor.allowedDomains]) accept any of
/// their domains; single-domain intents accept only their home [domain].
bool intentAllowsDomain(IntentDescriptor desc, String domain) =>
    desc.domains.contains(domain);

const intentDescriptors = <IntentDescriptor>[
  IntentDescriptor(
    name: 'explain_change',
    allowedObjectTypes: <String>{
      'expense',
      'recurring_pattern',
      'asset',
      'liability',
      'account',
    },
    preferredCapabilities: <AiCapability>{
      AiCapability.chat,
      AiCapability.visualization,
    },
    preferredReadModels: <String>[
      'subscription_changes',
      'recurring_patterns',
      'cashflow_buckets',
    ],
  ),
  IntentDescriptor(
    name: 'summarize_account',
    allowedObjectTypes: <String>{'account'},
    preferredCapabilities: <AiCapability>{
      AiCapability.chat,
      AiCapability.visualization,
    },
    preferredReadModels: <String>[
      'holdings_snapshot',
      'cashflow_buckets',
      'investment_performance',
    ],
  ),
  IntentDescriptor(
    name: 'stress_test_plan',
    allowedObjectTypes: <String>{'fire_plan'},
    preferredCapabilities: <AiCapability>{
      AiCapability.chat,
      AiCapability.proposal,
    },
    preferredReadModels: <String>[
      'net_worth_snapshot',
      'holdings_snapshot',
      'investment_performance',
    ],
  ),
  IntentDescriptor(
    name: 'compare_period',
    allowedObjectTypes: <String>{
      'expense',
      'account',
      'asset',
      'recurring_pattern',
    },
    preferredCapabilities: <AiCapability>{
      AiCapability.chat,
      AiCapability.visualization,
    },
    preferredReadModels: <String>['cashflow_buckets'],
  ),
  IntentDescriptor(
    name: 'explain_insight',
    allowedObjectTypes: <String>{'insight'},
    preferredCapabilities: <AiCapability>{
      AiCapability.chat,
      AiCapability.proposal,
    },
    preferredReadModels: <String>[
      'anomaly_flags',
      'subscription_changes',
      'refund_links',
    ],
  ),
  IntentDescriptor(
    name: 'explain_chart',
    // Charts are abstract — they don't carry a stable AiObjectRef of
    // their own. Allowed types stays empty so any chart-bearing
    // surface can pass an `AiObjectRef(type: 'chart', id: '<chart>')`
    // without tripping the registry's type-mismatch assertion.
    allowedObjectTypes: <String>{'chart'},
    preferredCapabilities: <AiCapability>{
      AiCapability.chat,
      AiCapability.visualization,
    },
    preferredReadModels: <String>[
      'net_worth_snapshot',
      'cashflow_buckets',
      'holdings_snapshot',
    ],
  ),
  IntentDescriptor(
    name: 'transactions.explainSelection',
    allowedObjectTypes: <String>{'transactions'},
    preferredCapabilities: <AiCapability>{
      AiCapability.chat,
      AiCapability.visualization,
    },
    preferredReadModels: <String>[
      'cashflow_buckets',
      'subscription_changes',
      'refund_links',
    ],
  ),
  // FIRE OS Phase 5 intents — explain / suggest / simulate / propose.
  IntentDescriptor(
    name: 'explain_fire_state',
    allowedObjectTypes: <String>{'fire_state', 'fire_plan'},
    preferredCapabilities: <AiCapability>{
      AiCapability.chat,
      AiCapability.visualization,
    },
    preferredReadModels: <String>[
      'fire_state',
      'net_worth_snapshot',
      'cashflow_buckets',
    ],
  ),
  IntentDescriptor(
    name: 'review_cash_bucket',
    allowedObjectTypes: <String>{'fire_state', 'fire_plan'},
    preferredCapabilities: <AiCapability>{
      AiCapability.chat,
      AiCapability.proposal,
    },
    preferredReadModels: <String>['fire_state', 'fire_buckets'],
  ),
  IntentDescriptor(
    name: 'simulate_fire_change',
    allowedObjectTypes: <String>{'fire_plan', 'fire_state'},
    preferredCapabilities: <AiCapability>{
      AiCapability.chat,
      AiCapability.visualization,
    },
    // `simulate_fire_plan` does not start with `get_` so the corpus
    // normaliser does not strip it; list it verbatim.
    preferredReadModels: <String>[
      'fire_state',
      'fire_plan',
      'simulate_fire_plan',
    ],
  ),
  IntentDescriptor(
    name: 'explain_stress_test',
    allowedObjectTypes: <String>{'fire_state', 'fire_plan'},
    preferredCapabilities: <AiCapability>{
      AiCapability.chat,
      AiCapability.visualization,
    },
    preferredReadModels: <String>['fire_state', 'fire_stress_tests'],
  ),
  IntentDescriptor(
    name: 'suggest_fire_actions',
    allowedObjectTypes: <String>{'fire_state', 'fire_plan'},
    preferredCapabilities: <AiCapability>{
      AiCapability.chat,
      AiCapability.proposal,
    },
    preferredReadModels: <String>[
      'fire_state',
      'fire_buckets',
      'fire_stress_tests',
    ],
  ),
];

/// Lookup by intent name. Returns `null` for off-registry strings —
/// callers should `assert(false)` in dev and use `suggestedPrompt`.
IntentDescriptor? lookupIntent(String name) {
  for (final d in intentDescriptors) {
    if (d.name == name) return d;
  }
  return null;
}

/// Render the prompt for an invocation. Returns the registered template
/// with placeholders filled (best-effort) when the intent is on
/// registry; otherwise returns [AiIntentInvocation.suggestedPrompt] or
/// a generic fallback.
String renderPromptFor(
  AiIntentInvocation invocation, {
  String? objectLabel,
  String? defaultTimeframe,
  String? defaultCurrency,
  IntentCopyResolver? copyResolver,
  String? fallbackObjectLabel,
  String? fallbackPromptTemplate,
}) {
  final desc = lookupIntent(invocation.intent);
  if (desc == null) {
    assert(
      false,
      'AiIntentInvocation uses unregistered intent "${invocation.intent}". '
      'Add to intent_policy.intentDescriptors or use suggestedPrompt.',
    );
    final label = objectLabel ?? fallbackObjectLabel ?? 'current object';
    return invocation.suggestedPrompt ??
        (fallbackPromptTemplate ?? 'Analyze {{object_label}}.').replaceAll(
          _objectLabelToken,
          label,
        );
  }
  if (invocation.object != null &&
      desc.allowedObjectTypes.isNotEmpty &&
      !desc.allowedObjectTypes.contains(invocation.object!.type)) {
    assert(
      false,
      'Intent "${invocation.intent}" does not allow object type '
      '"${invocation.object!.type}" (allowed: ${desc.allowedObjectTypes}).',
    );
  }
  // Domain guard (dev-only, mirrors the object-type assert): a surface
  // must trigger an intent only from a domain the intent declares. A
  // failure here flags a mis-wired call site — either the surface set
  // the wrong domain, or the intent needs `allowedDomains` widened.
  assert(
    intentAllowsDomain(desc, invocation.domain),
    'Intent "${invocation.intent}" triggered from domain '
    '"${invocation.domain}" but only allows ${desc.domains}.',
  );
  final timeframe =
      (invocation.context['timeframe'] as String?) ??
      defaultTimeframe ??
      'recent period';
  final currency =
      (invocation.context['currency'] as String?) ?? defaultCurrency ?? 'USD';
  final label =
      objectLabel ?? invocation.object?.toString() ?? 'current object';
  final copy = (copyResolver ?? fallbackIntentCopy)(desc);
  return copy.promptTemplate
      .replaceAll(_objectLabelToken, label)
      .replaceAll(_timeframeToken, timeframe)
      .replaceAll(_currencyToken, currency);
}
