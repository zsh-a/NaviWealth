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
  });

  final String text;
  final TextStyle? baseStyle;
  final InlineSpan? trailing;
  final bool selectable;

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
    // Streaming causes the block list to *restructure* mid-flight —
    // a "| a | b |" paragraph flips to a Table when the separator
    // arrives, a new fenced code block opens, etc. Without smoothing,
    // the bubble snaps between layouts and reads as jittery; with
    // AnimatedSize keyed off the parsed AST shape, the height change
    // glides on the AI motion curve.
    return AnimatedSize(
      duration: AiMotion.duration(context, AiMotion.short),
      curve: AiMotion.standard,
      alignment: Alignment.topLeft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: children,
      ),
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

// ─── Block model ─────────────────────────────────────────────────────────────

sealed class _MdBlock {
  const _MdBlock();
  Widget build(
    BuildContext context, {
    required TextStyle base,
    required InlineSpan? trailing,
    required bool selectable,
  });
}

class _MdParagraph extends _MdBlock {
  const _MdParagraph(this.text);
  final String text;

  @override
  Widget build(
    BuildContext context, {
    required TextStyle base,
    required InlineSpan? trailing,
    required bool selectable,
  }) {
    final spans = _InlineParser.parse(text, base, context);
    if (trailing != null) spans.add(trailing);
    return _selectableRich(spans, selectable: selectable);
  }
}

class _MdHeading extends _MdBlock {
  const _MdHeading(this.level, this.text);
  final int level;
  final String text;

  @override
  Widget build(
    BuildContext context, {
    required TextStyle base,
    required InlineSpan? trailing,
    required bool selectable,
  }) {
    final style = AiType.heading(context, base, level);
    final spans = _InlineParser.parse(text, style, context);
    if (trailing != null) spans.add(trailing);
    // Heading semantics so TalkBack / VoiceOver announce "Heading,
    // level N" instead of just reading the text inline. Flutter's
    // `header` flag is the cross-platform-friendly equivalent; the
    // level itself is mostly conveyed via font weight + size.
    return Semantics(
      header: true,
      child: _selectableRich(spans, selectable: selectable),
    );
  }
}

class _MdHr extends _MdBlock {
  const _MdHr();

  @override
  Widget build(
    BuildContext context, {
    required TextStyle base,
    required InlineSpan? trailing,
    required bool selectable,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.s4),
      child: Container(
        height: AppStroke.hairline,
        color: AiTone.outline(context),
      ),
    );
  }
}

class _MdQuote extends _MdBlock {
  const _MdQuote(this.text);
  final String text;

  @override
  Widget build(
    BuildContext context, {
    required TextStyle base,
    required InlineSpan? trailing,
    required bool selectable,
  }) {
    final style = base.copyWith(
      color: AiTone.muted(context),
      fontStyle: FontStyle.italic,
    );
    final spans = _InlineParser.parse(text, style, context);
    if (trailing != null) spans.add(trailing);
    return Container(
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(
            color: AiTone.outline(context),
            width: AppStroke.accent,
          ),
        ),
      ),
      padding: const EdgeInsets.only(left: AppSpacing.s8),
      child: _selectableRich(spans, selectable: selectable),
    );
  }
}

class _MdListItem {
  const _MdListItem(this.text, this.marker, {this.level = 0, this.checkbox});
  final String text;

  /// `null` for unordered (bullet); otherwise the displayed prefix
  /// ("1.", "2.", …). Pre-rendered by the parser so we keep the model's
  /// own numbering rather than re-numbering.
  final String? marker;

  /// Nesting depth derived from leading-whitespace (every two spaces
  /// is one level). Renderer indents the row by `level * 16` px so
  /// multi-level outlines read as a tree rather than a flat list.
  final int level;

  /// GFM task-list state. `null` = regular list item, `false` = `[ ]`
  /// unchecked, `true` = `[x]` / `[X]` checked. When set, the bullet /
  /// marker is replaced with a checkbox glyph.
  final bool? checkbox;
}

class _MdList extends _MdBlock {
  const _MdList(this.items);
  final List<_MdListItem> items;

