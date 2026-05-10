# NaviWealth Design Tokens

`tokens.json` is the shared source of truth between Figma and Flutter. It follows the [W3C Design Tokens Community Group format] and imports cleanly into [Tokens Studio for Figma].

[W3C Design Tokens Community Group format]: https://design-tokens.github.io/community-group/format/
[Tokens Studio for Figma]: https://tokens.studio/

The Flutter side mirrors a subset of the JSON in `apps/mobile/lib/design_system/`. The two are kept in sync **manually** for this baseline (FIR-22). Spacing / radius / shadow live as raw values in `tokens.json` for design handoff; on the Dart side the app is built on **Forui** (`FCard` / `FButton` / `FTheme(zinc)`), which provides those primitives via its own theme system — the Dart code does not currently mirror those JSON sections.

## Token groups currently mirrored to Dart

| Group | JSON path | Flutter file |
|-------|-----------|--------------|
| Brand / Neutral / Accent | `color.{brand,neutral,accent}.*` | `lib/design_system/tokens/color_palette.dart` |
| Semantic | `color.semantic.*` | `lib/design_system/theme/semantic_colors.dart` |
| Market (up / down / colorblind) | `color.market.*` | `lib/design_system/theme/market_colors.dart` (+ `accent_colors.dart`, `market_color_mode.dart`) |
| Typography | `typography.*` | `lib/design_system/tokens/typography_tokens.dart` (Inter primary, Outfit reserved for Display 2XL) |
| Motion | `motion.*` | `lib/design_system/tokens/motion_tokens.dart` |
| Breakpoint | `breakpoint.*` | `lib/design_system/tokens/breakpoints.dart` |

JSON-only sections (no Dart mirror today): `spacing.*`, `radius.*`, `shadow.*`. Flutter consumers use Forui's spacing / radius / shadow defaults, or pass raw values inline.

## Consuming tokens in Flutter

```dart
import 'package:naviwealth/design_system/design_system.dart';

// Static tokens — no theme required:
Motion.medium;          // Duration(milliseconds: 220)
Breakpoints.mobile;     // 600

// Theme-bound tokens — read from BuildContext:
final semantic = SemanticColors.of(context);
final market   = MarketColors.of(context);

return DeltaText(value: 0.0123, format: DeltaFormat.percent);
```

Spacing, radius, and elevation come from Forui (e.g. `FCard`) or raw `EdgeInsets` / `BorderRadius.circular(...)` inline. There is no `Spacing` / `Radii` / `AppElevations` class today.

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
- Mirror `spacing` / `radius` / `shadow` to Dart if/when we move off Forui defaults.
- Per-asset class chart palette extension on top of `MarketColors`.
