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
      duration: AiMotion.short,
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
    final baseSize = base.fontSize ?? 13;
    final fontSize = switch (level) {
      1 => baseSize + 3,
      2 => baseSize + 2,
      _ => baseSize + 1,
    };
    final style = base.copyWith(
      fontSize: fontSize,
      fontWeight: FontWeight.w600,
      height: 1.35,
      color: AiTone.onSurface(context),
    );
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
      child: Container(height: 1, color: AiTone.outline(context)),
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
          left: BorderSide(color: AiTone.outline(context), width: 3),
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
        padding: const EdgeInsets.only(right: AppSpacing.s8, top: AppSpacing.s2),
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
                width: 18,
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
          width: 18,
          child: Text(item.marker!, style: style, textAlign: TextAlign.right),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(
        left: AppSpacing.s4,
        right: AppSpacing.s8,
        top: 6,
      ),
      child: Container(
        width: 4,
        height: 4,
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
          width: 1.2,
        ),
        borderRadius: BorderRadius.circular(AppRadius.xs),
      ),
      alignment: Alignment.center,
      child: checked
          ? Icon(
              FLucideIcons.check,
              size: 10,
              color: Theme.of(context).colorScheme.onPrimary,
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
      fontSize: (base.fontSize ?? 13) - 1,
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
        color: AiTone.surfaceTint(context).withValues(alpha: 0.5),
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
    final headerStyle = base.copyWith(
      fontWeight: FontWeight.w600,
      color: AiTone.onSurface(context),
    );
    final headerBg = AiTone.surfaceTint(context).withValues(alpha: 0.4);

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
      border: TableBorder.all(color: outline, width: 1),
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

// ─── Block parser ────────────────────────────────────────────────────────────

class _MdParser {
  static final RegExp _heading = RegExp(r'^(#{1,3})\s+(.*)$');
  static final RegExp _unordered = RegExp(r'^(\s*)[-*+]\s+(.*)$');
  static final RegExp _ordered = RegExp(r'^(\s*)(\d{1,3})[.)]\s+(.*)$');
  static final RegExp _quote = RegExp(r'^\s*>\s?(.*)$');
  static final RegExp _hr = RegExp(r'^\s*(?:-{3,}|\*{3,}|_{3,})\s*$');
  static final RegExp _fence = RegExp(r'^(\s*)(```+)\s*([\w+\-.]*)\s*$');

  /// GFM task-list checkbox prefix inside a list item body. The
  /// surrounding `- ` / `1. ` is matched by [_unordered]/[_ordered] —
  /// this regex only consumes the `[ ]` / `[x]` token that follows.
  static final RegExp _task = RegExp(r'^\[([ xX])\]\s+(.*)$');

  /// Candidate table row: at least one internal pipe, whitespace
  /// tolerant. We only commit it to a table once the following line
  /// matches [_tableSep] — otherwise it falls back to paragraph (so a
  /// half-streamed header still reads naturally before the separator
  /// arrives).
  static final RegExp _tableRow = RegExp(r'^\s*\|?[^\n]*\|[^\n]*$');

  /// Separator under the header. Each column must be ≥3 dashes with
  /// an optional leading/trailing `:` for alignment.
  static final RegExp _tableSep = RegExp(
    r'^\s*\|?\s*:?-{3,}:?\s*(\|\s*:?-{3,}:?\s*)+\|?\s*$',
  );

  static List<_MdBlock> parse(String input) {
    final lines = input.split('\n');
    final blocks = <_MdBlock>[];
    var i = 0;
    while (i < lines.length) {
      final raw = lines[i];
      final line = raw;

      // Fenced code block.
      final fenceOpen = _fence.firstMatch(line);
      if (fenceOpen != null) {
        final fenceMarker = fenceOpen.group(2)!; // ``` or ````
        final lang = fenceOpen.group(3);
        final buf = StringBuffer();
        var j = i + 1;
        var closed = false;
        while (j < lines.length) {
          final cand = lines[j];
          final candMatch = _fence.firstMatch(cand);
          // Close on a fence of equal-or-greater backtick count and
          // empty language — standard markdown rule.
          if (candMatch != null &&
              candMatch.group(2)!.length >= fenceMarker.length &&
              (candMatch.group(3) ?? '').isEmpty) {
            closed = true;
            j++;
            break;
          }
          if (buf.isNotEmpty) buf.write('\n');
          buf.write(cand);
          j++;
        }
        blocks.add(
          _MdCode(code: buf.toString(), language: lang, closed: closed),
        );
        i = j;
        continue;
      }

      // Blank line: separates blocks.
      if (line.trim().isEmpty) {
        i++;
        continue;
      }

      // Horizontal rule.
      if (_hr.hasMatch(line)) {
        blocks.add(const _MdHr());
        i++;
        continue;
      }

      // Heading.
      final h = _heading.firstMatch(line);
      if (h != null) {
        final level = h.group(1)!.length;
        blocks.add(_MdHeading(level, h.group(2)!.trim()));
        i++;
        continue;
      }

      // Table — only when the next line is a `|---|---|` separator.
      // Without that gate, any line with a `|` (e.g. shell paths like
      // `foo|bar`) would tip the parser into table mode.
      if (i + 1 < lines.length &&
          _tableRow.hasMatch(line) &&
          _tableSep.hasMatch(lines[i + 1])) {
        final header = _splitRow(line);
        final aligns = _splitRow(lines[i + 1]).map(_alignFromMarker).toList();
        final rows = <List<String>>[];
        var j = i + 2;
        while (j < lines.length) {
          final l = lines[j];
          if (l.trim().isEmpty || !_tableRow.hasMatch(l)) break;
          // Treat a separator-looking line inside the body as the end
          // of the table (rare; protects against malformed input).
          if (_tableSep.hasMatch(l)) break;
          rows.add(_splitRow(l));
          j++;
        }
        blocks.add(_MdTable(header: header, aligns: aligns, rows: rows));
        i = j;
        continue;
      }

      // List (consecutive items, mix of types not allowed — switching
      // type opens a new list block).
      final isUnord = _unordered.hasMatch(line);
      final isOrd = _ordered.hasMatch(line);
      if (isUnord || isOrd) {
        // A list block can now mix ordered / unordered children — GFM
        // allows `1. parent` ↘ `  - child`. The outer block is opened
        // by the first qualifying line and stays open until either a
        // blank line or a non-list line.
        final items = <_MdListItem>[];
        var j = i;
        while (j < lines.length) {
          final l = lines[j];
          if (l.trim().isEmpty) break;
          final mOrd = _ordered.firstMatch(l);
          final mUn = _unordered.firstMatch(l);
          if (mOrd == null && mUn == null) break;
          final indent = (mOrd?.group(1) ?? mUn!.group(1))!.length;
          final level = indent ~/ 2;
          String body;
          String? marker;
          if (mOrd != null) {
            body = mOrd.group(3)!;
            marker = '${mOrd.group(2)}.';
          } else {
            body = mUn!.group(2)!;
            marker = null;
          }
          final task = _task.firstMatch(body);
          if (task != null) {
            // Strip the `[ ]` / `[x]` from the body — the renderer
            // surfaces it as a checkbox glyph instead. Unordered task
            // items drop the bullet (checkbox replaces it); ordered
            // task items keep their number so `1. [x] step` reads
            // naturally.
            final checked = task.group(1)! != ' ';
            items.add(
              _MdListItem(
                task.group(2)!,
                marker,
                level: level,
                checkbox: checked,
              ),
            );
          } else {
            items.add(_MdListItem(body, marker, level: level));
          }
          j++;
        }
        blocks.add(_MdList(items));
        i = j;
        continue;
      }

      // Blockquote — collect consecutive `> ` lines.
      if (_quote.hasMatch(line)) {
        final buf = StringBuffer();
        var j = i;
        while (j < lines.length) {
          final m = _quote.firstMatch(lines[j]);
          if (m == null) break;
          if (buf.isNotEmpty) buf.write('\n');
          buf.write(m.group(1) ?? '');
          j++;
        }
        blocks.add(_MdQuote(buf.toString()));
        i = j;
        continue;
      }

      // Paragraph — collect until blank line or a known block-starter.
      final buf = StringBuffer(line);
      var j = i + 1;
      while (j < lines.length) {
        final l = lines[j];
        if (l.trim().isEmpty) break;
        if (_heading.hasMatch(l) ||
            _unordered.hasMatch(l) ||
            _ordered.hasMatch(l) ||
            _quote.hasMatch(l) ||
            _hr.hasMatch(l) ||
            _fence.hasMatch(l)) {
          break;
        }
        // Stop one line before a table starts (header + separator on
        // the *next* line). Otherwise the table header gets eaten by
        // the paragraph above.
        if (j + 1 < lines.length &&
            _tableRow.hasMatch(l) &&
            _tableSep.hasMatch(lines[j + 1])) {
          break;
        }
        buf.write('\n');
        buf.write(l);
        j++;
      }
      blocks.add(_MdParagraph(buf.toString()));
      i = j;
    }
    return blocks;
  }

  /// Split a table row into cells. Strips the optional leading +
  /// trailing pipe so `| a | b |` and `a | b` both produce `["a","b"]`.
  static List<String> _splitRow(String line) {
    var s = line.trim();
    if (s.startsWith('|')) s = s.substring(1);
    if (s.endsWith('|')) s = s.substring(0, s.length - 1);
    return s.split('|').map((c) => c.trim()).toList(growable: false);
  }

  /// `:---` left, `:---:` center, `---:` right. Default left.
  static TextAlign _alignFromMarker(String cell) {
    final c = cell.trim();
    final left = c.startsWith(':');
    final right = c.endsWith(':');
    if (left && right) return TextAlign.center;
    if (right) return TextAlign.right;
    return TextAlign.left;
  }
}

// ─── Inline parser ───────────────────────────────────────────────────────────

class _InlineParser {
  /// Public entry. Returns a *mutable* list so the caller (block
  /// renderer) can append a trailing span.
  static List<InlineSpan> parse(
    String text,
    TextStyle base,
    BuildContext context,
  ) {
    final out = <InlineSpan>[];
    _walk(text, base, context, out);
    return out;
  }

  static void _walk(
    String text,
    TextStyle base,
    BuildContext context,
    List<InlineSpan> out,
  ) {
    var i = 0;
    final buf = StringBuffer();
    void flush() {
      if (buf.isEmpty) return;
      out.add(TextSpan(text: buf.toString(), style: base));
      buf.clear();
    }

    while (i < text.length) {
      final ch = text[i];

      // Inline code ` … `
      if (ch == '`') {
        final end = text.indexOf('`', i + 1);
        flush();
        if (end == -1) {
          // Unclosed — render the rest as code so streaming reads OK.
          out.add(_codeSpan(text.substring(i + 1), base, context));
          return;
        }
        out.add(_codeSpan(text.substring(i + 1, end), base, context));
        i = end + 1;
        continue;
      }

      // Bold **…** / __…__
      if ((ch == '*' || ch == '_') &&
          i + 1 < text.length &&
          text[i + 1] == ch) {
        final marker = '$ch$ch';
        final end = text.indexOf(marker, i + 2);
        flush();
        final childStyle = base.copyWith(fontWeight: FontWeight.w600);
        final inner = end == -1
            ? text.substring(i + 2)
            : text.substring(i + 2, end);
        _walk(inner, childStyle, context, out);
        i = end == -1 ? text.length : end + 2;
        continue;
      }

      // Strikethrough ~~…~~ (GFM). We keep the existing decoration
      // (e.g. completed task lines combine line-through + underline?
      // → no, just override) and toggle line-through on top so nested
      // `~~**bold gone**~~` works too.
      if (ch == '~' && i + 1 < text.length && text[i + 1] == '~') {
        final end = text.indexOf('~~', i + 2);
        flush();
        final childStyle = base.copyWith(
          decoration: TextDecoration.combine([
            if (base.decoration != null) base.decoration!,
            TextDecoration.lineThrough,
          ]),
        );
        final inner = end == -1
            ? text.substring(i + 2)
            : text.substring(i + 2, end);
        _walk(inner, childStyle, context, out);
        i = end == -1 ? text.length : end + 2;
        continue;
      }

      // Italic *…* / _…_  — only when flanked by a word boundary on the
      // open side, to keep `5*3*2` arithmetic out.
      if ((ch == '*' || ch == '_') && _isItalicOpen(text, i)) {
        final end = _findItalicClose(text, i + 1, ch);
        flush();
        final childStyle = base.copyWith(fontStyle: FontStyle.italic);
        final inner = end == -1
            ? text.substring(i + 1)
            : text.substring(i + 1, end);
        _walk(inner, childStyle, context, out);
        i = end == -1 ? text.length : end + 1;
        continue;
      }

      // Link [label](url)
      if (ch == '[') {
        final close = text.indexOf(']', i + 1);
        if (close != -1 && close + 1 < text.length && text[close + 1] == '(') {
          final paren = text.indexOf(')', close + 2);
          if (paren != -1) {
            final label = text.substring(i + 1, close);
            final url = text.substring(close + 2, paren);
            flush();
            final linkStyle = base.copyWith(
              color: AiTone.active(context),
              decoration: TextDecoration.underline,
              decorationColor: AiTone.active(context).withValues(alpha: 0.4),
            );
            // The label is rendered inside a tappable WidgetSpan so we
            // don't need to wire a TapGestureRecognizer (which would
            // need lifecycle management). The trade-off: link text
            // isn't part of the surrounding SelectableText selection.
            // That's an acceptable cost — copying the assistant turn
            // already uses the message-level "Copy" affordance, and
            // selection across hostile URLs is a rare need.
            out.add(_LinkSpan.build(label, url, linkStyle, context));
            i = paren + 1;
            continue;
          }
        }
      }

      buf.write(ch);
      i++;
    }
    flush();
  }

  static bool _isItalicOpen(String text, int i) {
    // Must be at start, or preceded by whitespace / punctuation —
    // avoids matching inside `word*word` style identifiers.
    if (i > 0) {
      final prev = text.codeUnitAt(i - 1);
      if (_isWordChar(prev)) return false;
    }
    // Must not be followed by whitespace (`* foo` is a stray asterisk
    // — block-parser already stripped real bullets) or by another copy
    // of the same marker (handled by the bold branch above).
    if (i + 1 >= text.length) return false;
    final next = text.codeUnitAt(i + 1);
    if (next == 0x20 || next == 0x09 || next == 0x0a) return false;
    return true;
  }

  static int _findItalicClose(String text, int start, String marker) {
    for (var j = start; j < text.length; j++) {
      if (text[j] != marker) continue;
      // Skip pairs (those belong to the bold branch).
      if (j + 1 < text.length && text[j + 1] == marker) {
        j++;
        continue;
      }
      // Close must not be flanked on the left by whitespace.
      if (j > start) {
        final prev = text.codeUnitAt(j - 1);
        if (prev == 0x20 || prev == 0x09 || prev == 0x0a) continue;
      }
      return j;
    }
    return -1;
  }

  static bool _isWordChar(int code) {
    // ASCII alphanumeric + underscore + CJK range (so `中文*强调*` opens
    // correctly only when the `*` actually starts a phrase).
    if (code >= 0x30 && code <= 0x39) return true;
    if (code >= 0x41 && code <= 0x5a) return true;
    if (code >= 0x61 && code <= 0x7a) return true;
    return false;
  }
}

/// Tappable link span. Hosted in a `WidgetSpan` so we don't have to
/// manage `TapGestureRecognizer` lifecycles — `SelectableText.rich`
/// would otherwise leak them on rebuild. Confirms the destination
/// with the user before handing the URL to the OS, because AI replies
/// are an untrusted surface (prompt-injection vector).
class _LinkSpan {
  static InlineSpan build(
    String label,
    String url,
    TextStyle style,
    BuildContext context,
  ) {
    return WidgetSpan(
      alignment: PlaceholderAlignment.baseline,
      baseline: TextBaseline.alphabetic,
      child: _LinkTappable(label: label, url: url, style: style),
    );
  }
}

class _LinkTappable extends StatelessWidget {
  const _LinkTappable({
    required this.label,
    required this.url,
    required this.style,
  });

  final String label;
  final String url;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      link: true,
      label: label,
      hint: url,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: () => _confirmAndOpen(context, url),
          child: Text(label, style: style),
        ),
      ),
    );
  }
}

