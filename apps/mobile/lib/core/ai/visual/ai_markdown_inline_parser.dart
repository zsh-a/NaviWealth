part of 'ai_markdown.dart';

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
        final childStyle = AiType.strong(base);
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
              decorationColor: AiTone.active(
                context,
              ).withValues(alpha: AppOpacity.disabled),
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
            color: AiTone.surfaceTint(
              context,
            ).withValues(alpha: AppOpacity.scrim),
            borderRadius: BorderRadius.circular(AppRadius.sm),
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
    AppMessenger.show(
      context,
      ToastKind.error,
      AppLocalizations.of(context).aiChatLinkOpenFailed,
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
      color: AiTone.active(context).withValues(alpha: AppOpacity.overlay),
    );
    final commentStyle = base.copyWith(
      color: AiTone.muted(context),
      fontStyle: FontStyle.italic,
    );
    final numberStyle = base.copyWith(
      color: AiTone.active(context).withValues(alpha: AppOpacity.strong),
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
        color: AiTone.surfaceTint(
          context,
        ).withValues(alpha: AppOpacity.prominent),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Text(
        text,
        style: base.copyWith(
          fontFamily: 'monospace',
          fontFamilyFallback: const ['Menlo', 'Consolas', 'monospace'],
          fontSize: (base.fontSize ?? TypographyTokens.bodySmall.fontSize!) - 1,
          color: AiTone.onSurface(context),
        ),
      ),
    ),
  );
}
