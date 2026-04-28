import 'package:flutter/material.dart';

import '../tokens/color_palette.dart';

/// Shadow scale exposed as a [ThemeExtension].
///
/// Two layered shadows per level (a tight ambient + a softer drop) give the
/// "expensive" fintech card depth without the "lifted-off-the-page" look of a
/// single hard shadow.
@immutable
class AppElevations extends ThemeExtension<AppElevations> {
  const AppElevations({
    required this.none,
    required this.level1,
    required this.level2,
    required this.level3,
    required this.level4,
  });

  final List<BoxShadow> none;
  final List<BoxShadow> level1;
  final List<BoxShadow> level2;
  final List<BoxShadow> level3;
  final List<BoxShadow> level4;

  factory AppElevations.light() {
    Color tint(double a) => ColorPalette.neutral900.withValues(alpha: a);
    return AppElevations(
      none: const [],
      level1: [
        BoxShadow(color: tint(0.04), blurRadius: 1, offset: const Offset(0, 1)),
        BoxShadow(color: tint(0.06), blurRadius: 2, offset: const Offset(0, 1)),
      ],
      level2: [
        BoxShadow(color: tint(0.05), blurRadius: 2, offset: const Offset(0, 1)),
        BoxShadow(color: tint(0.07), blurRadius: 6, offset: const Offset(0, 3)),
      ],
      level3: [
        BoxShadow(color: tint(0.06), blurRadius: 4, offset: const Offset(0, 2)),
        BoxShadow(
          color: tint(0.10),
          blurRadius: 12,
          offset: const Offset(0, 6),
        ),
      ],
      level4: [
        BoxShadow(color: tint(0.08), blurRadius: 6, offset: const Offset(0, 4)),
        BoxShadow(
          color: tint(0.16),
          blurRadius: 24,
          offset: const Offset(0, 12),
        ),
      ],
    );
  }

  factory AppElevations.dark() {
    Color tint(double a) => ColorPalette.neutral1000.withValues(alpha: a);
    return AppElevations(
      none: const [],
      level1: [
        BoxShadow(color: tint(0.30), blurRadius: 2, offset: const Offset(0, 1)),
      ],
      level2: [
        BoxShadow(color: tint(0.40), blurRadius: 6, offset: const Offset(0, 3)),
      ],
      level3: [
        BoxShadow(
          color: tint(0.50),
          blurRadius: 12,
          offset: const Offset(0, 6),
        ),
      ],
      level4: [
        BoxShadow(
          color: tint(0.60),
          blurRadius: 24,
          offset: const Offset(0, 12),
        ),
      ],
    );
  }

  static AppElevations of(BuildContext context) =>
      Theme.of(context).extension<AppElevations>() ?? AppElevations.light();

  @override
  AppElevations copyWith({
    List<BoxShadow>? none,
    List<BoxShadow>? level1,
    List<BoxShadow>? level2,
    List<BoxShadow>? level3,
    List<BoxShadow>? level4,
  }) {
    return AppElevations(
      none: none ?? this.none,
      level1: level1 ?? this.level1,
      level2: level2 ?? this.level2,
      level3: level3 ?? this.level3,
      level4: level4 ?? this.level4,
    );
  }

  @override
  AppElevations lerp(ThemeExtension<AppElevations>? other, double t) {
    if (other is! AppElevations) return this;
    List<BoxShadow> lerpList(List<BoxShadow> a, List<BoxShadow> b) {
      final length = a.length < b.length ? a.length : b.length;
      return [for (var i = 0; i < length; i++) BoxShadow.lerp(a[i], b[i], t)!];
    }

    return AppElevations(
      none: t < 0.5 ? none : other.none,
      level1: lerpList(level1, other.level1),
      level2: lerpList(level2, other.level2),
      level3: lerpList(level3, other.level3),
      level4: lerpList(level4, other.level4),
    );
  }
}
