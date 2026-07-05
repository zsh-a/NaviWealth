/// Intent contracts (governance for intent strings).
///
/// Without a catalog the codebase ends up with 50 intent strings, half
/// of them dead. Mirror the tool descriptor pattern: core defines the
/// descriptor contract and each domain contributes its concrete intent
/// list through DomainPack composition.
///
/// Each descriptor declares which object types the intent applies to
/// and which prompt template to render. Capsules + invocation surfaces
/// look up the descriptor at trigger time to derive the rendered
/// prompt; off-registry intents fall back to the caller's
/// `suggestedPrompt` and `assert(false)` in dev.
library;

import '../../../l10n/gen/app_localizations.dart';
import '../contracts/intent.dart' show kDomainFinance;
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
    'agent.explainResult' => const IntentCopy(
      label: 'Explain result',
      promptTemplate:
          'Explain {{object_label}}, summarize the evidence, and call out any caveats.',
    ),
    'finance.reviewWealth' => const IntentCopy(
      label: 'Review wealth',
      promptTemplate:
          'Review {{object_label}} with the attached net-worth, allocation, price freshness, and FX evidence.',
    ),
    'knowledge.reviewDueItems' => const IntentCopy(
      label: 'Review knowledge items',
      promptTemplate:
          'Review {{object_label}} and help prioritize the due decisions and stale assumptions.',
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
    this.domain = kDomainFinance,
    this.allowedDomains = const <String>{},
  });

  /// Stable identifier — `'explain_change'`, never renamed.
  final String name;

  /// Home LifeOS domain this intent belongs to (trace attribution +
  /// the default surface). Defaults to Finance for legacy descriptors
  /// that predate explicit domain registration.
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
  /// hint for context preparation, regression corpus checks, and UI
  /// affordance selection; empty means no hint.
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

class IntentCatalog {
  const IntentCatalog(this.descriptors);

  static const empty = IntentCatalog(<IntentDescriptor>[]);

  final List<IntentDescriptor> descriptors;

  IntentDescriptor? lookup(String name) {
    for (final d in descriptors) {
      if (d.name == name) return d;
    }
    return null;
  }
}

/// Lookup by intent name. Returns `null` for off-registry strings —
/// callers should `assert(false)` in dev and use `suggestedPrompt`.
IntentDescriptor? lookupIntent(
  String name, {
  IntentCatalog catalog = IntentCatalog.empty,
}) => catalog.lookup(name);

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
  IntentCatalog catalog = IntentCatalog.empty,
  String? fallbackObjectLabel,
  String? fallbackPromptTemplate,
}) {
  final desc = lookupIntent(invocation.intent, catalog: catalog);
  if (desc == null) {
    assert(
      false,
      'AiIntentInvocation uses unregistered intent "${invocation.intent}". '
      'Add it to the owning DomainPack intent catalog or use suggestedPrompt.',
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
