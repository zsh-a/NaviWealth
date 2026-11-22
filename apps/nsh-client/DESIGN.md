# NaviWealth native client: design standards

The NSH (Rust) client's design system and the decisions behind it. Tokens
live in `src/ui/theme.rs`; every screen is composed from `src/ui/`. Product
rules come from `docs/product/product-scope.md`: personal use, local-first,
AI only to turn text and images into drafts, using the owner's model account.

## The task

- **Primary task:** describe or photograph a record, confirm the result, and
  see what today adds up to; each week, see what changed.
- **Home:** four tabs (Today · Records · Assets · Review) in a floating 62 pt
  liquid-glass bar (`src/pages/dock.rs`, after FlClash's prism_ui
  `NavigationDock`) beside one round 62 pt capture button of the same glass,
  its plus in the accent (`IconBtn`, `Variant::Dock`). Its accessible name
  is New entry / 新记录; it opens the shared text/image composer. The chosen
  tab rests on a soft accent platter with its filled glyph and label in the
  accent. A finger on the bar lifts the platter into a clear lens that grows,
  magnifies the glyph under it and follows the finger across the tabs;
  lifting after a drag onto another tab chooses that tab, while a tap is
  left to the tab's own press. Every tab stays a `Tab` of one `Tabs` list,
  so keyboard focus and screen readers work as for any tab list.
  Settings is the corner action on Today.
  Pages pushed over the home cover the bar. Hidden tabs stay alive (their
  scroll position stays) and are hidden from screen readers. Each tab scrolls
  in a viewport that ends above the dock and system inset.
- **Capture:** one bounded conversation
  ([Capture Conversation](../../docs/architecture/capture-conversation.md)). The
  description or photo is the thread's first message on the right on a neutral surface. Results and questions use the full
  content width. A turn carries the record summaries inline (the same readable
  cards as before), one to three clarifying questions as quiet wells, and —
  while an answer is still wanted — the question's tap-first options as
  chips of known accounts and categories. A turn that revised records
  collapses, once superseded, to an "Updated n records" line. While the
  model works the thread shows progress and read-only cards as complete records arrive; a failure is a turn with Try again, Open settings and Keep
  previous result. No domain selection before input and no prefilled form
  as the main result. Missing values ask a concrete question; proposed new
  accounts are marked. Multiple records show their count on confirmation.
  New model decisions use `ask_user`: each question shows whether an answer is needed and full-width choices. A reason or option
  description appears when it adds context to the choice.
  The question and its choices are grouped together, with answer controls pinned below.
  No choice is preselected. Tapping stages a choice with a check; tapping again
  clears it. Pending questions show a labelled Continue / 继续 button
  beneath the options. It enables when the required answers are valid. The composer
  accepts extra text or photos. Selection persists immediately, while
  the model is called only on submission. Historical decisions have no active
  choices and the owner turn records the submitted answers. Pending tools and
  failed continuations withhold confirmation until a final result arrives.
  Manual meal/money/weight actions are secondary under one disclosure;
  favorites remain directly available with Undo. Close is a labelled cross,
  separate from Confirm and save; Discard draft is a header action with
  Undo; closing a nonempty draft reports that the draft is kept.
  The first entry opens a compact writing surface under the title. After sending,
  the conversation uses the available height above the live keyboard. Earlier exchanges
  fold under Earlier messages. A composer-shaped pill (photo glyph and the muted
  label Add text or photos / 补充文字或图片) opens the reply surface on demand.
  In both appearances, a ready draft places the pill and a 48 pt high,
  content-width cobalt save button on one row. At widths below 360 pt or
  font scales above 1.2 the controls stack. The light button uses a short contact shadow when stacked.
  Both writing surfaces group a photo control, the input
  (labelled What would you like to record? / 想记下什么？) and, for ordinary messages, a round send
  button. Input starts at one line (48 pt), grows with its content up to
  120 pt, and keeps the 48 pt photo and send controls aligned at its bottom.
  An empty composer keeps its send button visible and disabled.
  The footer shows the task's current action:
  Recognize on the consent sheet, Review later while the model works,
  Set up without a model, and Confirm and save once the records are ready.
  The draft accepts up to four images across all turns. Unsent evidence appears
  as contained thumbnails with visible Remove image actions; sent thumbnails
  stay with their owner message. At the limit, attachment is disabled. Pending
  questions or unsent evidence withhold confirmation.
  Only a draft with no thread yet requests initial focus after the sheet
  opens; a ready result stays readable.
  In light appearance, review cards have a white surface, a 20 pt radius,
  a 0.5 pt ink edge at 15% opacity and a short contact shadow when editable. A recent
  correction briefly tints the edge cobalt. Ready cards can show field
  evidence and support individual removal in a batch.
  Suggested cash accounts carry a separate approval action. Local editing includes
  money amount, meal name and weight: the
  record's main figure is that control, marked with a muted pencil and named
  Edit amount / Edit meal / Edit weight. Edits persist in the draft and the
  final confirmation writes the batch.
  Account and category rows in a ready result open a picker in the same
  sheet, each with a trailing chevron; categories list the existing expense
  or income categories in the record's currency. Transfer source and destination lists exclude the other account;
  internal holding accounts are never offered. Selection first persists the
  draft, then returns to the result, without calling the model or posting a
  transaction. With no eligible account, the picker explains how to name a
  proposed account through the composer. Back returns from the account
  picker or recognition consent; the cross closes the capture task.
  A successful confirmation reports the single record's kind and value, or
  the batch count. Undo reverses the saved batch if its records still match. View opens the saved record directly. For multiple records it opens a dated, actionable list of just that batch. Back from any item returns to the list.
  Content shared from another app opens this sheet with the shared images
  staged as unsent evidence and the text in the composer; the owner sends it
  like any first message (consent included). It waits while a pushed page or
  home sheet covers the home, then opens, so nothing unsaved is closed. A
  shared statement opens the statement review at once, never replacing one in
  progress (a notice says so); anything else shows one notice.
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
  Capture uses a content-sized entry sheet, then expands to 92% of the window
  less the visible keyboard. Android Back dismisses the keyboard first. The management
  menu and compact account editor also fit their content. Other task
  editors retain `task_sheet`'s filled height, capped at 540 pt. The holding
  trade form uses the space above the visible keyboard for its fields and
  fixed cash preview. Its listing search and other text-first editors plan
  for the keyboard when they open (the last height it reached, else 38% of
  the window). The NSH sheet lifts the panel by the keyboard height above the
  bottom safe area. NSH 0.6.1 presents each sheet in a dialog window whose
  root Android already lays out above the keyboard, so the app measures that
  root and places the panel so its content meets the keyboard instead of
  floating a keyboard's height above it (`panel_bottom` in `src/ui/sheet.rs`,
  `tests/keyboard_sheet.rs`); hosts that do not shrink the root keep the lift. The panel, scroll area and actions keep their size until
  a keyboard exceeds the planned height. Toasts belong to the active sheet while
  it is open, so Undo cannot be covered by its backdrop. Opening capture clears
  old informational notices and saved receipts; Undo messages keep their normal
  lifetime. A receipt's View cannot navigate behind a newly opened draft.
