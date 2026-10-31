---
name: NaviWealth · 澄白
description: A quiet porcelain workspace with precise figures and light floating navigation.
colors:
  iris-light: "#535FC5"
  iris-dark: "#98A4EF"
  iris-container-light: "#EAECF9"
  iris-container-dark: "#2C3152"
  iris-on-container-light: "#414C9F"
  iris-on-container-dark: "#E4E7FD"
  canvas-light: "#F7F8FB"
  card-light: "#FFFFFF"
  hero-light: "#FBFBFE"
  border-light: "#E3E6EE"
  strong-light: "#191D28"
  body-light: "#252B3A"
  muted-light: "#636B7B"
  faint-light: "#747C8C"
  canvas-dark: "#11131A"
  card-dark: "#1B1E28"
  raised-dark: "#222633"
  hero-dark: "#262B39"
  border-dark: "#343B4C"
  strong-dark: "#F7F8FC"
  body-dark: "#E7EAF2"
  muted-dark: "#B0B7C8"
  faint-dark: "#828B99"
  contrast-border-light: "#626B78"
  contrast-border-dark: "#8A94A3"
  contrast-muted-light: "#383D45"
  contrast-muted-dark: "#CED4DF"
typography:
  display:
    fontFamily: "Inter, AppCnSans, PingFang SC, Hiragino Sans GB, Microsoft YaHei, Source Han Sans SC, Noto Sans SC, sans-serif"
    fontSize: "48px"
    fontWeight: 500
    lineHeight: 1.0752
    letterSpacing: "-1.2px"
    fontFeature: "'tnum' 1, 'lnum' 1"
  display-small:
    fontFamily: "Inter, AppCnSans, sans-serif"
    fontSize: "32px"
    fontWeight: 600
    lineHeight: 1.104
    letterSpacing: "-0.25px"
  display-compact:
    fontFamily: "Inter, AppCnSans, sans-serif"
    fontSize: "26px"
    fontWeight: 600
    lineHeight: 1.152
    letterSpacing: "0px"
  heading:
    fontFamily: "Inter, AppCnSans, sans-serif"
    fontSize: "26px"
    fontWeight: 600
    lineHeight: 1.2
  heading-small:
    fontFamily: "Inter, AppCnSans, sans-serif"
    fontSize: "20px"
    fontWeight: 600
    lineHeight: 1.248
  title:
    fontFamily: "Inter, AppCnSans, sans-serif"
    fontSize: "16px"
    fontWeight: 500
    lineHeight: 1.344
  title-small:
    fontFamily: "Inter, AppCnSans, sans-serif"
    fontSize: "14px"
    fontWeight: 600
    lineHeight: 1.344
  body:
    fontFamily: "Inter, AppCnSans, sans-serif"
    fontSize: "16px"
    fontWeight: 400
    lineHeight: 1.44
  body-small:
    fontFamily: "Inter, AppCnSans, sans-serif"
    fontSize: "14px"
    fontWeight: 400
    lineHeight: 1.44
  label:
    fontFamily: "Inter, AppCnSans, sans-serif"
    fontSize: "14px"
    fontWeight: 600
    lineHeight: 1.248
    letterSpacing: "0px"
  label-small:
    fontFamily: "Inter, AppCnSans, sans-serif"
    fontSize: "12px"
    fontWeight: 600
    lineHeight: 1.248
    letterSpacing: "0px"
  caption:
    fontFamily: "Inter, AppCnSans, sans-serif"
    fontSize: "12px"
    fontWeight: 500
    lineHeight: 1.248
    letterSpacing: "0px"
  chart-caption:
    fontFamily: "Inter, AppCnSans, sans-serif"
    fontSize: "11px"
    fontWeight: 500
    lineHeight: 1.248
    letterSpacing: "0px"
  numeric-display:
    fontFamily: "Inter, AppCnSans, sans-serif"
    fontSize: "32px"
    fontWeight: 600
    lineHeight: 1.0752
    letterSpacing: "-0.4px"
  numeric-title:
    fontFamily: "Inter, AppCnSans, sans-serif"
    fontSize: "20px"
    fontWeight: 600
    lineHeight: 1.248
  numeric-body:
    fontFamily: "Inter, AppCnSans, sans-serif"
    fontSize: "14px"
    fontWeight: 500
    lineHeight: 1.344
