/// Capture classifier interface + pure-Dart heuristic
/// (`docs/domains/knowledgeos-domain.md` §3 + §4 + §14.2 P1).
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
    final structured = _detectStructuredKind(trimmed);
    if (structured != null) return structured;
    return CaptureClassification(
      kind: CaptureKind.note,
      confidence: 0.0,
      reasonZh: '未检出特定结构,保留为 Note',
    );
  }

  CaptureClassification? _detectStructuredKind(String text) {
    final lower = text.toLowerCase();
    final statement = _statementFromText(text);
    final scope = _scopeGuess(lower);

    if (_experimentMarkers.hasMatch(lower)) {
      return CaptureClassification(
        kind: CaptureKind.experiment,
        confidence: 0.72,
        reasonZh: '检出 "实验 / 验证 / 指标 / A/B" 等实验结构关键词',
        statement: statement,
        scope: scope,
      );
    }
    if (_decisionMarkers.hasMatch(lower)) {
      return CaptureClassification(
        kind: CaptureKind.decision,
        confidence: 0.7,
        reasonZh: '检出 "是否 / 还是 / vs / 选项" 等决策权衡关键词',
        statement: statement,
        scope: scope,
      );
    }
    if (_principleMarkers.hasMatch(lower)) {
      return CaptureClassification(
        kind: CaptureKind.principle,
        confidence: 0.68,
        reasonZh: '检出 "原则 / 始终 / 不应该 / always / never" 等原则表述',
        statement: statement,
        scope: scope,
      );
    }
    if (_assumptionMarkers.hasMatch(lower)) {
      return CaptureClassification(
        kind: CaptureKind.assumption,
        confidence: 0.66,
        reasonZh: '检出 "假设 / 我认为 / 预计 / 可能" 等可检验信念表述',
        statement: statement,
        scope: scope,
      );
    }
    if (_conceptMarkers.hasMatch(text)) {
      return CaptureClassification(
        kind: CaptureKind.concept,
        confidence: 0.64,
        reasonZh: '检出概念定义句式',
        statement: statement,
        scope: scope,
      );
    }
    return null;
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
        lower.contains('rebalance') ||
        lower.contains('收益率') ||
        lower.contains('对冲') ||
        lower.contains('hedge') ||
        lower.contains('qqq') ||
        lower.contains('boxx') ||
        lower.contains('美债') ||
        lower.contains('债券') ||
        lower.contains('tlt')) {
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

  static final RegExp _experimentMarkers = RegExp(
    r'(实验|试验|验证|a/b|ab\s*test|hypothesis|experiment|metric|指标|对照组|样本|观察\s*\d+\s*(天|周|月)|试运行)',
    caseSensitive: false,
  );

  static final RegExp _decisionMarkers = RegExp(
    r'(是否|要不要|该不该|应该.*还是|还是.*比较好|vs\.?|versus|选项|方案\s*[ab]|权衡|取舍|decision|decide|choose|should\s+i|whether\s+to)',
    caseSensitive: false,
  );

  static final RegExp _principleMarkers = RegExp(
    r'(原则|底线|长期坚持|始终|永远不|不应该|应该始终|价值观|principle|rule of thumb|always|never)',
    caseSensitive: false,
  );

  static final RegExp _assumptionMarkers = RegExp(
    r'(假设|我认为|我相信|预计|预期|大概率|可能会|如果.*那么|because|i think|i believe|assume|assumption|expect|likely)',
    caseSensitive: false,
  );

  static final RegExp _conceptMarkers = RegExp(
    r'(^.{1,40}(是|指的是|意味着|定义为).{2,120}$|^.{1,40}\s+(means|is defined as|refers to)\s+.{2,120}$)',
    caseSensitive: false,
  );
}
