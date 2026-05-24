// FIR-99: lint guard against new Chinese-character literals in app source.
//
// Scope: scans all .dart files under lib/ and bin/ except generated files,
// the l10n directory, and any path listed in cn_literal_allowlist.txt.
// Fails (exit 1) on any CN char (CJK Unified Ideographs U+4E00-U+9FFF) that
// appears in code (i.e. outside `//`, `///`, and `/* */` comments).
//
// User-facing strings must live in lib/l10n/app_*.arb and be accessed via
// AppLocalizations. The allowlist exists to baseline files we have not yet
// migrated; new entries should be rare and require justification.

import 'dart:io';

const allowlistPath = 'tool/cn_literal_allowlist.txt';
final cnPattern = RegExp(r'[一-鿿]');

void main(List<String> args) {
  final repoRoot = _findMobileRoot();
  final allowlist = _loadAllowlist(File('$repoRoot/$allowlistPath'));

  final violations = <_Violation>[];
  final scanned = <String>[];
  final libDir = Directory('$repoRoot/lib');
  if (!libDir.existsSync()) {
    stderr.writeln('lint: lib/ not found at $repoRoot');
    exit(2);
  }

  for (final entity in libDir.listSync(recursive: true)) {
    if (entity is! File) continue;
    if (!entity.path.endsWith('.dart')) continue;
    final relative = entity.path.substring(repoRoot.length + 1);
    if (_isExcluded(relative)) continue;
    scanned.add(relative);
    if (allowlist.contains(relative)) continue;
    final content = entity.readAsStringSync();
    final stripped = _stripComments(content);
    final lines = stripped.split('\n');
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (cnPattern.hasMatch(line)) {
        final originalLine = content.split('\n')[i];
        violations.add(_Violation(relative, i + 1, originalLine.trimRight()));
      }
    }
  }

  // Detect stale allowlist entries (files that no longer exist or no longer
  // have CN literals). Stale entries should be pruned promptly so the
  // baseline keeps shrinking.
  final stale = <String>[];
  for (final entry in allowlist) {
    final f = File('$repoRoot/$entry');
    if (!f.existsSync()) {
      stale.add('$entry (missing)');
      continue;
    }
    final stripped = _stripComments(f.readAsStringSync());
    if (!cnPattern.hasMatch(stripped)) {
      stale.add('$entry (no CN literal)');
    }
  }

  if (violations.isEmpty && stale.isEmpty) {
    stdout.writeln(
      'cn-literal-check: ok (${scanned.length} files scanned, '
      '${allowlist.length} allowlisted)',
    );
    exit(0);
  }

  if (violations.isNotEmpty) {
    stderr.writeln(
      'cn-literal-check: ${violations.length} forbidden CN literal(s) found.\n'
      'User-facing strings must live in lib/l10n/app_*.arb and be accessed '
      'via AppLocalizations. If a literal is genuinely unavoidable (e.g. an '
      'internal seed or domain constant), add the file path to '
      '$allowlistPath with a TODO follow-up.\n',
    );
    for (final v in violations) {
      stderr.writeln('  ${v.path}:${v.line}: ${v.snippet}');
    }
  }
  if (stale.isNotEmpty) {
    stderr.writeln(
      '\ncn-literal-check: ${stale.length} stale allowlist entry/entries. '
      'Remove them from $allowlistPath:\n',
    );
    for (final e in stale) {
      stderr.writeln('  $e');
    }
  }
  exit(1);
}

bool _isExcluded(String relative) {
  if (relative.endsWith('.g.dart')) return true;
  if (relative.endsWith('.freezed.dart')) return true;
  if (relative.startsWith('lib/l10n/')) return true;
  return false;
}

/// Replace single-line, doc, and block comments with spaces so line numbers
/// and column offsets stay stable. Leaves string literals intact (the lint
/// is about literals, after all). Handles `r''` and `r""` raw strings,
/// triple-quoted strings, and escape sequences inside non-raw strings.
String _stripComments(String input) {
  final out = StringBuffer();
  var i = 0;
  final n = input.length;
  while (i < n) {
    final c = input[i];
    final next = i + 1 < n ? input[i + 1] : '';

    if (c == '/' && next == '/') {
      while (i < n && input[i] != '\n') {
        out.write(' ');
        i++;
      }
      continue;
    }
    if (c == '/' && next == '*') {
      out.write('  ');
      i += 2;
      while (i < n && !(input[i] == '*' && i + 1 < n && input[i + 1] == '/')) {
        out.write(input[i] == '\n' ? '\n' : ' ');
        i++;
      }
      if (i < n) {
        out.write('  ');
        i += 2;
      }
      continue;
    }

    // Raw string: r'...' or r"..."
    if (c == 'r' && (next == '"' || next == "'")) {
      final quote = next;
      out.write(c);
      out.write(next);
      i += 2;
      // Detect triple raw string r"""..."""
      if (i + 1 < n && input[i] == quote && input[i + 1] == quote) {
        out.write(input[i]);
        out.write(input[i + 1]);
        i += 2;
        while (i < n) {
          if (i + 2 < n &&
              input[i] == quote &&
              input[i + 1] == quote &&
              input[i + 2] == quote) {
            out.write(input[i]);
            out.write(input[i + 1]);
            out.write(input[i + 2]);
            i += 3;
            break;
          }
          out.write(input[i]);
          i++;
        }
        continue;
      }
      while (i < n && input[i] != quote) {
        out.write(input[i]);
        i++;
      }
      if (i < n) {
        out.write(input[i]);
        i++;
      }
      continue;
    }

    if (c == '"' || c == "'") {
      final quote = c;
      // Triple-quoted: """ or '''
      if (i + 2 < n && input[i + 1] == quote && input[i + 2] == quote) {
        out.write(input[i]);
        out.write(input[i + 1]);
        out.write(input[i + 2]);
        i += 3;
        while (i < n) {
          if (i + 2 < n &&
              input[i] == quote &&
              input[i + 1] == quote &&
              input[i + 2] == quote) {
            out.write(input[i]);
            out.write(input[i + 1]);
            out.write(input[i + 2]);
            i += 3;
            break;
          }
          if (input[i] == r'\' && i + 1 < n) {
            out.write(input[i]);
            out.write(input[i + 1]);
            i += 2;
            continue;
          }
          out.write(input[i]);
          i++;
        }
        continue;
      }
      out.write(input[i]);
      i++;
      while (i < n && input[i] != quote) {
        if (input[i] == r'\' && i + 1 < n) {
          out.write(input[i]);
          out.write(input[i + 1]);
          i += 2;
          continue;
        }
        if (input[i] == '\n') break; // unterminated single-line literal
        out.write(input[i]);
        i++;
      }
      if (i < n && input[i] == quote) {
        out.write(input[i]);
        i++;
      }
      continue;
    }

    out.write(c);
    i++;
  }
  return out.toString();
}

Set<String> _loadAllowlist(File f) {
  if (!f.existsSync()) return {};
  return f
      .readAsLinesSync()
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty && !l.startsWith('#'))
      .toSet();
}

String _findMobileRoot() {
  var dir = Directory.current;
  while (dir.path != dir.parent.path) {
    if (File('${dir.path}/pubspec.yaml').existsSync() &&
        Directory('${dir.path}/lib').existsSync() &&
        Directory('${dir.path}/lib/l10n').existsSync()) {
      return dir.path;
    }
    dir = dir.parent;
  }
  return Directory.current.path;
}

class _Violation {
  _Violation(this.path, this.line, this.snippet);
  final String path;
  final int line;
  final String snippet;
}
