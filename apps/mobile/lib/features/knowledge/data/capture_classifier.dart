/// Capture classifier interface + pure-Dart heuristic
/// (`docs/knowledgeos-domain.md` §3 + §4 + §14.2 P1).
///
/// Two-step layering matches the InboxTriageAgent pattern:
///
/// - [HeuristicCaptureClassifier] — deterministic, dependency-free.
///   The safe fallback when no LLM is configured and the structural
///   baseline the LLM classifier can degrade to on any failure.
/// - The LLM-driven implementation lives in
///   `llm_capture_classifier.dart` so this file stays free of network
///   / provider imports. Both implement [CaptureClassifier].
///
/// `classify` is async so the LLM path is the same shape; the
/// heuristic returns synchronously inside the future.
library;

import '../domain/knowledge_text.dart';
import 'capture_kind.dart';

class CaptureClassification {
  CaptureClassification({
    required this.kind,
    required this.confidence,
    required this.reasonZh,
    this.intervalDays,
    this.scope,
    this.statement,
    this.polishedTitle,
    this.polishedBody,
  });

  /// `note` is the default fallback — the caller should *not* prompt
  /// the user when this comes back **unless** a polish suggestion is
  /// present; the sheet uses [hasSuggestion] to decide whether to
  /// surface the inline card at all.
  final CaptureKind kind;
  final double confidence;
  final String reasonZh;

  // Kind-specific extracted fields. The heuristic only fills these for
  // routines; the LLM may fill them for any kind it confidently
  // matches.
  final int? intervalDays;
  final String? scope;
  final String? statement;

  /// Optional AI rewrite of the user's title / body. Same meaning, just
  /// clearer / fixes typos / restructures Markdown. The LLM populates
  /// these when it sees room to improve; the heuristic leaves them
  /// null. Empty / whitespace-only strings are normalised to null at
  /// the parse boundary so the sheet can rely on `!= null` as the
  /// "polish exists" gate.
  final String? polishedTitle;
  final String? polishedBody;

  bool get isUpgrade => kind != CaptureKind.note;

  bool get hasPolish =>
      (polishedTitle != null && polishedTitle!.isNotEmpty) ||
      (polishedBody != null && polishedBody!.isNotEmpty);

  /// The sheet enters its suggestion stage when this is true — either
  /// the kind warrants an upgrade, or the polished version differs
  /// enough from the raw input to be worth showing.
  bool get hasSuggestion => isUpgrade || hasPolish;
}

/// Common interface so the Sheet + the `propose_capture` tool can swap
/// heuristic ↔ LLM without changing call sites.
abstract class CaptureClassifier {
  Future<CaptureClassification> classify({required String text});
}

/// Stateless pure-Dart classifier — every call independent so the same
/// instance can be used from anywhere without coordination.
class HeuristicCaptureClassifier implements CaptureClassifier {
  const HeuristicCaptureClassifier();

  @override
  Future<CaptureClassification> classify({required String text}) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      return CaptureClassification(
        kind: CaptureKind.note,
        confidence: 0.0,
        reasonZh: '空输入',
      );
    }
    final routine = _detectRoutine(trimmed);
    if (routine != null) return routine;
    // Other kinds (decision / assumption / principle / concept /
    // experiment) currently fall through to note. The LLM classifier
    // covers them; the heuristic intentionally stays minimal so a
    // user without an LLM profile still gets the routine case
    // (highest-leverage real-world use) without any false positives
    // from naive keyword matching against the other 5 types.
    return CaptureClassification(
      kind: CaptureKind.note,
      confidence: 0.0,
      reasonZh: '未检出特定结构,保留为 Note',
    );
  }

  /// Routine heuristic: surface text patterns that overwhelmingly mean
  /// "recurring user-defined reminder". Anchors are intentionally
  /// conservative — false positives erode trust in the upgrade card.
  CaptureClassification? _detectRoutine(String text) {
    final lower = text.toLowerCase();

    final intervalMatch =
        _everyN.firstMatch(text) ?? _everyMonthDay.firstMatch(text);
    final routineLike = _routineMarkers.hasMatch(lower);

    if (intervalMatch == null && !routineLike) return null;

    int intervalDays;
    String reason;
    if (intervalMatch != null) {
      // `n` may be empty when the input is "每月" / "每个月" / "每年" —
      // implicit single-unit cadence.
      final nText = intervalMatch.namedGroup('n')?.trim() ?? '';
      final raw = int.tryParse(nText) ?? 1;
      final unit = intervalMatch.namedGroup('unit') ?? '';
      intervalDays = switch (unit) {
        '日' || '天' || 'd' => raw,
        '周' || '星期' || 'w' => raw * 7,
        '月' || 'mo' => raw * 30,
        '年' || 'y' => raw * 365,
        _ => raw * 30,
      };
      reason = '检出周期模式 "${intervalMatch.group(0)}"';
    } else {
      intervalDays = 180;
      reason = '检出 "定期 / 活跃 / 续期 / 缴费" 等定期关键词,默认每 6 个月';
    }
    if (intervalDays < 1) intervalDays = 1;
    if (intervalDays > 3650) intervalDays = 3650;

    final statement = _statementFromText(text);
    return CaptureClassification(
      kind: CaptureKind.routine,
      confidence: intervalMatch != null ? 0.85 : 0.65,
      reasonZh: reason,
      intervalDays: intervalDays,
      statement: statement,
      scope: _scopeGuess(lower),
    );
  }

  static String _statementFromText(String text) {
    final line = text
        .split(RegExp(r'[\n。]'))
        .firstWhere((s) => s.trim().isNotEmpty, orElse: () => text);
    final trimmed = line.trim();
    return knowledgeExcerpt(trimmed, max: 60);
  }

  static String? _scopeGuess(String lower) {
    if (lower.contains('港卡') ||
        lower.contains('信用卡') ||
        lower.contains('debit') ||
        lower.contains('信用') && lower.contains('卡')) {
      return 'finance/cards';
    }
    if (lower.contains('税') || lower.contains('报税') || lower.contains('tax')) {
      return 'finance/tax';
    }
    if (lower.contains('定投') ||
        lower.contains('dca') ||
        lower.contains('基金') ||
        lower.contains('rebalance')) {
      return 'finance/investing';
    }
    if (lower.contains('体检') ||
        lower.contains('health') ||
        lower.contains('医院') ||
        lower.contains('hrv')) {
      return 'health';
    }
    return null;
  }

  // "每 6 个月" / "每隔 30 天" / "每 2 周" / "每 90 天" — captures (n, unit).
  // The optional `个` between digit and unit is the common Chinese measure
  // word ("6 个月" reads "six months" with the implicit classifier).
  static final RegExp _everyN = RegExp(
    r'每(?:隔)?\s*(?<n>\d+)\s*个?\s*(?<unit>日|天|周|星期|月|年)',
  );

  // Implicit n=1 cadence: "每月" / "每年" / "每周" / "每天" /
  // "每个月" / "每个星期". The optional `个` after 每 is the Chinese
  // measure word — colloquial Mandarin often inserts it before the
  // time unit even when no explicit count follows.
  static final RegExp _everyMonthDay = RegExp(
    r'每个?(?<n>)(?<unit>日|天|周|星期|月|年)(?!\d)',
  );

  // Routine markers without explicit interval.
  static final RegExp _routineMarkers = RegExp(
    r'(定期|需要.*活跃|需要.*续期|需要.*缴费|每.*提醒|提醒我每|periodically|recurring|every\s+(?:\d+\s+)?(?:months?|years?|weeks?|days?))',
    caseSensitive: false,
  );
}
