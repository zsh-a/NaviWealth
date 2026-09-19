import 'package:flutter/widgets.dart';

import '../theme/app_theme_scope.dart';
import '../tokens/color_palette.dart';

/// Shared light field for floating material.
///
/// HyperOS-style soft glass reads as one material because nearby surfaces
/// share an environmental light source. Keeping the field in an inherited
/// scope prevents every card from inventing an unrelated highlight direction.
@immutable
class AppGlassLightField {
  const AppGlassLightField({
    required this.lightColor,
    required this.shadeColor,
    this.origin = const Alignment(-0.82, -1),
    this.energy = 1,
  });

  final Color lightColor;
  final Color shadeColor;
  final Alignment origin;
  final double energy;

  /// Derives a field from the resolved theme and optionally the active domain
  /// accent. The accent is deliberately mixed at low energy so the chrome
  /// responds to route context without recolouring readable content.
  factory AppGlassLightField.fromTheme(
    BuildContext context, {
    Color? accentColor,
  }) {
    final theme = context.appTheme;
    final dark = theme.brightness == Brightness.dark;
    final lightBase = dark ? theme.surfaces.raised : ColorPalette.neutral0;
    final accent = accentColor ?? theme.accent.fg;
    final lightColor = Color.lerp(
      lightBase,
      accent,
      dark
          ? (accentColor == null ? 0.22 : 0.30)
          : (accentColor == null ? 0.12 : 0.18),
    )!;
    final shadeColor = Color.lerp(
      theme.surfaces.canvas,
      theme.content.strong,
      dark ? 0.24 : 0.08,
    )!;
    return AppGlassLightField(
      lightColor: lightColor,
      shadeColor: shadeColor,
      energy: dark ? 0.86 : 0.92,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is AppGlassLightField &&
      other.lightColor == lightColor &&
      other.shadeColor == shadeColor &&
      other.origin == origin &&
      other.energy == energy;

  @override
  int get hashCode => Object.hash(lightColor, shadeColor, origin, energy);
}

/// Installs one light field for a page or shell.
///
/// When no explicit field is supplied, the field is derived from the resolved
/// app theme. Widget tests and isolated components can therefore use the same
/// material without having to install another provider.
class AppGlassEnvironment extends StatelessWidget {
  const AppGlassEnvironment({super.key, required this.child, this.field});

  final Widget child;
  final AppGlassLightField? field;

  static AppGlassLightField of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<_AppGlassEnvironmentScope>();
    return scope?.field ?? AppGlassLightField.fromTheme(context);
  }

  @override
  Widget build(BuildContext context) {
    return _AppGlassEnvironmentScope(
      field: field ?? AppGlassLightField.fromTheme(context),
      child: child,
    );
  }
}

class _AppGlassEnvironmentScope extends InheritedWidget {
  const _AppGlassEnvironmentScope({required this.field, required super.child});

  final AppGlassLightField field;

  @override
  bool updateShouldNotify(_AppGlassEnvironmentScope oldWidget) =>
      field != oldWidget.field;
}
