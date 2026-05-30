/// Contradiction-judge seam (`docs/knowledgeos-domain.md` §7 + §14.2
/// "ContradictionAgent cosine + LLM judge 路径").
///
/// The [ContradictionAgent]'s check-2 (principle ↔ recent-memory drift)
/// finds *candidate* pairs with a cosine pre-filter, then delegates the
/// final yes/no call to a [ContradictionJudge]. Two implementations
/// exist, mirroring the inbox-triage / capture-classifier layering:
///
/// - [HeuristicContradictionJudge] — the pure-Dart, dependency-free
///   baseline. It owns the original marker-token logic verbatim (moved
///   here from the agent, behaviour-preserving) and is the safe fallback
///   when no LLM is configured or the LLM round-trip fails.
/// - The LLM-backed implementation lives in `llm_contradiction_judge.dart`
///   so this file stays free of network / provider imports. It degrades
///   to the heuristic on *any* failure, so the no-LLM (Web / no key) path
///   stays deterministic.
///
/// `judge` is async so both paths share the same shape; the heuristic
/// returns synchronously inside the future. Returning a [ContradictionVerdict]
/// (not the persisted flag) keeps the judge pure — the agent owns the
/// `_ContradictionFlag` envelope + the memory write.
library;

/// A judge's verdict on one (principle, memory-text) candidate pair.
class ContradictionVerdict {
  const ContradictionVerdict({
    required this.isContradiction,
    required this.confidence,
    required this.reasonZh,
  });

  /// Behaviour-preserving "no genuine contradiction" verdict.
  const ContradictionVerdict.none()
    : isContradiction = false,
      confidence = 0.0,
      reasonZh = '';

  /// True when the memory genuinely contradicts the principle (value /
  /// fact drift), not a mere mention / restatement / unrelated text.
  final bool isContradiction;

  /// 0..1 self-reported confidence. The agent gates on >= 0.6.
  final double confidence;

  /// One-sentence Chinese rationale, surfaced as the flag detail.
  final String reasonZh;
}

/// Common interface so the agent can swap heuristic ↔ LLM without
/// touching its candidate-finding loop or the memory write.
abstract class ContradictionJudge {
  /// Decide whether [memoryText] (a recent decision / note's indexed
  /// title+summary) genuinely contradicts [principleStatement].
  Future<ContradictionVerdict> judge({
    required String principleStatement,
    required String memoryText,
  });
}

/// Deterministic pure-Dart judge — the original marker-token logic,
/// preserved verbatim from the agent. Stateless, so a single `const`
/// instance can be shared everywhere and used as the LLM judge's
/// fallback so the LLM path degrades to the exact same verdict.
class HeuristicContradictionJudge implements ContradictionJudge {
  const HeuristicContradictionJudge();

  /// Negation / avoidance markers that, when they co-occur with a
  /// principle reference, flagged a mismatch in the original agent.
  static const List<String> kContradictionMarkers = <String>[
    '违反',
    '冲突',
    'counter',
    'violate',
    'avoid',
    '规避',
  ];

  @override
  Future<ContradictionVerdict> judge({
    required String principleStatement,
    required String memoryText,
  }) async {
    return verdict(
      principleStatement: principleStatement,
      memoryText: memoryText,
    );
  }

  /// Synchronous entry point — also used by [LlmContradictionJudge] as
  /// its fallback so the LLM path degrades to the exact same verdict.
  static ContradictionVerdict verdict({
    required String principleStatement,
    required String memoryText,
  }) {
    final lower = memoryText.toLowerCase();
    for (final marker in kContradictionMarkers) {
      if (lower.contains(marker)) {
        return ContradictionVerdict(
          isContradiction: true,
          // Marker heuristic is a weak signal — sit it right at the gate
          // so it counts as a flag but never outranks an LLM verdict.
          confidence: 0.6,
          reasonZh:
              '内容提到 active principle "$principleStatement",'
              '但同时出现否定/规避词("$marker")。',
        );
      }
    }
    return const ContradictionVerdict.none();
  }
}
