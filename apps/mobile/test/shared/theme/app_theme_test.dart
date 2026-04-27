import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/shared/theme/app_theme.dart';
import 'package:naviwealth/shared/theme/design_tokens.dart';

void main() {
  test('light theme uses Material 3 + brand seed', () {
    final theme = AppTheme.light();
    expect(theme.useMaterial3, isTrue);
    expect(theme.brightness, Brightness.light);
    expect(theme.colorScheme.brightness, Brightness.light);
  });

  test('dark theme uses Material 3 + brand seed', () {
    final theme = AppTheme.dark();
    expect(theme.useMaterial3, isTrue);
    expect(theme.brightness, Brightness.dark);
    expect(theme.colorScheme.brightness, Brightness.dark);
  });

  test('SemanticColors extension is registered for both brightnesses', () {
    expect(
      AppTheme.light().extension<SemanticColors>(),
      same(SemanticColors.light),
    );
    expect(
      AppTheme.dark().extension<SemanticColors>(),
      same(SemanticColors.dark),
    );
  });

  test('SemanticColors light vs dark differ for gain/loss', () {
    expect(SemanticColors.light.gain, isNot(SemanticColors.dark.gain));
    expect(SemanticColors.light.loss, isNot(SemanticColors.dark.loss));
  });
}
