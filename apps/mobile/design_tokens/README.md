# NaviWealth Design Tokens

**Dart is the single source of truth.** The token and theme classes under
`apps/mobile/lib/design_system/` define every design token; `tokens.json` in
this directory is a **generated, read-only export** of those values in the
[W3C Design Tokens Community Group format] for design-tool handoff (it imports
cleanly into [Tokens Studio for Figma]). Never edit `tokens.json` by hand —
edit the Dart token files and regenerate. The [design system contract](../docs/design/15-ui-refactor-blueprint.md) defines theme and component ownership.
[DESIGN.md](../../../DESIGN.md) records the implemented visual language and a
portable default token snapshot; [.impeccable/design.json](../../../.impeccable/design.json)
extends it with preview metadata. Neither replaces the Dart source or this
generated W3C export. Flutter-specific Impeccable boundaries are recorded in
[.agents/IMPECCABLE.md](../../../.agents/IMPECCABLE.md).

[W3C Design Tokens Community Group format]: https://design-tokens.github.io/community-group/format/
[Tokens Studio for Figma]: https://tokens.studio/

## Regenerating tokens.json

The exporter (`apps/mobile/tool/export_design_tokens.dart`) imports Flutter
types (`Color`, `TextStyle`, `Cubic`), so it cannot run under plain
`dart run`; it runs through a flutter-test wrapper instead. From
`apps/mobile/`:

```bash
# Regenerate design_tokens/tokens.json from the Dart tokens:
UPDATE_DESIGN_TOKENS=1 rtk flutter test test/tools/export_design_tokens_test.dart

# Verify the committed file matches the Dart tokens (what CI runs):
rtk flutter test test/tools/export_design_tokens_test.dart
```

CI runs this freshness test once in the regular Flutter test shards.
`tool/check-design-tokens-export.sh` (repo root) is an optional local wrapper
that prints a diff when the file is stale.

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
| `appearance.{classic,refined}` | `app_visual_style.dart`、`surface_ladder.dart`、`app_type_scale.dart`，导出预设圆角、表面色阶与字体 |

The exporter reads token **values** at run time, so value changes flow into
the JSON automatically on regeneration. Adding a **new** token constant
requires a one-line addition in `apps/mobile/tool/export_design_tokens.dart` so it is
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
t.type.caption;         // semantic type scale
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
   `UPDATE_DESIGN_TOKENS=1 rtk flutter test test/tools/export_design_tokens_test.dart`
3. Run the relevant `rtk flutter analyze` and focused `rtk flutter test` checks from `apps/mobile/`.
4. Commit the Dart change together with the regenerated `tokens.json`.
5. For Figma, re-import the regenerated `tokens.json` via Tokens Studio.

## Visual hierarchy and transitions

- Porcelain is the shared content palette for classic and refined. Refined,
  iris-blue (`indigo`) interaction color and navigation-only glass are the
  defaults for absent or invalid preferences. Explicitly saved choices remain
  valid. Domain chrome accents keep their identity; status and market colors
  retain their own semantic roles.
- The semantic display is Inter 48 medium; secondary display roles are 32 and
  26. Numerals use lining tabular figures. Refined resolves the base line
  height at 0.96 and removes tracking below 26dp; read `context.appTheme.type`
  rather than styling feature text from the base table. Outfit remains a
  legacy family constant, not the current display family.
- Content cards use neutral opaque fills with no resting shadow or gradient.
  Hero cards use a larger radius and stronger typography. Light pointer hover
  adds a short contact shadow; dark separation comes from the surface ladder.
  Floating menus and navigation retain restrained neutral shadows. Page-wide
  atmosphere is an explicit opt-in; standard canvases remain neutral.
- Primary buttons use a light tonal fill. Pinned form actions and sheet submits
  opt into `AppButtonEmphasis.filled`, with separately resolved fill and label
  colors. Ordinary commands stay light even when other actions are submitting.
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
- Material effects are independent of classic/refined. The default navigation
  material enables live blur on navigation chrome while sticky surfaces,
  sheets and overlays remain opaque. Solid disables live blur; fully
  translucent is an explicit choice that permits additional chrome roles.
  System high contrast takes precedence; forms remain opaque and scrims use
  color barriers.
- Glass highlights belong to shared application chrome. Theme role gates
  control the live backdrop; content modules remain opaque. Do not add
  per-scroll blur passes at feature call sites.
- The floating dock has a 20dp radius and a normal 64dp height. Its shared
  height function grows with actual scaled navigation-label metrics; the
  shell uses that same result for bottom content reservation plus spacing
  and safe area. Preserve this relationship under large text.
- `AppGlassEnvironment` owns one light field for the shell. The active domain
  accent is mixed into that field at low energy, so switching FinanceOS,
  HealthOS, KnowledgeOS or ExecutionOS changes the chrome atmosphere without
  tinting readable content cards.
- `AppGlassFeedback` consumes the owning Forui control's selected, hovered,
  focused, pressed and disabled variants. The dock owns one surface-level
  hover/drag light and keeps item-level state feedback local; pointer drag
  uses a tinted core, velocity-based soft trail and leading specular glint.
  Do not add a second gesture recognizer or pointer response at the tab call
  site. Keep selection indicators, keyboard focus outlines and control
  semantics alongside the light.
- `AppGlassStatus` gives pinned actions a steady busy wash, subdued disabled
  finish or semantic error rim. Busy/disabled stops pointer tracking immediately.
  Loading indicators and inline errors remain authoritative; light is never
  the only status cue. Transitions do not change geometry or run continuously.
  Reduced motion keeps static state differences, while system high contrast
  omits decorative light entirely. `SoftGlassSpec` owns both light/dark budgets.
- Advanced material depth is role-aware: chrome, sticky, sheet and overlay use
  progressively stronger specular, occlusion and inset-rim budgets. The light
  field is a paint-only approximation of thin translucent glass. Navigation
  uses the theme-gated `BackdropFilter` by default; the fully translucent
  option can enable sheet and other chrome roles. The surface pointer listener is translucent so a drag can
  start in any empty part of the chrome without stealing child semantics.
  Keep the role from `AppGlassSurface`; do not recreate gradients at feature
  call sites.

The redesign's captured evidence is Flutter widget-renderer output under
`.impeccable/review/goldens/`, not a simulator or device capture. Native-device
material/performance verification and comparison against the Linux golden
baseline remain outstanding. Sidecar HTML/CSS snippets are self-contained
translations for the preview panel; synthesized tonal strips are display
metadata, not additional runtime tokens. No raster assets were added by this
code-led redesign.
