import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('UI token migration guardrails stay enforced', () {
    final appRoot = _appRoot();
    final libDir = Directory('${appRoot.path}/lib');
    final libFiles = _dartFiles(libDir).toList(growable: false);

    expect(
      _countMatches(
        libFiles,
        RegExp(r'\b(?:captionStyle|bodyCaptionStyle|microCaptionStyle)\b'),
      ),
      greaterThanOrEqualTo(300),
      reason:
          'Caption text should keep using the shared text-style presets at '
          'scale instead of drifting back to hand-written typography.copyWith.',
    );

    _expectNoFileMatches(
      libFiles.where((file) => !file.path.endsWith('/text_style_presets.dart')),
      RegExp(
        r'(?:context\.theme\.)?typography\.xs\.copyWith\([\s\S]{0,240}?color:\s*colors\.mutedForeground',
      ),
      'Use context.captionStyle / bodyCaptionStyle / microCaptionStyle '
      'instead of rebuilding the muted xs caption style.',
    );

    _expectNoFileMatches(
      libFiles.where((file) => !file.path.endsWith('/text_style_presets.dart')),
      RegExp(r'(?:context\.theme\.)?typography\.xs\.copyWith\('),
      'Use context.captionStyle / captionLabelStyle / microCaptionStyle as '
      'the base for xs text instead of rebuilding typography.body.xs.copyWith.',
    );

    _expectNoMatches(
      libFiles.where((file) => !file.path.endsWith('/text_style_presets.dart')),
      RegExp(
        r'(?:context\.theme\.)?typography\.sm\.copyWith\(\s*color:\s*(?:context\.theme\.)?colors\.mutedForeground',
      ),
      'Use context.bodyCaptionStyle instead of rebuilding the muted sm '
      'caption style.',
    );

    _expectNoFileMatches(
      libFiles.where((file) => !file.path.endsWith('/text_style_presets.dart')),
      RegExp(
        r'labelStyle\.copyWith\([\s\S]{0,160}?color:\s*(?:context\.theme\.)?colors\.mutedForeground',
      ),
      'Use context.mutedLabelStyle instead of rebuilding the muted label '
      'style.',
    );

    _expectNoMatches(
      [
        Directory('${appRoot.path}/lib/app'),
        Directory('${appRoot.path}/lib/features'),
        Directory('${appRoot.path}/lib/core/ai'),
      ].expand(_dartFiles),
      RegExp(r'Theme\.of\('),
      'App shell, feature UI, and AI visual helpers should use context.theme / FTheme '
      'tokens, not Material Theme.of(...).',
    );

    _expectNoMatches(
      libFiles,
      RegExp(r'(ColorPalette|ExpenseCategoryColors)\.teal|Colors\.teal'),
      'Use CyanBrand / semantic tokens instead of legacy teal aliases.',
    );

    _expectNoMatches(
      libFiles,
      RegExp(r'#14B8A6|\bteal\b', caseSensitive: false),
      'Runtime UI code should use cyan brand naming and tokens, not legacy '
      'teal labels or hex values.',
    );

    _expectNoMatches(
      _dartFiles(Directory('${appRoot.path}/lib/features')).where(
        (file) => !file.path.endsWith(
          '/features/finance/shared/forms/manual_security_sheet.dart',
        ),
      ),
      RegExp(r'showFDialog|FDialog\.raw|FDialog\('),
      'Feature dialogs should go through design-system wrappers; the manual '
      'security picker is the only custom raw dialog exception.',
    );

    _expectNoMatches(
      _dartFiles(Directory('${appRoot.path}/lib/features/settings')),
      RegExp(r'fontWeight:\s*FontWeight\.(?:w500|w600|w700|bold)'),
      'Settings typography should use text-style presets/tokens rather than '
      'manual FontWeight overrides.',
    );

    _expectNoMatches(
      [
        ...[
          Directory('${appRoot.path}/lib/features/expense'),
          Directory('${appRoot.path}/lib/features/health'),
          Directory('${appRoot.path}/lib/features/knowledge'),
          Directory('${appRoot.path}/lib/features/cashflow'),
          Directory('${appRoot.path}/lib/features/ai_chat'),
          Directory('${appRoot.path}/lib/features/home'),
          Directory('${appRoot.path}/lib/features/finance/activity'),
          Directory('${appRoot.path}/lib/features/rebalance'),
          Directory('${appRoot.path}/lib/features/options_income'),
          Directory('${appRoot.path}/lib/features/fire'),
          Directory('${appRoot.path}/lib/features/analytics'),
          Directory('${appRoot.path}/lib/features/finance'),
          Directory('${appRoot.path}/lib/features/ingest'),
          Directory('${appRoot.path}/lib/features/investment'),
          Directory('${appRoot.path}/lib/features/finance/shared'),
          Directory('${appRoot.path}/lib/features/auth'),
        ].expand(_dartFiles),
      ].where((file) => file.existsSync()),
      RegExp(r'fontWeight:\s*[\s\S]{0,80}?FontWeight\.w600'),
      'Audited feature typography should use label/caption presets rather '
      'than manual FontWeight.w600.',
    );

    _expectNoFileMatches(
      libFiles.where(
        (file) =>
            !file.path.endsWith('/text_style_presets.dart') &&
            !file.path.endsWith('/typography_tokens.dart') &&
            !file.path.endsWith('/core/ai/visual/ai_typography.dart'),
      ),
      RegExp(r'fontWeight:\s*[\s\S]{0,80}?FontWeight\.w600'),
      'UI surfaces should use text-style presets/tokens rather than manual '
      'FontWeight.w600.',
    );

    _expectNoFileMatches(
      libFiles.where(
        (file) =>
            !file.path.endsWith('/text_style_presets.dart') &&
            !file.path.endsWith('/typography_tokens.dart') &&
            !file.path.endsWith('/core/ai/visual/ai_typography.dart'),
      ),
      RegExp(r'fontWeight:\s*[\s\S]{0,80}?FontWeight\.(?:w500|w700|bold)'),
      'UI surfaces should use text-style presets/tokens rather than manual '
      'FontWeight.w500/w700/bold.',
    );

    _expectNoFileMatches(
      libFiles.where((file) => !file.path.endsWith('/typography_tokens.dart')),
      RegExp(r'letterSpacing:\s*-?(?:0\.[1-9]\d*|[1-9]\d*(?:\.\d+)?)'),
      'UI surfaces should not override letterSpacing outside typography '
      'tokens.',
    );

    _expectNoMatches(
      libFiles,
      RegExp(r'EdgeInsets\.[^(]+\([^)]*\b(?:[0-9]+(?:\.[0-9]+)?)\b'),
      'UI spacing should use AppSpacing tokens rather than naked '
      'EdgeInsets numbers.',
    );

    _expectNoMatches(
      libFiles,
      RegExp(r'SizedBox\(\s*(?:width|height):\s*(?:[1-9]\d*(?:\.\d+)?|0\.\d+)'),
      'Fixed SizedBox dimensions should use AppSpacing/AppIconSizes tokens.',
    );

    _expectNoFileMatches(
      libFiles,
      RegExp(r'SizedBox\(\s*(?:width|height):\s*(?:[1-9]\d*(?:\.\d+)?|0\.\d+)'),
      'Fixed SizedBox dimensions should use AppSpacing/AppIconSizes/'
      'AppChartHeights/AppControlWidths tokens.',
    );

    _expectNoMatches(
      libFiles,
      RegExp(
        r'(?:BorderRadius|Radius)\.circular\(\s*(?:[0-9]+(?:\.[0-9]+)?)\s*\)',
      ),
      'Corner radii should use AppRadius tokens rather than naked numbers.',
    );

    _expectNoMatches(
      libFiles,
      RegExp(r'withValues\(\s*alpha:\s*(?:0|0\.[0-9]+|1(?:\.0)?)\b'),
      'Opacity should use AppOpacity tokens rather than raw alpha numbers.',
    );

    _expectNoMatches(
      libFiles,
      RegExp(
        r'(?:BorderSide\([^\n]*width:\s*|Border\.all\([^\n]*width:\s*|strokeWidth\s*=\s*|strokeWidth:\s*)(?:0|1|1\.2|1\.5|2|2\.2|3|4|6)\b',
      ),
      'Stroke widths should use AppStroke tokens rather than raw numbers.',
    );

    _expectNoMatches(
      libFiles,
      RegExp(r'\b(?:left|right|top|bottom):\s*(?:[1-9]\d*(?:\.\d+)?|0\.\d+)\b'),
      'Positional insets should use AppSpacing/AppRadius/AppStroke tokens '
      'rather than raw non-zero numbers.',
    );

    _expectNoMatches(
      libFiles,
      RegExp(
        r'\b(?:left|right|top|bottom):\s*[A-Za-z0-9_.]+\s*[+\-]\s*(?:[1-9]\d*(?:\.\d+)?|0\.\d+)\b',
      ),
      'Calculated positional insets should add/subtract design tokens rather '
      'than raw non-zero numbers.',
    );

    _expectNoHardcodedHexColors(
      [
        Directory('${appRoot.path}/lib/app'),
        Directory('${appRoot.path}/lib/core'),
        Directory('${appRoot.path}/lib/features'),
        Directory('${appRoot.path}/lib/design_system'),
      ].expand(_dartFiles),
    );

    _expectNoRawColorFactories(
      [
        Directory('${appRoot.path}/lib/app'),
        Directory('${appRoot.path}/lib/core'),
        Directory('${appRoot.path}/lib/features'),
        Directory('${appRoot.path}/lib/design_system'),
      ].expand(_dartFiles),
    );

    _expectNoMaterialColorSwatches(
      [
        Directory('${appRoot.path}/lib/app'),
        Directory('${appRoot.path}/lib/core'),
        Directory('${appRoot.path}/lib/features'),
        Directory('${appRoot.path}/lib/design_system'),
      ].expand(_dartFiles),
    );
  });
}

