# NaviWealth native client: design standards

The NSH (Rust) client's design system and the decisions behind it. Tokens
live in `src/ui/theme.rs`; every screen is composed from `src/ui/`. Product
rules come from `docs/product/product-scope.md`: personal use, local-first,
AI only to turn text and images into drafts, using the owner's model account.

## The task

- **Primary task:** describe or photograph a record, confirm the result, and
  see what today adds up to; each week, see what changed.
- **Home:** four tabs (Today · Records · Assets · Review) in a floating glass bar
  beside one round ink capture button with a plus icon. The primary `IconBtn`
  is 56 pt, vertically centered beside the 64 pt dock. Its accessible name
  is New entry / 新记录; it opens the shared text/image composer.
  Settings is the corner action on Today.
  Pages pushed over the home cover the bar. Hidden tabs stay alive (their
  scroll position stays) and are hidden from screen readers.
- **Capture:** one text/image composer. The result is a readable receipt-like
  summary, with one correction box. No domain selection before input and no
  prefilled form as the main result. Missing values ask a concrete question;
  proposed new accounts are marked. Multiple records show their count on
  confirmation. Manual meal/money/weight actions are secondary under one
  disclosure; favorites remain directly available with Undo.
- **Task sheets:** header and actions stay fixed; only the body scrolls.
  Available height excludes the keyboard. Toasts belong to the active sheet
  while it is open, so Undo cannot be covered by its backdrop.
- **Manual money:** amount, account/category (or from/to), a calendar date,
  optional details. Pickers replace the body in the same sheet; Back returns
  to the draft. Time, payee and note live in Details. Successful saves alone
  update remembered account/category choices.
- **No hidden gestures.** Every action is a visible control; nothing
  depends on a long press.
