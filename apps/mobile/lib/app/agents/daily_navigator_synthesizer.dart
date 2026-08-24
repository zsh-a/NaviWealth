/// Cross-domain synthesis for the app-owned Daily Navigator.
library;

import 'dart:async';
import 'dart:convert';

import '../../core/ai/runtime/agent_runtime/agent_runtime_profile_turn.dart';
import '../../core/lifeos/life_context.dart';
import '../../core/lifeos/life_signal.dart';
import '../../features/life/ui/life_event_l10n.dart';
import '../../l10n/gen/app_localizations.dart';

enum DailyNavigatorSynthesisSource { programmatic, llm }

class DailyNavigatorDecision {
  const DailyNavigatorDecision({required this.signals});

  final List<LifeEvent> signals;

  LifeEvent get primary => signals.first;

  Map<String, Object?> materialJson(
    LifeContextSnapshot context,
  ) => <String, Object?>{
    'signals': [
      for (final signal in signals)
        <String, Object?>{
          'id': signal.id,
          'domain': signal.domain.wire,
          'template': signal.template.name,
          'params': signal.params,
          'priority': signal.priority.name,
          'evidence': [for (final source in signal.evidence) source.toJson()],
        },
    ],
    'confirmed_constraint_ids': [
      for (final constraint in context.constraints) constraint.id,
    ],
  };
}

DailyNavigatorDecision? evaluateDailyNavigatorContext(
  LifeContextSnapshot context,
) {
  final activeDomains = context.activeDomains.toSet();
  final freshDomains = <String>{
    for (final state in context.domainStates)
      if (activeDomains.contains(state.domain) &&
          state.freshness == LifeContextFreshness.fresh)
        state.domain.wire,
  };
  final signals =
      <LifeEvent>[
        for (final state in context.domainStates)
          for (final signal in state.signals)
            if (freshDomains.contains(signal.domain.wire) &&
                signal.priority == LifeSignalPriority.high &&
                signal.evidence.isNotEmpty)
              signal,
      ]..sort((a, b) {
        final rank = _signalRank(a).compareTo(_signalRank(b));
        return rank != 0 ? rank : a.id.compareTo(b.id);
      });
  if (signals.isEmpty) return null;
  return DailyNavigatorDecision(
    signals: List<LifeEvent>.unmodifiable(signals.take(3)),
  );
}

int _signalRank(LifeEvent signal) => switch (signal.template) {
  LifeEventTemplate.recoveryAlert => 0,
  LifeEventTemplate.executionBlocked => 1,
  LifeEventTemplate.financeBudgetPressure => 2,
  LifeEventTemplate.executionDue => 3,
  LifeEventTemplate.knowledgeInbox => 4,
  LifeEventTemplate.financeDaySummary => 5,
};

class DailyNavigatorOutput {
  const DailyNavigatorOutput({
    required this.summary,
    required this.recommendation,
    this.source = DailyNavigatorSynthesisSource.programmatic,
    this.traceId,
  });

  final String summary;
  final String recommendation;
  final DailyNavigatorSynthesisSource source;
  final String? traceId;
}

abstract interface class DailyNavigatorSynthesizer {
  Future<DailyNavigatorOutput> synthesize({
    required LifeContextSnapshot context,
    required DailyNavigatorDecision decision,
    required AppLocalizations l10n,
  });
}

class ProgrammaticDailyNavigatorSynthesizer
    implements DailyNavigatorSynthesizer {
  const ProgrammaticDailyNavigatorSynthesizer();

  @override
  Future<DailyNavigatorOutput> synthesize({
    required LifeContextSnapshot context,
    required DailyNavigatorDecision decision,
    required AppLocalizations l10n,
  }) async {
    final lines = <String>[
      for (final signal in decision.signals)
        '${signal.localizedTitle(l10n)} ${signal.localizedSubtitle(l10n)}',
    ];
    final primary = decision.primary;
    return DailyNavigatorOutput(
      summary: lines.join(' '),
      recommendation:
          primary.localizedActionTitle(l10n) ?? primary.localizedTitle(l10n),
    );
  }
}

class FrbDailyNavigatorSynthesizer implements DailyNavigatorSynthesizer {
  const FrbDailyNavigatorSynthesizer({
    required this.runtime,
    this.fallback = const ProgrammaticDailyNavigatorSynthesizer(),
    this.maxTokens = 4096,
    this.requestTimeout = const Duration(seconds: 45),
  });

  final AgentRuntimeProfileTurnBinding runtime;
  final DailyNavigatorSynthesizer fallback;
  final int maxTokens;
  final Duration requestTimeout;

  @override
  Future<DailyNavigatorOutput> synthesize({
    required LifeContextSnapshot context,
    required DailyNavigatorDecision decision,
    required AppLocalizations l10n,
  }) async {
    final baseline = await fallback.synthesize(
      context: context,
      decision: decision,
      l10n: l10n,
    );
    try {
      final result = await runtime
          .run(
            messages: <Map<String, Object?>>[
              const <String, Object?>{
                'role': 'system',
                'content':
                    'You are NaviWealth Daily Navigator. Correlate only the '
                    'provided fresh signals. Do not diagnose, recalculate '
                    'domain metrics, invent facts, or propose a direct write. '
                    'Return one concise judgment in the user language.',
              },
              <String, Object?>{
                'role': 'user',
                'content': jsonEncode(<String, Object?>{
                  'deterministic_baseline': baseline.summary,
                  'decision': decision.materialJson(context),
                  'profile_constraints': [
                    for (final constraint in context.constraints)
                      constraint.toJson(),
                  ],
                }),
              },
            ],
            maxOutputTokens: maxTokens,
            metadata: <String, Object?>{
              'life_context_fingerprint': context.fingerprint,
            },
            maxEffectSteps: 0,
          )
          .timeout(requestTimeout);
      final text = result.llmResponse['content']?.toString().trim();
      if (text == null || text.isEmpty) return baseline;
      return DailyNavigatorOutput(
        summary: text,
        recommendation: baseline.recommendation,
        source: DailyNavigatorSynthesisSource.llm,
        traceId: result.traceId,
      );
    } on Object {
      return baseline;
    }
  }
}