  @override
  Widget build(
    BuildContext context, {
    required TextStyle base,
    required InlineSpan? trailing,
    required bool selectable,
  }) {
    final rows = <Widget>[];
    for (var i = 0; i < items.length; i++) {
      final isLast = i == items.length - 1;
      final item = items[i];
      // Completed tasks read with a muted strikethrough so the eye
      // can sweep the list and see at a glance what is still pending.
      final lineStyle = item.checkbox == true
          ? base.copyWith(
              color: AiTone.muted(context),
              decoration: TextDecoration.lineThrough,
            )
          : base;
      final spans = _InlineParser.parse(item.text, lineStyle, context);
      if (isLast && trailing != null) spans.add(trailing);
      rows.add(
        Padding(
          padding: EdgeInsets.only(
            left: item.level * AppSpacing.s16,
            bottom: isLast ? 0 : AppSpacing.s2,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _marker(context, base, item),
              Expanded(child: _selectableRich(spans, selectable: selectable)),
            ],
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: rows,
    );
  }

  Widget _marker(BuildContext context, TextStyle base, _MdListItem item) {
    // Checkbox (GFM task list). Drawn as a 14×14 stroked square so it
    // sits on the AiTone outline scale rather than introducing a new
    // hue. Checked state fills with the active tone + check glyph.
    if (item.checkbox != null) {
      final box = Padding(
        padding: const EdgeInsets.only(
          right: AppSpacing.s8,
          top: AppSpacing.s2,
        ),
        child: _TaskCheckbox(checked: item.checkbox!),
      );
      // Ordered task items (`1. [x] step`) keep their number so the
      // outline still reads as a numbered sequence — the checkbox
      // sits between the number and the text.
      final marker = item.marker;
      if (marker != null) {
        final style = base.copyWith(color: AiTone.muted(context));
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.s4),
              child: SizedBox(
                width: AppControlWidths.markdownMarker,
                child: Text(marker, style: style, textAlign: TextAlign.right),
              ),
            ),
            box,
          ],
        );
      }
      return box;
    }
    final style = base.copyWith(color: AiTone.muted(context));
    if (item.marker != null) {
      return Padding(
        padding: const EdgeInsets.only(right: AppSpacing.s8),
        child: SizedBox(
          width: AppControlWidths.markdownMarker,
          child: Text(item.marker!, style: style, textAlign: TextAlign.right),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(
        left: AppSpacing.s4,
        right: AppSpacing.s8,
        top: AppSpacing.s6,
      ),
      child: Container(
        width: AppStroke.indicator,
        height: AppStroke.indicator,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AiTone.muted(context),
        ),
      ),
    );
  }
}

/// Read-only GFM task-list checkbox. Non-interactive on purpose: the
/// state lives in the chat history, not in widget state — toggling
/// would imply the user could edit the AI's reply, which is not the
/// contract here.
class _TaskCheckbox extends StatelessWidget {
  const _TaskCheckbox({required this.checked});
  final bool checked;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 14,
      height: 14,
      decoration: BoxDecoration(
        color: checked ? AiTone.active(context) : Colors.transparent,
        border: Border.all(
          color: checked ? AiTone.active(context) : AiTone.outline(context),
          width: AppStroke.thin,
        ),
        borderRadius: BorderRadius.circular(AppRadius.xs),
      ),
      alignment: Alignment.center,
      child: checked
          ? Icon(
              FLucideIcons.check,
              size: 10,
              color: context.theme.colors.primaryForeground,
            )
          : null,
    );
  }
}

class _MdCode extends _MdBlock {
  const _MdCode({required this.code, this.language, required this.closed});
  final String code;
  final String? language;

  /// `false` while streaming a fence whose closing ``` hasn't arrived
  /// yet — used to suppress the copy button (copying a half-emitted
  /// snippet is almost always a mistake) and to thread a streaming
  /// caret in.
  final bool closed;