rounded:
  sm: "8px"
  md: "12px"
  lg: "16px"
  xl: "20px"
  xxl: "24px"
  full: "9999px"
spacing:
  s4: "4px"
  s6: "6px"
  s8: "8px"
  s10: "10px"
  s12: "12px"
  s16: "16px"
  s20: "20px"
  s24: "24px"
  s32: "32px"
  s48: "48px"
  s64: "64px"
components:
  button-primary:
    textColor: "{colors.iris-light}"
    rounded: "{rounded.lg}"
    padding: "10px 16px"
  button-filled:
    textColor: "{colors.card-light}"
    rounded: "{rounded.lg}"
    padding: "10px 16px"
  button-secondary:
    textColor: "{colors.body-light}"
    rounded: "{rounded.lg}"
    padding: "10px 16px"
  input:
    backgroundColor: "{colors.card-light}"
    textColor: "{colors.body-light}"
    rounded: "{rounded.lg}"
    padding: "10px 12px"
  filter-chip:
    rounded: "{rounded.full}"
    padding: "0px 10px"
  soft-card:
    backgroundColor: "{colors.card-light}"
    textColor: "{colors.body-light}"
    rounded: "{rounded.lg}"
    padding: "{spacing.s16}"
  grouped-surface:
    backgroundColor: "{colors.card-light}"
    rounded: "{rounded.lg}"
    padding: "0px 10px"
  floating-navigation:
    rounded: "{rounded.xl}"
    padding: "6px 8px"
---

# Design System: NaviWealth

## Overview

**Creative North Star: "澄白 · Porcelain, with 流光 navigation"**

A precise, quiet workspace for inspecting a situation, recording a change,
and taking the next action. Porcelain canvases, opaque grouped surfaces and
graphite text keep dense personal data readable. Iris blue marks actions and
selection; the floating dock contributes the light material chosen from 流光.

This records the implemented Flutter system. Dart under
`apps/mobile/lib/design_system/` remains the source of truth; the frontmatter
is a portable snapshot of its default refined appearance. Dimensions expressed
as px here correspond to Flutter logical pixels, before text scaling. The
sidecar's HTML/CSS previews translate Flutter primitives and do not validate
the app. Its synthesized tonal strips are preview metadata, not runtime color
ramps. Product and architecture context stays in [PRODUCT.md](PRODUCT.md)
and [the agent map](docs/agent-map.md).

**Key Characteristics:**

- Opaque porcelain content with a quiet ink-and-slate dark appearance.
- Medium-weight tabular display figures and compact, readable labels.
- Shared continuous corners and grouped rows, with few resting shadows.
- Translucency concentrated in navigation by default.
- Independent, persisted appearance choices and accessible state cues.

## Colors

The neutral ladder carries the page; iris gives interaction a clear, restrained voice.

### Primary

- **Iris** (`iris-light` / `iris-dark`) supplies default interaction foregrounds,
  links, selected controls and Finance chrome. The container and on-container
  pairs support semantic accent surfaces. Tonal buttons resolve their own
  lighter blend over the current card surface.
- Saved cyan and violet interaction seeds remain supported through
  `AccentSeedSlots`; this snapshot does not replace those preference ramps.

### Neutral

- **Porcelain** (`canvas-light`, `card-light`, `hero-light`) separates the
  canvas from white groups and quiet anchors. Light raised surfaces share white.
- **Graphite** (`strong-light`, `body-light`, `muted-light`, `faint-light`)
  distinguishes primary values, readable copy, metadata and tertiary detail.
- **Ink and Slate** (`canvas-dark`, `card-dark`, `raised-dark`, `hero-dark`)
  step upward in brightness for dark content. Dark text roles retain the same hierarchy.