int _countMatches(Iterable<File> files, RegExp pattern) {
  var count = 0;
  for (final file in files) {
    count += pattern.allMatches(file.readAsStringSync()).length;
  }
  return count;
}

Iterable<File> _dartFiles(Directory root) {
  if (!root.existsSync()) return const [];
  return root
      .listSync(recursive: true)
      .whereType<File>()
      .where((file) => file.path.endsWith('.dart'))
      .where((file) => !file.path.endsWith('.g.dart'))
      .where((file) => !file.path.endsWith('.freezed.dart'));
}

void _expectNoMatches(Iterable<File> files, RegExp pattern, String message) {
  final violations = <String>[];
  for (final file in files) {
    final lines = file.readAsLinesSync();
    for (var i = 0; i < lines.length; i++) {
      if (pattern.hasMatch(lines[i])) {
        violations.add('${_relative(file.path)}:${i + 1}: ${lines[i].trim()}');
      }
    }
  }

  expect(violations, isEmpty, reason: '$message\n${violations.join('\n')}');
}

void _expectNoFileMatches(
  Iterable<File> files,
  RegExp pattern,
  String message,
) {
  final violations = <String>[];
  for (final file in files) {
    final text = file.readAsStringSync();
    if (pattern.hasMatch(text)) {
      violations.add(_relative(file.path));
    }
  }

  expect(violations, isEmpty, reason: '$message\n${violations.join('\n')}');
}

