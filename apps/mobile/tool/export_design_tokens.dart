/// Exports the Dart design-system tokens to `design_tokens/tokens.json`.
///
/// Dart is the single source of truth (blueprint doc 15 §10 "SSOT 治理");
/// the JSON file is a generated, read-only export for design tools
/// (Tokens Studio / Figma import, W3C Design Tokens format).
///
/// This library imports `package:flutter` types (Color, TextStyle, Cubic),
/// so it cannot run under plain `dart run`. The supported entrypoint is the
/// test wrapper, executed from `apps/mobile/`:
///
/// ```bash
/// # Regenerate design_tokens/tokens.json:
/// UPDATE_DESIGN_TOKENS=1 flutter test test/tools/export_design_tokens_test.dart
///
/// # Verify the committed file is up to date (CI gate):
/// flutter test test/tools/export_design_tokens_test.dart
/// ```
///
/// Values are read from the design-system constants at run time — never
/// copy literals into this file. Adding a *new* token constant requires
/// adding one line here so it is exported.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:naviwealth/design_system/theme/accent_colors.dart';
import 'package:naviwealth/design_system/theme/market_color_mode.dart';
import 'package:naviwealth/design_system/theme/market_colors.dart';
import 'package:naviwealth/design_system/theme/semantic_colors.dart';
import 'package:naviwealth/design_system/tokens/breakpoints.dart';
import 'package:naviwealth/design_system/tokens/color_palette.dart';
import 'package:naviwealth/design_system/tokens/dimens_tokens.dart';
import 'package:naviwealth/design_system/tokens/motion_tokens.dart';
import 'package:naviwealth/design_system/tokens/typography_tokens.dart';

/// Relative path of the exported file from the `apps/mobile` package root.
const String kTokensJsonPath = 'design_tokens/tokens.json';

/// Serializes the full token tree as pretty JSON (2-space indent, stable
/// insertion order, trailing newline).
String encodeTokens() {
  const encoder = JsonEncoder.withIndent('  ');
  return '${encoder.convert(buildTokens())}\n';
}

/// Writes the export to [path] (defaults to [kTokensJsonPath] relative to
/// the current working directory, which is `apps/mobile` under
/// `flutter test`).
void writeTokens({String path = kTokensJsonPath}) {
  File(path).writeAsStringSync(encodeTokens());
}

// ─── Serialization helpers ──────────────────────────────────────────────

String _hex(Color color) {
  final argb = color.toARGB32();
  final alpha = (argb >> 24) & 0xFF;
  final rgb = (argb & 0xFFFFFF).toRadixString(16).toUpperCase().padLeft(6, '0');
  if (alpha == 0xFF) return '#$rgb';
  return '#$rgb${alpha.toRadixString(16).toUpperCase().padLeft(2, '0')}';
}

String _numStr(double value) {
  if (value == value.roundToDouble()) return value.toInt().toString();
  return value.toString();
}

Map<String, Object> _color(Color color, [String? description]) => {
  r'$value': _hex(color),
  r'$type': 'color',
  r'$description': ?description,
};

Map<String, Object> _dimension(double value, [String? description]) => {
  r'$value': _numStr(value),
  r'$type': 'dimension',
  r'$description': ?description,
};

Map<String, Object> _number(double value, [String? description]) => {
  r'$value': value,
  r'$type': 'number',
  r'$description': ?description,
};

Map<String, Object> _duration(Duration duration, [String? description]) => {
  r'$value': '${duration.inMilliseconds}ms',
  r'$type': 'duration',
  r'$description': ?description,
};

Map<String, Object> _easing(Curve curve) => {
  r'$value': curve is Cubic
      ? 'cubic-bezier(${_numStr(curve.a)}, ${_numStr(curve.b)}, '
            '${_numStr(curve.c)}, ${_numStr(curve.d)})'
      : 'linear',
  r'$type': 'cubicBezier',
};

Map<String, Object> _shadow(List<BoxShadow> layers) => {
  r'$type': 'shadow',
  r'$value': [
    for (final layer in layers)
      <String, Object>{
        'color': _hex(layer.color),
        'offsetX': _numStr(layer.offset.dx),
        'offsetY': _numStr(layer.offset.dy),
        'blur': _numStr(layer.blurRadius),
        'spread': _numStr(layer.spreadRadius),
      },
  ],
};

