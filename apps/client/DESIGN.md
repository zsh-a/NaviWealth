---
name: "NaviWealth Native FinanceOS"
description: "A precise marine-and-mist native financial workspace."
colors:
  light-background: "#F3F7F6"
  light-foreground: "#162D35"
  light-card: "#FFFFFF"
  light-primary: "#153D52"
  light-primary-foreground: "#FFFFFF"
  light-secondary: "#DFEEEB"
  light-secondary-foreground: "#174E50"
  light-muted: "#E8F0EE"
  light-muted-foreground: "#526A70"
  light-destructive: "#B91C1C"
  light-destructive-foreground: "#FFFFFF"
  light-border: "#D8E4E1"
  light-ring: "#168F88"
  dark-background: "#0D1C23"
  dark-foreground: "#E6F0ED"
  dark-card: "#152A33"
  dark-primary: "#8DD7CF"
  dark-primary-foreground: "#103337"
  dark-secondary: "#23434C"
  dark-secondary-foreground: "#C2E9E2"
  dark-muted: "#1B333D"
  dark-muted-foreground: "#A5BDBE"
  dark-destructive: "#F87171"
  dark-destructive-foreground: "#1A0B0B"
  dark-border: "#2C4650"
  dark-ring: "#8DD7CF"
typography:
  page:
    fontFamily: "system-ui, sans-serif"
    fontSize: "21px"
    fontWeight: 600
  section:
    fontFamily: "system-ui, sans-serif"
    fontSize: "15px"
    fontWeight: 600
  row-title:
    fontFamily: "system-ui, sans-serif"
    fontSize: "15px"
    fontWeight: 500
  body:
    fontFamily: "system-ui, sans-serif"
    fontSize: "16px"
    lineHeight: "24px"
  label:
    fontFamily: "system-ui, sans-serif"
    fontSize: "14px"
    lineHeight: "20px"
  caption:
    fontFamily: "system-ui, sans-serif"
    fontSize: "12px"
    lineHeight: "16px"
  action:
    fontFamily: "system-ui, sans-serif"
    fontSize: "14px"
    fontWeight: 600
  action-quiet:
    fontFamily: "system-ui, sans-serif"
    fontSize: "14px"
    fontWeight: 500
  finance-field:
    fontFamily: "system-ui, sans-serif"
    fontSize: "15px"
  amount-compact:
    fontFamily: "system-ui, sans-serif"
    fontSize: "19px"
    fontWeight: 600
  amount-summary:
    fontFamily: "system-ui, sans-serif"
    fontSize: "22px"
    fontWeight: 500
  amount-metric:
    fontFamily: "system-ui, sans-serif"
    fontSize: "29px"
    fontWeight: 600
  amount-detail:
    fontFamily: "system-ui, sans-serif"
    fontSize: "34px"
  amount-input:
    fontFamily: "system-ui, sans-serif"
    fontSize: "40px"
    fontWeight: 500
rounded:
  quiet-action: "8px"
  finance-field: "10px"
  control: "12px"
  group: "16px"
  pill: "999px"
spacing:
  related: "4px"
  compact: "8px"
  row: "12px"
  page: "16px"
  sheet: "20px"
  generous: "24px"
