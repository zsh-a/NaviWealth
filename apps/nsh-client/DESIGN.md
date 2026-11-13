# NaviWealth native client: design standards

The NSH (Rust) client's design system and the decisions behind its first
page, HealthOS meal logging. Tokens live in `src/ui/theme.rs`; every screen is
composed from `src/ui/`. Product rules come from the repository's
`docs/domains/healthos-domain.md` and the shell contract: local-first, device
AI only, the user's own model account, no relay.

## The task

- **Primary task:** log a meal from a photo and see what today adds up to.
- **Objects:** a meal (foods with eaten grams and per-100 g nutrients, a slot,
  a photo kept only on the device) and a day (its meals and their total).
- **Home:** three tabs (Today · Records · Review) in a floating glass bar
  beside one ink capture button; Settings is the corner action on Today.
  Pages pushed over the home cover the bar. Hidden tabs stay alive (their
  scroll position stays) and are hidden from screen readers.
- **Capture sheet (the one way to record):** Log a meal (the system photo
  picker also takes photos) and Log weight as two large actions, favorites
  as a row of photo tiles (tap logs today with Undo; hold offers Adjust,
  then log / Remove), and Add manually. A saved meal's bookmark saves or
  removes it as a favorite.
- **Today shows today:** the intake glance (figure, what is left of the
  goal, a compact macro ring), three vitals (sleep, weight, Body Battery
  with resting heart rate; a Garmin vital opens all of the day's Garmin
  data), and today's records. Past days are in Records; a meal is moved to
  another day with the date chip on its review page.
- **Drafts:** a sent photo becomes a draft; leaving the review page never
  loses it. Drafts are cards edged in the AI's light, pinned on Today and
  atop Records: being read (shimmer), ready (Confirm), no food found or
  failed (open to add foods or try again). Edits on a draft's page are
  kept on the draft; its trash discards it with Undo.
- **Records:** every day newest first with its total, meals and weights as
  rows of one card, filtered by all / meals / weight, 21 days at a time.
- **States designed:** first run (no account), empty day, past day, photo
  being prepared, consent pending / declined, analyzing (and slow), results,
  no food found, every failure with its recovery, editing, unsaved changes.

Missing records never read as zero intake: an empty day shows "—" and
"Nothing logged yet", not 0 kcal.

## Visual language: 墨与日光 · Ink & Daylight

A warm daylight canvas, white surfaces lifted by soft light, and ink for
everything that acts. The interface itself is monochrome so that the food,
its photos and its nutrition colors, carries the color; an iris-to-sky light
marks the moments the AI works. Dark is a deep graphite with white ink, its
surfaces separated by tone and a hairline instead of shadows.

| Role | Tokens |
|---|---|
| Surfaces | `CANVAS`, `SURFACE`, `SURFACE_2` (wells), `SUNKEN` (fields, tracks), `RAISED`, `LINE`, `LINE_STRONG` |
| Text | `INK` (titles, figures), `BODY`, `MUTED`, `FAINT` |
| Action | `ACTION` (ink), `ACTION_PRESSED`, `ACTION_SHEEN`, `ON_ACTION` |
| AI | `AI_FROM` → `AI_TO` (analysis light, estimate marks) |
| Status | `DANGER(_SOFT)`, `CAUTION(_SOFT)` (estimates to check), `POSITIVE` |
| Data | `PROTEIN` coral, `CARBS` saffron, `FAT` azure, `OTHER`, `TRACK` |
| Media | `ON_MEDIA`, `MEDIA_SCRIM`, `PHOTO_WELL` |

- **Type** (`Type`): Display 44, LargeTitle 34, Title 22,
  Figure 20, Headline 17, Body 16, Callout 15, Subhead 14, Caption 12.5;
  tight tracking on large figures, tabular numerals everywhere numbers move.
- **Shape:** controls are pills; sheet 32 > card 24 > well 18 > field 16 >
  thumbnail 16 > badge 8.
