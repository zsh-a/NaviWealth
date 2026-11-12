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
- **Always available:** Log a meal (photo library), Add manually, previous
  days, Settings.
- **States designed:** first run (no account), empty day, past day, photo
  being prepared, consent pending / declined, analyzing (and slow), results,
  no food found, every failure with its recovery, editing, unsaved changes.

Missing records never read as zero intake: an empty day shows "—" and
"Nothing logged yet", not 0 kcal.

## Visual language

"澄白 · Porcelain": a cool porcelain canvas, white grouped surfaces, graphite
text, iris for what can be pressed or is selected. Food data has its own
colors (protein rose, carbs amber, fat teal) that never stand for actions or
status. Light and dark are both first-class (`AdaptiveColor` everywhere).

| Role | Tokens |
|---|---|
| Surfaces | `CANVAS`, `SURFACE`, `SUNKEN`, `LINE`, `LINE_STRONG` |
| Text | `INK` (titles, figures), `BODY`, `MUTED`, `FAINT` |
| Action | `ACCENT`, `ACCENT_FILL`, `ON_ACCENT`, `ACCENT_SOFT` |
| Status | `DANGER(_SOFT)`, `CAUTION(_SOFT)` (estimates to check), `POSITIVE` |
| Data | `PROTEIN`, `CARBS`, `FAT`, `OTHER`, `TRACK` |
| Media | `ON_MEDIA`, `MEDIA_SCRIM`, `PHOTO_WELL` |

- **Type** (`Type`): Display 34, LargeTitle 30, Title 20, Headline 16/600,
  Body 16, Callout 15, Subhead 14, Caption 12.5. Figures use tabular numerals.
- **Spacing:** the 4 pt scale; page gutter 20, card inset 18.
- **Radii:** sheet 28 > card 22 > photo 18 > control 14 > small 10 > badge 6;
  the floating main action is the one intentional capsule.
- **Sizes:** large 56, medium 48, small 36 (44 pt hit area kept).

## Components (`src/ui/`)

Buttons (`Btn` primary / tonal / secondary / ghost / danger, three sizes,
busy and disabled states; `IconBtn`; `chip`), surfaces (`card`, grouped rows,
hairlines, section and group labels, `disclosure`), `segmented` (one
selection that slides), fields (labelled text and number inputs with notes),
`checkbox_row` / `switch_row`, `bottom_sheet`, toast with Undo, `spinner`,
`skeleton`, `badge`, `empty_state`, `appear` (shared entrance), the energy
`ring`, and one icon family (24 pt line glyphs in `currentColor`).

## Platform decisions

- Pages hide the system header and draw one top bar, so Android shows what
  is verified on the desktop; the system back gesture still pops natively and
  `pop_on_back` guards unsaved work.
- Photos come only from the system photo picker (no camera yet). Every
  pick becomes an upright JPEG of at most 1280 px, which drops EXIF/GPS.
- Requests go through NSH's `fetch` (the platform network stack), straight
  to the account's base URL.
- Before a photo leaves the device, a sheet names the server and model it
  goes to. "Don't ask again" is remembered per server and model, so changing
  either asks again; Settings can turn asking back on.
- The API key is stored on the device under its own storage key, never with
  the other settings, never logged.

## Motion inventory

Tokens: instant 120 ms, fast 180, base 240, slow 360, slower 520; press
springs (stiffness 520, damping 36); rise 10 pt; stagger 45 ms (8 at most).
Reduced motion: every item below is instant or still.

| Screen | Change | Motion | Reduced motion |
|---|---|---|---|
| All | Button press | Spring to 0.97 (icon buttons 0.92) and a deeper fill, `fast` | Fill only |
| All | Hover (desktop) | Fill wash, `instant` | Same |
| Today | Day's energy changes | Each ring segment's ends animate from the old ring to the new, `slower`, ease-out (native, on the canvas) | Set at once |
| Today | Day figure changes | The number rises in again, `slow` | Shown at once |
| Today | Meals arrive (open, save, undo) | Rows rise and fade in, staggered 45 ms | Shown at once |
| Today | Meal deleted | Toast slides up 16 pt and fades, `slow`; Undo restores | Shown at once |
| Review | Photo prepared | Placeholder spinner, then the photo | Static spinner |
| Review | Analyzing | A band of light passes over the photo (1.9 s loop), shaded caption fades in, hint line rises in on change | No band; caption static |
| Review | Results arrive | Shade fades out `slow`; "3 foods" chip and rows rise in, staggered | Shown at once |
| Review | Meal slot | One selection slides to the chosen segment (spring) | Jumps |
| Sheets | Open / close | Slide from the bottom over a fading scrim; swipe down to close | Appear / disappear |
| Editor | Nutrition details | Chevron turns 90°, `base` | Instant |
| Settings | Test connection | Button shows a spinner while working; result line appears | Static spinner |
| Toggles | Checkbox / switch | Fill `instant`; thumb slides `fast` | Instant |

Verified on the GTK desktop build (screenshots under `.screenshots/`, not
committed); Android verification happens on the device build.
