# NaviWealth Design Tokens

`tokens.json` is the shared source of truth between Figma and Flutter. It follows the [W3C Design Tokens Community Group format] and imports cleanly into [Tokens Studio for Figma].

[W3C Design Tokens Community Group format]: https://design-tokens.github.io/community-group/format/
[Tokens Studio for Figma]: https://tokens.studio/

The Flutter side mirrors a subset of the JSON in `apps/mobile/lib/design_system/`. The two are kept in sync **manually** for this baseline (FIR-22). Spacing / radius / shadow live as raw values in `tokens.json` for design handoff. Spacing and radius are now mirrored to Dart in `lib/design_system/tokens/dimens_tokens.dart` (`AppSpacing` / `AppRadius`); **shadow has no Dart mirror** — the app is built on **Forui** (`FCard` / `FButton` / `FTheme(zinc)`), which provides shadow/elevation primitives via its own theme system.

## Token groups currently mirrored to Dart

| Group | JSON path | Flutter file |
|-------|-----------|--------------|
| Brand / Neutral / Accent | `color.{brand,neutral,accent}.*` | `lib/design_system/tokens/color_palette.dart` |
| Semantic | `color.semantic.*` | `lib/design_system/theme/semantic_colors.dart` |
| Market (up / down / colorblind) | `color.market.*` | `lib/design_system/theme/market_colors.dart` (+ `accent_colors.dart`, `market_color_mode.dart`) |
| Typography | `typography.*` | `lib/design_system/tokens/typography_tokens.dart` (Inter primary, Outfit reserved for Display 2XL) |
| Motion | `motion.*` | `lib/design_system/tokens/motion_tokens.dart` |
| Breakpoint | `breakpoint.*` | `lib/design_system/tokens/breakpoints.dart` |
| Dimension (Spacing / Radius) | `spacing.*`, `radius.*` | `lib/design_system/tokens/dimens_tokens.dart` (`AppSpacing` / `AppRadius`) |

JSON-only sections (no Dart mirror today): `shadow.*`. Flutter consumers use Forui's shadow / elevation defaults, or pass raw values inline. Spacing/radius now have a Dart mirror — see the Dimension row above.

## Consuming tokens in Flutter

```dart
import 'package:naviwealth/design_system/design_system.dart';

// Static tokens — no theme required:
Motion.medium;          // Duration(milliseconds: 220)
Breakpoints.mobile;     // 600
AppSpacing.s16;         // 16.0
AppRadius.lg;           // 16.0

// Theme-bound tokens — read from BuildContext:
final semantic = SemanticColors.of(context);
final market   = MarketColors.of(context);

return DeltaText(value: 0.0123, format: DeltaFormat.percent);
```

Spacing and radius come from the `AppSpacing` / `AppRadius` scales in `dimens_tokens.dart` — chrome (sheets, cards, headers) references the scale instead of inlining magic numbers, which is what makes a global restyle a one-file change. Elevation/shadow still comes from Forui (e.g. `FCard`); there is no `AppElevations` class today.

## Direction-sensitive (market) colors

Money deltas, charts, and any "up vs. down" indicator must read from `MarketColors.of(context)` — never hard-code red or green. Three modes:

| Mode | Up | Down | Use case |
|------|----|------|----------|
| `redUpGreenDown` (default) | red | green | 中国习惯 |
| `greenUpRedDown` | green | red | International convention |
| `colorblind` | blue | orange | Wong / Okabe-Ito; distinguishable under deuteranopia / protanopia / tritanopia |

User toggles the mode in Settings → 外观. Switching it re-skins every `DeltaText` / `DeltaChip` / chart series in the tree.

`DeltaText` also renders a directional arrow icon — color is never the only signal of direction, even in colorblind mode.

## Updating tokens

1. Edit `tokens.json` (or change in Tokens Studio and re-export).
2. Mirror the change into the matching Dart file under `apps/mobile/lib/design_system/tokens/` or `theme/` (only for the groups in the table above).
3. Run `flutter analyze` and `flutter test` from `apps/mobile/`.
4. Most consumers go through `MoneyText` / `DeltaText` / `MarketColors`, so blast radius is small.

## Future work

- Generator: `tokens.json` → Dart codegen so the manual mirror step goes away (FIR-12 follow-up).
- Mirror `shadow` to Dart if/when we move off Forui defaults (spacing/radius are already mirrored in `dimens_tokens.dart`).
- Per-asset class chart palette extension on top of `MarketColors`.