- **Depth:** `shadow::CARD` (a contact shadow and a wide faint glow) under
  cards, `shadow::FLOAT` under the main action and raised buttons; none in
  dark. Glass (translucent scrim + backdrop blur, opaque enough without blur
  below Android 12) only for controls over photos.
- **Spacing:** the 4 pt scale; page gutter 20, card inset 20.

## Components (`src/ui/`)

`Btn` (primary ink with sheen / tonal / secondary raised / ghost / danger /
glass; three pill sizes; busy keeps its look, disabled goes flat and faint),
`IconBtn` (circles of the same
variants), `chip`, `card` / `card_button` (sinks under the finger),
`row_button`, `hairline`, `section_header`, `group_label`, `disclosure`,
`segmented` (pill track, one raised pill that slides), fields (labelled
inputs, ink focus edge), `checkbox_row` / `switch_row` (ink when on),
`bottom_sheet`, toast (ink pill with Undo), `spinner`, `shimmer` +
`skeleton`, `badge` (neutral pills; the AI's estimate marked by its light),
`empty_state`, `appear`, `counting` (figures that count to new values),
`macro_tiles` (percentages rounded to add up to 100), the energy `ring`, and
one icon family (24 pt line glyphs). Pushed pages share one top bar: a raised
round Back and the title centered.

## Platform decisions

- Pages hide the system header and draw their own top bar, so Android shows
  what is verified on the desktop; the system back gesture still pops
  natively and `pop_on_back` guards unsaved work.
- The review page's photo runs under the status bar (light icons over it,
  switched back once it scrolls away).
- Photos come only from the system photo picker (no camera yet). Every pick
  becomes an upright JPEG of at most 1280 px, which drops EXIF/GPS.
- Requests go through NSH's `fetch` (the platform network stack), straight
  to the account's base URL.
- Before a photo leaves the device, a sheet names the server and model it
  goes to. "Don't ask again" is remembered per server and model.
- The API key is stored on the device under its own storage key, never with
  the other settings, never logged.

## Motion inventory

Tokens: instant 120 ms, fast 180, base 240, slow 380, slower 640; settle
curve `cubic-bezier(0.22, 1, 0.36, 1)`; press spring (600 / 38); rise 14 pt;
stagger 50 ms (8 at most). Reduced motion: every item below is instant or
still.

| Screen | Change | Motion | Reduced motion |
|---|---|---|---|
| All | Button press | Spring to 0.96 (cards 0.98, icon buttons 0.90), deeper fill | Fill only |
| Home | Tab chosen | The bar's pill slides to the tab (native spring) | Jumps |
| Review | Day chosen (date chip) | One ink pill slides to the day (native spring) | Jumps |
| Today | Day's energy changes | Ring segments sweep from old to new ends, `slower`, settle; the figure counts to its new value | Set at once |
| Today | Meals arrive (open, save, undo) | Rows rise 14 pt and fade in, staggered | Shown at once |
| Today | Meal deleted | Toast slides up and fades, `slow`; Undo restores | Shown at once |
| Review | Scrolling | Photo drifts at half speed; pulling stretches it; once the panel slides under the top bar, the bar frosts in (`fast`) and its buttons turn solid, never resting half-faded | No stretch; bar switches at once |
| Review | Analyzing | The AI's light passes over the photo (2 s loop); a frosted caption rises in; placeholders shimmer | No light, no shimmer |
| Review | Results arrive | Caption lifts; "3 foods" chip, summary and rows rise in, staggered; the total counts up | Shown at once |
| Review | Meal slot | Raised pill slides to the segment (spring) | Jumps |
| Sheets | Open / close | Slide from the bottom over a fading scrim; swipe down to close | Appear / disappear |
| Editor | Nutrition details | Chevron turns 90°, `base` | Instant |
| Toggles | Checkbox / switch | Fill `instant`; knob slides `fast` | Instant |

Verified on the GTK desktop build (screenshots under `.screenshots/`, not
committed); Android verification happens on the device build.
