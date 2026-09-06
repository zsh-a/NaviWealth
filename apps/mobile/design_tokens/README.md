# NaviWealth Design Tokens

**Dart is the single source of truth.** The token and theme classes under
`apps/mobile/lib/design_system/` define every design token; `tokens.json` in
this directory is a **generated, read-only export** of those values in the
[W3C Design Tokens Community Group format] for design-tool handoff (it imports
cleanly into [Tokens Studio for Figma]). Never edit `tokens.json` by hand —
edit the Dart token files and regenerate (blueprint doc 15 §10 "SSOT 治理").

[W3C Design Tokens Community Group format]: https://design-tokens.github.io/community-group/format/
[Tokens Studio for Figma]: https://tokens.studio/

## Regenerating tokens.json

The exporter (`apps/mobile/tool/export_design_tokens.dart`) imports Flutter
types (`Color`, `TextStyle`, `Cubic`), so it cannot run under plain
`dart run`; it runs through a flutter-test wrapper instead. From
`apps/mobile/`:

```bash
# Regenerate design_tokens/tokens.json from the Dart tokens:
UPDATE_DESIGN_TOKENS=1 flutter test test/tools/export_design_tokens_test.dart

# Verify the committed file matches the Dart tokens (what CI runs):
flutter test test/tools/export_design_tokens_test.dart
```

`tool/check-design-tokens-export.sh` (repo root) wraps the check mode, prints
a diff when the file is stale, and runs as part of
`tool/check-mobile-static.sh`.

The output is deterministic: fixed key order, 2-space indent, trailing
newline — so a regenerated file only differs when Dart token values actually
changed.

## Exported groups

| JSON group | Dart source |
|------------|-------------|
| `color.brand/navy/neutral/surface/accent/overlay/chart` | `lib/design_system/tokens/color_palette.dart` (`ColorPalette`) |
| `color.knowledge` | `color_palette.dart` (`KnowledgeTypeColors`) |
| `color.expenseCategory` | `color_palette.dart` (`ExpenseCategoryColors`) |
| `color.interaction` | `lib/design_system/theme/accent_colors.dart` (`AccentColors`, light + dark) |
| `color.semantic.{light,dark}` | `lib/design_system/theme/semantic_colors.dart` (`SemanticColors`) |
| `color.market.{redUpGreenDown,greenUpRedDown,colorblind}.{light,dark}` | `lib/design_system/theme/market_colors.dart` (`MarketColors.fromMode`) |
| `spacing`, `stroke`, `radius`, `opacity`, `iconSize`, `blur`, `shadow` | `lib/design_system/tokens/dimens_tokens.dart` (`AppSpacing`, `AppStroke`, `AppRadius`, `AppOpacity`, `AppIconSizes`, `AppBlur`, `AppShadow`) |
| `size.{chart,controlHeight,controlWidth}` | `dimens_tokens.dart` (simulation history, loading placeholder, schedule date) |
| `typography` | `lib/design_system/tokens/typography_tokens.dart` (`TypographyTokens`) |
| `motion.{duration,easing}` | `lib/design_system/tokens/motion_tokens.dart` (`Motion`) |
| `breakpoint` | `lib/design_system/tokens/breakpoints.dart` (`Breakpoints`) |

The exporter reads token **values** at run time, so value changes flow into
the JSON automatically on regeneration. Adding a **new** token constant
requires a one-line addition in `tool/export_design_tokens.dart` so it is
exported; the CI check fails when the committed JSON no longer matches the
Dart values.

## Consuming tokens in Flutter

```dart
import 'package:naviwealth/design_system/design_system.dart';

// Static tokens — no theme required:
Motion.medium;          // Duration(milliseconds: 220)
AppMotionPolicy.duration(
  context,
  Motion.medium,
  role: AppMotionRole.transition,
);                      // reduce-motion: transition halves; decorative/status → zero
Breakpoints.mobile;     // 600
AppSpacing.s16;         // 16.0
AppRadius.lg;           // 16.0

// Theme-bound tokens — one read entry point:
final t = context.appTheme;
t.status.success.fg;    // status ColorRole (fg / container / onContainer)
t.market.roleForDelta(delta).fg;   // direction ColorRole per user preference
t.type.caption;         // semantic type scale (blueprint §4)
t.card.padding;         // L2 component specs (card / press / badge / …)
t.categorical.adapt(seedColor);    // brightness-adapted categorical color

return DeltaText(value: 0.0123, format: DeltaFormat.percent);
```

Spacing and radius come from the `AppSpacing` / `AppRadius` scales in
`dimens_tokens.dart` — chrome (sheets, cards, headers) references the scale
instead of inlining magic numbers, which is what makes a global restyle a
one-file change.

Application-owned animation must go through `AppMotionPolicy`. Choose a
semantic role (`transition`, `decorative`, or `status`) and never read
`MediaQuery.disableAnimationsOf` from feature code. Imperative navigation uses
`buildAppPageRoute`, and shared-element navigation uses `OptionalHero`; both
disable spatial motion automatically when requested by the operating system.
`tool/lint-motion-policy.sh` enforces these boundaries in mobile CI.

## Direction-sensitive (market) colors

Money deltas, charts, and any "up vs. down" indicator must read from
`context.appTheme.market` — never hard-code red or green. Three modes:

| Mode | Up | Down | Use case |
|------|----|------|----------|
| `redUpGreenDown` (default) | red | green | 中国习惯 |
| `greenUpRedDown` | green | red | International convention |
| `colorblind` | blue | orange | Wong / Okabe-Ito; distinguishable under deuteranopia / protanopia / tritanopia |

User toggles the mode in Settings → 外观. Switching it re-skins every
`DeltaText` / `DeltaChip` / chart series in the tree.

`DeltaText` also renders a directional arrow icon — color is never the only
signal of direction, even in colorblind mode.

## Updating tokens

1. Edit the Dart token file under `apps/mobile/lib/design_system/tokens/` or
   `theme/` (see the table above).
2. Regenerate the JSON export:
   `UPDATE_DESIGN_TOKENS=1 flutter test test/tools/export_design_tokens_test.dart`
3. Run `flutter analyze` and `flutter test` from `apps/mobile/`.
4. Commit the Dart change together with the regenerated `tokens.json`.
5. For Figma, re-import the regenerated `tokens.json` via Tokens Studio.

## Visual hierarchy and transitions

- Ordinary cards use the medium radius with close, soft shadows. Hero cards
  use the large radius and a faint accent wash; dark separation comes mainly
  from the surface ladder rather than bright outlines.
- Use `emphasizeInteger: true` on display-size `MoneyText`,
  `AnimatedMoneyText`, or `SignedMoneyText`. This preserves the formatter's
  full amount and accessibility label while reducing the size of the currency
  and fraction. Dense rows retain uniform type; privacy placeholders apply
  before the styled amount is rendered.
- Use `AnimatedSizeFade` for disclosures. Outgoing content fades before being
  removed and cannot receive input or accessibility focus. Reduced motion
  uses a short fade without spatial expansion.
- Segmented controls use a sliding selection surface when options fit one
  row, and retain local selection marks in wrapped layouts. Selection motion
  and chart interpolation stop under reduced motion.
- Glass highlights are reserved for floating navigation and sticky chrome;
  content modules remain opaque and high-contrast surfaces omit live blur.