/// Shared confirm dialog — surfaces the *full URL* in a non-editable
/// SelectableText so the user can verify (and copy) the destination
/// before opening it. Returns silently on cancel; shows a snackbar if
/// `launchUrl` reports failure (no installed handler / blocked).
Future<void> _confirmAndOpen(BuildContext context, String url) async {
  final l10n = AppLocalizations.of(context);
  final ok = await showConfirmDialog(
    context: context,
    title: Text(l10n.aiChatLinkConfirmTitle),
    body: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          l10n.aiChatLinkConfirmBody,
          style: AiType.meta(context).copyWith(color: AiTone.muted(context)),
        ),
        const SizedBox(height: AppSpacing.s8),
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.s8,
            vertical: AppSpacing.s6,
          ),
          decoration: BoxDecoration(
            color: AiTone.surfaceTint(context).withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(AppRadius.xs),
            border: Border.all(color: AiTone.outline(context)),
          ),
          child: SelectableText(
            url,
            style: AiType.body(context).copyWith(
              fontFamily: 'monospace',
              fontFamilyFallback: const ['Menlo', 'Consolas', 'monospace'],
            ),
            maxLines: 4,
          ),
        ),
      ],
    ),
    confirmLabel: l10n.aiChatLinkOpen,
    cancelLabel: l10n.commonCancel,
  );
  if (ok != true) return;
  if (!context.mounted) return;
  Uri? uri;
  try {
    uri = Uri.parse(url);
  } on FormatException {
    uri = null;
  }
  if (uri == null) return;
  final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
  if (!launched && context.mounted) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text(AppLocalizations.of(context).aiChatLinkOpenFailed),
        duration: const Duration(seconds: 2),
      ),
    );
  }
}