Map<String, Object> _typography(TextStyle style) {
  final features = style.fontFeatures;
  return {
    r'$type': 'typography',
    r'$value': <String, Object>{
      'fontFamily': style.fontFamily ?? TypographyTokens.fontFamilySans,
      'fontSize': _numStr(style.fontSize!),
      'fontWeight': '${(style.fontWeight ?? FontWeight.w400).value}',
      'lineHeight': _numStr(style.height!),
      'letterSpacing': _numStr(style.letterSpacing ?? 0),
      if (features != null && features.isNotEmpty)
        'fontFeatures': features.map((f) => f.feature).join(','),
    },
  };
}

// ─── Token tree ─────────────────────────────────────────────────────────

/// Builds the full token tree in a fixed, deterministic key order.
Map<String, Object> buildTokens() => {
  r'$schema': 'https://design-tokens.github.io/community-group/format/',
  r'$description':
      'NaviWealth design tokens. GENERATED from the Dart design system '
      '(apps/mobile/lib/design_system) by '
      'apps/mobile/tool/export_design_tokens.dart — do not edit by hand. '
      'Dart is the source of truth; this file is a read-only export for '
      'design tools (Tokens Studio / Figma). Regenerate from apps/mobile: '
      'UPDATE_DESIGN_TOKENS=1 flutter test '
      'test/tools/export_design_tokens_test.dart',
  'color': _colorGroup(),
  'spacing': _spacingGroup(),
  'stroke': _strokeGroup(),
  'radius': _radiusGroup(),
  'opacity': _opacityGroup(),
  'iconSize': _iconSizeGroup(),
  'blur': _blurGroup(),
  'shadow': _shadowGroup(),
  'typography': _typographyGroup(),
  'motion': _motionGroup(),
  'breakpoint': _breakpointGroup(),
};

