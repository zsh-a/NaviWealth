# NaviWealth Design Tokens

`tokens.json` is the shared source of truth between Figma and Flutter. It
follows the [W3C Design Tokens Community Group format] and imports cleanly
into [Tokens Studio for Figma].

[W3C Design Tokens Community Group format]: https://design-tokens.github.io/community-group/format/
[Tokens Studio for Figma]: https://tokens.studio/

The Flutter side mirrors the JSON in `apps/mobile/lib/design_system/tokens/`.
The two are kept in sync **manually** for this baseline (FIR-22) — a generator
is a future task once the surface stabilises.

## Token groups

| Group        | JSON path           | Flutter file                                      |
|--------------|---------------------|---------------------------------------------------|
| Brand        | `color.brand.*`     | `tokens/color_palette.dart` (`brand50`–`brand900`) |
| Neutral      | `color.neutral.*`   | `tokens/color_palette.dart` (`neutral0`–`neutral1000`) |
| Accent       | `color.accent.*`    | `tokens/color_palette.dart` — `green` is now Tailwind emerald, `red` is Tailwind rose / soft crimson (FIR-104) |
| Semantic     | `color.semantic.*`  | `theme/semantic_colors.dart` (light + dark)        |
| Market       | `color.market.*`    | `theme/market_colors.dart` — adds `upMuted` / `downMuted` (80% saturation) and `profitGlow` (FIR-104) |
| Glass        | `glass.*`           | `tokens/glass_tokens.dart` (`GlassTokens` ThemeExtension, FIR-104) |
| Spacing      | `spacing.*`         | `tokens/spacing_tokens.dart` (`Spacing`)           |
| Radius       | `radius.*`          | `tokens/radius_tokens.dart` (`Radii`)              |
| Typography   | `typography.*`      | `tokens/typography_tokens.dart` — Inter primary, Outfit reserved for Display 2XL (FIR-104) |
| Shadow       | `shadow.*`          | `theme/app_elevations.dart` (`AppElevations`)      |
| Motion       | `motion.*`          | `tokens/motion_tokens.dart` (`Motion`)             |
| Breakpoint   | `breakpoint.*`      | `tokens/breakpoints.dart` (`Breakpoints`)          |

## How to consume tokens in Flutter

```dart
import 'package:naviwealth/design_system/design_system.dart';

// Static tokens — no theme required:
Spacing.s16;            // 16.0
Radii.brLg;             // BorderRadius.circular(16)
Motion.medium;          // Duration(milliseconds: 220)
Breakpoints.mobile;     // 600

// Theme-bound tokens — read from BuildContext:
final semantic = SemanticColors.of(context);
final market   = MarketColors.of(context);
final shadows  = AppElevations.of(context);

return Container(
  padding: Spacing.card,
  decoration: BoxDecoration(
    color: Theme.of(context).colorScheme.surface,
    borderRadius: Radii.brLg,
    boxShadow: shadows.level2,
  ),
  child: DeltaText(value: 0.0123, format: DeltaFormat.percent),
);
```

## Direction-sensitive (market) colors

Money deltas, charts, and any "up vs. down" indicator must read from
`MarketColors.of(context)` — never hard-code red or green. This keeps the
three modes truthful:

| Mode                          | Up    | Down   | Use case |
|-------------------------------|-------|--------|----------|
| `redUpGreenDown` (default)    | red   | green  | 中国习惯 |
| `greenUpRedDown`              | green | red    | International convention |
| `colorblind`                  | blue  | orange | Wong / Okabe-Ito palette, distinguishable under deuteranopia / protanopia / tritanopia |

The user toggles the mode in Settings → 外观. Switching it re-skins every
`DeltaText` / `DeltaChip` / chart series in the tree.

For accessibility, `DeltaText` also renders a directional arrow icon by
default — color is never the only signal of direction, even in the colorblind
mode.

## Updating tokens

1. Edit `tokens.json` (or change in Tokens Studio and re-export).
2. Mirror the change into the matching Dart file under
   `apps/mobile/lib/design_system/tokens/` or `theme/`.
3. Run `flutter analyze` and `flutter test` from `apps/mobile/`.
4. Bump anything that breaks downstream — most consumers go through the
   `MoneyText` / `DeltaText` / `Spacing` / `Radii` indirections, so the blast
   radius is small.

## Future work

- Generator: `tokens.json` → Dart codegen so the manual mirror step goes
  away (FIR-12 follow-up).
- Per-asset class chart palette extension on top of these tokens.
- Density modes for tablet / desktop layouts (consume the same scale, choose
  different defaults).