/// Zero-dep code tinter. Walks `code` once and emits a list of
/// TextSpans, colouring strings + comments + numbers with derived
/// shades of the base mono style. Keywords are intentionally NOT
/// highlighted — keyword sets are language-specific and we don't
/// want to ship a multi-language dictionary.
///
/// Behaviour:
///   - `"..."` / `'...'` / `` `...` ``  → string tone
///   - `// … \n` / `# … \n` / `-- … \n` → line comment (muted)
///   - `/* … */`                        → block comment (muted)
///   - integers / floats / hex literals → number tone
///   - everything else                  → base style
class _CodeTinter {
  static List<InlineSpan> tint(
    String code,
    TextStyle base,
    BuildContext context,
  ) {
    final stringStyle = base.copyWith(
      color: AiTone.active(context).withValues(alpha: 0.85),
    );
    final commentStyle = base.copyWith(
      color: AiTone.muted(context),
      fontStyle: FontStyle.italic,
    );
    final numberStyle = base.copyWith(
      color: AiTone.active(context).withValues(alpha: 0.7),
    );
    final spans = <InlineSpan>[];
    final buf = StringBuffer();
    void flushPlain() {
      if (buf.isEmpty) return;
      spans.add(TextSpan(text: buf.toString(), style: base));
      buf.clear();
    }

    var i = 0;
    while (i < code.length) {
      final ch = code[i];
      final next = i + 1 < code.length ? code[i + 1] : '';

      // Block comment `/* ... */`
      if (ch == '/' && next == '*') {
        flushPlain();
        final end = code.indexOf('*/', i + 2);
        final last = end == -1 ? code.length : end + 2;
        spans.add(TextSpan(text: code.substring(i, last), style: commentStyle));
        i = last;
        continue;
      }
      // Line comment: `//`, `#`, `--` (avoid stray `--` inside words by
      // requiring a non-word character before — for `#` we accept any
      // position since shell + Python comments often start the line).
      bool startsLineComment() {
        if (ch == '/' && next == '/') return true;
        if (ch == '#') return true;
        if (ch == '-' && next == '-') return true;
        return false;
      }

      if (startsLineComment()) {
        flushPlain();
        final eol = code.indexOf('\n', i);
        final last = eol == -1 ? code.length : eol;
        spans.add(TextSpan(text: code.substring(i, last), style: commentStyle));
        i = last;
        continue;
      }

      // Quoted string — match `"`, `'`, or `` ` ``. Honours `\\` escapes
      // so `"a\"b"` doesn't terminate on the inner quote.
      if (ch == '"' || ch == "'" || ch == '`') {
        flushPlain();
        var j = i + 1;
        while (j < code.length) {
          final c = code[j];
          if (c == '\\' && j + 1 < code.length) {
            j += 2;
            continue;
          }
          if (c == ch) {
            j++;
            break;
          }
          // Don't run strings across newlines — most languages don't
          // allow them and unclosed quotes would otherwise paint the
          // entire rest of the file as one string.
          if (c == '\n') break;
          j++;
        }
        spans.add(TextSpan(text: code.substring(i, j), style: stringStyle));
        i = j;
        continue;
      }

      // Numeric literal — int, float, hex. Require a non-word char
      // before to skip e.g. `x10` (identifier).
      if (_isDigit(ch.codeUnitAt(0))) {
        final prevOk =
            buf.isEmpty ||
            !_isIdentChar(buf.toString().codeUnitAt(buf.length - 1));
        if (prevOk) {
          flushPlain();
          var j = i;
          // Hex?
          if (ch == '0' && (next == 'x' || next == 'X')) {
            j = i + 2;
            while (j < code.length && _isHex(code.codeUnitAt(j))) {
              j++;
            }
          } else {
            while (j < code.length && _isDigit(code.codeUnitAt(j))) {
              j++;
            }
            // Optional decimal portion.
            if (j < code.length &&
                code[j] == '.' &&
                j + 1 < code.length &&
                _isDigit(code.codeUnitAt(j + 1))) {
              j++;
              while (j < code.length && _isDigit(code.codeUnitAt(j))) {
                j++;
              }
            }
          }
          spans.add(TextSpan(text: code.substring(i, j), style: numberStyle));
          i = j;
          continue;
        }
      }

      buf.write(ch);
      i++;
    }
    flushPlain();
    return spans;
  }

  static bool _isDigit(int code) => code >= 0x30 && code <= 0x39;
  static bool _isHex(int code) =>
      _isDigit(code) ||
      (code >= 0x41 && code <= 0x46) ||
      (code >= 0x61 && code <= 0x66);
  static bool _isIdentChar(int code) =>
      _isDigit(code) ||
      (code >= 0x41 && code <= 0x5a) ||
      (code >= 0x61 && code <= 0x7a) ||
      code == 0x5f;
}

InlineSpan _codeSpan(String text, TextStyle base, BuildContext context) {
  return WidgetSpan(
    alignment: PlaceholderAlignment.middle,
    child: Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s4,
        vertical: 1,
      ),
      decoration: BoxDecoration(
        color: AiTone.surfaceTint(context).withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(AppRadius.xs),
      ),
      child: Text(
        text,
        style: base.copyWith(
          fontFamily: 'monospace',
          fontFamilyFallback: const ['Menlo', 'Consolas', 'monospace'],
          fontSize: (base.fontSize ?? 13) - 1,
          color: AiTone.onSurface(context),
        ),
      ),
    ),
  );
}