components:
  button-primary:
    backgroundColor: "{colors.light-primary}"
    textColor: "{colors.light-primary-foreground}"
    typography: "{typography.action}"
    rounded: "{rounded.control}"
    padding: "0px 16px"
  button-secondary:
    backgroundColor: "{colors.light-secondary}"
    textColor: "{colors.light-secondary-foreground}"
    typography: "{typography.label}"
    rounded: "{rounded.control}"
    padding: "0px 16px"
  button-quiet:
    textColor: "{colors.light-primary}"
    typography: "{typography.action-quiet}"
    rounded: "{rounded.quiet-action}"
    padding: "0px 12px"
  button-destructive:
    backgroundColor: "{colors.light-destructive}"
    textColor: "{colors.light-destructive-foreground}"
    typography: "{typography.body}"
    rounded: "{rounded.control}"
    padding: "12px 16px"
  field-finance:
    backgroundColor: "{colors.light-card}"
    textColor: "{colors.light-foreground}"
    typography: "{typography.finance-field}"
    rounded: "{rounded.finance-field}"
    padding: "8px 12px"
  choice-selected:
    backgroundColor: "{colors.light-secondary}"
    textColor: "{colors.light-secondary-foreground}"
    typography: "{typography.action-quiet}"
    rounded: "{rounded.control}"
    padding: "8px 12px"
  chip-selected:
    backgroundColor: "{colors.light-primary}"
    textColor: "{colors.light-primary-foreground}"
    typography: "{typography.label}"
    rounded: "{rounded.pill}"
    padding: "6px 12px"
  group:
    backgroundColor: "{colors.light-card}"
    rounded: "{rounded.group}"
  navigation:
    backgroundColor: "{colors.light-card}"
    textColor: "{colors.light-muted-foreground}"
    typography: "{typography.caption}"
  changed-fact:
    textColor: "{colors.light-primary}"
    typography: "{typography.caption}"
    rounded: "{rounded.control}"
  chart:
    textColor: "{colors.light-primary}"
    height: "112px"
---

# Design System: NaviWealth Native FinanceOS

## Overview

**Creative North Star: "Contemporary Atlas Precision"**

Marine, mist, and restrained teal-family tones frame a precise native financial workspace. Compact system typography, quiet dated lists, thin line icons, and aligned tabular amounts make recorded facts easy to inspect. The recurring signature is an acknowledgment beside the fact an action changed.

This system is scoped to the Rust/nsh client in `apps/client`. `theme.json`, `src/ui.rs`, and `src/finance_ui.rs` own the implemented roles and shared primitives; repository-root design artifacts describe Flutter separately. Product terminology, explicit financial meaning, native navigation, and readable scaled text take priority over decorative expression. Surface composition belongs in `.impeccable/surfaces/apps-client-finance-core.md`.

**Key Characteristics:**

- Marine actions and mist surfaces, with paired light and dark roles.
- Compact flat rows, explicit currencies, and exact tabular financial values.
- Native controls, guarded drafts, and in-place changed-fact receipts.

## Colors

Deep marine anchors actions; mist and sea-glass tones separate surfaces and choices. Frontmatter extracts the shared roles from `theme.json`, including their dark counterparts. It is the portable token record; runtime theme resolution remains authoritative.

### Primary

Marine identifies primary commits, quiet links, selected business tabs, and chart marks. The dark primary becomes pale sea glass, paired with a dark primary foreground. The ring role is teal in light appearance and sea glass in dark appearance; it is a theme role, not evidence of a custom focus treatment on every native control. Shared input carets explicitly use primary.

### Secondary

Sea-glass selection surfaces support secondary actions, selected rectangular choices, and local changed-fact emphasis. Their text uses the matching secondary foreground. The selected pill chip uses primary, while an unselected pill uses muted.

### Neutral

Mist background frames card-white grouped content and fields. Ink foreground carries facts; muted foreground carries dates, field labels, and supporting text. Fine border tone separates fields, rows, and persistent navigation. Dark appearance uses deep marine canvas and lifted marine content tones, with pale ink text.

Destructive and destructive foreground form a dedicated pair for final destructive commits; destructive text also identifies errors and the explicit discard action. Pair it with wording and the operation's stated effect.

**The Currency Rule.** Currency, signs, labels, and unavailable states carry meaning; color is supplementary.

## Typography

**Body and label font:** platform system sans-serif. There is no external font dependency or authored display family. `system-ui` in the portable tokens is an HTML illustration of the native role. Monetary text uses tabular figures rather than a separate monospace family.

Core page titles use the compact page role; shared section titles and row titles stay close to body size, with weight establishing hierarchy. The body, label, and caption presets inherit nsh's explicit line heights. Roles set with `text_size` do not invent a separate line height in the token record.

- **Page and section:** compact semibold titles; sheet titles may use nsh's larger native title preset (18 logical units, 28-unit lines).
- **Row title and fields:** medium row identities and readable financial inputs.
- **Body, label, caption:** principal explanatory text, supporting labels, and compact dates/currencies respectively.
- **Amounts:** compact cash summaries, monthly paired totals, and standalone metrics use separate roles. Record detail and editable record amount use the two larger roles. Supporting amounts remain aligned with their owning row.
- **Actions:** primary labels are semibold; secondary labels are normal weight; quiet actions are medium weight at the same compact size.