void _expectNoHardcodedHexColors(Iterable<File> files) {
  final violations = <String>[];
  final colorConstructor = RegExp(r'\bColor\s*\(\s*0x[0-9A-Fa-f]+');
  for (final file in files) {
    final lines = file.readAsLinesSync();
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (!colorConstructor.hasMatch(line)) continue;
      if (file.path.endsWith('/design_system/tokens/color_palette.dart')) {
        continue;
      }
      violations.add('${_relative(file.path)}:${i + 1}: ${line.trim()}');
    }
  }

  expect(
    violations,
    isEmpty,
    reason:
        'App/core/feature UI should use ColorPalette/SemanticColors tokens; '
        'raw 8-digit hex colors belong in the design-system palette only.\n'
        '${violations.join('\n')}',
  );
}

void _expectNoRawColorFactories(Iterable<File> files) {
  final violations = <String>[];
  final rawColorFactory = RegExp(r'\bColor\.(?:fromARGB|fromRGBO)\s*\(');
  for (final file in files) {
    final lines = file.readAsLinesSync();
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (rawColorFactory.hasMatch(line)) {
        violations.add('${_relative(file.path)}:${i + 1}: ${line.trim()}');
      }
    }
  }

  expect(
    violations,
    isEmpty,
    reason:
        'App/core/feature UI should use ColorPalette/SemanticColors tokens; '
        'raw Color.fromARGB/fromRGBO factories bypass the palette.\n'
        '${violations.join('\n')}',
  );
}

void _expectNoMaterialColorSwatches(Iterable<File> files) {
  final violations = <String>[];
  final materialColor = RegExp(r'\bColors\.([A-Za-z0-9_]+)');
  const allowed = {'transparent'};
  for (final file in files) {
    final lines = file.readAsLinesSync();
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      for (final match in materialColor.allMatches(line)) {
        final name = match.group(1);
        if (name == null || allowed.contains(name)) continue;
        violations.add('${_relative(file.path)}:${i + 1}: ${line.trim()}');
      }
    }
  }

  expect(
    violations,
    isEmpty,
    reason:
        'Use ColorPalette/SemanticColors/MarketColors tokens instead of '
        'Material Colors.* swatches. Colors.transparent is the only allowed '
        'Material color constant.\n'
        '${violations.join('\n')}',
  );
}

Directory _appRoot() {
  var current = Directory.current.absolute;
  while (true) {
    if (File('${current.path}/pubspec.yaml').existsSync() &&
        Directory('${current.path}/lib').existsSync() &&
        Directory('${current.path}/test').existsSync()) {
      return current;
    }
    final parent = current.parent;
    if (parent.path == current.path) {
      throw StateError('Could not locate apps/mobile root');
    }
    current = parent;
  }
}

String _relative(String path) {
  final root = _appRoot().path;
  if (path.startsWith('$root/')) {
    return path.substring(root.length + 1);
  }
  return path;
}
