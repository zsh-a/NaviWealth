/// Heuristic classifier for unified Capture input
/// (`docs/knowledgeos-domain.md` §3 + §4 + §14.2 P1).
///
/// Pure-Dart, no LLM dependency. Same approach as
/// `InboxTriageAgent._heuristicProposals`: regex / keyword rules over
/// the raw capture text + a single-result envelope. Used by:
///
/// - `propose_capture` device tool (AI surface)
/// - `KnowledgeCaptureSheet` (after-save inline upgrade card)
///
/// LLM-augmented classification replaces the heuristic in the same
/// call sites once the on-device LLM round-trip is plumbed — the public
/// API ([classify]) stays the same so the swap is local.
library;

import 'capture_kind.dart';

class CaptureClassification {
  CaptureClassification({
    required this.kind,
    required this.confidence,
    required this.reasonZh,
    this.intervalDays,
    this.scope,
    this.statement,
  });

  /// `note` is the default fallback — the caller should *not* prompt
  /// the user when this comes back; the saved note is the right
  /// representation as-is.
  final CaptureKind kind;
  final double confidence;
  final String reasonZh;

  // Kind-specific extracted fields. Only routine fills these today;
  // decision / assumption / etc. arrive when their heuristics land.
  final int? intervalDays;
  final String? scope;
  final String? statement;

  bool get isUpgrade => kind != CaptureKind.note;
}

/// Pure-Dart classifier. Stateless on purpose — every call independent
/// so the same instance can be used from the sheet and the AI tool
/// without coordination.
class CaptureClassifier {
  const CaptureClassifier();

  CaptureClassification classify({required String text}) {
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
    // Future hooks: decision / assumption / principle / concept /
    // experiment heuristics. Slice A ships only the routine path
    // because that's the user-stated MVP need; the rest stay on
    // §14.2 P1 alongside the LLM swap.
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

    // Strong direct markers: "定期 X" / "每 N 天" / "需要 X 活跃" / etc.
    // We match the most specific form first so we can pull the interval
    // out of the same sentence.
    final intervalMatch =
        _everyN.firstMatch(text) ?? _everyMonthDay.firstMatch(text);
    final routineLike = _routineMarkers.hasMatch(lower);

    if (intervalMatch == null && !routineLike) return null;

    int intervalDays;
    String reason;
    if (intervalMatch != null) {
      final raw = int.tryParse(intervalMatch.namedGroup('n') ?? '1') ?? 1;
      final unit = intervalMatch.namedGroup('unit') ?? '';
      intervalDays = switch (unit) {
        '日' || '天' || 'd' => raw,
        '周' || 'w' => raw * 7,
        '月' || 'mo' => raw * 30,
        '年' || 'y' => raw * 365,
        _ => raw * 30,
      };
      reason = '检出周期模式 "${intervalMatch.group(0)}"';
    } else {
      // Routine markers without an explicit interval → guess 180 days
      // (covers the prototypical 港卡 case). User adjusts in the upgrade
      // card if 6 months is wrong.
      intervalDays = 180;
      reason = '检出 "定期 / 活跃 / 续期 / 缴费" 等定期关键词,默认每 6 个月';
    }
    // Clamp absurd values produced by typos / unit confusion.
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
    // First non-empty line, trimmed and length-capped — Routine
    // statements are short user-facing labels, not the full free-text.
    final line = text.split(RegExp(r'[\n。]')).firstWhere(
          (s) => s.trim().isNotEmpty,
          orElse: () => text,
        );
    final trimmed = line.trim();
    if (trimmed.length <= 60) return trimmed;
    return '${trimmed.substring(0, 60)}…';
  }

  static String? _scopeGuess(String lower) {
    // Tiny dictionary — same idea as `_suggestTags` in InboxTriageAgent.
    // Routine scope is free-form so we only emit a guess when the input
    // hits a clear bucket.
    if (lower.contains('港卡') ||
        lower.contains('信用卡') ||
        lower.contains('debit') ||
        lower.contains('信用') && lower.contains('卡')) {
      return 'finance/cards';
    }
    if (lower.contains('税') ||
        lower.contains('报税') ||
        lower.contains('tax')) {
      return 'finance/tax';
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
    r'每(?:隔)?\s*(?<n>\d+)\s*个?\s*(?<unit>日|天|周|月|年)',
  );

  // "每月" / "每年" / "每周" — n defaults to 1.
  static final RegExp _everyMonthDay = RegExp(
    r'每(?<n>)(?<unit>日|天|周|月|年)(?!\d)',
  );

  // Routine markers without explicit interval. "定期 / 活跃 / 续期 /
  // 缴费 / 体检 / 缴税 / 提醒我 / 记得每…"
  // English: "every N months/years/weeks/days" (any count, including
  // single-word form like "every month").
  static final RegExp _routineMarkers = RegExp(
    r'(定期|需要.*活跃|需要.*续期|需要.*缴费|每.*提醒|提醒我每|periodically|recurring|every\s+(?:\d+\s+)?(?:months?|years?|weeks?|days?))',
    caseSensitive: false,
  );
}