Map<String, Object> _colorGroup() => {
  'brand': {
    r'$description': 'Cyan brand ramp — ColorPalette.cyanBrand*.',
    '50': _color(ColorPalette.cyanBrand50),
    '100': _color(ColorPalette.cyanBrand100),
    '200': _color(ColorPalette.cyanBrand200),
    '300': _color(ColorPalette.cyanBrand300),
    '400': _color(ColorPalette.cyanBrand400, 'Dark-mode primary fg'),
    '500': _color(ColorPalette.cyanBrand500, 'Light-mode primary fg'),
    '600': _color(ColorPalette.cyanBrand600),
    '700': _color(ColorPalette.cyanBrand700),
    '800': _color(ColorPalette.cyanBrand800),
    '900': _color(ColorPalette.cyanBrand900),
  },
  'navy': {
    r'$description':
        'Deep blue-black text / dark-surface ramp — ColorPalette.navy*.',
    '50': _color(ColorPalette.navy50),
    '100': _color(ColorPalette.navy100),
    '200': _color(ColorPalette.navy200),
    '300': _color(ColorPalette.navy300),
    '400': _color(ColorPalette.navy400),
    '500': _color(ColorPalette.navy500),
    '600': _color(ColorPalette.navy600),
    '700': _color(ColorPalette.navy700),
    '800': _color(ColorPalette.navy800),
    '900': _color(ColorPalette.navy900),
    '950': _color(ColorPalette.navy950),
    'glass': _color(ColorPalette.navyGlass),
    'raised': _color(ColorPalette.navyRaised),
    'hero': _color(ColorPalette.navyHero),
    'softBorder': _color(ColorPalette.navySoftBorder),
  },
  'neutral': {
    '0': _color(ColorPalette.neutral0),
    '50': _color(ColorPalette.neutral50),
    '100': _color(ColorPalette.neutral100),
    '200': _color(ColorPalette.neutral200),
    '300': _color(ColorPalette.neutral300),
    '400': _color(ColorPalette.neutral400),
    '500': _color(ColorPalette.neutral500),
    '600': _color(ColorPalette.neutral600),
    '700': _color(ColorPalette.neutral700),
    '800': _color(ColorPalette.neutral800),
    '900': _color(ColorPalette.neutral900),
    '950': _color(ColorPalette.neutral950),
    '1000': _color(ColorPalette.neutral1000),
  },
  'oled': {
    r'$description':
        'True-black surfaces — ColorPalette.oled* (AppSurfaceStyle.oled).',
    'canvas': _color(ColorPalette.oledCanvas),
    'card': _color(ColorPalette.oledCard),
    'raised': _color(ColorPalette.oledRaised),
    'hero': _color(ColorPalette.oledHero),
  },
  'surface': {
    r'$description': 'Light-mode surfaces — ColorPalette.surface*.',
    'background': _color(ColorPalette.surfaceBackground),
    'surface': _color(ColorPalette.surface),
    'raised': _color(ColorPalette.surfaceRaised),
    'overlay': _color(ColorPalette.surfaceOverlay),
    'hairline': _color(ColorPalette.surfaceHairline),
  },
  'accent': {
    'green': {
      r'$description':
          'Profit / success (emerald) — ColorPalette.green*. '
          '500 = dark-mode fg, 600 = light-mode fg.',
      '50': _color(ColorPalette.green50),
      '100': _color(ColorPalette.green100),
      '300': _color(ColorPalette.green300),
      '500': _color(ColorPalette.green500),
      '600': _color(ColorPalette.green600),
      '700': _color(ColorPalette.green700),
      '900': _color(ColorPalette.green900),
      '950': _color(ColorPalette.green950),
      'containerDark': _color(ColorPalette.greenContainerDark),
    },
    'red': {
      r'$description':
          'Loss / danger (rose) — ColorPalette.red*. '
          '500 = dark-mode fg, 600 = light-mode fg.',
      '50': _color(ColorPalette.red50),
      '100': _color(ColorPalette.red100),
      '300': _color(ColorPalette.red300),
      '500': _color(ColorPalette.red500),
      '600': _color(ColorPalette.red600),
      '700': _color(ColorPalette.red700),
      '900': _color(ColorPalette.red900),
      '950': _color(ColorPalette.red950),
      'containerDark': _color(ColorPalette.redContainerDark),
    },
    'amber': {
      '50': _color(ColorPalette.amber50),
      '100': _color(ColorPalette.amber100),
      '400': _color(ColorPalette.amber400),
      '450': _color(ColorPalette.amber450),
      '500': _color(ColorPalette.amber500),
      '700': _color(ColorPalette.amber700),
      '950': _color(ColorPalette.amber950),
    },
    'cyan': {
      '50': _color(ColorPalette.cyan50),
      '100': _color(ColorPalette.cyan100),
      '500': _color(ColorPalette.cyan500),
      '600': _color(ColorPalette.cyan600),
      '700': _color(ColorPalette.cyan700),
      '950': _color(ColorPalette.cyan950),
    },
    'violet': {
      '50': _color(ColorPalette.violet50),
      '100': _color(ColorPalette.violet100),
      '400': _color(ColorPalette.violet400),
      '500': _color(ColorPalette.violet500),
      '700': _color(ColorPalette.violet700),
      '800': _color(ColorPalette.violet800),
      '900': _color(ColorPalette.violet900),
    },
    'indigo': {
      '50': _color(ColorPalette.indigo50),
      '100': _color(ColorPalette.indigo100),
      '400': _color(ColorPalette.indigo400),
      '700': _color(ColorPalette.indigo700),
      '800': _color(ColorPalette.indigo800),
      '900': _color(ColorPalette.indigo900),
    },
    'orange': {'500': _color(ColorPalette.orange500)},
    'colorblind': {
      r'$description':
          'Wong / Okabe-Ito accents for the colorblind market mode — '
          'ColorPalette.cb*.',
      'blue': _color(ColorPalette.cbBlue),
      'blueLight': _color(ColorPalette.cbBlueLight),
      'blueDark': _color(ColorPalette.cbBlueDark),
      'blueContainerLight': _color(ColorPalette.cbBlueContainerLight),
      'blueContainerDark': _color(ColorPalette.cbBlueContainerDark),
      'orange': _color(ColorPalette.cbOrange),
      'orangeLight': _color(ColorPalette.cbOrangeLight),
      'orangeDark': _color(ColorPalette.cbOrangeDark),
      'orangeContainerLight': _color(ColorPalette.cbOrangeContainerLight),
      'orangeContainerDark': _color(ColorPalette.cbOrangeContainerDark),
    },
  },
  'overlay': {
    r'$description':
        'Shadow / scrim / glow colors — ColorPalette.shadow*, scrim*, '
        'profitGlow*.',
    'shadowMedium': _color(ColorPalette.shadowMedium),
    'shadowDarkRaised': _color(ColorPalette.shadowDarkRaised),
    'shadowDarkHero': _color(ColorPalette.shadowDarkHero),
    'scrimLight': _color(ColorPalette.scrimLight),
    'scrimDark': _color(ColorPalette.scrimDark),
    'shadowNavy04': _color(ColorPalette.shadowNavy04),
    'shadowNavy08': _color(ColorPalette.shadowNavy08),
    'shadowNavy10': _color(ColorPalette.shadowNavy10),
    'shadowCyan04': _color(ColorPalette.shadowCyan04),
    'profitGlowDark': _color(ColorPalette.profitGlowDark),
    'profitGlowLight': _color(ColorPalette.profitGlowLight),
  },
  'chart': {
    r'$description':
        'Chart-only categorical series accents — ColorPalette.chart*.',
    'cyanDark': _color(ColorPalette.chartCyanDark),
    'purpleDark': _color(ColorPalette.chartPurpleDark),
    'emeraldDark': _color(ColorPalette.chartEmeraldDark),
    'pinkDark': _color(ColorPalette.chartPinkDark),
    'yellowDark': _color(ColorPalette.chartYellowDark),
    'blueDark': _color(ColorPalette.chartBlueDark),
    'roseDark': _color(ColorPalette.chartRoseDark),
    'purpleLight': _color(ColorPalette.chartPurpleLight),
    'pinkLight': _color(ColorPalette.chartPinkLight),
    'yellowLight': _color(ColorPalette.chartYellowLight),
  },
  'knowledge': {
    r'$description': 'Knowledge object-type accents — KnowledgeTypeColors.',
    'principle': _color(KnowledgeTypeColors.principle),
    'assumption': _color(KnowledgeTypeColors.assumption),
    'concept': _color(KnowledgeTypeColors.concept),
    'experiment': _color(KnowledgeTypeColors.experiment),
    'routine': _color(KnowledgeTypeColors.routine),
  },
  'expenseCategory': {
    r'$description':
        'Expense-category accents — ExpenseCategoryColors. Hex values match '
        'kExpenseCategorySeedHexByPath in the Finance expense domain.',
    'dining': _color(ExpenseCategoryColors.dining),
    'groceries': _color(ExpenseCategoryColors.groceries),
    'coffee': _color(ExpenseCategoryColors.coffee),
    'transport': _color(ExpenseCategoryColors.transport),
    'rideHailing': _color(ExpenseCategoryColors.rideHailing),
    'housing': _color(ExpenseCategoryColors.housing),
    'utilities': _color(ExpenseCategoryColors.utilities),
    'household': _color(ExpenseCategoryColors.household),
    'shopping': _color(ExpenseCategoryColors.shopping),
    'subscriptions': _color(ExpenseCategoryColors.subscriptions),
    'entertainment': _color(ExpenseCategoryColors.entertainment),
    'medical': _color(ExpenseCategoryColors.medical),
    'fitness': _color(ExpenseCategoryColors.fitness),
    'education': _color(ExpenseCategoryColors.education),
    'travel': _color(ExpenseCategoryColors.travel),
    'communication': _color(ExpenseCategoryColors.communication),
    'gift': _color(ExpenseCategoryColors.gift),
    'familySupport': _color(ExpenseCategoryColors.familySupport),
    'pets': _color(ExpenseCategoryColors.pets),
    'trading': _color(ExpenseCategoryColors.trading),
    'tradingFee': _color(ExpenseCategoryColors.tradingFee),
    'tradingTax': _color(ExpenseCategoryColors.tradingTax),
    'tradingInterest': _color(ExpenseCategoryColors.tradingInterest),
    'tax': _color(ExpenseCategoryColors.tax),
    'taxWithholding': _color(ExpenseCategoryColors.taxWithholding),
    'other': _color(ExpenseCategoryColors.other),
    'fastfood': _color(ExpenseCategoryColors.fastfood),
    'car': _color(ExpenseCategoryColors.car),
    'apartment': _color(ExpenseCategoryColors.apartment),
    'movie': _color(ExpenseCategoryColors.movie),
    'hospital': _color(ExpenseCategoryColors.hospital),
    'cart': _color(ExpenseCategoryColors.cart),
    'redeem': _color(ExpenseCategoryColors.redeem),
    'category': _color(ExpenseCategoryColors.category),
    'pieOther': _color(ExpenseCategoryColors.pieOther),
  },
  'interaction': {
    r'$description':
        'Brand interaction roles resolved per brightness — AccentColors.',
    'light': {
      'primary': _color(AccentColors.primary(Brightness.light)),
      'onPrimary': _color(AccentColors.onPrimary(Brightness.light)),
      'tint': _color(AccentColors.tint(Brightness.light)),
      'areaFill': _color(AccentColors.areaFill(Brightness.light)),
    },
    'dark': {
      'primary': _color(AccentColors.primary(Brightness.dark)),
      'onPrimary': _color(AccentColors.onPrimary(Brightness.dark)),
      'tint': _color(AccentColors.tint(Brightness.dark)),
      'areaFill': _color(AccentColors.areaFill(Brightness.dark)),
    },
    'series': _color(AccentColors.series, 'Chart primary series'),
  },
  'semantic': {
    r'$description':
        'Direction-neutral status colors — SemanticColors.light / .dark.',
    'light': _semanticSet(SemanticColors.light),
    'dark': _semanticSet(SemanticColors.dark),
  },
  'market': _marketGroup(),
};