- **Today shows today:** the intake card (figure, what is left of the goal,
  the macro ring) and, laid flat beneath it, the vitals: weight, plus sleep
  and Body Battery once Garmin is connected (a Garmin vital opens all of the
  day's Garmin data). Then today's meals. Past days are in Records.
- **Drafts:** text/image inputs and recognition results are kept on device,
  pinned on Today and atop Records from one shared source. They can be left,
  reopened, corrected in a sentence, retried, confirmed or discarded with
  Undo. Confirmation consumes the draft and writes all its records together.
  A draft never contributes to totals. Recognized food nutrition remains an
  estimate, and unknown payment accounts are never silently guessed.
- **Records:** every day newest first, its header on one line (date, the
  day's kcal, a weight chip that opens the weight editor), its meals as rows
  of one card; all / meals / weight / money; 21 days at a time. The calendar button
  opens a month calendar; a chosen day is shown alone, under a bar with its
  date, steps to the days with records before and after it, and All days.
- **Assets:** one overview card leads with net worth, followed by asset and
  debt totals in two columns. Cash accounts, open holdings and debt accounts
  follow as flat rows on the canvas.
  With holdings, values use dated manual CNY prices, falling back to cost
  when unpriced; without holdings, the basis is book balances. The visible
  short valuation basis links to Asset changes, which holds the 30-day chart,
  full valuation basis and a note that changes are not investment returns.
  Each holding keeps its manual price date or cost-fallback label. Unchecked
  accounts keep a visible label; ordinary last-check dates live in account
  details and remain in the row's accessible description. Internal holding
  cost accounts stay out of the account list. Manage opens one bottom sheet
  with Add account, Add holding and Closed holdings. No accounts or holdings
  shows a short empty state with Add account and Add holding. The global text/image
  capture button remains the main record entry.
- **Holdings:** flat overview rows show name, value and price status; quantity
  and average unit cost live in details. Closed positions remain accessible
  through Manage → Closed holdings, with their history and trade actions;
  buying again returns a position to the overview automatically. A row opens
  a detail page with value, an explicit price-edit action, quantity, cost, unrealized
  gain, Record trade, and newest-first activity. Realized gain and dividends
  appear when nonzero; unpriced unrealized gain is a dash. Opening a holding
  needs name, quantity and unit cost. Buy/sell use quantity, price and a cash
  account; dividends use amount and a cash account. Optional fees and date
  sit under Details. Date and cash pickers replace the same sheet body;
  Back preserves the draft. Unsaved trade input has a discard guard. Prices
  have their own compact amount-and-date sheet. Activity opens a receipt
  with an explicit, confirmed remove action.
- **Own accounts:** creation asks only for asset/liability type and name;
  the balance can be checked later. Creating an account opens its detail
  page. Account rows open the book balance or debt, latest check status and
  newest-first activity, with Show earlier for more history. Rename is a
  visible pencil action; it edits the name, not the account type.
- **Balance checks:** one compact task sheet asks for amount and date.
  The calendar and then the difference preview replace its body; Back
  preserves the input. The preview names the account and date, shows book
  balance or debt, actual balance or debt, and the difference before an
  explicit confirmation. A match saves the observation without a posting;
  a difference also records an equity posting (opening balance when there
  is no prior activity, adjustment otherwise), with copy explaining that
  income and spending are unaffected. Debt is presented as an amount owed,
  including in the preview; credit is negative. Unsaved name or amount edits
  have a discard guard. Opening and adjustment entries open a readable
  summary linked to the account; corrections go through another balance check.
- **Review:** a calendar week (Monday first in Chinese and ISO locales) or
  month, stepped back with a labelled stepper. It leads with one sentence of
  what changed (daily average against the period before, weight trend),
  then the intake card: a bar per day for a week, a calendar for a month
  (shaded by share of the goal, amber past it, a dot on weighed days, today
  outlined; a day opens in Records). Then the one-line note, the weight with
  its 7-day trend line, and Garmin averages.
- **Settings keep every change as it is made; there is no Save.** The model
  has its own page; the goal, asking before recognition, Garmin and backups
  sit on the Settings page. A changed model account requires consent again
  before sending text, images and account names.

Missing records never read as zero: an empty day shows "—" and "Nothing
logged yet", never 0 kcal; a day without meals has no bar and no shade.

## Visual language: 墨与日光 · Ink & Daylight

A warm daylight canvas, white surfaces lifted by soft light, and ink for
everything that acts. The interface is monochrome; the food's photos carry
the color. Color is reserved for state: the AI's iris-to-sky light while it
works, amber past a goal or for estimates to check, red for destructive
actions, green for a passed connection. Data never gets decorative color:
the macronutrients are three steps of one warm-stone ramp. Dark is a deep
graphite with white ink, surfaces separated by tone and a hairline.

| Role | Tokens |
|---|---|
| Surfaces | `CANVAS`, `SURFACE`, `SURFACE_2` (wells), `SUNKEN` (fields, tracks), `RAISED`, `LINE`, `LINE_STRONG` |
| Text | `INK` (titles, figures), `BODY`, `MUTED` |
| Decorative / inactive | `FAINT` (tertiary marks such as chevrons, disabled controls and unavailable dates) |
| Action | `ACTION` (ink), `ACTION_PRESSED`, `ACTION_SHEEN`, `ON_ACTION` |
| AI | `AI_FROM` → `AI_TO` (analysis light, estimate marks) |
| Status | `DANGER(_SOFT)`, `CAUTION(_SOFT)` (past a goal, estimates to check), `POSITIVE` |
| Data | `PROTEIN` / `CARBS` / `FAT` (dark / middle / light stone), `OTHER`, `TRACK`, `HEAT` (calendar shade) |
| Media | `ON_MEDIA`, `MEDIA_SCRIM`, `PHOTO_WELL` |

Core palette from `src/ui/theme.rs`; each adaptive token switches with the
system appearance. The warm neutral surfaces and ink actions retain the
Ink & Daylight identity in both appearances.

| Token | Light | Dark |
|---|---|---|
| `CANVAS` | `#F4F3EF` | `#111211` |
| `SURFACE` | `#FFFFFF` | `#1B1C1B` |
| `SURFACE_2` | `#F3F2EE` | `#242522` |
| `SUNKEN` / `TRACK` | `#ECEBE6` | `#20211F` |
| `RAISED` | `#FFFFFF` | `#2D2E2B` |
| `LINE` | `#E7E6E0` | `#30312E` |
| `LINE_STRONG` | `#D0CFC8` | `#484944` |
| `INK` / `ACTION` | `#1C1D1A` | `#EAEBE7` |
| `BODY` | `#32332F` | `#D5D6D0` |
| `MUTED` | `#696A66` | `#A1A29E` |
| `FAINT` | `#A4A59E` | `#686A63` |
| `ACTION_PRESSED` | `#383A34` | `#D0D2CA` |
| `ACTION_SHEEN` | `#34362F` | `#F0F1ED` |
| `ON_ACTION` | `#FFFFFF` | `#1C1D1A` |
| `DANGER` / `DANGER_SOFT` | `#AE303B` / `#FDECEC` | `#FF6369` / `#3A1618` |
| `CAUTION` / `CAUTION_SOFT` | `#8C5A14` / `#FFF3DA` | `#FFC046` / `#372809` |
| `POSITIVE` | `#23754F` | `#4CC38A` |

Use `MUTED` for readable secondary copy, labels, placeholders, missing-value
dashes, macro percentages and past dates without records. Reserve `FAINT`
for decorative marks and inactive states, including disabled controls and
future dates without records; it is outside the text contrast checks below.
Status color conveys meaning: `DANGER` for errors and destructive actions,
`CAUTION` for estimates to check or a goal exceeded, and `POSITIVE` for a
completed connection. Soft status fills hold their matching foreground.
Financial values, including gains and losses, stay in neutral ink.

- **Type** (`Type`): Display 44, LargeTitle 34, Title 22, Figure 20,
  Headline 17, Body 16, Callout 15, Subhead 14, Caption 12.5; tabular
  numerals everywhere numbers move.
- **Numbers:** every standalone number is a `stat`: the whole part in ink,
  decimals one step quieter, the unit muted on the same baseline, a
  dash and no unit without a value. `Scale::Hero` (Display) is the one
  headline number of a card; `Scale::Tile` (Figure) sits among others. Assets
  uses its own exact money renderer: net worth follows the same baseline
  hierarchy, while other financial amounts keep a single text style.
- **Cards** hold the one main figure of a screen (Today's intake, Review's
  intake, Assets' net worth), repeated rows, sheets and framed tools.
  Secondary figures (vitals, Review's weight and Garmin averages) lie flat
  on the canvas, grouped by hairlines and space. Cards never nest.
- **Rows** for meals lead with the photo when present; otherwise the text
  starts at the card's inset. No placeholder art. Asset overview rows use
  existing semantic icons: Wallet for cash accounts, Minus for debt accounts
  and Chart for holdings, without inferring account subtypes from names.
- **Shape:** controls are pills; sheet 32 > card 24 > well 18 > field 16 >
  thumbnail 16 > badge 8.
- **Depth:** `shadow::CARD` under cards, `shadow::FLOAT` under the main
  action and raised buttons; none in dark. Glass only for controls over
  photos and the tab bar. The tab bar uses the lighter `shadow::SEGMENT`,
  a nearly opaque `SURFACE` fill (0.94 opacity) and restrained blur (12 pt).
- **Spacing:** the 4 pt scale; page gutter 20, card inset 20.

## Components (`src/ui/`)

`Btn` (primary ink with sheen / tonal / secondary raised / ghost / danger /
glass; three pill sizes), `IconBtn` (circles of the same variants), `chip`,
`card`, `row_button`, `hairline`, `section_header`, `group_label`,
`disclosure`, `segmented`, fields (visible labels and placeholders in
`MUTED`, ink focus edge),
`checkbox_row` / `switch_row`, `bottom_sheet`, toast (ink pill with one
action, usually Undo), `spinner`, `shimmer` + `skeleton`, `badge`,
`empty_state`, `appear`, `stat` with `counted` (a figure easing to its new
value), `macro_tiles`, the energy `ring`, and one icon family (24 pt line
glyphs). Pages share one top bar: a raised round Back and the title
centered. Screens: the month calendar (`pages/review_calendar.rs`) serves
Review's month and Records' go-to-day sheet.

Assets reuses the existing `card` for its single overview panel. Net worth
aligns an ink whole amount (`Type::Display`), muted currency (`Type::Figure`)
and muted decimals (`Type::Title`) on one baseline, exposed as one accessible
element labelled with the full exact amount. The two subordinate totals use
`Type::Body` values with muted caption labels. Holding and account rows stay
flat, separated by space without hairlines, with muted 22 pt semantic icons
and their existing valuation statuses. Activity rows retain hairlines.
Asset changes carries the trend on a separate pushed page:
a single ink line with a visible range and date endpoints, plus an accessible
start/end summary; insufficient history gets explanatory text. Money keeps
tabular numerals and neutral ink, including gains and losses. Overview
amounts and primary balance/value figures use grouped thousands and two
decimal places through a display-only formatter that preserves exact minor
units and editable input. Detailed cost and gain figures keep their existing
money formatting and come from the domain calculation. Quantity, average
unit cost and unit price retain up to six decimal places. The price basis is
manual CNY, without live quotes, FX, catalog search or AI trade entry.
Account, holding and price editors reuse `task_sheet` and the existing
calendar picker, with actions fixed above the keyboard. Quantity and unit
cost/price share one row; secondary trade details remain collapsed initially.

## Platform decisions

- Pages hide the system header and draw their own top bar; the system back
  gesture still pops natively, and the meal page's `pop_on_back` guards an
  unsaved meal.
- The meal page's photo runs under the status bar.
- Photos come only from the system photo picker (it also takes photos).
  Every pick becomes an upright JPEG of at most 1280 px, which drops
  EXIF/GPS.
- Requests go through NSH's `fetch`, straight to the account's base URL.
- Before recognition input leaves the device, a sheet names the server,
  model and data being sent. "Don't ask again" is remembered per account
  fingerprint; old photo-only consent does not authorize text/account context.
- The API key is stored on the device under its own storage key, never with
  the other settings, never logged.

## Motion inventory

Tokens: instant 120 ms, fast 180, base 240, slow 380, slower 640; settle
curve `cubic-bezier(0.22, 1, 0.36, 1)`; press spring (600 / 38); rise 14 pt;
stagger 50 ms (8 at most). Reduced motion: every item below is instant or
still.

| Screen | Change | Motion | Reduced motion |
|---|---|---|---|
| All | Button press | Spring to 0.96 (cards and tiles 0.98, icon buttons 0.90), deeper fill | Fill only |
| Home | Tab chosen | The bar's pill slides to the tab (native spring) | Jumps |
| Today | Day's energy changes | Ring segments sweep to their new ends, `slower`; the figure eases to its new value | Set at once |
| Today | Meals arrive (open, save, undo) | Rows rise 14 pt and fade in, staggered | Shown at once |
| All | Toast | Slides up and fades, `slow`; its action (Undo) restores | Shown at once |
| Meal page | Scrolling | Photo drifts at half speed; the top bar frosts in once the panel slides under it | Bar switches at once |
| Meal page | Analyzing | The AI's light passes over the photo (2 s loop); placeholders shimmer | No light, no shimmer |
| Meal page | Results arrive | Rows rise in, staggered; the total eases up | Shown at once |
| Segmented | Choice | Raised pill slides to the segment (spring) | Jumps |
| Sheets | Open / close | Slide from the bottom over a fading scrim; swipe down to close | Appear / disappear |
| Toggles | Checkbox / switch | Fill `instant`; knob slides `fast` | Instant |

Verified on the GTK desktop build with the previews in `src/preview.rs`;
holdings review captures are in `.impeccable/review/holdings/` at the repository
root. The simplified Assets overview, Manage sheet, Asset changes, closed
holdings and empty state are captured in `.impeccable/review/assets-simple/`,
including light and dark overview captures. The subsequent overview-card,
row-icon and quieter-dock refinement is captured in
`.impeccable/review/assets-polished/`. These are desktop development evidence
only; Android device verification remains outstanding.

The warm neutral palette refinement is captured in
`.impeccable/review/palette/`: `assets-light.png`, `assets-dark.png`,
`capture-missing-light.png` and `capture-missing-dark.png`, alongside the
other reviewed states. These captures are also GTK desktop development
evidence only. The source-token calculation in that directory's
`contrast.json` checks 72 text/background pairs across both appearances;
all are at least 4.5:1. The minimum is light `MUTED` on `SUNKEN` (4.56:1).
Light status minima are `DANGER` on its pressed soft fill (4.77:1),
`CAUTION` on `SUNKEN` (4.90:1), and `POSITIVE` on `SUNKEN` (4.72:1).
The dark minimum is `DANGER` on `RAISED` (4.71:1). This is evidence for
those checked token pairs, not a whole-app WCAG conformance claim.
