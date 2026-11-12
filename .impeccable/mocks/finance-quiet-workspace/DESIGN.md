---
name: "FinanceOS Quiet Workspace — browser proposal"
description: "User-selected quiet professional strategy; artifact-only extracted system, not production authority."
colors:
  light-canvas: "#F8F8F8"
  light-paper: "#FFFFFF"
  light-ink: "#262626"
  light-muted: "#656565"
  light-line: "#E2E2E2"
  light-soft: "#EFEFEF"
  light-wash: "#EAEFF2"
  light-action: "#2C2C2C"
  light-onAction: "#FFFFFF"
  light-focus: "#345E74"
  light-link: "#345E74"
  light-gain: "#356747"
  light-error: "#AD3833"
  light-warning: "#815728"
  light-dataCash: "#8A8A8A"
  light-dataInvestment: "#536978"
  dark-canvas: "#191919"
  dark-paper: "#232323"
  dark-ink: "#ECECEC"
  dark-muted: "#B0B0B0"
  dark-line: "#383838"
  dark-soft: "#2E2E2E"
  dark-wash: "#303A40"
  dark-action: "#E7E7E7"
  dark-onAction: "#252525"
  dark-focus: "#9BB5C9"
  dark-link: "#BACDD8"
  dark-gain: "#96B79F"
  dark-error: "#E9A39B"
  dark-warning: "#D3B287"
  dark-dataCash: "#808080"
  dark-dataInvestment: "#A4B4BF"
typography:
  page:
    fontFamily: "system-ui, -apple-system, Noto Sans SC, Source Han Sans CN, sans-serif"
    fontSize: "22px"
    fontWeight: 600
    lineHeight: 1.3
    letterSpacing: "-0.025em"
  section:
    fontFamily: "system-ui, -apple-system, Noto Sans SC, Source Han Sans CN, sans-serif"
    fontSize: "14px"
    fontWeight: 600
    lineHeight: 1.5
  row-title:
    fontFamily: "system-ui, -apple-system, Noto Sans SC, Source Han Sans CN, sans-serif"
    fontSize: "14px"
    fontWeight: 450
    lineHeight: 1.45
  row-amount:
    fontFamily: "system-ui, -apple-system, Noto Sans SC, Source Han Sans CN, sans-serif"
    fontSize: "15px"
    fontWeight: 500
  expense:
    fontFamily: "system-ui, -apple-system, Noto Sans SC, Source Han Sans CN, sans-serif"
    fontSize: "29px"
    fontWeight: 500
    lineHeight: 1.15
    letterSpacing: "-0.035em"
  income:
    fontFamily: "system-ui, -apple-system, Noto Sans SC, Source Han Sans CN, sans-serif"
    fontSize: "20px"
    fontWeight: 450
  net-worth:
    fontFamily: "system-ui, -apple-system, Noto Sans SC, Source Han Sans CN, sans-serif"
    fontSize: "32px"
    fontWeight: 450
    lineHeight: 1.2
  amount-input:
    fontFamily: "system-ui, -apple-system, Noto Sans SC, Source Han Sans CN, sans-serif"
    fontSize: "40px"
    fontWeight: 450
    letterSpacing: "-0.035em"
  action:
    fontFamily: "system-ui, -apple-system, Noto Sans SC, Source Han Sans CN, sans-serif"
    fontSize: "13px"
    fontWeight: 550
    lineHeight: 1.4
  choice:
    fontFamily: "system-ui, -apple-system, Noto Sans SC, Source Han Sans CN, sans-serif"
    fontSize: "12px"
    fontWeight: 450
    lineHeight: 1.25
rounded:
  row: "7px"
  field: "9px"
  control: "10px"
  sheet: "18px"
spacing:
  choice: "6px"
  row: "11px"
  page: "22px"
  page-narrow: "18px"
components:
  button-primary:
    backgroundColor: "{colors.light-action}"
    textColor: "{colors.light-onAction}"
    typography: "{typography.action}"
    rounded: "{rounded.control}"
    padding: "0px 18px"
    height: "48px"
  button-secondary:
    backgroundColor: "{colors.light-soft}"
    textColor: "{colors.light-ink}"
    rounded: "{rounded.control}"
    padding: "0px 12px"
    height: "48px"
  field:
    backgroundColor: "{colors.light-canvas}"
    textColor: "{colors.light-ink}"
    rounded: "{rounded.field}"
    padding: "11px 12px"
    height: "48px"
  choice-selected:
    backgroundColor: "{colors.light-wash}"
    textColor: "{colors.light-ink}"
    typography: "{typography.choice}"
    rounded: "{rounded.control}"
    padding: "8px 5px"
    height: "48px"
  choice-unselected:
    textColor: "{colors.light-muted}"
    typography: "{typography.choice}"
    rounded: "{rounded.control}"
    padding: "8px 5px"
    height: "48px"
  navigation:
    textColor: "{colors.light-muted}"
    height: "52px"
  changed-fact:
    textColor: "{colors.light-ink}"
    rounded: "{rounded.control}"
  flat-row:
    textColor: "{colors.light-ink}"
    typography: "{typography.row-title}"
    rounded: "{rounded.row}"
    padding: "12px 0px"
    height: "68px"