Map<String, Object> _semanticSet(SemanticColors c) => {
  'success': _color(c.success),
  'onSuccess': _color(c.onSuccess),
  'successContainer': _color(c.successContainer),
  'onSuccessContainer': _color(c.onSuccessContainer),
  'warning': _color(c.warning),
  'onWarning': _color(c.onWarning),
  'warningContainer': _color(c.warningContainer),
  'onWarningContainer': _color(c.onWarningContainer),
  'danger': _color(c.danger),
  'onDanger': _color(c.onDanger),
  'dangerContainer': _color(c.dangerContainer),
  'onDangerContainer': _color(c.onDangerContainer),
  'info': _color(c.info),
  'onInfo': _color(c.onInfo),
  'infoContainer': _color(c.infoContainer),
  'onInfoContainer': _color(c.onInfoContainer),
  'divider': _color(c.divider),
  'scrim': _color(c.scrim),
};

Map<String, Object> _marketGroup() => {
  r'$description':
      'Direction-sensitive colors — MarketColors.fromMode per '
      'MarketColorMode and brightness. redUpGreenDown is the default (中国'
      '习惯); greenUpRedDown is the international convention; colorblind '
      'uses the Wong / Okabe-Ito palette.',
  for (final mode in MarketColorMode.values)
    mode.name: {
      'light': _marketSet(
        MarketColors.fromMode(mode, brightness: Brightness.light),
      ),
      'dark': _marketSet(
        MarketColors.fromMode(mode, brightness: Brightness.dark),
      ),
    },
};

