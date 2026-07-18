/// Lightweight markdown renderer for AI surfaces.
///
/// LLMs reliably emit a small subset of markdown — headings, bold,
/// italic, inline + fenced code, lists, blockquotes, links. Pulling in
/// `flutter_markdown` (now archived) or `markdown` for that would bloat
/// the web bundle and force a parallel theme. Instead this file parses
/// the subset directly, renders through [AiType] / [AiTone] / [AppRadius]
/// so a palette swap lands in one place, and tolerates unclosed
/// delimiters so a streaming chunk that ends mid-`**bold` renders
/// stable as the next token arrives.
///
/// Supported:
///   - paragraphs, hard line breaks (`\n` between lines = single line)
///   - `#` / `##` / `###` headings
///   - `**bold**`, `__bold__`, `*italic*`, `_italic_`
///   - `` `inline code` ``
///   - ``` ```lang ``` ``` fenced code, with copy button
///   - `- ` / `* ` / `+ ` unordered lists, `1. ` ordered lists
///   - `> ` blockquotes (multiline)
///   - `---` / `***` / `___` horizontal rule
///   - GFM tables with `:---`/`:---:`/`---:` alignment
///   - `[label](url)` links (styled, non-clickable — url_launcher isn't
///     a dependency; SelectableText lets the user copy)
///   - ``` ```flow ``` ``` fenced flow diagrams (vertical card-based flowchart)
///
/// Trailing inline span (e.g. the streaming caret) is appended to the
/// last text-bearing block so the cursor reads as part of the
/// in-flight paragraph rather than orphaned below it.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:forui/forui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import 'ai_motion.dart';
import 'ai_tone.dart';
import 'ai_typography.dart';
import 'flow_block.dart';

part 'ai_markdown_block_parser.dart';
part 'ai_markdown_blocks.dart';
part 'ai_markdown_code_blocks.dart';
part 'ai_markdown_inline_parser.dart';

/// Render `text` as markdown.
///
/// [baseStyle] defaults to [AiType.body]. [trailing] is appended at the
/// end of the last text block — typically a streaming caret widget —
/// and is dropped silently when the text is empty.
///
/// `AiMarkdown` is stateful so each instance can memoize its last
/// parsed AST: a streaming bubble rebuilds ~10× / second as new tokens
/// arrive, and re-parsing every byte on every rebuild is wasted work.
/// The cache is keyed on the *exact* text string; a single-character
/// change invalidates it (parsing 4KB is sub-millisecond, so this is
/// only meaningful at the build-frequency scale).
class AiMarkdown extends StatefulWidget {
  const AiMarkdown({
    super.key,
    required this.text,
    this.baseStyle,
    this.trailing,
    this.selectable = true,
    this.streaming = false,
  });

  final String text;
  final TextStyle? baseStyle;
  final InlineSpan? trailing;
  final bool selectable;

  /// When true, skip [AnimatedSize] and prefer lighter text selection
  /// so high-frequency streaming rebuilds stay smooth.
  final bool streaming;

  @override
  State<AiMarkdown> createState() => _AiMarkdownState();
}

class _AiMarkdownState extends State<AiMarkdown> {
  String? _cachedText;
  List<_MdBlock>? _cachedBlocks;

  List<_MdBlock> _blocks() {
    if (_cachedText == widget.text && _cachedBlocks != null) {
      return _cachedBlocks!;
    }
    final next = _MdParser.parse(widget.text);
    _cachedText = widget.text;
    _cachedBlocks = next;
    return next;
  }

  @override
  Widget build(BuildContext context) {
    final blocks = _blocks();
    final trailing = widget.trailing;
    final baseStyle = widget.baseStyle;
    final selectable = widget.selectable;
    if (blocks.isEmpty) {
      // Empty input + a streaming caret still wants the caret visible
      // so the bubble doesn't collapse to zero height while waiting for
      // the first token after a tool call.
      if (trailing != null) {
        return Text.rich(TextSpan(children: [trailing]));
      }
      return const SizedBox.shrink();
    }
    final effectiveBase = baseStyle ?? AiType.body(context);
    final children = <Widget>[];
    for (var i = 0; i < blocks.length; i++) {
      final isLast = i == blocks.length - 1;
      children.add(
        blocks[i].build(
          context,
          base: effectiveBase,
          trailing: isLast ? trailing : null,
          selectable: selectable,
        ),
      );
      if (!isLast) {
        children.add(SizedBox(height: _gapAfter(blocks[i], blocks[i + 1])));
      }
    }
    final column = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: children,
    );
    // Streaming rebuilds ~10×/s — AnimatedSize on every token costs
    // layout thrash. Only smooth height changes once the turn settles.
    if (widget.streaming) return column;
    return AnimatedSize(
      duration: AppMotionPolicy.duration(context, AiMotion.short),
      curve: AiMotion.standard,
      alignment: Alignment.topLeft,
      child: column,
    );
  }

  /// Gap between two adjacent blocks. Tighter between list rows so a
  /// 4-item list reads as one unit, wider around code/quote/table so
  /// they breathe.
  double _gapAfter(_MdBlock a, _MdBlock b) {
    if (a is _MdList && b is _MdList) return AppSpacing.s4;
    if (a is _MdCode || b is _MdCode) return AppSpacing.s8;
    if (a is _MdFlowBlock || b is _MdFlowBlock) return AppSpacing.s8;
    if (a is _MdQuote || b is _MdQuote) return AppSpacing.s8;
    if (a is _MdTable || b is _MdTable) return AppSpacing.s8;
    if (a is _MdHeading || b is _MdHeading) return AppSpacing.s8;
    if (a is _MdHr || b is _MdHr) return AppSpacing.s4;
    return AppSpacing.s6;
  }
}
