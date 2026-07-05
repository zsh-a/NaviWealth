part of 'ai_markdown.dart';

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
        // Route `flow` blocks to the flow diagram parser. If parsing
        // fails (empty / invalid DSL), fall back to a plain code block.
        if (lang == 'flow') {
          final diagram = FlowParser.parse(buf.toString());
          if (diagram != null) {
            blocks.add(_MdFlowBlock(diagram));
          } else {
            blocks.add(
              _MdCode(code: buf.toString(), language: lang, closed: closed),
            );
          }
        } else {
          blocks.add(
            _MdCode(code: buf.toString(), language: lang, closed: closed),
          );
        }
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
