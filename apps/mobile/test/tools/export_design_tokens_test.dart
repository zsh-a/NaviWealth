import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/export_design_tokens.dart' as exporter;

/// Generator + freshness gate for `design_tokens/tokens.json`.
///
/// The exporter imports Flutter types (Color, TextStyle, Cubic), so it
/// cannot run under plain `dart run`; this test is the supported
/// entrypoint (run from `apps/mobile/`):
///
/// ```bash
/// # Regenerate design_tokens/tokens.json from the Dart tokens:
/// UPDATE_DESIGN_TOKENS=1 flutter test test/tools/export_design_tokens_test.dart
///
/// # Verify the committed file matches the Dart tokens (CI):
/// flutter test test/tools/export_design_tokens_test.dart
/// ```
///
/// `tool/check-design-tokens-export.sh` (repo root) wraps the check mode
/// and prints a diff; it sets DESIGN_TOKENS_OUT so the generated JSON is
/// also written to a temp file for diffing.
void main() {
  test('design_tokens/tokens.json matches the Dart design-system tokens', () {
    final generated = exporter.encodeTokens();
    final committed = File(exporter.kTokensJsonPath);

    if (Platform.environment['UPDATE_DESIGN_TOKENS'] == '1') {
      committed.writeAsStringSync(generated);
      return;
    }

    final outPath = Platform.environment['DESIGN_TOKENS_OUT'];
    if (outPath != null && outPath.isNotEmpty) {
      File(outPath).writeAsStringSync(generated);
    }

    expect(
      committed.existsSync(),
      isTrue,
      reason:
          '${exporter.kTokensJsonPath} is missing. Regenerate with: '
          'UPDATE_DESIGN_TOKENS=1 flutter test '
          'test/tools/export_design_tokens_test.dart',
    );
    expect(
      committed.readAsStringSync(),
      generated,
      reason:
          '${exporter.kTokensJsonPath} is stale relative to the Dart '
          'design-system tokens (Dart is the source of truth). Regenerate '
          'with: UPDATE_DESIGN_TOKENS=1 flutter test '
          'test/tools/export_design_tokens_test.dart',
    );
  });
}
