import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/design_system/design_system.dart';

/// Guards against drift between the W3C tokens.json (Figma source of truth)
/// and the Dart token mirror. If you change one, this test forces you to
/// change the other.
void main() {
  late Map<String, dynamic> tokens;

  setUpAll(() {
    final file = File('design_tokens/tokens.json');
    expect(
      file.existsSync(),
      isTrue,
      reason: 'apps/mobile/design_tokens/tokens.json must exist',
    );
    tokens = json.decode(file.readAsStringSync()) as Map<String, dynamic>;
  });

  String colorAt(String path) {
    final parts = path.split('.');
    Map<String, dynamic> node = tokens;
    for (var i = 0; i < parts.length - 1; i++) {
      node = node[parts[i]] as Map<String, dynamic>;
    }
    final leaf = node[parts.last] as Map<String, dynamic>;
    return (leaf[r'$value'] as String).toUpperCase();
  }

  String hexOf(Color c) {
    final r = (c.r * 255).round();
    final g = (c.g * 255).round();
    final b = (c.b * 255).round();
    return '#${r.toRadixString(16).padLeft(2, '0')}'
            '${g.toRadixString(16).padLeft(2, '0')}'
            '${b.toRadixString(16).padLeft(2, '0')}'
        .toUpperCase();
  }

  num numAt(String path) {
    final parts = path.split('.');
    Map<String, dynamic> node = tokens;
    for (var i = 0; i < parts.length - 1; i++) {
      node = node[parts[i]] as Map<String, dynamic>;
    }
    final leaf = node[parts.last] as Map<String, dynamic>;
    return num.parse(leaf[r'$value'] as String);
  }

  test('brand seed matches Dart palette', () {
    expect(colorAt('color.brand.500'), hexOf(ColorPalette.brand500));
    expect(colorAt('color.brand.700'), hexOf(ColorPalette.brand700));
  });

  test('neutral palette matches', () {
    expect(colorAt('color.neutral.0'), hexOf(ColorPalette.neutral0));
    expect(colorAt('color.neutral.500'), hexOf(ColorPalette.neutral500));
    expect(colorAt('color.neutral.900'), hexOf(ColorPalette.neutral900));
  });

  test('accent green/red/cyan/amber match', () {
    expect(colorAt('color.accent.green.500'), hexOf(ColorPalette.green500));
    expect(colorAt('color.accent.red.500'), hexOf(ColorPalette.red500));
    expect(colorAt('color.accent.amber.500'), hexOf(ColorPalette.amber500));
    expect(colorAt('color.accent.cyan.500'), hexOf(ColorPalette.cyan500));
  });

  test('colorblind primitives match Dart', () {
    expect(colorAt('color.accent.colorblindBlue'), hexOf(ColorPalette.cbBlue));
    expect(
      colorAt('color.accent.colorblindOrange'),
      hexOf(ColorPalette.cbOrange),
    );
  });

  test('spacing scale matches', () {
    expect(numAt('spacing.s4'), Spacing.s4);
    expect(numAt('spacing.s16'), Spacing.s16);
    expect(numAt('spacing.s64'), Spacing.s64);
  });

  test('radius scale matches', () {
    expect(numAt('radius.sm'), Radii.sm);
    expect(numAt('radius.lg'), Radii.lg);
  });

  test('breakpoints match', () {
    expect(numAt('breakpoint.mobile'), Breakpoints.mobile);
    expect(numAt('breakpoint.desktop'), Breakpoints.desktop);
  });
}