  @override
  Widget build(
    BuildContext context, {
    required TextStyle base,
    required InlineSpan? trailing,
    required bool selectable,
  }) {
    final lang = (language ?? '').trim();
    final l10n = AppLocalizations.of(context);
    final mono = base.copyWith(
      fontFamily: 'monospace',
      fontFamilyFallback: const ['Menlo', 'Consolas', 'monospace'],
      fontSize: (base.fontSize ?? TypographyTokens.bodySmall.fontSize!) - 1,
      height: 1.5,
      color: AiTone.onSurface(context),
    );

    // Subtle syntax tinting: strings/comments/numbers get muted +
    // tinted variants of `mono`. Zero-dep — `flutter_highlight` would
    // add ~100KB to the web bundle for a feature we use sparingly.
    // The lexer is language-agnostic on strings/numbers and accepts
    // `//` / `#` / `--` line comments + `/* */` block comments,
    // which covers Dart / Python / SQL / JS / Rust / Go.
    final spans = _CodeTinter.tint(code, mono, context);
    if (trailing != null) spans.add(trailing);

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AiTone.surfaceTint(context).withValues(alpha: AppOpacity.scrim),
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: AiTone.outline(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (lang.isNotEmpty || closed)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.s12,
                AppSpacing.s6,
                AppSpacing.s4,
                AppSpacing.s2,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      lang.isEmpty ? '' : lang,
                      style: AiType.meta(
                        context,
                      ).copyWith(color: AiTone.muted(context)),
                    ),
                  ),
                  if (closed)
                    _CopyButton(
                      text: code,
                      tooltip: l10n.aiChatMessageCopy,
                      confirm: l10n.aiChatMessageCopied,
                    ),
                ],
              ),
            ),
          // Horizontal scroll: code is structural — soft-wrap mangles
          // indentation and turns one logical line into two visual
          // lines, so we let long lines extend off-screen and the
          // user scrolls. The padding lives *inside* the scroll view
          // so left/right padding moves with the content (standard
          // GitHub/IDE behaviour).
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.fromLTRB(
              AppSpacing.s12,
              (lang.isNotEmpty || closed) ? AppSpacing.s2 : AppSpacing.s8,
              AppSpacing.s12,
              AppSpacing.s8,
            ),
            child: _NoSoftWrap(
              child: _selectableRich(spans, selectable: selectable),
            ),
          ),
        ],
      ),
    );
  }
}

/// Disables soft-wrap inside its child by wrapping the descendant
/// `Text` / `SelectableText` in an unbounded width. Without this, a
/// `SelectableText` inside a `SingleChildScrollView(horizontal)` still
/// honours the *outer* viewport width as a soft-wrap hint and the
/// long lines get broken anyway.
class _NoSoftWrap extends StatelessWidget {
  const _NoSoftWrap({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return UnconstrainedBox(
      constrainedAxis: Axis.vertical,
      alignment: Alignment.topLeft,
      child: child,
    );
  }
}

/// GFM table. Header row + body rows; column alignment carried in
/// [aligns] (from the `:---`/`:---:`/`---:` separator). The block is
/// only emitted once the separator line has actually arrived so a
/// half-streamed header still reads as a paragraph and resolves into
/// a table on the next chunk.
class _MdTable extends _MdBlock {
  const _MdTable({
    required this.header,
    required this.aligns,
    required this.rows,
  });

  final List<String> header;
  final List<TextAlign> aligns;
  final List<List<String>> rows;