Map<String, Object> _marketSet(MarketColors m) => {
  'up': _color(m.up),
  'upMuted': _color(m.upMuted),
  'onUp': _color(m.onUp),
  'upContainer': _color(m.upContainer),
  'onUpContainer': _color(m.onUpContainer),
  'down': _color(m.down),
  'downMuted': _color(m.downMuted),
  'onDown': _color(m.onDown),
  'downContainer': _color(m.downContainer),
  'onDownContainer': _color(m.onDownContainer),
  'flat': _color(m.flat),
  'onFlat': _color(m.onFlat),
  'profitGlow': _color(m.profitGlow),
};

Map<String, Object> _spacingGroup() => {
  r'$description': 'Spacing scale — AppSpacing.',
  's0': _dimension(AppSpacing.s0),
  'hairline': _dimension(AppSpacing.hairline),
  's2': _dimension(AppSpacing.s2),
  'accentBar': _dimension(AppSpacing.accentBar),
  's4': _dimension(AppSpacing.s4),
  's6': _dimension(AppSpacing.s6),
  's8': _dimension(AppSpacing.s8),
  's10': _dimension(AppSpacing.s10),
  's12': _dimension(AppSpacing.s12),
  's14': _dimension(AppSpacing.s14),
  's16': _dimension(AppSpacing.s16),
  's20': _dimension(AppSpacing.s20),
  's24': _dimension(AppSpacing.s24),
  's28': _dimension(AppSpacing.s28),
  's32': _dimension(AppSpacing.s32),
  's40': _dimension(AppSpacing.s40),
  's48': _dimension(AppSpacing.s48),
  's56': _dimension(AppSpacing.s56),
  's64': _dimension(AppSpacing.s64),
};

