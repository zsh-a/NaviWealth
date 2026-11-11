---
name: NaviWealth Rust Client
description: A calm, precise daily finance workspace.
colors:
  light-background: "#F7F8FB"
  light-foreground: "#252B3A"
  light-card: "#FFFFFF"
  light-primary: "#535FC5"
  light-primary-foreground: "#FFFFFF"
  light-secondary: "#EAECF9"
  light-secondary-foreground: "#414C9F"
  light-muted: "#EEF0F6"
  light-muted-foreground: "#636B7B"
  light-destructive: "#DC2626"
  light-destructive-foreground: "#FFFFFF"
  light-border: "#E3E6EE"
  dark-background: "#11131A"
  dark-foreground: "#E7EAF2"
  dark-card: "#1B1E28"
  dark-primary: "#98A4EF"
  dark-primary-foreground: "#10122A"
  dark-secondary: "#2C3152"
  dark-secondary-foreground: "#E4E7FD"
  dark-muted: "#222633"
  dark-muted-foreground: "#B0B7C8"
  dark-destructive: "#F87171"
  dark-destructive-foreground: "#1A0B0B"
  dark-border: "#343B4C"
typography:
  page:
    fontFamily: "system-ui, sans-serif"
    fontSize: "26px"
    fontWeight: 600
  section:
    fontFamily: "system-ui, sans-serif"
    fontSize: "18px"
    fontWeight: 600
    lineHeight: "28px"
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
  amount-summary:
    fontFamily: "system-ui, sans-serif"
    fontSize: "22px"
    fontWeight: 500
  amount-detail:
    fontFamily: "system-ui, sans-serif"
    fontSize: "34px"
  amount-input:
    fontFamily: "system-ui, sans-serif"
    fontSize: "40px"
    fontWeight: 500
rounded:
  control: "12px"
  group: "16px"
spacing:
  related: "4px"
  compact: "8px"
  row: "12px"
  group: "16px"
  page: "20px"
  generous: "24px"
components:
  button-primary:
    backgroundColor: "{colors.light-primary}"
    textColor: "{colors.light-primary-foreground}"
    typography: "{typography.body}"
    rounded: "{rounded.control}"
    padding: "0px 16px"
  button-secondary:
    backgroundColor: "{colors.light-secondary}"
    textColor: "{colors.light-secondary-foreground}"
    typography: "{typography.body}"
    rounded: "{rounded.control}"
    padding: "0px 16px"
  button-destructive:
    backgroundColor: "{colors.light-destructive}"
    textColor: "{colors.light-destructive-foreground}"
    typography: "{typography.body}"
    rounded: "{rounded.control}"
    padding: "12px 16px"
  error-line:
    textColor: "{colors.light-destructive}"
    typography: "{typography.label}"
  field:
    backgroundColor: "{colors.light-card}"
    textColor: "{colors.light-foreground}"
    typography: "{typography.body}"
    rounded: "{rounded.control}"
    padding: "0px 12px"
  group:
    backgroundColor: "{colors.light-card}"
    rounded: "{rounded.group}"
  choice-selected:
    backgroundColor: "{colors.light-secondary}"
    textColor: "{colors.light-secondary-foreground}"
    typography: "{typography.label}"
    rounded: "{rounded.control}"
    padding: "8px 12px"
---

# Design System: NaviWealth Rust Client

## Overview

**Creative North Star: "The Porcelain Ledger"**

A quiet porcelain-and-graphite workspace for inspecting money and recording daily activity. Iris identifies the next useful action; exact amounts and dated rows carry the hierarchy. The Rust client extends the established 澄白 identity with native controls and restrained tonal grouping.

This system is scoped to `apps/client`. `theme.json` and the Rust implementation are the source of truth; the repository-root Flutter design system remains separate. This records daily-finance patterns, not release or platform acceptance.

**Key Characteristics:**

- Flat dated activity with right-aligned, explicit-currency amounts.
- Clear capture actions, grouped fields, and restrained iris emphasis.
- Native safe-area handling and guarded changes.

## Colors

The palette uses cool porcelain surfaces, graphite text, and a measured iris accent. Frontmatter records the reused light and dark roles from `theme.json`; runtime theme selection remains authoritative.

### Primary

Iris marks primary commits, active navigation, and selected emphasis. Primary foreground is paired with its own mode's primary surface.

### Secondary

Pale iris supports quiet actions and selected choices, leaving the main commit prominent.

### Neutral

Background is the workspace canvas; card is the grouped content and input surface. Foreground carries values; muted foreground carries supporting labels. Border separates fields and persistent navigation. Dark appearance uses the matching ink/slate roles.

Destructive is reserved for errors and destructive actions, accompanied by explicit text and confirmation.

**The Currency Rule.** Currency labels and signs carry financial meaning; color is supplementary.

## Typography

Native text uses the platform's default sans-serif and system text behavior. `system-ui` in the portable tokens and previews describes that role, not an external font dependency. The body and label line heights follow nsh 0.4 text presets; custom amount sizes do not declare a separate line height.

