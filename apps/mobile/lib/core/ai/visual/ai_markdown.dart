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

import '../../../design_system/tokens/dimens_tokens.dart';
import '../../../l10n/gen/app_localizations.dart';
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: children,
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
    return _selectableRich(spans, selectable: selectable);
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
  const _MdListItem(this.text, this.marker);
  final String text;

  /// `null` for unordered (bullet); otherwise the displayed prefix
  /// ("1.", "2.", …). Pre-rendered by the parser so we keep the model's
  /// own numbering rather than re-numbering.
  final String? marker;
}

class _MdList extends _MdBlock {
  const _MdList(this.items, this.ordered);
  final List<_MdListItem> items;
  final bool ordered;

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
      final spans = _InlineParser.parse(item.text, base, context);
      if (isLast && trailing != null) spans.add(trailing);
      rows.add(
        Padding(
          padding: EdgeInsets.only(bottom: isLast ? 0 : AppSpacing.s2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _bullet(context, base, item.marker),
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

  Widget _bullet(BuildContext context, TextStyle base, String? marker) {
    final style = base.copyWith(color: AiTone.muted(context));
    if (marker != null) {
      return Padding(
        padding: const EdgeInsets.only(right: AppSpacing.s8),
        child: SizedBox(
          width: 18,
          child: Text(marker, style: style, textAlign: TextAlign.right),
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

    final spans = <InlineSpan>[TextSpan(text: code, style: mono)];
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
          Padding(
            padding: EdgeInsets.fromLTRB(
              AppSpacing.s12,
              (lang.isNotEmpty || closed) ? AppSpacing.s2 : AppSpacing.s8,
              AppSpacing.s12,
              AppSpacing.s8,
            ),
            child: _selectableRich(spans, selectable: selectable),
          ),
        ],
      ),
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
        child: selectable
            ? SelectableText.rich(
                TextSpan(children: spans),
                textAlign: align,
              )
            : Text.rich(TextSpan(children: spans), textAlign: align),
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

    final wrapped = ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.sm),
      // Wide tables stay readable: scroll horizontally rather than
      // squeezing cells past their intrinsic width.
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: table,
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
          child: Icon(icon, size: 14, color: color),
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
        final ordered = isOrd;
        final items = <_MdListItem>[];
        var j = i;
        while (j < lines.length) {
          final l = lines[j];
          if (l.trim().isEmpty) break;
          if (ordered) {
            final m = _ordered.firstMatch(l);
            if (m == null) break;
            items.add(_MdListItem(m.group(3)!, '${m.group(2)}.'));
          } else {
            final m = _unordered.firstMatch(l);
            if (m == null) break;
            items.add(_MdListItem(m.group(2)!, null));
          }
          j++;
        }
        blocks.add(_MdList(items, ordered));
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
        if (close != -1 &&
            close + 1 < text.length &&
            text[close + 1] == '(') {
          final paren = text.indexOf(')', close + 2);
          if (paren != -1) {
            final label = text.substring(i + 1, close);
            flush();
            final linkStyle = base.copyWith(
              color: AiTone.active(context),
              decoration: TextDecoration.underline,
              decorationColor: AiTone.active(context).withValues(alpha: 0.4),
            );
            _walk(label, linkStyle, context, out);
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