Map<String, Object> _strokeGroup() => {
  r'$description': 'Border / line widths — AppStroke.',
  'none': _dimension(AppStroke.none),
  'hairline': _dimension(AppStroke.hairline),
  'thin': _dimension(AppStroke.thin),
  'medium': _dimension(AppStroke.medium),
  'branch': _dimension(AppStroke.branch),
  'sparkline': _dimension(AppStroke.sparkline),
  'accent': _dimension(AppStroke.accent),
  'handle': _dimension(AppStroke.handle),
  'indicator': _dimension(AppStroke.indicator),
  'halo': _dimension(AppStroke.halo),
};

Map<String, Object> _radiusGroup() => {
  r'$description': 'Corner radii — AppRadius.',
  'none': _dimension(AppRadius.none),
  'sm': _dimension(AppRadius.sm),
  'md': _dimension(AppRadius.md),
  'lg': _dimension(AppRadius.lg),
  'xl': _dimension(AppRadius.xl, 'Hero cards'),
  'xxl': _dimension(AppRadius.xxl, 'Sheets / large panels'),
  'full': _dimension(AppRadius.full),
};

Map<String, Object> _opacityGroup() => {
  r'$description': 'Semantic opacity scale — AppOpacity.',
  'transparent': _number(AppOpacity.transparent),
  'hoverTint': _number(AppOpacity.hoverTint),
  'hoverTintDark': _number(AppOpacity.hoverTintDark),
  'whisper': _number(AppOpacity.whisper),
  'faint': _number(AppOpacity.faint),
  'softTint': _number(AppOpacity.softTint),
  'subtle': _number(AppOpacity.subtle),
  'light': _number(AppOpacity.light),
  'medium': _number(AppOpacity.medium),
  'accentContainer': _number(AppOpacity.accentContainer),
  'highlight': _number(AppOpacity.highlight),
  'focusRing': _number(AppOpacity.focusRing),
  'halo': _number(AppOpacity.halo),
  'muted': _number(AppOpacity.muted),
  'disabled': _number(AppOpacity.disabled),
  'scrim': _number(AppOpacity.scrim),
  'softScrim': _number(AppOpacity.softScrim),
  'prominent': _number(AppOpacity.prominent),
  'strong': _number(AppOpacity.strong),
  'emphasis': _number(AppOpacity.emphasis),
  'overlay': _number(AppOpacity.overlay),
  'solidSurface': _number(AppOpacity.solidSurface),
  'nearOpaque': _number(AppOpacity.nearOpaque),
  'nearOpaqueDark': _number(AppOpacity.nearOpaqueDark),
  'opaque': _number(AppOpacity.opaque),
};

Map<String, Object> _iconSizeGroup() => {
  r'$description': 'Icon sizes — AppIconSizes.',
  'xs': _dimension(AppIconSizes.xs),
  'sm': _dimension(AppIconSizes.sm),
  'h18': _dimension(AppIconSizes.h18),
  'md': _dimension(AppIconSizes.md),
  'mlg': _dimension(AppIconSizes.mlg),
  'lg': _dimension(AppIconSizes.lg),
  'xl': _dimension(AppIconSizes.xl),
  'xxl': _dimension(AppIconSizes.xxl),
  'hero': _dimension(AppIconSizes.hero),
  'heroLg': _dimension(AppIconSizes.heroLg),
};

Map<String, Object> _blurGroup() => {
  r'$description': 'Backdrop blur sigmas — AppBlur.',
  'sheet': _dimension(AppBlur.sheet),
  'nav': _dimension(AppBlur.nav),
  'sticky': _dimension(AppBlur.sticky),
};

Map<String, Object> _shadowGroup() => {
  r'$description': 'Shadow sets keyed by surface role — AppShadow.',
  'elevation1': _shadow(AppShadow.elevation1),
  'elevation2': _shadow(AppShadow.elevation2),
  'card': _shadow(AppShadow.card),
  'cardDark': _shadow(AppShadow.cardDark),
  'cardHover': _shadow(AppShadow.cardHover),
  'hero': _shadow(AppShadow.hero),
  'heroDark': _shadow(AppShadow.heroDark),
  'panel': _shadow(AppShadow.panel),
  'desktopSheet': _shadow(AppShadow.desktopSheet),
  'banner': _shadow(AppShadow.banner),
  'nav': _shadow(AppShadow.nav),
};