- Border and contrast variants come from `resolveSurfaceLadder`. The listed
  contrast-border values describe refined appearance; classic retains its
  source-defined high-contrast border variants.

### Named Rules

**The Meaning Before Accent Rule.** Status, market direction and categorical
data retain their semantic roles. Read `status`, `market` or `categorical`;
do not recolor them with the interaction or domain accent.

**The Chrome Identity Rule.** A domain accent identifies shell chrome only.
Finance iris and Knowledge violet stay distinct. Domain inventory and current
accent registration belong to the existing registry and `DomainAccents`.

## Typography

**Display Font:** self-hosted Inter, with the CJK and system fallback stack in `TypographyTokens`.
**Body Font:** the same family and fallback stack.
**Label/Mono Font:** Inter for labels; `numericMono` uses monospace only for explicit data-grid needs.

The hierarchy pairs measured, medium-weight large figures with compact
semibold labels. Lining tabular figures apply globally. There is no invented
scale ratio: roles are authored individually in `TypographyTokens` and resolved
through `context.appTheme.type`.

### Hierarchy

- **Display** is the page-level amount. `displaySmall` and `displayCompact`
  provide secondary amounts and compact verdicts; `numericDisplay` is the
  secondary marquee alias, with its own line height and tracking.
- **Heading / headingSmall** distinguish page and section or sheet titles.
- **Title / titleSmall** identify groups, cards and dense rows.
- **Body / bodySmall** carry prose and ordinary copy.
- **Label / labelSmall / caption / chartCaption** separate actions, compact
  controls, metadata and chart-internal annotations.

The frontmatter records resolved refined roles. Classic uses the base token
line heights and tracking; refined multiplies line height by 0.96 and clears
tracking below 26 logical pixels. The Forui slot table is also sourced from
`app_type_scale.dart`; use the semantic roles for new page hierarchy rather
than assuming a Forui slot name is the same role.

**The Measured Figure Rule.** Use shared money and delta formatters and
components so privacy, localization, full semantic values and market preferences
survive styling. Do not introduce a new display family or feature-local size ladder.

## Layout

Use the existing page, form and domain shell templates. Major sections follow
`AppPageRhythm.section`, related modules use `module`, and dense rows use `row`:
the corresponding frontmatter spacing steps are s24, s16 and s8. Regular,
hero and dense card inset recommendations use s16, s20 and s12. `SoftCard`
itself defaults to zero padding so callers do not receive a second inset.

Window navigation uses the viewport: a floating dock below the mobile
breakpoint, a domain rail below the desktop breakpoint, and the app-owned
sidebar above it. Content composition uses its own available width.
`Breakpoints` owns all thresholds; the sidecar records the reused subset.
Finance's established Today and Wealth views use the page-width cap, with
Today pairing actions beside the amount when the supporting-pane composition fits.
Narrow and large-text layouts stack in reading order.

The dock's normal height is s64. It grows by the actual scaled 11px navigation
label increase times its 1.15 line height, rounded upward. The shell reserves
that same computed height plus dock spacing and the safe-area inset. Do not
freeze the dock height or duplicate its bottom reservation in pages.

## Elevation & Depth

Depth comes primarily from opaque tonal layers and spacing. Both visual
presets disable resting card gradients, borders and shadows. Interactive
light cards may gain a short contact shadow on pointer hover; dark cards use
tonal feedback. Focus and high-contrast boundaries remain explicit.

### Shadow Vocabulary

- **Card hover** is the close contact shadow from `AppShadow.cardHover`.
- **Floating navigation** uses the single quiet layer from `AppShadow.nav`.
- **Desktop sheet** uses the two-layer `AppShadow.desktopSheet` vocabulary.
  Exact Flutter shadow values and CSS translations are in the sidecar.

**The Opaque Content Rule.** Content modules and forms remain opaque.
The default `navigation` material permits live glass on navigation chrome;
sticky surfaces, sheets and overlays resolve opaque. `solid` disables live
glass. Broader `translucent` material remains an explicit user option, and
system high contrast disables live blur and decorative light.