  @override
  Widget build(
    BuildContext context, {
    required TextStyle base,
    required InlineSpan? trailing,
    required bool selectable,
  }) {
    final cols = header.length;
    final outline = AiTone.outline(context);
    final headerStyle = AiType.tableHeader(context, base);
    final headerBg = AiTone.surfaceTint(
      context,
    ).withValues(alpha: AppOpacity.disabled);

    // Pad short rows / clip long rows so every row has exactly `cols`
    // cells — `Table` throws if rows differ in length.
    final normalizedRows = <List<String>>[];
    for (final row in rows) {
      if (row.length == cols) {
        normalizedRows.add(row);
      } else if (row.length > cols) {
        normalizedRows.add(row.sublist(0, cols));
      } else {
        normalizedRows.add([...row, ...List.filled(cols - row.length, '')]);
      }
    }

    Widget cell(
      String text,
      TextStyle style,
      TextAlign align, {
      Color? background,
    }) {
      final spans = _InlineParser.parse(text, style, context);
      return Container(
        color: background,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s8,
          vertical: AppSpacing.s6,
        ),
        alignment: switch (align) {
          TextAlign.right => Alignment.centerRight,
          TextAlign.center => Alignment.center,
          _ => Alignment.centerLeft,
        },
        // Min column width: a 4-column table with one-character cells
        // would otherwise crush every column down to a single char's
        // width. 80 px reads as "a real cell", and the outer
        // SingleChildScrollView still lets wide cells expand past it.
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 80),
          child: selectable
              ? SelectableText.rich(TextSpan(children: spans), textAlign: align)
              : Text.rich(TextSpan(children: spans), textAlign: align),
        ),
      );
    }

    final table = Table(
      border: TableBorder.all(color: outline, width: AppStroke.hairline),
      defaultColumnWidth: const IntrinsicColumnWidth(),
      children: [
        TableRow(
          decoration: BoxDecoration(color: headerBg),
          children: [
            for (var i = 0; i < cols; i++)
              cell(
                header[i],
                headerStyle,
                i < aligns.length ? aligns[i] : TextAlign.left,
              ),
          ],
        ),
        for (final row in normalizedRows)
          TableRow(
            children: [
              for (var i = 0; i < cols; i++)
                cell(
                  row[i],
                  base,
                  i < aligns.length ? aligns[i] : TextAlign.left,
                ),
            ],
          ),
      ],
    );

    final wrapped = Semantics(
      // Screen readers announce "Table with N rows, M columns" before
      // descending into cells, so the user can decide whether to skim
      // the structure or skip past it.
      container: true,
      label: 'Table, ${normalizedRows.length + 1} rows, $cols columns',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        // Wide tables stay readable: scroll horizontally rather than
        // squeezing cells past their intrinsic width.
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: table,
        ),
      ),
    );

    // Trailing caret on a table: parsed tables are virtually always
    // complete (the separator-line gate prevents partial parses), but
    // if this block ends up last *and* trailing is set, hang the caret
    // in a small row below so the bubble still reads "live".
    if (trailing == null) return wrapped;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        wrapped,
        const SizedBox(height: AppSpacing.s4),
        Text.rich(TextSpan(children: [trailing])),
      ],
    );
  }
}

/// Flow diagram block — rendered by [FlowDiagramWidget] when a fenced
/// block uses the `flow` language tag. Falls back to [_MdCode] if the
/// DSL content cannot be parsed.
class _MdFlowBlock extends _MdBlock {
  const _MdFlowBlock(this.diagram);
  final FlowDiagram diagram;

  @override
  Widget build(
    BuildContext context, {
    required TextStyle base,
    required InlineSpan? trailing,
    required bool selectable,
  }) {
    final widget = Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.s4),
      child: FlowDiagramWidget(diagram: diagram),
    );
    if (trailing == null) return widget;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        widget,
        const SizedBox(height: AppSpacing.s4),
        Text.rich(TextSpan(children: [trailing])),
      ],
    );
  }
}

class _CopyButton extends StatefulWidget {
  const _CopyButton({
    required this.text,
    required this.tooltip,
    required this.confirm,
  });

  final String text;
  final String tooltip;
  final String confirm;

  @override
  State<_CopyButton> createState() => _CopyButtonState();
}

class _CopyButtonState extends State<_CopyButton> {
  bool _copied = false;

  @override
  Widget build(BuildContext context) {
    final color = AiTone.muted(context);
    final icon = _copied ? FLucideIcons.check : FLucideIcons.copy;
    return Semantics(
      button: true,
      label: widget.tooltip,
      child: FTappable(
        onPress: () async {
          await Clipboard.setData(ClipboardData(text: widget.text));
          if (!mounted) return;
          setState(() => _copied = true);
          Future<void>.delayed(const Duration(milliseconds: 1400), () {
            if (mounted) setState(() => _copied = false);
          });
        },
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.s6),
          child: Icon(icon, size: AppIconSizes.xs, color: color),
        ),
      ),
    );
  }
}

Widget _selectableRich(List<InlineSpan> spans, {required bool selectable}) {
  final span = TextSpan(children: spans);
  return selectable ? SelectableText.rich(span) : Text.rich(span);
}
