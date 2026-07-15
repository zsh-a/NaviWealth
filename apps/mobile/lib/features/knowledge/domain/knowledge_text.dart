/// Shared KnowledgeOS text-display helpers.
///
/// Kept out of `ui/_widgets.dart` so composition providers can reuse the same
/// excerpt rules without importing widget code.
library;

/// Max chars shown for a body / summary / rationale excerpt in compact UI.
const int kKnowledgeExcerptMaxChars = 200;

/// Short headline excerpt derived from the shared excerpt budget.
const int kKnowledgeHeadlineExcerptMaxChars = kKnowledgeExcerptMaxChars ~/ 3;

/// Inline label excerpt derived from the shared headline budget.
const int kKnowledgeInlineExcerptMaxChars =
    kKnowledgeHeadlineExcerptMaxChars ~/ 2;

/// Shared intent note title excerpt budget.
const int kKnowledgeSharedTitleMaxChars = 80;

/// Supporting-detail excerpt derived from the shared excerpt budget.
const int kKnowledgeSupportingExcerptMaxChars =
    kKnowledgeExcerptMaxChars - kKnowledgeHeadlineExcerptMaxChars;

/// Collapse markdown noise into plain text, then truncate for list UIs.
///
/// Strips common GFM-ish markers so Inbox / Library / search chips do not
/// show raw `**`, `#`, or `- [ ]` residue. Safe for memory/tool excerpts too.
String knowledgeExcerpt(String text, {int max = kKnowledgeExcerptMaxChars}) {
  final plain = knowledgePlainText(text).trim();
  if (plain.isEmpty) return '';
  if (plain.length <= max) return plain;
  // Prefer a clean break near the budget (word / CJK-safe soft cut).
  final hard = plain.substring(0, max);
  final soft = hard.lastIndexOf(RegExp(r'[\s，。；、,.!?;:]'));
  final cut = soft >= (max * 0.6).floor() ? hard.substring(0, soft) : hard;
  return '${cut.trimRight()}…';
}

/// Markdown → plain text for previews, search chips, and memory summaries.
String knowledgePlainText(String markdown) {
  if (markdown.isEmpty) return '';
  var s = markdown.replaceAll('\r\n', '\n');

  // Fenced code: keep inner text, drop fences / language tag.
  s = s.replaceAllMapped(
    RegExp(r'```[^\n]*\n([\s\S]*?)```', multiLine: true),
    (m) => '\n${m.group(1) ?? ''}\n',
  );
  s = s.replaceAll(RegExp(r'```+'), '');

  // Images → alt text; links → label.
  s = s.replaceAllMapped(
    RegExp(r'!\[([^\]]*)\]\([^)]*\)'),
    (m) => m.group(1) ?? '',
  );
  s = s.replaceAllMapped(
    RegExp(r'\[([^\]]+)\]\([^)]*\)'),
    (m) => m.group(1) ?? '',
  );

  // Autolinks / bare angle URLs.
  s = s.replaceAllMapped(RegExp(r'<(https?://[^>]+)>'), (m) => m.group(1) ?? '');

  // Headings, blockquotes, HR, list markers (incl. task lists).
  s = s.replaceAllMapped(
    RegExp(r'^#{1,6}\s*', multiLine: true),
    (_) => '',
  );
  s = s.replaceAllMapped(
    RegExp(r'^>\s?', multiLine: true),
    (_) => '',
  );
  s = s.replaceAll(RegExp(r'^([-*_]){3,}\s*$', multiLine: true), '');
  s = s.replaceAllMapped(
    RegExp(r'^(\s*)([-*+]|\d+\.)\s+(\[[ xX]\]\s+)?', multiLine: true),
    (m) => m.group(1) ?? '',
  );

  // Inline emphasis / code (non-greedy; tolerates unclosed leftovers).
  s = s.replaceAllMapped(
    RegExp(r'`([^`]+)`'),
    (m) => m.group(1) ?? '',
  );
  s = s.replaceAllMapped(
    RegExp(r'(\*\*|__)(.+?)\1'),
    (m) => m.group(2) ?? '',
  );
  s = s.replaceAllMapped(
    RegExp(r'(\*|_)([^*_\n]+?)\1'),
    (m) => m.group(2) ?? '',
  );
  s = s.replaceAllMapped(
    RegExp(r'~~(.+?)~~'),
    (m) => m.group(1) ?? '',
  );

  // Table pipes → spaces.
  s = s.replaceAllMapped(
    RegExp(r'^\|(.+)\|$', multiLine: true),
    (m) => (m.group(1) ?? '').replaceAll('|', ' '),
  );
  s = s.replaceAll(RegExp(r'^\s*\|?[\s:|-]+\|?\s*$', multiLine: true), '');

  // Collapse whitespace.
  s = s.replaceAll(RegExp(r'[ \t]+\n'), '\n');
  s = s.replaceAll(RegExp(r'\n{3,}'), '\n\n');
  s = s.replaceAll(RegExp(r'[ \t]{2,}'), ' ');
  return s.trim();
}
