---
name: "NaviWealth Native FinanceOS — Quiet Workspace"
description: "Quiet professional financial workspace for the Rust nsh client."
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

# NaviWealth Native FinanceOS — Quiet Workspace

This document owns the visual system for `apps/client`. The approved sources are
[the quiet workspace mock](../../.impeccable/mocks/finance-quiet-workspace/DESIGN.md)
and [its tokens](../../.impeccable/mocks/finance-quiet-workspace/tokens.json), promoted
by the user for this migration. This native document now takes over that authority.
Flutter (`apps/mobile`) retains its separate design system.

## World and roles

Neutral paper and ink organize a dense financial tool. Graphite marks primary
commits; steel blue marks focus; separators and whitespace organize facts.
`theme.json` owns runtime values. The paired light/dark colors and dimensions
above record the approved source tokens; Rust logical lengths are not claims
about physical pixels. Platform system fonts and tabular monetary figures remain.

Page titles use 22; expense and income summaries 29 and 20; net worth 32;
section/row titles 14–15; row amounts 15; actions 13; choices and captions at least
12; editable amount 40. Text grows with system scaling. Do not shrink exact facts
or touch targets to preserve density. Primary and secondary actions have a 48
minimum height. Rows start at 68 with 11 vertical inset; page gutters are 22,
or 18 at window widths up to 370. Long content may grow.

## Material and structure

**The Bounded Material Rule.** Glass belongs only to the top workspace and bottom
navigation. Content and editors remain opaque. The desired shell material is a
96%/88% neutral tint with 20 blur; opening a modal must suspend that blur. The
current Linux renderer has no identified backdrop-filter implementation. Core
exposes the style API; the Android Java bridge supports blur on API 31+. This client uses the approved solid paper fallback
for both shell regions on all current targets. No active blur requires suspension.
Do not enable transparent shells on another platform without native verification
and modal lifetime gating.

The workspace is 64 high with a 48 capture button on Today and Ledger only.
Four persistent business roots preserve filters and scroll context. Navigation
uses 52-high targets, 12 labels, a hairline top separator and an 18×2 ink selection
line. Native safe areas remain outside these content dimensions. Detail pages
retain native push/pop and Back behavior.

Reading content uses flat rows and separators; never nest cards. Editors use
opaque paper, 18 corners and a 36% scrim. Complex financial forms retain full-page
navigation, stable drafts, explicit errors and a guarded exit.

## Choices, focus and motion

**The Independent Choice Rule.** Categories form four independent columns with
6 gaps and targets at least 48×48. No common tray, raised inset or shadow. A
selected choice uses wash and ink; a 17 steel check replaces its line icon with
120ms opacity. Button accessibility selection state announces the same choice.
Account and date pickers retain their existing controls and keyboard dismissal.

Interactive shared controls use a 2 steel focus outline. Amount, payee and note
Enter submit through the same guarded save path as the commit button. Press
feedback retains quiet scale, disabled gating and reduced-motion behavior.
Reduced motion shows final icon and selection state immediately.

## Exact facts and feedback

**The Exact Fact Rule.** Keep cash, quantity, cost, price, gain and currencies
separate. Use exact Decimal text and at least two fractional places for money;
retain small nonzero facts. Never interpolate money during animation. Investment
rows name operation and holding/settlement account roles; arrows mean transfers.
Missing price/FX evidence remains explicit; chart gaps stay gaps.

Income uses gain and a plus sign, expense uses destructive and a minus sign.
Normal budget progress uses investment color; near-limit warning and reached/
exceeded destructive states also carry text. Cash projection charts use data-cash;
wealth and investment charts use data-investment. Color never carries meaning alone.

Saving on Today keeps the user there, shows up to five dated records and a link
to all activity. A receipt stays next to changed facts; the affected visible row
receives a wash. Saving under a filter explains that dates/filters may hide the
record. New records and ordinary record deletions offer a 60-second undo with
remaining seconds and retry on failure, across root tabs and pushed detail pages.
New actions replace the offer; editing does not offer removal. Undo availability
ends on expiry or restart. Structured investment/plan records keep their original
workflow guards. Continue editing is the filled primary action in discard guards;
discard is explicit destructive text.

## Evidence boundary

Browser mock screenshots establish the selected direction only. They do not
validate native layout, keyboard, focus, accessibility, blur, performance or
hardware behavior. Headless tests verify engine behavior and exact balances,
not native appearance. Current verification and outstanding platform checks live
in `docs/architecture/nsh-rust-rewrite.md`; historical marine screenshots do not
validate this replacement world. No iOS, tablet, ARM or Web acceptance is implied.
