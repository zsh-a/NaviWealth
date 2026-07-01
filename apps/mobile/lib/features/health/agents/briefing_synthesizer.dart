/// Morning Briefing synthesis seam (`docs/domains/healthos-domain.md` §8,
/// D-2.5 + D-2.5b).
///
/// Production implementations:
///
///  * [ProgrammaticBriefingSynthesizer] — pure-Dart, deterministic.
///    Wraps the original D-2.5 static logic; what tests assert against
///    and the safe fallback when FRB/profile is unavailable.
///  * [FrbBriefingSynthesizer] — calls the user's configured device
///    LLM through the FRB agent runtime profile-turn seam.
///
/// The agent stays composition-blind: it takes a [BriefingSynthesizer]
/// and asks for `synthesize(events, …)`. Bootstrap picks which
/// implementation to inject (FRB profile-turn when available, programmatic
/// otherwise).
library;

import '../../../app/agent_runtime_profile_turn_binding.dart';
import '../../../core/ai/contracts/event_record.dart';
import '../data/health_metric_memory_indexer.dart';

/// Inputs to a single synthesis call. The agent pre-partitions events
/// so each synthesizer can stay shape-blind to the event log.
class BriefingInputs {
  const BriefingInputs({
    required this.dayKey,
    required this.healthEvents,
    required this.financeEvents,
  });

  /// `yyyy-MM-dd` of the briefing's anchor day (local). Used by the
  /// LLM prompt header and as a back-pointer in tests.
  final String dayKey;
  final List<EventRecord> healthEvents;
  final List<EventRecord> financeEvents;

  bool get hasHealthSignals => healthEvents.isNotEmpty;
}

/// Output of one synthesis call.
class BriefingOutput {
  const BriefingOutput({
    required this.summary,
    this.sleepLine,
    this.hrvLine,
    this.financeLine,
    this.source = BriefingSource.programmatic,
  });

  /// Empty-summary sentinel — caller treats this as "no usable signals"
  /// and skips writing a memory record.
  factory BriefingOutput.empty() =>
      const BriefingOutput(summary: '', source: BriefingSource.programmatic);

  /// Single-line summary string to embed in the memory `summary` field
  /// and on the notification body.
  final String summary;

  /// Component lines kept around for the agent's `outcome` payload and
  /// for the LLM prompt's structured input. `null` when the kind had
  /// no signal in the window.
  final String? sleepLine;
  final String? hrvLine;
  final String? financeLine;

  /// Which synthesizer produced this output. The agent stamps it into
  /// the memory `outcome` payload so a future "which synth" UI can
  /// surface it without re-running.
  final BriefingSource source;

  bool get isEmpty => summary.isEmpty;
}

enum BriefingSource { programmatic, llm }

abstract class BriefingSynthesizer {
  Future<BriefingOutput> synthesize(BriefingInputs inputs);
}

const String _kBriefingSystemPrompt =
    'You are HealthOS Morning Briefing. Given structured Health + '
    'Finance signals from the last 24 hours, write a single-sentence '
    'morning briefing in the user\'s tone (short, calm, factual). '
    'Use only the numbers provided. Do not add advice unless the '
    'numbers are clearly outliers. Reply in the same language the '
    'inputs are in (Chinese or English).';

/// Deterministic fallback. Replicates the D-2.5 logic verbatim so the
/// existing tests still pin behaviour.
class ProgrammaticBriefingSynthesizer implements BriefingSynthesizer {
  const ProgrammaticBriefingSynthesizer();

  @override
  Future<BriefingOutput> synthesize(BriefingInputs inputs) async {
    final sleepLine = _summariseSleep(inputs.healthEvents);
    final hrvLine = _summariseHrv(inputs.healthEvents);
    final financeLine = _summariseFinance(inputs.financeEvents);

    final parts = <String>[?sleepLine, ?hrvLine, ?financeLine];
    if (parts.isEmpty) return BriefingOutput.empty();
    return BriefingOutput(
      summary: parts.join(' · '),
      sleepLine: sleepLine,
      hrvLine: hrvLine,
      financeLine: financeLine,
    );
  }