---

# Design System: FinanceOS Quiet Workspace proposal

## Overview

**Creative North Star: "Quiet Professional Workspace"**

The user selected a quiet professional tool strategy: Linear-like order, Things-like editing continuity, and glass limited to navigation layers. This record captures the final browser artifact after the later category-choice refinement; it does not authorize a native system migration.

Neutral paper and graphite keep exact financial facts central. Independent, low-weight choices and a local changed-fact receipt connect capture with its result. Production Rust and Flutter authorities remain unchanged.

**Key Characteristics:**

- Compact system type and exact tabular money.
- Independent category choices with a quiet wash and small check.
- Flat financial content, opaque editing, and bounded shell glass.

## Colors

### Primary

Graphite/light-neutral action pairs carry commits. Steel-blue focus and links orient action; they do not tint all reading surfaces. Use the matching appearance's foreground pair from frontmatter.

### Secondary

The selection wash is a restrained steel-tinted surface. Selected labels stay ink; the check uses the link role. Unselected choices remain muted.

### Neutral

Paper and graphite canvas, opaque editor paper, muted labels and fine lines organize reading. Gain, error, warning, cash and investment remain separate semantic roles, paired with signs, labels and evidence. Normal budget progress uses the investment-data role; near-limit and over-budget states use warning and error with explicit wording.

## Typography

Platform system sans-serif is the only family; no external font or raster lettering is loaded. Tabular figures apply to financial values. Frontmatter records standard-size roles: compact titles and rows; unequal expense/income summaries; a standalone net-worth role; and a larger input role. At widths up to 370px, summary sizes become 26/19px before user text scaling.

**The Exact Fact Rule.** Keep cash, quantity, cost, price and gain distinct; commit integer cents synchronously without money interpolation.

## Layout

A narrow phone column (maximum 430 CSS px) contains four persistent roots and preserves each scroll position. The workspace is 64px high; actual capture visual and hit height are both 48px. Capture appears on Today and Ledger. Slim bottom navigation replaces the earlier combined floating action slab. Insets are measured with ResizeObserver; content reserves top height and bottom height plus 24px. Standard/narrow page insets follow frontmatter.

The final first ledger row begins at 312.34375 CSS px in a 390×844 carrier. There is no simulated OS status bar; this is not a native safe-area comparison. Rows grow for enlarged text rather than shrinking amounts. At 600px and wider the browser adds a review frame, not an approved tablet layout. All dimensions are CSS lengths, not verified Android dp/sp equivalents.

## Elevation & Depth

Reading groups are flat. Fine separators and whitespace organize Today, budgets and account lists. Only the full-width top workspace and slim bottom navigation use a 96–88% neutral tint with 20px backdrop blur and 105% saturation. The editor is opaque paper, with a neutral 36% scrim and restrained modal shadow. Motion never animates blur. Solid query/settings/emulated transparency paths have browser evidence; unsupported-backdrop CSS exists but has not been run in a non-supporting browser.

**The Bounded Material Rule.** Use glass only on the two shell control regions; an opaque editor suspends their blur.

## Shapes

Control, field, row and sheet treatments use the extracted frontmatter corners. There is no shared category tray, white inset block, raised icon tile or choice shadow. Small line icons share a 24-unit viewbox and 1.65 stroke; category icons and check use a 17px rendered box. Navigation selection uses a short 18×2px line.

## Components

Primary commits use the paired action colors, a 48px minimum height and quiet press scale. Secondary browsing and text links have lower visual weight. The top capture button stays 48px high inside its 64px workspace.

Category choices form four independent columns with 6px gaps and targets at least 48×48px. Selection applies wash and ink text; a steel check replaces the icon through 120ms opacity. Text identity and aria-pressed remain. Focus has a separate outline; that is not a resting selection border.

**The Independent Choice Rule.** Keep category choices separate; selected wash and a check replace the category icon without a shared track, raised inset or shadow.

Fields keep labels visible, exact amount entry, optional metadata and guarded drafts. Account selection is a flat contextual row. The opaque editor retains recovery errors and a stable commit footer. Four labeled tabs preserve route identity; cash accounts precede holdings and debt in Wealth. Current balance date and historical valuation date remain distinct.

Successful commits update exact facts synchronously, then close the sheet, acknowledge the new row and retain a local receipt with undo while its snapshot remains. Navigation/later actions may clear or replace the receipt. Sheet entry/exit (280/220ms), pane transition (200ms), choices/presses (120ms), and row acknowledgment (1000ms) remain bounded and interruptible. Reduced motion shows final state; its supplied preference-switch test concerns a settled dialog, not active entry.

## Do's and Don'ts

### Do:

- Do preserve exact amounts, signs, account roles and dated price evidence.
- Do retain visible labels, aria states, keyboard focus and targets of at least 48 CSS px.
- Do keep the final category treatment independent and quiet.

### Don't:

- Don't restore the superseded shared gray category track or white inset.
- Don't add glass to financial rows, budget groups or the editor.
- Don't interpret browser pixels, encoded video fps or proposal approval as native acceptance.