- **Page:** semibold page names.
- **Section:** semibold sheet headings and grouped section titles.
- **Body:** inputs, actions, and principal row text.
- **Label:** descriptions, field labels, and dates.
- **Caption:** compact currency labels beneath ledger amounts.
- **Amounts:** monthly summaries, record detail, and the larger editable amount use the corresponding amount roles. Account totals use the page-size scale with medium weight.

**The Exact Amount Rule.** Use tabular digits for displayed monetary values and exact Decimal text; never round a small nonzero amount to zero for presentation.

## Layout

The native shell opens on 流水 and keeps existing tab identities. A page inset frames a fixed title/action row above scrolling content; related text is tighter than fields and groups. Dated records share a flat white/slate group, separated by spacing. Account rows use the same structure with dividers; both row types have a minimum height of 80 logical pixels.

Interactive scrolling content uses shared `ui::interactive_scroll()` with `KeyboardTaps::Handled`. Buttons and pickers remain eligible for taps while an input retains focus; an unhandled background tap can dismiss the keyboard. Use this helper for editable or actionable scroll content, including sheets and reopened editors.

The ledger keeps search visible and moves account/type/time controls into a compact filter sheet. Monthly totals are paired within each currency. Detail and record editing occupy a full page. The record editor keeps a scrolling body between its header and safe-area-padded save footer; the amount field leads the form.

Choice sheets scroll and use 75% of window height, clamped between 240 and 480 logical pixels; account editing uses available height minus 80, clamped between 320 and 680. Shared sheet footers reserve the system bottom inset plus normal content padding. The tab bar reserves the bottom inset plus 6 logical pixels. No separate breakpoint-based desktop layout is implemented.

## Elevation & Depth

Surfaces are flat at rest; grouping comes from tone, spacing, borders, and dividers. Shared native sheets dim the underlying task with a black scrim at 32% opacity. There is no authored shadow vocabulary. Press feedback reduces shared action opacity to 75%; no custom motion timing is established.

## Shapes

Controls have gently rounded corners; content groups have a broader radius. Shared line icons use a 24-unit viewbox, a 1.7-unit round stroke, and a 22-pixel rendered box. Icon buttons reserve a 48-pixel square. Repeated rows stay flat inside a group.

## Components

### Buttons

Primary and secondary actions share a minimum 48-pixel height and horizontal group padding. Primary labels are semibold; secondary labels use normal weight. Saving disables duplicate commits; pressed actions use opacity feedback. Destructive buttons use their dedicated foreground/surface pair for the final delete confirmation, including empty-account deletion.

### Choices and filters

The main choice control is a rounded, minimum 48-pixel selection button. Selected state uses secondary iris; unselected state uses card with muted text. Account/category selection dismisses the keyboard before opening a scrolling sheet. The compact filter sheet contains type, account, and time options with a Done action.

### Cards / Containers

Grouped surfaces hold repeated rows, paired summaries, or linked form choices. Ledger rows use spacing; account rows and linked form choices use dividers. Neither needs another card. Background remains visible between groups.

### Inputs / Fields

Fields have a visible label, minimum 48-pixel height, card surface, fine border, and control radius. Shared `ui::themed_input()` explicitly sets foreground text, muted hints, an iris caret, and secondary selection in the current appearance; native inputs must not depend on inherited text or hint color. Errors preserve the draft and use destructive text. Secrets use native masking. The amount input has a larger type role and an explicit currency annotation.

### Navigation

The persistent bottom tab bar pairs line icons and labels; iris marks the selected tab. 流水 comes first and is the default. Account detail can open that account's ledger history. Shared shell, header, and footer patterns handle safe-area padding.

### Guarded editors and confirmations

Income, expense, transfer, and opening-balance correction use the full record editor. Switching record kind preserves the draft and revalidates choices. Account creation and metadata editing use a focused sheet. Both guard unsaved changes and retain failed writes for correction. Record deletion explains its balance effect; account deletion is limited to accounts without history. Archive removes an account from new-entry pickers while preserving history and a restore action.

Backup export and import use the Android system document picker, followed by explicit restore confirmation. The UI does not request arbitrary filesystem paths. Restore failures use the shared error line with Chinese recovery guidance and confirm that existing data remains; technical diagnostics belong in debug logs.

## Do's and Don'ts

### Do:

- **Do** keep currencies explicit and totals separate by currency.
- **Do** use exact Decimal text with at least two fractional places; retain smaller nonzero values.
- **Do** use shared buttons, fields, sheets, icons, and theme roles.
- **Do** preserve dirty drafts and show errors beside the operation that failed.

### Don't:

- **Don't** combine unlike currencies without a real conversion.
- **Don't** put a card around each row inside an already grouped surface.
- **Don't** rely on color alone for income, expense, transfer, or destructive intent.
- **Don't** turn the daily workspace into a marketing page.
