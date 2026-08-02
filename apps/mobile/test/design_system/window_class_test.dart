import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/design_system/design_system.dart';

void main() {
  group('AppWindowClass width', () {
    const cases = <(double, AppWidthClass)>[
      (0, AppWidthClass.compact),
      (599, AppWidthClass.compact),
      (600, AppWidthClass.medium),
      (839, AppWidthClass.medium),
      (840, AppWidthClass.expanded),
      (1199, AppWidthClass.expanded),
      (1200, AppWidthClass.large),
      (1599, AppWidthClass.large),
      (1600, AppWidthClass.extraLarge),
    ];

    for (final entry in cases) {
      test('${entry.$1} resolves to ${entry.$2.name}', () {
        expect(AppWindowClass.widthClassFor(entry.$1), entry.$2);
      });
    }
  });

  group('AppWindowClass height', () {
    const cases = <(double, AppHeightClass)>[
      (0, AppHeightClass.compact),
      (479, AppHeightClass.compact),
      (480, AppHeightClass.medium),
      (899, AppHeightClass.medium),
      (900, AppHeightClass.expanded),
    ];

    for (final entry in cases) {
      test('${entry.$1} resolves to ${entry.$2.name}', () {
        expect(AppWindowClass.heightClassFor(entry.$1), entry.$2);
      });
    }
  });

  test('fromSize combines independent width and height classes', () {
    final classification = AppWindowClass.fromSize(const Size(1024, 440));

    expect(classification.width, AppWidthClass.expanded);
    expect(classification.height, AppHeightClass.compact);
    expect(classification.isAtLeastExpanded, isTrue);
    expect(classification.hasCompactHeight, isTrue);
  });
}