Glass belongs to the shared `AppGlassSurface` and its role-specific theme
budget. Soft navigation light uses the shared shell environment and restrained
pointer feedback. It supplements selection, focus, busy and error cues.
Scrims use animated color barriers rather than a whole-page blur.

## Shapes

Refined is the default: continuous superellipse corners for shared surfaces,
with the lg content/control, xl floating-dock and xxl sheet/overlay steps.
Classic remains supported for previously saved preferences, with conventional
rounded geometry, md regular cards and buttons, and lg sheets. Appearance no
longer exposes the redundant preset preview picker. Both share the porcelain/graphite palette;
they are not separate color identities. Chips retain the full pill radius.

## Components

### Buttons

Ordinary primary actions use an iris foreground over an opaque blend of 8%
primary and the card surface. Secondary actions use a quiet neutral blend;
outline and ghost actions reduce emphasis further. Final commits opt into
`AppButtonEmphasis.filled`, with a separately resolved filled background and
white label. Filled emphasis is an available component state, not a rule that
every primary action must be filled.

Shared button styles own hover, pressed, selected, disabled and focus states.
Touch buttons have a minimum target of s48; desktop density keeps the authored
compact size variants. The frontmatter padding describes the large text-button
variant. Busy/action wrappers retain geometry and labels, prevent duplicate
activation, and own the shared commit haptic.

### Chips

`AppFilterChip` uses a full pill, a s48 minimum height, a check/circle icon,
and a quiet border. Active state adds a 6% primary wash, 20% primary border
and primary text. It has explicit selected semantics; color is supplemental.
High-level exclusive modes use the existing segmented control instead.

### Cards / Containers

`SoftCard` uses the theme's card, raised or hero surface. Default refined
regular and hero geometry follows lg and xl respectively. Use explicit shared
inset tokens, and apply the hover/focus behavior through the component.
`AppGroupedSurface` collects related settings, actions or business rows into
one opaque group with s10 horizontal inset. Its quiet divider is indented
from the leading icon; rows remain flat.

### Inputs / Fields

Forui fields inherit the shared surface, content, border, cursor and control
radius. Focus uses the primary border; errors and disabled fields keep Forui's
semantic states. The frontmatter and preview show the medium touch field,
with 10px vertical and 12px horizontal content inset and a 44px minimum height.
Retain labels, descriptions and inline errors; the preview is not a replacement
for the app's form scaffolds or dirty guards.

### Navigation

The floating dock uses the xl continuous radius, s8 horizontal and s6 vertical
inset, shared nav shadow and theme-gated soft glass. A selected destination
combines an opaque 8% accent blend over the card surface, a stronger 11px label,
accent icon and short underline; unselected labels are medium weight and muted.
The dock grows with system text scaling. Focus and selected semantics remain
independent of the light field. Tablet and desktop navigation retain their
existing shell ownership and keyboard behavior.

State changes use `AppMotionPolicy`, the shared Motion durations and curves.
Reduced motion suppresses decorative movement and retains recognizable states.
Refined sheets use the bounded damped spring in `AppVisualStyle`; keep that
curve in Dart rather than approximating it at a feature call site.

## Do's and Don'ts

### Do:

- **Do** read resolved semantic colors and type through `context.appTheme`.
- **Do** use opaque shared groups, meaningful spacing and a clear primary task.
- **Do** preserve saved visual, accent, material, market, privacy and theme preferences.
- **Do** verify light/dark, Chinese/English, large text and state cues in Flutter.

### Don't:

- **Don't** tint content groups with domain identity or substitute accent for status or market meaning.
- **Don't** add resting content shadows, decorative card gradients or nested card stacks.
- **Don't** freeze navigation height, shrink system text to fit ordinary controls, or duplicate shell navigation.
- **Don't** use HTML direction sketches or sidecar previews as proof of Flutter rendering or device performance.
- **Don't** edit generated token exports or introduce feature-local palette and typography tables.