**The Exact Amount Rule.** Display monetary values as exact Decimal text with tabular digits, preserving small nonzero values and at least two fractional places.

## Layout

Use the native safe-area-aware shell and route depth. Shared root and detail content follows a narrow phone column, with a page inset and a four-unit spacing rhythm. Related labels use the smallest gap; rows and fields use the middle steps; sheets use the larger inset. Native `px(...)` values are logical lengths; the portable CSS units illustrate them and do not establish physical pixel equivalence.

Shared financial rows have a minimum height (62 logical units) and vertical row padding. Activity rows have a minimum height (64), with a compact icon well, flexible identity, and a fixed trailing amount/currency stack. Titles may truncate within the flexible identity; trailing facts must remain readable. Shared action targets have a minimum height (48), and icon actions reserve a square of that size. Grow content for text scaling rather than shrinking text to preserve a screenshot's row count.

The shared page has a compact header (minimum 52), scrollable body, and bottom safe-area reserve plus 96 logical units. The four-tab bar reserves the system bottom inset plus 4; its tab targets have a minimum height (58). Root panes remain mounted and use visibility to retain their state, including Activity filters, while switching tabs. There is no authored desktop breakpoint system or verified tablet composition to inherit.

Editable and actionable scrolling content uses `ui::interactive_scroll()` with `KeyboardTaps::Handled`. Selection controls dismiss the keyboard before showing a sheet. Shared choice sheets use 75% of the window height, clamped between 240 and 480 logical units; sheet footers reserve the system bottom inset plus 20. Full record editing uses a scrolling form and safe-area-padded commit footer. Complex Finance forms use the shared guarded page flow.

## Elevation & Depth

Surfaces are flat at rest. Tone, spacing, borders, and dividers establish grouping; there is no authored shadow vocabulary. Native sheets and calendar popups dim the underlying task with a black scrim (32% opacity). Keep modal depth attached to a concrete choice, confirmation, or form task.

## Shapes

Quiet text actions and calendar cells use the smallest corner treatment; Finance fields use the intermediate treatment; shared controls, icon actions, and local acknowledgments use the control treatment. Groups and calendar popup top corners use the broader treatment. Pill chips are fully rounded. Frontmatter owns the exact radius values.

Icons are consistent inline vector linework: a 24-unit viewbox, round caps and joins, a thin stroke (1.7), and a usual rendered box (22 logical units). Row chevrons are smaller (16). Activity icon wells are compact (30), and repeated rows share a surface rather than becoming individual cards.

## Components

### Buttons

Primary and secondary buttons share a minimum target height (48) and horizontal padding (16). Primary uses its foreground/surface pair and semibold compact text; secondary uses its own pair and normal text. Quiet actions have a smaller corner treatment and medium primary-colored text. Final destructive buttons use the dedicated destructive pair with normal body-size medium text. Busy state gates repeated commits.

Shared primary/secondary presses reduce opacity (0.82) and scale slightly (0.985); quiet actions use opacity (0.65), scale (0.98); icon actions use opacity (0.65), scale (0.96). Their transform transitions last 100 ms with ease-out. Reduced motion removes scale and transform duration while retaining immediate opacity feedback. State buttons, chips, and flat rows have immediate opacity feedback without an authored transform. HTML hover and keyboard-focus rules in the sidecar are documentation affordances, not proof of corresponding native states.

### Choices and chips

Rectangular choices use a minimum target height (48), control radius, and label-size medium text. Selected choices use secondary roles; unselected choices use card and muted text. Shared pill chips use compact horizontal/vertical padding (12/6), primary when selected and muted otherwise. Use the existing native choice sheet for long account or asset lists.

### Cards / Containers

A group is a broad-corner card surface for a related set of rows or fields. Row content owns its padding; the container adds no universal padding. Flat financial lists use fine separators where the shared row defines them. Avoid nesting another card around every item.

### Activity rows and account roles

