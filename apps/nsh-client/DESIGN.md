# NaviWealth native client: design standards

The NSH (Rust) client's design system and the decisions behind it. Tokens
live in `src/ui/theme.rs`; every screen is composed from `src/ui/`. Product
rules come from `docs/product/product-scope.md`: personal use, local-first,
AI only to turn a photo into a draft, the owner's own model account.

## The task

- **Primary task:** log a meal from a photo and see what today adds up to;
  each week, see what changed.
- **Home:** three tabs (Today · Records · Review) in a floating glass bar
  beside one ink capture button. Settings is the corner action on Today.
  Pages pushed over the home cover the bar. Hidden tabs stay alive (their
  scroll position stays) and are hidden from screen readers.
- **Capture sheet (the one way to record):** Log a meal (the system picker
  also takes photos) and Log weight as two large actions, favorites as a
  row of photo tiles, and Add manually. A tap on a favorite logs it today
  with Undo; the logged meal is adjusted like any other meal, from Today.
  Edit beside Favorites marks each tile for removal (with Undo). A saved
  meal's bookmark saves or removes it as a favorite.
- **No hidden gestures.** Every action is a visible control; nothing
  depends on a long press.
- **Today shows today:** the intake card (figure, what is left of the goal,
  the macro ring) and, laid flat beneath it, the vitals: weight, plus sleep
  and Body Battery once Garmin is connected (a Garmin vital opens all of the
  day's Garmin data). Then today's meals. Past days are in Records.
- **Drafts:** a sent photo becomes a draft; leaving the meal page never
  loses it. Drafts are edged in the AI's light, pinned on Today and atop
  Records: being read (shimmer), ready (Confirm), no food found or failed.
- **Records:** every day newest first, its header on one line (date, the
  day's kcal, a weight chip that opens the weight editor), its meals as rows
  of one card; all / meals / weight; 21 days at a time. The calendar button
  opens a month calendar to go to any day with records.
- **Review:** a calendar week (Monday first in Chinese and ISO locales) or
  month, stepped back with a labelled stepper. It leads with one sentence of
  what changed (daily average against the period before, weight trend),
  then the intake card: a bar per day for a week, a calendar for a month
  (shaded by share of the goal, amber past it, a dot on weighed days, today
  outlined; a day opens in Records). Then the one-line note, the weight with
  its 7-day trend line, and Garmin averages.
- **Settings keep every change as it is made; there is no Save.** The vision
  model has its own page; the goal, asking before each photo, Garmin and
  backups sit on the Settings page. A changed model account is asked about
  again before a photo goes to it.

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
| Text | `INK` (titles, figures), `BODY`, `MUTED`, `FAINT` |
| Action | `ACTION` (ink), `ACTION_PRESSED`, `ACTION_SHEEN`, `ON_ACTION` |
| AI | `AI_FROM` → `AI_TO` (analysis light, estimate marks) |
| Status | `DANGER(_SOFT)`, `CAUTION(_SOFT)` (past a goal, estimates to check), `POSITIVE` |
| Data | `PROTEIN` / `CARBS` / `FAT` (dark / middle / light stone), `OTHER`, `TRACK`, `HEAT` (calendar shade) |
| Media | `ON_MEDIA`, `MEDIA_SCRIM`, `PHOTO_WELL` |

- **Type** (`Type`): Display 44, LargeTitle 34, Title 22, Figure 20,
  Headline 17, Body 16, Callout 15, Subhead 14, Caption 12.5; tabular
  numerals everywhere numbers move.
- **Numbers:** every standalone number is a `stat`: the whole part in ink,
  decimals one step quieter, the unit muted on the same baseline, a faint
  dash and no unit without a value. `Scale::Hero` (Display) is the one
  headline number of a card; `Scale::Tile` (Figure) sits among others.
- **Cards** hold the one main figure of a screen (Today's intake, Review's
  intake), repeated rows, sheets and framed tools. Secondary figures (vitals,
  Review's weight and Garmin averages) lie flat on the canvas, grouped by
  hairlines and space. Cards never nest.
- **Rows** lead with the meal's photo when it has one; otherwise the text
  starts at the card's inset. No placeholder art.
- **Shape:** controls are pills; sheet 32 > card 24 > well 18 > field 16 >
  thumbnail 16 > badge 8.
- **Depth:** `shadow::CARD` under cards, `shadow::FLOAT` under the main
  action and raised buttons; none in dark. Glass only for controls over
  photos and the tab bar.
- **Spacing:** the 4 pt scale; page gutter 20, card inset 20.

## Components (`src/ui/`)

`Btn` (primary ink with sheen / tonal / secondary raised / ghost / danger /
glass; three pill sizes), `IconBtn` (circles of the same variants), `chip`,
`card`, `row_button`, `hairline`, `section_header`, `group_label`,
`disclosure`, `segmented`, fields (labelled inputs, ink focus edge),
`checkbox_row` / `switch_row`, `bottom_sheet`, toast (ink pill with one
action, usually Undo), `spinner`, `shimmer` + `skeleton`, `badge`,
`empty_state`, `appear`, `stat` with `counted` (a figure easing to its new
value), `macro_tiles`, the energy `ring`, and one icon family (24 pt line
glyphs). Pages share one top bar: a raised round Back and the title
centered. Screens: the month calendar (`pages/review_calendar.rs`) serves
Review's month and Records' go-to-day sheet.

## Platform decisions

- Pages hide the system header and draw their own top bar; the system back
  gesture still pops natively, and the meal page's `pop_on_back` guards an
  unsaved meal.
- The meal page's photo runs under the status bar.
- Photos come only from the system photo picker (it also takes photos).
  Every pick becomes an upright JPEG of at most 1280 px, which drops
  EXIF/GPS.
- Requests go through NSH's `fetch`, straight to the account's base URL.
- Before a photo leaves the device, a sheet names the server and model it
  goes to. "Don't ask again" is remembered per account fingerprint.
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
| Records | Go to a day | The list scrolls to the day (animated reveal) | Jumps |
| Meal page | Scrolling | Photo drifts at half speed; the top bar frosts in once the panel slides under it | Bar switches at once |
| Meal page | Analyzing | The AI's light passes over the photo (2 s loop); placeholders shimmer | No light, no shimmer |
| Meal page | Results arrive | Rows rise in, staggered; the total eases up | Shown at once |
| Segmented | Choice | Raised pill slides to the segment (spring) | Jumps |
| Sheets | Open / close | Slide from the bottom over a fading scrim; swipe down to close | Appear / disappear |
| Toggles | Checkbox / switch | Fill `instant`; knob slides `fast` | Instant |

Verified on the GTK desktop build with the previews in `src/preview.rs`;
Android verification happens on the device build.
