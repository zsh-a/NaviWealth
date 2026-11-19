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
  scroll position stays) and are hidden from screen readers. Each tab scrolls
  in a viewport that ends above the dock and system inset.
- **Capture:** one bounded conversation
  ([Capture Conversation](../../docs/architecture/capture-conversation.md)). The
  description or photo is the thread's first message on the right, in an ink
  pill; the model's turns sit on the left behind a 2 pt iris-to-sky
  hairline. A turn carries the record summaries inline (the same readable
  cards as before), one to three clarifying questions as quiet wells, and —
  while an answer is still wanted — the question's tap-first options as
  chips of known accounts and categories. A turn that revised records
  collapses, once superseded, to an "Updated n records" badge. While the
  model works the thread shows a spinner in its light with "Reading your
  entry…"; a failure is a turn with Try again, Open settings and Keep
  previous result. No domain selection before input and no prefilled form
  as the main result. Missing values ask a concrete question; proposed new
  accounts are marked. Multiple records show their count on confirmation.
  New model decisions use `ask_user`: each question shows its reason and
  whether an answer is needed, then full-width choices with short descriptions.
  The question and its choices are grouped together, with answer controls pinned below.
  No choice is preselected. Tapping stages a choice with a check; tapping again
  clears it. Submit answers is the single primary continuation action, and the
  composer accepts extra text or photos. Selection persists immediately, while
  the model is called only on submission. Historical decisions have no active
  choices and the owner turn records the submitted answers. Pending tools and
  failed continuations withhold confirmation until a final result arrives.
  Manual meal/money/weight actions are secondary under one disclosure;
  favorites remain directly available with Undo. Close is a labelled cross,
  separate from Confirm and save; Discard draft is a header action with
  Undo; closing a nonempty draft reports that the draft is kept and no
  records were saved.
  The composer is the one stable input, pinned in the task actions above the
  keyboard: an accessible photo icon on every owner turn, the input
  (labelled What would you like to record? / 想记下什么？) and a round send
  button. The action row above it swaps the task's current action:
  Recognize on the consent sheet, Review later while the model works,
  Set up without a model, and Confirm and save once the records are ready.
  The draft accepts up to four images across all turns. Unsent evidence appears
  as contained thumbnails with visible Remove image actions; sent thumbnails
  stay with their owner message. At the limit, attachment is disabled. Pending
  questions or unsent evidence withhold confirmation.
  Only a draft with no thread yet requests initial focus after the sheet
  opens; a ready result stays readable.
  Account rows in a ready result open an existing-account picker in the same
  sheet. Transfer source and destination lists exclude the other account;
  internal holding accounts are never offered. Selection first persists the
  draft, then returns to the result, without calling the model or posting a
  transaction. With no eligible account, the picker explains how to name a
  proposed account through the composer. Back returns from the account
  picker or recognition consent; the cross closes the capture task.
  A successful confirmation reports the single record's kind and value, or
  the batch count. Its View action opens the common day in Records, or the
  unfiltered all-days timeline when the batch spans days.
  The thread is kept with its draft and never outlives it: confirming
  consumes it, discarding deletes it, and reopening a draft shows the whole
  conversation. An older single-question draft migrates into the thread as
  a plain question turn.
- **Task sheets:** header and actions stay fixed; only the body scrolls.
  Manage, account creation and holding creation share one native sheet;
  changing panels does not replay its entrance. Nested pickers return to the
  entered draft before Back leaves the task. Closing retains the mounted
  scope until the native exit completes. Initial focus follows the native
  Open event and a committed frame, rather than racing the entrance.
  Back (the button or the system back) steps back one panel; a swipe down
  or a backdrop press leaves the whole task, after the panel's discard
  guard. Saving closes the shared sheet before its panel resets, so the
  sheet leaves with the form rather than swapping the menu in.
  Capture uses `fitted_task_sheet`: short content determines its height,
  while longer results scroll at the available-height limit. The management
  menu and compact account editor also fit their content. Other task
  editors retain `task_sheet`'s filled height, capped at 540 pt. Both plan
  for the keyboard when they open (the last height it reached, else 38% of
  the window), so a showing keyboard only lifts the whole panel through a
  native `env()` margin; the panel, its scroll area and actions keep their
  size. Only a keyboard taller than planned still shrinks the sheet. Toasts belong to the active sheet while
  it is open, so Undo cannot be covered by its backdrop. Opening capture clears
  old informational notices and saved receipts; Undo messages keep their normal
  lifetime. A receipt's View cannot navigate behind a newly opened draft.