  static String? _summariseSleep(List<EventRecord> healthEvents) {
    EventRecord? latest;
    for (final e in healthEvents) {
      if (e.type != kEventSleepSessionEnded) continue;
      if (latest == null || e.timestamp.isAfter(latest.timestamp)) {
        latest = e;
      }
    }
    if (latest == null) return null;
    final value = latest.payload['value'];
    final unit = latest.payload['unit'];
    if (value is! num) return null;
    final hours = switch (unit) {
      's' => value / 3600.0,
      'min' => value / 60.0,
      'h' => value.toDouble(),
      _ => value / 3600.0,
    };
    final rounded = (hours * 10).round() / 10.0;
    final tag = latest.entities.contains('short_sleep')
        ? ' (short)'
        : latest.entities.contains('long_sleep')
        ? ' (long)'
        : '';
    return 'Slept ${rounded}h$tag';
  }

  static String? _summariseHrv(List<EventRecord> healthEvents) {
    EventRecord? latest;
    for (final e in healthEvents) {
      if (e.type != kEventHrvRecorded) continue;
      if (latest == null || e.timestamp.isAfter(latest.timestamp)) {
        latest = e;
      }
    }
    if (latest == null) return null;
    final value = latest.payload['value'];
    if (value is! num) return null;
    return 'HRV ${value.toStringAsFixed(0)}ms';
  }

  static String? _summariseFinance(List<EventRecord> financeEvents) {
    if (financeEvents.isEmpty) return null;
    final byType = <String, int>{};
    for (final e in financeEvents) {
      byType[e.type] = (byType[e.type] ?? 0) + 1;
    }
    final pieces = <String>[];
    byType.forEach((type, count) {
      pieces.add('$count ${type.replaceAll('_', ' ')}');
    });
    return 'Finance: ${pieces.join(', ')}';
  }
}

/// FRB-backed synthesis for the first production agent migration onto the
/// embedded Rust agent-runtime path. The native side owns LLM profile
/// completion + first runtime step; Dart keeps the existing fallback contract.
class FrbBriefingSynthesizer implements BriefingSynthesizer {
  const FrbBriefingSynthesizer({
    required this.runtime,
    this.fallback = const ProgrammaticBriefingSynthesizer(),
    this.maxTokens = 200,
    this.requestTimeout = const Duration(seconds: 20),
  });

  final AgentRuntimeProfileTurnBinding runtime;
  final BriefingSynthesizer fallback;
  final int maxTokens;
  final Duration requestTimeout;

  @override
  Future<BriefingOutput> synthesize(BriefingInputs inputs) async {
    final baseline = await fallback.synthesize(inputs);
    if (baseline.isEmpty) return baseline;
    try {
      final prompt = _buildBriefingPrompt(inputs, baseline);
      final result = await runtime
          .run(
            messages: <Map<String, Object?>>[
              const <String, Object?>{
                'role': 'system',
                'content': _kBriefingSystemPrompt,
              },
              <String, Object?>{'role': 'user', 'content': prompt},
            ],
            maxOutputTokens: maxTokens,
            metadata: <String, Object?>{'day_key': inputs.dayKey},
            maxToolSteps: 0,
          )
          .timeout(requestTimeout);
      final text = result.llmResponse['content']?.toString().trim();
      if (text == null || text.isEmpty) return baseline;
      return BriefingOutput(
        summary: text,
        sleepLine: baseline.sleepLine,
        hrvLine: baseline.hrvLine,
        financeLine: baseline.financeLine,
        source: BriefingSource.llm,
      );
    } on Object {
      return baseline;
    }
  }
}

String _buildBriefingPrompt(BriefingInputs inputs, BriefingOutput baseline) {
  final buf = StringBuffer()
    ..writeln('Date: ${inputs.dayKey}')
    ..writeln('---')
    ..writeln(
      'Structured signals (use these numbers verbatim, do not change them):',
    );
  if (baseline.sleepLine != null) buf.writeln('- ${baseline.sleepLine}');
  if (baseline.hrvLine != null) buf.writeln('- ${baseline.hrvLine}');
  if (baseline.financeLine != null) buf.writeln('- ${baseline.financeLine}');
  buf
    ..writeln('---')
    ..writeln(
      'Write one calm, factual sentence (<= 30 words) that mentions '
      'each signal. No bullet points. No emojis.',
    );
  return buf.toString();
}