Investment rows name the actual operation before the asset identity, such as **买入 · CoreStock**. Their subtitle names each account's role explicitly: **结算 CoreBank · 持仓 CoreBroker** when a cash account exists, or the holding account alone when it does not. An arrow denotes an actual account transfer; it does not describe an investment's settlement relationship.

The trailing value preserves its economic meaning: opening positions label the amount **成本**, splits label their zero cash effect **现金**, and positive investment cash movements carry a plus sign. Investment entry details label **资产**, **持仓账户**, and **结算账户** separately, with **无现金结算** when appropriate. A row's accessibility label contains the complete operation, account roles, signed/labeled amount, and currency even when visible identity text truncates.

**The Account Role Rule.** Name investment operations and holding/settlement roles explicitly; reserve arrows for actual account transfers.

### Inputs / Fields

All native inputs explicitly bind foreground text, muted hints, primary caret, and secondary selection through `ui::themed_input()`. Shared standard fields use control radius, a fine border, card background, a minimum height (48), and body text. Finance form fields use the intermediate radius, compact financial-field text, and row/compact padding. Multiline Finance fields have a taller minimum (112). Labels remain visible above fields. Secret fields use native masking; dates use the native calendar grid with labeled navigation and selectable day targets (minimum 48 by 48).

Write failures preserve the draft and display a destructive error line. Draft guards prioritize the filled primary **继续填写** action; **放弃修改** is explicit destructive text with a full touch target. Saving blocks duplicate submissions and exit during the commit. Background read refreshes must not recreate an authored draft.

### Navigation

The native shell pairs line icons with compact labels in four stable business tabs: 今日, 流水, 财富, 规划. 流水 is the default. Primary identifies selection; muted foreground identifies other tabs. FinanceOS, assistant, and settings remain workspace-level actions. Details use native push/pop depth with a visible return affordance; guarded forms own exit decisions. Reduced motion selects no authored screen transition.

### Changed-fact acknowledgment

`finance_ui::changed_fact` places a caption-size primary receipt beside the affected facts. Its secondary palette wash fades from opacity 0.75 to 0 over 1800 ms using `cubic-bezier(0.16,1,0.3,1)`. The receipt remains until the next task. Reduced motion shows a static secondary highlight and the receipt immediately. Budget, asset valuation, and Activity summary owners use this primitive.

The supplementary bottom notice enters from a small vertical offset (6 logical units) over 180 ms with the same easing, without movement under reduced motion. It can be dismissed; the shell clears it after 8 seconds. It must not replace the affected fact's receipt.

**The Local Receipt Rule.** A changed-fact receipt stays beside the affected financial facts until the next task; a bottom notice is supplementary.

### Analytical chart and sparse observations

The shared line chart uses a thin primary line (2.2), a quiet baseline, and a visible dot for each known sample (radius 3) in a shallow plot (112 logical units). Native text provides the chart name, boundary dates, latest dated exact value, and any missing-evidence explanation; the vector is supplementary. Chart coordinates may use presentation-only floating point, while financial values remain Decimal text.

With fewer than two known values, show the latest dated observation and the insufficient-history explanation instead of a blank plot. Missing samples break the line. A known observation beside missing history must remain visible and must not imply a continuous trend.

**The Evidence Rule.** Plot recorded observations and break the line at missing evidence; insufficient history becomes a dated textual observation.

## Do's and Don'ts

### Do:

- Do pair each surface with its own appearance's foreground role.
- Do keep amounts aligned and distinguish quantity, cost, price, cash, and gain.
- Do reuse native shared fields, buttons, sheets, icons, and guarded navigation.
- Do retain invalid drafts and give the user a concrete correction or retry.
- Do show changed facts and missing valuation evidence in native text.
- Do preserve complete operation, account-role, amount, and currency semantics in row accessibility labels.

### Don't:

- Don't combine currencies without recorded conversion evidence.
- Don't add a card around each row inside an existing group.
- Don't rely on color alone for financial direction or destructive intent.
- Don't use a transfer arrow for an investment's holding and settlement relationship.
- Don't fabricate chart history or connect a line across missing prices or exchange rates.
- Don't add decorative atlas graphics, raster ornament, or marketing hierarchy to the task workspace.