- **Manual money:** amount, account/category (or from/to), a calendar date,
  optional details. Pickers replace the body in the same sheet; Back returns
  to the draft. Time, payee and note live in Details. Successful saves alone
  update remembered account/category choices.
- **No hidden gestures.** Every action is a visible control; nothing
  depends on a long press.
- **Today shows today:** the main card is health only: intake as the one
  Display figure, what is left of the goal, and the macro ring (below the
  figure at large text). Flat beneath it are weight, plus sleep
  and Body Battery once Garmin is connected (a Garmin vital opens all of the
  day's Garmin data). Then today's records, whose header carries the count
  and the day's spending in each currency ("3 条 · 支出 ¥12.00"): spending
  is summarized beside the records it adds up. Opening balances and
  adjustments remain in the timeline with quieter labels and amounts; they
  are not spending. Groups are 24 pt apart, the records 32 pt below the
  vitals. Before any meals are logged, the card omits the empty ring and macro
  legend. Model setup is a compact row below the daily content. Past days are
  in Records.
- **Drafts:** text/image inputs and recognition results are kept on device,
  pinned on Today and atop Records from one shared source. They can be left,
  reopened, corrected in a sentence, retried, confirmed or discarded with
  Undo. Confirmation consumes the draft and writes all its records together.
  A draft never contributes to totals. Recognized food nutrition remains an
  estimate, and unknown payment accounts are never silently guessed.
- **Records:** every day newest first, its header on one line (date, the
  day's kcal, a weight chip that opens the weight editor), its meals as rows
  of one card; all / meals / weight / money; 21 days at a time. The calendar button
  opens a month calendar and shares the header with the statement import action.
  A chosen day is shown alone, under a bar with its date, steps to adjacent
  days with records, and All days.
- **Assets:** one overview card leads with net worth, followed by asset and
  debt totals in two columns. Cash accounts, open holdings and debt accounts
  follow as flat rows on the canvas.
  With holdings, values use dated native-currency prices, falling back to cost
  when unpriced; without holdings, the basis is book balances. CNY, HKD and
  USD accounts and holdings retain their original amounts. The overview converts
  to CNY using the latest rate on or before its date; missing rates label the
  figure as known value and name the excluded currencies. A history with missing
  dated rates shows an explicit message instead of an incomplete chart. The visible
  short valuation basis links to Asset changes, which holds the 30-day chart,
  full valuation basis and a note that changes are not investment returns.
  Each holding keeps its manual price date or cost-fallback label. Unchecked
  accounts keep a visible label; ordinary last-check dates live in account
  details and remain in the row's accessible description. Internal holding
  cost accounts stay out of the account list. Manage opens one bottom sheet
  with Add account, Add holding, Exchange rates and Closed holdings. No accounts or holdings
  shows a short empty state with Add account as the main action and Add holding
  as a quiet alternative. The global text/image capture button remains the
  main record entry.
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
- **Own accounts:** creation leads with the name and compact type/currency
  choices; the balance can be checked later. Creation stays on Assets and
  offers Check balance in the confirmation notice. Account rows open the
  book balance or debt, latest check status and
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
  outlined; a day opens in Records). Spending and weight follow, then the
  one-line note and Garmin averages. An empty intake card shows a short message.
- **Settings keep every change as it is made; there is no Save.** Recognition
  model / 识别模型 has its own page with one continuous form for API protocol,
  base URL, model and key. The protocol field shows the current choice;
  its native select opens an anchored desktop list or an Android touch picker
  containing Anthropic, OpenAI Chat and OpenAI Responses. Endpoint paths appear
  only in that list. Keep full labels, accessible selection state and field-sized
  touch targets at narrow widths and larger text. Test connection follows the
  fields; the device-storage note is a quiet footer. Protocol changes preserve
  custom connection fields and require recognition consent again; Test
  connection follows the chosen endpoint. Settings groups related rows under
  Health profile & goals, Devices & connections, Recognition & consent, Data
  & backups, and About. Body profile opens a dedicated editor and the index
  shows completion status. The scale opens that editor directly when needed.
  Body profile asks for an actual birth date using a calendar/year selector
  or ISO date entry. Age is computed on the current local day; previous
  entered ages are labelled legacy and never converted to invented birthdays.
  The daily calorie goal and goal weight expand in place. Garmin shows its
  connection or sync state and has explicit connect and disconnect actions.
  The scale sheet keeps the reading in its scroll region and the current
  action in a fixed footer. Three restrained stage tracks show actual connection,
  stable weight and composition completion; they never imply a timed percentage.
  The saved scale is a flat device row and signal strength uses plain language.
  Opening measurement makes one foreground auto-connect attempt to the saved
  scale, unless a retained draft needs review. Failures expose retry/change
  device, without repeated connection loops. Valid dynamic weight packets
  update a separate live figure but never enable confirmation before stability.
  Stable weight leads with a tabular figure and quieter decimals/unit; composition
  follows in three flat columns. Device/date details expand on request.
  Details also show the captured profile, BMI, estimated fat/fat-free/muscle/
  water masses, reference-derived resistance, and the named estimation model.
  Those derived values belong to this measurement, never a newer manual weight.
  After stable weight, the primary action waits for impedance while instructing
  the owner to remain on the scale. After 15 seconds, the sheet says it is still
  waiting, keeps accepting readings and offers Measure again. Interrupted and
  reopened weight-only drafts explicitly say composition is unfinished and also
  offer Measure again. Saving weight alone remains an explicit secondary action;
  only valid composition is labelled complete. Late timers cannot overwrite
  completed, cancelled or reopened reviews.
  All touch actions are at least 48 pt. Backup & restore shows automatic backup status
  and the last outcome. About displays the installed version before opening
  update details. A changed model account requires consent again before
  sending text, images and account names.

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
| Floating material | `ON_GLASS_MUTED` (dock labels), `GLASS_EDGE` |
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

- **Type** (`Type`): Display 44/700, LargeTitle 34/700, Title 20/600
  (sheet titles, empty states), Figure 20/24 600, Headline 17/600 (rows and
  section headers), Body 16, Callout 15, Subhead 14, Caption 12.5; tabular
  numerals everywhere numbers move. Headline is 600; Subhead and Caption
  use 500 so supporting text does not compete with figures.
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
- **Rows** for meals and money share a 52 pt leading footprint. A meal without
  a photo uses the semantic food icon; financial rows use their semantic
  icon (Check for opening balances and adjustments; Sliders stays Settings).
  Footprint icons are 20 pt and muted so the column aligns without reading
  as a column of icons. Dividers start where row text starts and run to the
  card's edge (weight rows, without a footprint, at the card inset). Amount
  and currency share a baseline,
  with a stacked layout for large text or long exact amounts. Asset rows use
  existing semantic icons: Wallet for cash accounts, Minus for debt accounts
  and Chart for holdings, without inferring account subtypes from names.
- **Shape:** controls are pills; sheet 32 > card 24 > well 18 > field 16 >
  thumbnail 16 > badge 8. Cards and sheet top corners use continuous curves.
- **Depth:** matte content and task sheets, with local frosted navigation;
  light appearance uses the shared shadow vocabulary below, dark uses tone
  and edges without shadows.
- **Spacing:** the 4 pt scale; page gutter 20, card inset 20.

## App mark: Folio · 页间

The app mark is two turning pages with a parallel diagonal channel,
drawn as two filled paths in [`brand/folio.svg`](brand/folio.svg). It uses
the interface's ink `#1C1D1A` and warm canvas `#F4F3EF`. The open space
between the pages is part of the mark; preserve it at small sizes. Inverse
and launcher versions reuse the same paths, without gradients or textures.

Run `rtk proxy python3 tool/render-nsh-brand.py` from the repository to
export the full-square [`brand/icon-folio.svg`](brand/icon-folio.svg) and
1024 px [`icon.png`](icon.png) used by the Android release workflow, plus
mask and 16–64 px review renders in `.impeccable/review/folio-refined/`.
Presentation corners are previews; the exported icon has a complete opaque
background. Edit the master and regenerate rather than editing the PNG.
Desktop raster previews do not establish Android launcher or adaptive-icon
behavior.

## Elevation & Depth

### Materials

Cards, rows, fields and reading surfaces remain opaque. `src/ui/material.rs`
shares the floating materials' surface tint, reflected edge and fallback;
`src/ui/theme.rs` owns their values. Status and data colors keep their
existing meanings.

| Material | Surface | Edge and light | Lift |
|---|---|---|---|
| Dock | `SURFACE` at 0.80 opacity, 20 pt backdrop blur | 0.75 pt `GLASS_EDGE` around the pill | `shadow::DOCK` |
| Sheet | Opaque `SURFACE`, no backdrop blur or highlight wash | Tone separates content from a 0.32 black scrim | None: a large blurred shadow is costly to redraw while the sheet moves with the keyboard |
| Media controls and captions | `MEDIA_SCRIM` at 0.64 opacity, 18 pt backdrop blur; pressed buttons use 0.74 opacity | White `ON_MEDIA`; caption secondary text at 0.8 opacity | No additional shadow |

The glass edge is white at `#B8` alpha in light appearance and `#20`
in dark. No canvas-colored fade covers the content beneath the dock;
scroll clearance still lets the final row move fully above it.
Inactive dock labels use `ON_GLASS_MUTED` (`#545550` light / `#BDBFB7` dark)
for legibility through the tint. The chosen tab's indicator is `INK` at 7%,
a tint that reads on glass in both appearances (an opaque well read as a
grey patch). Media readability comes from the dark mask
even when backdrop blur is unavailable.

The dock falls back to fully opaque `SURFACE`, with no
backdrop filter, on Linux and Android below API 31. NSH 0.5's GTK renderer
does not render backdrop filters. Android API 31 and above takes the blur
path; its rendering and performance remain unverified on a real device.
The home dock also becomes opaque while a home-owned sheet is open or a
pushed route is active. This is a local home lifecycle rule, not a global
limit on simultaneous materials.

### Shadow vocabulary

Shadow tuples below are `(x, y, blur, spread, #RRGGBBAA)` in points, from
`src/ui/theme.rs`. All layers are outside shadows; `Lift` removes them in
dark appearance.

| Token | Layers | Use |
|---|---|---|
| `CARD` | `(0, 1, 2, 0, #1A14080A)`; `(0, 6, 20, -5, #1A140814)` | Content cards and secondary raised buttons |
| `FLOAT` | `(0, 2, 6, 0, #0A0A0B1F)`; `(0, 8, 20, -6, #0A0A0B30)` | Primary buttons, including the round capture action |
| `DOCK` | `(0, 1, 3, 0, #1A14080A)`; `(0, 5, 18, -5, #1A14081F)` | Floating tab bar |
| `SEGMENT` | `(0, 2, 6, 0, #1A140814)` | Selected segments and pressed primary buttons |

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

Button feedback is restrained: buttons and chips press to 98%, icon buttons
to 96%. Primary buttons lose their sheen and settle to `shadow::SEGMENT`
while pressed. The shared primary button and primary icon button each emit
one light impact on activation; the home capture action adds no second
haptic. Reduced motion keeps scale at 1 without starting the press spring.
Sheets retain `nsh_base`'s entrance, backdrop, back/Escape and swipe-down
behavior; the material layer adds no custom transition.

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
unit cost and unit price retain up to six decimal places.

Holding creation offers offline code/name/pinyin search before quantity and
unit cost, with manual naming still available. Search replaces the body of
the same task sheet at a stable height and shows market,
code and currency; unsupported currencies and instrument types are visibly
unavailable. Existing holdings require a separate link confirmation: catalog
identity never replaces the holding's internal id, label, account or trades.
Results settle after 120 ms and grow in batches of 16. The catalog keeps a
normalized search index; decoding and verification of downloaded updates run
off the engine thread before a short atomic installation. Stale refreshes
cannot replace a newly loaded catalog. The bundled GitHub Releases catalog
checks for updates when the picker opens,
at most once per 24 hours, with a manual retry and an explicit offline fallback.
Mainland China, Hong Kong and US stocks and ETFs can be linked in their
CNY, HKD and USD trading currencies. Manual creation offers compact currency
choices; catalog selection sets currency automatically. Existing holdings keep
their currency, and trade cash choices include only matching asset accounts.

Assets has one visible quote refresh action inside its overview card.
Tencent marks refresh in the
foreground with a five-minute automatic throttle; manual refresh bypasses the
throttle. Holding price captions distinguish manual input, Tencent observations,
previous close and earlier dates. A manual mark wins on the same or a newer
date; a failed network request keeps the last dated mark. Unpriced holdings
remain visibly valued at cost. Exchange rates shows dated HKD/CNY and USD/CNY
observations and a compact manual rate editor. Manual rates take precedence over
network rates on the same day; no rate is applied before its recorded date.
Cross-currency transfers require separate sent and received amounts and preserve
both native values. Schema 14 backs up rates with the ledger. Other currencies,
crypto, allocation and AI trade entry remain outside this increment. Android
TLS and physical-device behavior remain unverified.
Account, holding and price editors reuse `task_sheet` and the existing
calendar picker, with actions fixed above the keyboard. Quantity and unit
cost/price share one row; secondary trade details remain collapsed initially.

Review calls the money panel “Recorded spending”: its total reflects confirmed
journal entries, with the three largest expense categories initially visible.
The total and category rows open the corresponding editable transactions.
A current partial week or month compares the same elapsed days in the preceding
period; missing earlier records show no comparison rather than invented zeroes.

Statement files enter through the import action on Records.
This opens a full review page rather than recognition: account
mapping, selected rows, possible duplicates, corrections and skipped-line reasons
stay on device through restart. Only confirmation posts selected entries, with
mapping rules saved together. The fixed footer shows the selected count; long
reviews reveal rows in batches of 50. A changed journal requires review again.

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
| All | Button press | Spring to 0.98 (cards and tiles 0.98, icon buttons 0.96), deeper fill; primary sheen clears and lift lowers | Fill and surface state only; no scale spring |
| Home | Tab chosen | The bar's pill slides to the tab (native spring) | Jumps |
| Today | Day's energy changes | Ring segments sweep to their new ends, `slower`; the figure eases to its new value | Set at once |
| Today | Meals arrive (open, save, undo) | Rows rise 14 pt and fade in, staggered | Shown at once |
| All | Toast | Slides up and fades, `slow`; its action (Undo) restores | Shown at once |
| Meal page | Scrolling | Photo drifts at half speed; the top bar frosts in once the panel slides under it | Bar switches at once |
| Meal page | Analyzing | The AI's light passes over the photo (2 s loop); placeholders shimmer | No light, no shimmer |
| Meal page | Results arrive | Rows rise in, staggered; the total eases up | Shown at once |
| Capture | A turn arrives | It rises 14 pt and fades in, staggered; while the model works its turn shows the spinner in the AI's light | Shown at once |
| Segmented | Choice | Raised pill slides to the segment (spring) | Jumps |
| Sheets | Open / close | Slide from the bottom over a fading scrim; swipe down to close | Appear / disappear |
| Toggles | Checkbox / switch | Fill `instant`; knob slides `fast` | Instant |

Numbers display their actual value on first appearance, including a delayed
initial load. Subsequent changes between present values ease over 180 ms;
they do not count from an invented zero.

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

Material review captures in `.impeccable/review/materials/` are GTK desktop
evidence of the opaque dock/sheet fallback, not proof of Android blur.
The current 0.80-opacity dock and revised label colors have calculated
text minima of 4.68:1 light / 4.83:1 dark over black and white backdrops.
Sheets now use the opaque surface text palette. Over a white photo, the media
mask gives 4.79:1 for secondary caption text and 6.38:1 for white text.
These calculations cover the specified material/text combinations only;
they do not establish whole-app accessibility or device performance.

Capture and settings refinement previews in
`.impeccable/review/capture-polish/` show the fitted composer, missing-account
review and collapsed settings in GTK, including light/dark and a narrow
360 × 640 capture review. These are desktop development captures; Android
keyboard, system Back, rendering and performance still need device evidence.

The November 15 refinement is captured in
`.impeccable/review/ui-polish-2026-11-15/`: Today, Records, Assets, Review,
capture and management in desktop light/dark and narrow viewports. Large-text
layout is additionally covered by headless flows with an explicit font-scale
environment; desktop captures do not prove Android blur or frame timing.


Historical financial data stays below the Assets overview. Asset changes uses
one two-option segmented control for Recalculated / Recorded, with a single
contextual action in each mode. Price history is a flat, paginated list under
Manage or a holding detail; OHLC, source and revisions expand inline. Retain
native currency beside security prices, show local observation times without
raw timestamp precision, and suppress empty status messages. Partial FX
observations never masquerade as complete net worth or closing-day values.

History review captures are in `.impeccable/review/history/`, including the
390 × 844 light and 360 × 640 dark price-history page, its corrections view,
and both Asset changes modes. Headless flows cover expansion, mode switching
and appending immutable observations. Desktop captures do not establish Android
native behavior, rendering performance or physical-device TLS behavior.