Map<String, Object> _typographyGroup() => {
  r'$description':
      'Type scale — TypographyTokens. Inter is the primary family; Outfit '
      'is reserved for displayLarge (Display 2XL). Tabular + lining figures '
      'apply globally. CJK resolves through fontFamilyFallback.',
  'fontFamily': {
    'sans': {
      r'$value': TypographyTokens.fontFamilySans,
      r'$type': 'fontFamily',
    },
    'display': {
      r'$value': TypographyTokens.fontFamilyDisplay,
      r'$type': 'fontFamily',
    },
    'mono': {
      r'$value': TypographyTokens.fontFamilyMono,
      r'$type': 'fontFamily',
    },
    'fallback': {
      r'$value': TypographyTokens.fontFamilyFallback,
      r'$type': 'fontFamily',
    },
  },
  'displayLarge': _typography(TypographyTokens.displayLarge),
  'displayMedium': _typography(TypographyTokens.displayMedium),
  'displaySmall': _typography(TypographyTokens.displaySmall),
  'headlineLarge': _typography(TypographyTokens.headlineLarge),
  'headlineMedium': _typography(TypographyTokens.headlineMedium),
  'headlineSmall': _typography(TypographyTokens.headlineSmall),
  'titleLarge': _typography(TypographyTokens.titleLarge),
  'titleMedium': _typography(TypographyTokens.titleMedium),
  'titleSmall': _typography(TypographyTokens.titleSmall),
  'bodyLarge': _typography(TypographyTokens.bodyLarge),
  'bodyMedium': _typography(TypographyTokens.bodyMedium),
  'bodySmall': _typography(TypographyTokens.bodySmall),
  'labelLarge': _typography(TypographyTokens.labelLarge),
  'labelMedium': _typography(TypographyTokens.labelMedium),
  'labelSmall': _typography(TypographyTokens.labelSmall),
  'labelSmallMedium': _typography(TypographyTokens.labelSmallMedium),
  'numericDisplay': _typography(TypographyTokens.numericDisplay),
  'numericTitle': _typography(TypographyTokens.numericTitle),
  'numericTitleStrong': _typography(TypographyTokens.numericTitleStrong),
  'numericBody': _typography(TypographyTokens.numericBody),
  'numericBodyStrong': _typography(TypographyTokens.numericBodyStrong),
  'numericCaption': _typography(TypographyTokens.numericCaption),
  'numericCaptionStrong': _typography(TypographyTokens.numericCaptionStrong),
  'numericMono': _typography(TypographyTokens.numericMono),
};

Map<String, Object> _motionGroup() => {
  'duration': {
    r'$description': 'Durations — Motion. Includes semantic aliases.',
    'fast': _duration(Motion.fast),
    'medium': _duration(Motion.medium),
    'slow': _duration(Motion.slow),
    'ticker': _duration(Motion.ticker),
    'ambient': _duration(Motion.ambient),
    'shimmerCycle': _duration(Motion.shimmerCycle),
    'typingCycle': _duration(Motion.typingCycle),
    'caretBlink': _duration(Motion.caretBlink),
    'tapFeedback': _duration(Motion.tapFeedback, 'Alias of fast'),
    'componentChange': _duration(Motion.componentChange, 'Alias of medium'),
    'contentTransition': _duration(Motion.contentTransition, 'Alias of medium'),
    'pageTransition': _duration(Motion.pageTransition, 'Alias of slow'),
  },
  'easing': {
    r'$description': 'Easing curves — Motion.',
    'emphasized': _easing(Motion.emphasized),
    'emphasizedDecelerate': _easing(Motion.emphasizedDecelerate),
    'standard': _easing(Motion.standard),
    'standardDecelerate': _easing(Motion.standardDecelerate),
    'standardAccelerate': _easing(Motion.standardAccelerate),
    'reducedMotion': _easing(Motion.reducedMotion),
  },
};

Map<String, Object> _breakpointGroup() => {
  r'$description': 'Responsive breakpoints — Breakpoints.',
  'mobile': _dimension(Breakpoints.mobile),
  'desktop': _dimension(Breakpoints.desktop),
  'shellDesktop': _dimension(Breakpoints.shellDesktop, 'Aliases desktop'),
  'contentTwoColumn': _dimension(Breakpoints.contentTwoColumn),
  'contentThreeColumn': _dimension(Breakpoints.contentThreeColumn),
};