- **Manual money:** amount, account/category (or from/to), a calendar date,
  optional details. Pickers replace the body in the same sheet; Back returns
  to the draft. Time, payee and note live in Details. Successful saves alone
  update remembered account/category choices. Existing records expose Delete
  in the fixed header, including when the simple editor cannot edit their
  postings. New entries have no Delete action. A confirmation names the saved
  record, date and account amounts; cancelling preserves the draft. Balance
  receipts expose Revoke in the same header position. Successful deletion
  offers Undo; temporary Undo failures keep a retry action, while identity or
  account changes are explained instead of overwriting newer data.
- **No hidden gestures.** Every action is a visible control; nothing
  depends on a long press.
- **Today shows today:** the page leads, flat on the canvas, with intake as
  the one Display figure, what is left of the goal, and an accent progress
  ring when a goal is set. The ring fills up to one
  turn and its center reports the actual percentage, including values above
  100%. Protein, carbohydrate and fat appear separately in grams. Once the
  ledger has any entry, a hairline separates Spent today / 今日支出 with the
  day's spending in each currency (a dash when nothing was spent). Before the
  first meal the figure is replaced by the sentence Nothing logged yet and a
  hint to use +, never a figure-sized dash. Flat beneath it, between hairlines, is a full-width Body metrics summary:
  three compact columns for weight, body fat and BMI. The seven-day trend
  stays beside the weight as a muted signed value (−0.5 kg · 7天), wrapping locally
  on narrow screens. The weight history chart lives in Review. Today’s
  measurement date is omitted visually; an older date
  shares the trend caption, while the accessible label always includes the date. For a saved measurement, the header’s
  Overview / 概览 control opens the same overview as the whole row. Large text
  stacks the columns.
  Missing facts use a dash. Composition belongs to that weight's day, never
  a newer or older reading. Extra composition, goal distance and original
  measurement details live in the overview; its manual editor shares one
  native sheet and returns to the overview. With no weight, the summary
  opens entry directly and shows only Log weight / 记录体重 as its action. Its accessible name includes that action. The editor confirms before discarding changes and keeps input available when a write fails. A reading panel uses the sheet's space; entry reserves
  the keyboard. Sleep and Body Battery occupy a separate equal-width row
  once Garmin is connected, stacking at large text (a Garmin vital opens all
  of the day's Garmin data). Then today's records, newest first, whose header carries the count
  ("3 条"). Spending rows read account then time ("Wallet · 16:30"); the sign
  and icon already say spending, so narrow rows truncate the time, not the
  account. Other kinds keep their label first, and every time follows the
  device's 12/24-hour setting. Opening balances and
  adjustments remain in the timeline with quieter labels and amounts; they
  are not spending. Groups are 24 pt apart, the records 32 pt below the
  vitals. Before any meals are logged, the glance omits the empty ring and macro
  legend. Model setup is a compact row below the daily content. Past days are
  in Records.
- **Drafts:** text/image inputs and recognition results are kept on device,
  pinned on Today and atop Records from one shared source. They can be left,
  reopened, corrected in a sentence, retried, confirmed or discarded with
  Undo. Confirmation consumes the draft and writes all its records together.
  A draft never contributes to totals. Recognized food nutrition remains an
  estimate, and unknown payment accounts are never silently guessed.
- **Records:** days appear newest first. The date and optional weight action
  head each group, followed by its recorded totals. Meals and money use the same
  flat timeline rows as Today. The filters cover all records, money, meals and
  weight. The timeline loads 21 days at a time. The calendar button
  opens a month calendar and shares the header with the statement import action.
  In All days, consecutive weight-only entries collapse into one light
  summary with the date span as its title and logged-day count plus oldest → newest
  weight as secondary text. The whole row is one accessible button, labelled
  Show daily records / 展开每日记录 with the full summary and a visible right
  chevron; its expanded state exposes Collapse with a downward chevron. Mixed days break runs, single days remain individual,
  and filters or a chosen day show individual entries. Day headers show spending
  only for currencies with expense records; opening balances, adjustments,
  income and transfers alone never create a zero-spending summary.
  A chosen day is shown alone, under a bar with its date, steps to adjacent
  days with records, and All days.
- **Assets:** net worth leads, flat on the canvas. Asset and debt totals sit together above
  a tappable trend footer with the sparkline and Asset changes link. Cash accounts, open holdings and debt accounts
  follow as flat rows on the canvas with a half-point divider beneath each row.
  The sparkline reuses dated valuation history and keeps missing-rate gaps;
  the line is the accent with a soft accent wash beneath it, and the latest valuation is dotted.
  The caption shows the 30-day change when records reach back that far, else
  the nonzero change from the first complete valuation, with its date.
  When either endpoint is missing, the caption gives the valuation basis.
  With holdings, values use dated native-currency prices, falling back to cost
  when unpriced; without holdings, the basis is book balances. CNY, HKD and
  USD accounts and holdings retain their original amounts. The overview converts
  to CNY using the latest rate on or before its date. When rates are missing,
  the headline and subtotals identify the included amounts. Tapping an excluded
  currency opens its rate and identifies the affected accounts and holdings.
  Asset changes marks the affected dates and gaps in the historical chart.
  Its valuation basis expands on demand. The change breakdown uses Review’s
  attribution over the interval from the chart’s first point to the inspected day.
  Each holding keeps its manual price date or cost-fallback label. Unchecked
  accounts keep a visible label; ordinary last-check dates live in account
  details and remain in the row's accessible description. Internal holding
  cost accounts stay out of the account list. Manage opens one bottom sheet
  with Add account, Add holding, Prices & rates and Closed holdings. No accounts or holdings
  shows a short empty state with Add account as the main action and Add holding
  as a quiet alternative. The global text/image capture button remains the
  main record entry.
- **Holdings:** flat overview rows show name, value and price status; quantity
  and average unit cost live in details. Closed positions remain accessible
  through Manage → Closed holdings, with their history and trade actions;
  buying again returns a position to the overview automatically. A row opens
  a detail page with value, the price source, quantity, cost, unrealized
  gain, and newest-first activity. The valuation leads the page with Record trade and
  the full native amount. An unpriced open holding labels its cost fallback.
  A linked market and code opens the listing picker; an unlinked position
  shows Link code. Price history and the latest quote source sit beside the
  unit-price chart, with manual pricing available for unlinked open positions.
  At large text sizes the price actions stack. Unrealized gain shows its signed
  amount and one-decimal percentage of cost when the cost is positive. Realized gain and dividends
  appear when nonzero; unpriced unrealized gain is a dash. Opening a holding
  needs name, quantity and unit cost. Buy/sell use quantity, price and a cash
  account. Dividends use amount and a cash account. The fixed footer shows the
  account’s net debit or credit including fees above Save. Price history opens
  on the source of the displayed price. Optional fees and date
  sit under Details. Date and cash pickers replace the same sheet body;
  Back preserves the draft. Unsaved trade input has a discard guard. Prices
  have their own compact amount-and-date sheet. Activity opens a receipt
  with an explicit, confirmed remove action.
- **Own accounts:** creation leads with the name and compact type/currency
  choices; the balance can be checked later. Creation stays on Assets and
  offers Check balance in the confirmation notice. Account rows open the
  book balance or debt, latest check status and newest-first activity.
  Expanding the last check shows dated observations, including matches.
  Each adjustment opens its original posting. Show earlier pages through
  history. The pencil action renames the account.
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
  month. The compact period selector sits at the right of the title and wraps below it when large text needs the space. The dated stepper follows.
  The headline (Title, a step above section headers) shows one observed change, preferring the period’s weight change
  and falling back to intake per logged day when both periods have entries. Partial periods compare matching elapsed days;
  missing observations never imply a zero or an invented comparison.
  Next comes the intake section: a bar per day for a week, every day on a faint
  full-height track, with a labelled dashed goal line and labelled empty
  columns (track only) for days without meals, a calendar for a month
  (shaded by share of the goal, amber past it, a dot on weighed days, today
  outlined; a day opens in Records; today's bar is the accent). Coverage sits directly beneath intake per logged day. The monthly caption
  includes the goal, which the weekly chart labels on its reference line.
  Spending, the net-worth change and weight follow, then the
  Garmin averages and a one-line note. The Week / Month switch keeps the same
  labels while browsing history. Same-month date spans share the month.
  The note accepts up to 280 characters and shows a counter for the final 20.
  A failed autosave keeps the input available with a retry action.
  A ledger-only period without weight or
  intake comparisons leads with its net-worth change instead. An empty intake section shows a short message.
  Each Review part is a flat `section` (a hairline above, its title and
  figures at the page gutter), not a card.
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
  Compare methods reveals the scope and calibration notes for all three options.
  Body profile presents three exclusive algorithm rows below the profile,
  each with its scope and limitations. Segal remains the default; Wu 2015 and
  Sun 2003 always carry Experimental. The scale sheet keeps the chosen model
  visible in a compact disclosure; choosing before connection changes the
  default, choosing during review updates only the draft. Successful selection
  folds the list to expose the new readings. Saving and dismissing are locked
  during recalculation; late results cannot replace newer evidence. Unsupported
  inputs explain why composition is unavailable and offer a model switch or
  weight-only saving. Saved body metrics show their own model; body-fat charts
  never join observations from different algorithms.
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
  Measurement results keep a dated, quiet status above a weight row with
  tabular figures and quieter decimals/unit. Completion retires the stage
  tracks and the connection prompt. Body fat and BMI form the first pair;
  muscle and water form the second, divided by a hairline on the same surface.
  Each composition share carries its mass from the same frozen Rust summary
  as smaller secondary text. Large text stacks the pairs, and compact phones
  use a smaller weight figure. The details row has a rotating chevron and
  reveals device/date and provenance on request. No decorative scores,
  reference-range bars or fabricated comparisons are added.
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
  The shared `size::TOUCH` is 48 pt; icon controls, compact-button hit areas
  disclosures and segmented choices keep that minimum. All touch actions are at least 48 pt. Backup & restore shows automatic backup status
  and the last outcome. Its page leads with the passphrase every backup uses,
  then Backup file (Include meal photos, Export backup file as the primary
  action, Restore from file… beside it, Last exported), then the WebDAV
  folder and WebDAV backups. A missing passphrase is said before any sheet
  or picker opens; a dismissed share sheet says nothing. About displays the installed version before opening
  update details. A changed model account requires consent again before
  sending text, images and account names.

Missing records never read as zero: an empty day shows "—" and "Nothing
logged yet", never 0 kcal; a day without meals has no filled bar and no shade.

## Visual language: 精密仪表 · Instrument

One plane, one accent, numbers first. A quiet near-white canvas (near-black
in dark), content grouped by space and hairlines rather than lifted cards,
and a single cobalt accent reserved for the one action of a screen and for
"now": the chosen tab, today's bar, the latest point of a trend and the
progress toward today's goal. Data never takes decorative color; the
macronutrients are three steps of the accent ramp. Amber is reserved past a
goal or for estimates to check, red for destructive actions, green for a
passed connection. Dark is a near-black canvas whose surfaces separate by
tone and a hairline.

| Role | Tokens |
|---|---|
| Surfaces | `CANVAS`, `SURFACE`, `SURFACE_2` (wells), `SUNKEN` (fields, tracks), `LINE`, `LINE_STRONG` |
| Text | `INK` (titles, figures), `BODY`, `MUTED` |
| Decorative / inactive | `FAINT` (tertiary marks such as chevrons, disabled controls and unavailable dates) |
| Accent | `ACCENT` (fills, chart lines, the goal ring), `ACCENT_INK` (accent text and glyphs, on the platter too), `ACCENT_SOFT` (the chosen tab's platter, selected chips) |
| Action | `ACTION` (the accent), `ACTION_PRESSED`, `ACTION_SHEEN`, `ON_ACTION` |
| Floating material | `GLASS` (the dock's tint), `ON_GLASS_MUTED` (dock labels), `GLASS_EDGE` |
| Status | `DANGER(_SOFT)`, `CAUTION(_SOFT)` (past a goal, estimates to check), `POSITIVE` |
| Data | `PROTEIN` / `CARBS` / `FAT` (the accent at 100 / ~55 / ~26%), `TRACK`, `HEAT` (calendar shade) |
| Media | `ON_MEDIA`, `MEDIA_SCRIM`, `PHOTO_WELL` |

Core palette from `src/ui/theme.rs`; each adaptive token switches with the
chosen or system appearance.

| Token | Light | Dark |
|---|---|---|
| `CANVAS` | `#FAFAF8` | `#0B0B0C` |
| `SURFACE` | `#FFFFFF` | `#151517` |
| `SURFACE_2` | `#F3F3F0` | `#1C1C1F` |
| `SUNKEN` / `TRACK` | `#EDEDEA` | `#19191C` |
| `LINE` | `#E6E6E2` | `#26262A` |
| `LINE_STRONG` | `#D1D1CC` | `#3C3C41` |
| `INK` | `#111113` | `#F2F2F0` |
| `BODY` | `#2B2B2F` | `#D8D8D5` |
| `MUTED` | `#6B6B70` | `#96969B` |
| `FAINT` | `#A1A1A6` | `#5A5A5F` |
| `ACCENT` / `ACTION` | `#2F5BEA` | `#7C9BFF` |
| `ACCENT_INK` | `#2448C8` | `#9FB5FF` |
| `ACCENT_SOFT` | `#E1E6FB` | `#1B2140` |
| `ACTION_PRESSED` | `#2449C9` | `#6A88F0` |
| `ACTION_SHEEN` | `#4A73F5` | `#93AEFF` |
| `ON_ACTION` | `#FFFFFF` | `#0B0B0C` |
| `GLASS` | `#F6F6F4` | `#222226` |
| `ON_GLASS_MUTED` | `#45454A` | `#B8B8BD` |
| `DANGER` / `DANGER_SOFT` | `#B0262F` / `#FCEBEB` | `#FF6369` / `#3A1618` |
| `CAUTION` / `CAUTION_SOFT` | `#8A5810` / `#FFF3DA` | `#FFC046` / `#372809` |
| `POSITIVE` | `#1F7350` | `#4CC38A` |
| `CARBS` / `FAT` / `HEAT` | `#8AA3F0` / `#C5D1F4` / `#9FB3F2` | `#495A92` / `#2E375A` / `#3E4E85` |

Use `MUTED` for readable secondary copy, labels, placeholders, missing-value
dashes, macro percentages and past dates without records. Reserve `FAINT`
for decorative marks and inactive states, including disabled controls and
future dates without records; it is outside the text contrast checks below.
Status color conveys meaning: `DANGER` for errors and destructive actions,
`CAUTION` for estimates to check or a goal exceeded, and `POSITIVE` for a
completed connection. Soft status fills hold their matching foreground.
Financial values, including gains and losses, stay in neutral ink; the accent
never marks a gain.

- **Type** (`Type`): Display 52/58 300 (the page's one headline number),
  Lead 34/40 300 (a section's or record's lead figure: spending, the
  net-worth change, a record's amount, a chart readout, the amount being
  entered), LargeTitle 30/36 600 (page titles), Title 20/600 (sheet titles,
  empty states), Figure 22/28 400 (figures among others), Headline 16/22 600
  (rows and section headers), Body 15.5, Callout 14.5, Subhead 13, Caption
  12; tabular numerals everywhere numbers move. Large numbers are light and
  small labels medium, so the figures lead without shouting.
- **Numbers:** every standalone number is a `stat`: the whole part in ink,
  decimals one step quieter, the unit muted on the same baseline, a
  dash and no unit without a value. `Scale::Hero` (Display) is the one
  headline number of a page; `Scale::Section` (Lead) leads a section;
  `Scale::Tile` (Figure) sits among others. Assets uses its own exact money
  renderer: net worth follows the same baseline hierarchy, while other
  financial amounts keep a single text style.
- **Sections and cards:** headline figures and groups of figures lie flat on
  the canvas. `section` divides a page's parts with a hairline above and
  keeps the title and figures at the page gutter (Review's parts); Today's
  body metrics sit between hairlines. Assets, the Today and Records timelines,
  and a meal's food list lie directly on the canvas. Grouped settings and framed
  tools use an opaque surface with a 0.5 pt hairline edge. Pending drafts have a short contact shadow.
  Cards never nest.
- **Rows** for meals and money share a 28 pt icon column. A group with any meal
  photo reserves 52 pt for every leading cell. Transfers use the source and
  destination as the title, with the transfer label and time below. A meal without
  a photo uses the semantic food icon; financial rows use their semantic
  icon (Check for opening balances and adjustments; Sliders stays Settings).
  Footprint icons are 20 pt and muted so the column aligns without reading
  as a column of icons. Timeline dividers start at the following row's title
  and run to the page gutter. Amount
  and currency share a baseline,
  with a stacked layout for large text or long exact amounts. Asset rows use
  existing semantic icons: Wallet for cash accounts, CreditCard for debt accounts
  and Chart for holdings, without inferring account subtypes from names.
- **Shape:** controls are pills; sheet 28 > card 20 > well 14 > field 12 >
  thumbnail 12 > badge 6, concentric where they nest. Cards and sheet top
  corners use continuous curves.
- **Depth:** only what floats casts a shadow (the dock, its capture button
  and lifted lens, raised buttons); content separates by tone and hairlines.
  Dark uses tone and edges without shadows.
- **Spacing:** the 4 pt scale; page gutter 20, card inset 18, hairlines 0.5 pt.

## App mark: Folio · 页间

The app mark is two turning pages with a parallel diagonal channel,
drawn as two filled paths in [`brand/folio.svg`](brand/folio.svg). It keeps
the Ink & Daylight ink `#1C1D1A` and warm canvas `#F4F3EF`; recoloring the
mark for Instrument is a separate change that regenerates the icon. The open space
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
| Dock and its capture button | `GLASS` at 0.84 opacity, 24 pt backdrop blur | 0.75 pt `GLASS_EDGE` around the pill | `shadow::FLOAT` |
| Dock lens (while a finger is down) | `SURFACE` at 0.46 over the glass, replacing the `ACCENT_SOFT` platter | 0.75 pt `GLASS_EDGE` | `shadow::LENS` |
| Sheet | Opaque `SURFACE`, no backdrop blur or highlight wash | Shared modal scrim at 30% in light, 55% in dark | None: a large blurred shadow is costly to redraw while the sheet moves with the keyboard |
| Media controls and captions | `MEDIA_SCRIM` at 0.64 opacity, 18 pt backdrop blur; pressed buttons use 0.74 opacity | White `ON_MEDIA`; caption secondary text at 0.8 opacity | No additional shadow |

The glass edge is white at `#C8` alpha in light appearance and `#1F`
in dark. No canvas-colored fade covers the content beneath the dock;
scroll clearance still lets the final row move fully above it.
Inactive dock labels use `ON_GLASS_MUTED` (`#45454A` light / `#B8B8BD` dark)
for legibility through the tint. The chosen tab rests on an opaque
`ACCENT_SOFT` platter with its filled glyph and label in `ACCENT_INK`; the
accent follows the lens, so whatever it covers while the finger moves takes
the color. The refraction of FlClash's Liquid Glass (a backdrop shader) is
deliberately absent: on Android a backdrop shader pictures the window before
every frame, which a dock that is always visible cannot afford without
device evidence. Media readability comes from the dark mask
even when backdrop blur is unavailable.

The dock falls back to fully opaque `GLASS`, with no
backdrop filter, on Linux and Android below API 31. Android API 31 and above takes the blur
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
| `CONTACT` | `(0, 1, 2, 0, #1111130A)` | Pending drafts, small raised controls and pressed primary buttons |
| `ACTION` | `CONTACT` and `(0, 5, 10, -4, #2F5BEA38)` | Cobalt actions and compact capture confirmation |
| `FLOAT` | `CONTACT` and `(0, 8, 18, -6, #1111131A)` | Dock, floating capture button, pickers and transient notices |
| `LENS` | `(0, 6, 16, -6, #1111131A)` | Dock lens while following a press |

## Components (`src/ui/`)

`Btn` (primary accent with sheen / tonal / secondary raised / ghost /
danger / glass / dock; three pill sizes), `IconBtn` (circles of the same
variants), `chip` (selected: `ACCENT_SOFT` with `ACCENT_INK`),
`card`, `section`, `row_button`, `hairline`, `section_header`, `group_label`,
`disclosure`, `segmented`, fields (visible labels and placeholders in
`MUTED`, ink focus edge),
`checkbox_row` / `switch_row`, `bottom_sheet`, toast (ink pill with one
action, usually Undo), `spinner`, `shimmer` + `skeleton`, `badge`,
`empty_state`, `appear`, `stat` with `counted` (a figure easing to its new
value), `macro_tiles`, the energy `ring` (an accent arc), and one icon
family (24 pt line glyphs, plus four filled tab glyphs for the dock). Exclusive
choices in page headers, filters and forms use accent text and a sliding 2 pt
underline. Tabs keep 48 pt minimum touch heights and labels can wrap. New
account forms label the account type and currency separately. Compact choices
such as food portions and chart ranges use an accent fill on the current value.
Portion shortcuts wrap in groups of three when space is tight. Pushed pages
use ghost toolbar actions and a centered title. Meal controls use glass over a photo.
The month calendar (`pages/review_calendar.rs`) serves Review's month and
the go-to-day sheet in Records.

Button feedback is restrained: buttons and chips press to 98%, icon buttons
to 96%. Primary buttons lose their sheen and settle to `shadow::CONTACT`
while pressed. The shared primary button and primary icon button each emit
one light impact on activation, as does the dock's capture button
(`Variant::Dock`); the home capture action adds no second haptic. Reduced motion keeps scale at 1 without starting the press spring.
Sheets retain `nsh_base`'s entrance, backdrop, back/Escape and swipe-down
behavior; the material layer adds no custom transition.

Assets leads with its overview flat on the canvas, not in a card. Net worth
aligns an ink whole amount (`Type::Display`, light), muted currency
(`Type::Figure`) and muted decimals (`Type::Figure`) on one baseline, exposed
as one accessible
element labelled with the full exact amount. The two subordinate totals use
`Type::Body` values with muted caption labels. Holding and account rows stay
flat, separated by space without hairlines, with muted 22 pt semantic icons
and their existing valuation statuses. Activity rows retain hairlines.
Asset changes carries the trend on a separate pushed page:
a single ink line with a soft area fill and a dated value above it. Holding unit prices,
FX pairs, estimated net worth and saved snapshots share that inspection surface.
Touch or drag horizontally to inspect an observation. Mouse, keyboard and screen-reader
stepping update the same readout. The seven- and thirty-day windows include
today and the preceding six or twenty-nine calendar days. Older records unlock
All. The plotted axis starts at the window's first observation, so a short
history fills the plot; axis ends and dates read as local short dates
(Oct 23 / 10月23日), adding the year only when the ends span years.
An empty recent window shows the latest available observation date. History fills automatically while the app is active. A missing FX rate or valuation error breaks the line. Isolated valid days get a dot. The chart lists missing currencies and affected dates in the displayed window. Money keeps
tabular numerals and neutral ink, including gains and losses. Overview
amounts and primary balance/value figures use grouped thousands and two
decimal places through a display-only formatter that preserves exact minor
units and editable input. Every financial display uses the shared exact currency formatter: CNY has
a ¥ prefix, HKD/USD retain their code, with grouped thousands and two decimals.
Signs precede the currency (−¥68.00, +USD 100.00); accessible names use the
same amounts. Editors retain ungrouped decimal input. Cost and gain figures
come from the domain calculation. Quantity, average
unit cost and unit price retain up to six decimal places.

Holding creation offers offline code/name/pinyin search before quantity and
unit cost, with manual naming still available. Search replaces the body of
the same task sheet at a stable height and shows market,
code and currency; unsupported currencies and instrument types are visibly
unavailable. Existing holdings require a separate link confirmation: catalog
identity never replaces the holding's internal id, label, account or trades.
Results settle after 120 ms and grow in batches of 16. The search footer
offers a compact secondary manual-entry action with a 48 pt touch target. The catalog keeps a
normalized search index; decoding and verification of downloaded updates run
off the engine thread before a short atomic installation. Stale refreshes
cannot replace a newly loaded catalog. The bundled GitHub Releases catalog
checks when the picker opens. Successful checks are cached for 24 hours. A failed
check is retried after five minutes while the picker is in use.
Mainland China, Hong Kong and US stocks and ETFs can be linked in their
CNY, HKD and USD trading currencies. Manual creation offers compact currency
choices; catalog selection sets currency automatically. Existing holdings keep
their currency, and trade cash choices include only matching asset accounts.

A disclosure beside the net worth label counts included holdings valued at cost
and opens links to those positions. Checked accounts keep their last check
date in details and the spoken row label. Account and holding rows stack the
native amount below the name on narrow screens, at large text sizes or for long amounts.
Historical estimates and net worth snapshots are separate views.

Assets displays the last stored observations immediately. The holding price date
identifies the quote used for valuation. Foreground updates fetch newly needed
symbols and currencies, with a five-minute throttle per item. Holding price captions distinguish manual input, Tencent observations,
previous close and earlier dates. A manual mark wins on the same or a newer
date; a failed network request keeps the last dated mark. Unpriced holdings
remain visibly valued at cost. The Rates tab in Prices & rates shows dated HKD/CNY and USD/CNY
observations with their dates and sources. Manual rates take precedence over
network rates on the same day; no rate is applied before its recorded date.
Cross-currency transfers require separate sent and received amounts and preserve
both native values. Schema 14 backs up rates with the ledger. Other currencies,
crypto and allocation remain outside this increment. Android
TLS and physical-device behavior remain unverified.
Account, holding and price editors reuse `task_sheet` and the existing
calendar picker, with actions fixed above the keyboard. Quantity and unit
cost/price share one row; secondary trade details remain collapsed initially.

Review calls the money panel “Recorded spending”: its total reflects confirmed
journal entries, with the three largest expense categories initially visible.
The total and category rows open the corresponding editable transactions.
Comparison or missing-comparison copy is a caption below the total. Each
category row has a thin stone share track, calculated only for a positive
net total and clamped to the available width; refunds keep their signed exact
amount and have no positive share fill.
A current partial week or month compares the same elapsed days in the preceding
period; missing earlier records show no comparison rather than invented zeroes.

The “Net worth change” section follows it: the signed CNY change as the
section's figure (Lead, neutral ink), then a caption naming the close it starts
from with both values (`11月15日 周日收盘 ¥55,320.20 → ¥55,433.20`). Below are
only the nonzero parts in a fixed order — income, spending, investments,
opening balances, balance corrections, exchange rates — each a label with a
signed amount in one right-aligned column. Investments expand per holding and
the two correction parts list their entries; those rows are visible
disclosures with a rotating chevron, and an entry opens its editor or balance
summary. A caption says recorded amounts convert at opening rates and that
openings and corrections are bookkeeping, not gains. A missing rate replaces
the figure and parts with one sentence naming the currencies; no partial split
is shown. Without a ledger the card is absent.

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

Tokens: instant 120 ms, fast 180, slow 380; settle
curve `cubic-bezier(0.22, 1, 0.36, 1)`; press spring (600 / 38); rise 14 pt;
stagger 50 ms (8 at most). Reduced motion: every item below is instant or
still.

| Screen | Change | Motion | Reduced motion |
|---|---|---|---|
| All | Button press | Spring to 0.98 (cards and tiles 0.98, icon buttons 0.96), deeper fill; primary sheen clears and lift lowers | Fill and surface state only; no scale spring |
| Home | Tab chosen | The platter travels to the tab (400 ms spring, ζ 0.85), stretching along its travel (9% per tab, at most 18%, flattening 1.4×) and wobbling back on an underdamped jelly spring (k 100, ζ 0.4) | Jumps; no stretch |
| Home | Finger on the dock | The platter lifts into a lens (×1.14, a 250 ms critically damped spring), the glyph under it magnifies ×1.12, and the lens follows the finger | No lift or magnification; the tint still follows the finger |
| Today | Day's energy changes | The goal arc moves to its new endpoint in 180 ms; the figure eases to its new value | Set at once |
| All | Toast | Slides up and fades, `slow`; its action (Undo) restores | Shown at once |
| Meal page | Scrolling | Photo drifts at half speed; the top bar frosts in once the panel slides under it | Bar switches at once |
| Meal page | Analyzing | A spinner accompanies the status caption | Static status caption |
| Meal page | Results arrive | Rows rise in, staggered; the total eases up | Shown at once |
| Capture | Model output arrives | Newly parsed cards rise 14 pt. The reviewed figure lifts 4 pt and fades in on its first value and after a change. The actual amount is visible throughout. | Cards and figures appear at their final positions |
| Capture | Batch saved | After the sheet exits, compact copies fly from the reviewed rows to the dock over 380 ms. Spending and income land on Records. Today’s meals and weights land on Today, earlier ones on Records. Transfers, trades, balance checks and manual prices land on Assets. Notes land on Review. The receipt and Undo are available immediately. | Only the actionable receipt appears |
| Segmented | Choice | The short underline slides to the selected label | Jumps |
| Sheets | Open / close | Slide from the bottom over a fading scrim; swipe down to close | Appear / disappear |
| Toggles | Checkbox / switch | Fill `instant`; knob slides `fast` | Instant |

Capture emits one selection haptic for the first model card in an open draft and one when the owner accepts a proposed funding account. A successful database commit emits one success haptic. The flight is decorative and lets all touches pass through to the receipt and dock.

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

The November 22 Instrument palette audit included the since-retired raised
segment surface. It replaced Ink & Daylight. Calculated from
the source tokens in `src/ui/theme.rs` with the WCAG 2 formula, 90
text/background pairs across both appearances are all at least 4.5:1: `INK`,
`BODY`, `MUTED`, `ACCENT_INK` and the three status colors on `CANVAS`,
`SURFACE`, `SURFACE_2`, `SUNKEN` and `RAISED`; `ON_ACTION` on `ACTION`;
`ACCENT_INK` on `ACCENT_SOFT`; status colors on their soft fills; and dock
text on 0.84 `GLASS` over black and white backdrops. The minimum is light
`MUTED` on `SUNKEN` (4.52:1); light status minima are `POSITIVE` (4.94:1),
`CAUTION` (5.14:1) and `DANGER` (5.66:1), all on `SUNKEN`; the dark minimum
is `ACCENT_INK` on the dock glass over white (4.78:1). This covers those
token pairs, not whole-app WCAG conformance. The four tabs in light and dark
are captured in `.impeccable/review/instrument/`; they are GTK desktop
development evidence only (the desktop dock is the opaque fallback);
Android blur, the lens's touch tracking and frame timing still need device
evidence.

The earlier warm neutral palette refinement (Ink & Daylight) is captured in
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
Those captures predate Instrument. The current 0.84-opacity `GLASS` dock has
calculated text minima of 4.75:1 light (`ACCENT_INK`) / 4.78:1 dark
(`ACCENT_INK`) over black and white backdrops; inactive labels reach 6.11:1
light / 4.83:1 dark.
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
one two-option segmented control for Historical estimates / Net worth snapshots.
Both views update automatically. Manage opens Prices & rates with Rates, Daily closes
and Changes tabs. A holding opens directly to its own Daily closes and Changes.
The history lists are paginated, with OHLC, source and revisions expanding inline. Retain
native currency beside security prices, show local observation times without
raw timestamp precision, and suppress empty status messages. Partial FX
observations never masquerade as complete net worth or closing-day values.

History review captures are in `.impeccable/review/history/`, including the
390 × 844 light and 360 × 640 dark price-history page, its corrections view,
and both Asset changes modes. Headless flows cover expansion, mode switching
and appending immutable observations. Desktop captures do not establish Android
native behavior, rendering performance or physical-device TLS behavior.

Home corner actions have localized accessible names and 48 pt touch targets.
Settings uses Sliders and Records uses Import (a page with an inward arrow,
so it never reads as download) beside Calendar. A holding's price history
action is labelled Price history / 价格记录. Assets has a
visible Manage text button. Settings rows use semantic members of the same 24 pt, 1.8 pt
line family: Profile for body profile, Target for daily energy goal, Scale for
goal weight and scale hardware, Watch for Garmin, Server for recognition and
CloudLock for encrypted backups. Icons share the same round strokes. Financial signs never change ink color.

Weight and body-fat plots use the accent and its 55% step, with the latest
point marked by a dot. Their fixed readout above the line uses the same selection
and accessible description as asset charts. Each chart expands in place, keeping
the selected day. Weight retains its goal line in range and body-fat curves stay
separate by estimation algorithm. Full plots support scrubbing;
mini sparklines pass touches through. Plot motion is unset (instant), and
skeleton shimmer uses a native indefinite loop, stopped when its scope closes,
and rests when reduced motion is enabled.
