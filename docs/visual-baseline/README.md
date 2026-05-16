# Visual baseline (FIR-113)

Final acceptance for the [FIR-103](https://multica/issues/FIR-103) "premium UI" epic. Three deliverables:

1. **Golden screenshot regression** — locks the rendered look of the seven golden-path mobile pages against drift.
2. **Figma mock baseline** — three-breakpoint mocks, kept in sync with the Dart `design_tokens/tokens.json`.
3. **Cross-end walkthrough** — manual verification of FIR-103 §10 "Golden Path", with screenshots archived under `walkthrough/`.

---

## 1. Golden screenshot regression

### What's locked

| Page | File | Variants |
|------|------|----------|
| Home (dashboard) | `apps/mobile/test/golden/home_page_golden_test.dart` | dark / colorblind |
| Asset detail (skeleton) | `apps/mobile/test/golden/asset_detail_page_golden_test.dart` | dark / colorblind |
| Analytics (empty) | `apps/mobile/test/golden/analytics_page_golden_test.dart` | dark / colorblind |
| FIRE (unconfigured) | `apps/mobile/test/golden/fire_page_golden_test.dart` | dark / colorblind |
| AI Chat (login required) | `apps/mobile/test/golden/ai_chat_page_golden_test.dart` | dark / colorblind |
| Settings | `apps/mobile/test/golden/settings_page_golden_test.dart` | dark / colorblind |

6 pages × 2 themes = **12 PNG baselines** under `apps/mobile/test/golden/goldens/`. (Light-mode was dropped — see *Variant choice* below.)

Mobile-only for now. Per FIR-103 §11 R7 ("截图回归在 CI 上跨端不稳"), tablet and desktop snapshots are deferred — those layouts use the same primitives the mobile goldens already cover, and the master-detail surfaces add CI flake without a visual signal we don't already get from the unit suite.

### Variant choice

Two variants: dark (red-up-green-down) and dark-colorblind (blue+orange). Both exercise `MarketColors`, `GlassTokens`, and the type ramp under different accent regimes. A light variant adds CI cost without catching anything the dark+colorblind pair doesn't.

### Where the baselines come from

Goldens are byte-compared PNGs and depend on the rasteriser. **Linux is the source of truth** — `mobile.yml`'s `golden regression (mobile)` job runs on `ubuntu-latest` and asserts against the checked-in PNGs.

`apps/mobile/test/golden/flutter_test_config.dart` skips the byte comparison off-Linux so devs on macOS / Windows still see a green bar locally; the matcher still executes (a render-time exception still fails the test). `--update-goldens` always writes, regardless of platform.

### Workflow

```bash
cd apps/mobile

# Regenerate the baseline locally (only meaningful on Linux; macOS / Windows
# baselines won't match what CI generates):
flutter test test/golden --tags=golden --update-goldens

# Verify against the committed baseline:
flutter test test/golden --tags=golden
```

In CI:

- `analyze + test (coverage)` runs `flutter test --exclude-tags=golden` for the unit / widget suite.
- `golden regression (mobile)` runs `flutter test test/golden --tags=golden`. Fails the PR on byte-diff. On failure the diff PNGs (`apps/mobile/test/golden/failures/`) are uploaded as a workflow artifact (7-day retention).

### Adding a new golden

1. Add a test file under `apps/mobile/test/golden/`. Reuse `pumpAndSnapshotMobile` + `runAllVariants(name, body)` from `_golden_setup.dart` — they handle device profile, font fallback, theme variants, motion suppression.
2. Override every `StreamProvider` / `FutureProvider` that would otherwise reach the real Drift DB (`appDatabaseProvider` / `outboxStoreProvider` / `syncEngineProvider` leave a stream-query timer dangling at scope dispose). When in doubt, copy the override block from a sibling page test.
3. Run with `--update-goldens` on a Linux box (locally or via a "regenerate goldens" PR) and commit the resulting `goldens/<name>_<variant>.png`.

If you need to regenerate from a non-Linux machine, use Docker:

```bash
docker run --rm -v "$(pwd):/work" -w /work/apps/mobile \
  ghcr.io/cirruslabs/flutter:stable \
  flutter test test/golden --tags=golden --update-goldens
```

---

## 2. Figma mock baseline

### Source of truth contract

Visual tokens live in **two places that must stay aligned**:

| Surface | Location | Owner |
|---------|----------|-------|
| Dart runtime | `apps/mobile/lib/design_system/tokens/*.dart` | Eng (review on every PR that touches `lib/design_system/`) |
| W3C tokens JSON | `apps/mobile/design_tokens/tokens.json` | Eng — regenerated alongside the Dart tokens, see `apps/mobile/design_tokens/README.md` |
| Figma library | <https://figma.com/file/PLACEHOLDER/NaviWealth-DS> *(replace with the published library URL on first import)* | Design (mimo) |

`design_tokens/tokens.json` is the **handover format** between the two — it follows the
[W3C Design Tokens Community Group](https://design-tokens.github.io/community-group/format/) draft
spec and imports cleanly into the Figma "Tokens Studio" plugin.

### Sync protocol

Color / type / spacing changes must move in this order, never in reverse:

1. **Dart first.** Edit `lib/design_system/tokens/{color_palette,typography_tokens,spacing_tokens,…}.dart`
   and re-export `design_tokens/tokens.json` (instructions in `design_tokens/README.md`).
2. **Update the visual baseline.** Re-run goldens; commit the diff in the same PR as the token change.
3. **Hand the JSON to design.** Mention the design owner on the PR with a one-line summary of the
   token diff. Design pulls it into Figma via Tokens Studio → publishes a new library version → cuts
   a Figma release note.

If a change starts in Figma (designer tweaks a tone in the library), it doesn't ship until step 1
above is done by an engineer — Figma is downstream.

### Three-breakpoint mocks

Per FIR-103 §4 (`mobile <600 / tablet 600–1240 / desktop ≥1240`) the Figma library covers each
critical path at **all three** breakpoints:

| Path | Mobile | Tablet | Desktop |
|------|--------|--------|---------|
| Home / dashboard | ✓ | ✓ | ✓ |
| Asset detail | ✓ | ✓ | ✓ (master-detail right pane) |
| AI Chat sheet (FIR-111 floating pill) | ✓ | ✓ | ✓ |
| Command palette (FIR-112) | n/a | ✓ | ✓ |
| Master-Detail layout (FIR-106) | n/a | ✓ | ✓ |

The Figma library URL and the per-frame links go in this README once design publishes the v1
library — replace the placeholder URL above and add a `Figma frames` table mapping each path to a
Figma node id.

---

## 3. Cross-end walkthrough — FIR-103 §10 Golden Path

Verify each item on each of the three layout shells (`_MobileShell`, `_TabletShell`, `_DesktopShell`)
before signing off the epic. Drop the screenshot evidence into `walkthrough/<step>-<shell>.png` and
tick the box.

| # | Step | Mobile | Tablet | Desktop | Notes |
|---|------|:--:|:--:|:--:|------|
| 1 | App launch → home Hero net-worth CountUp; no font flash, no horizontal jitter on tabular figures | ☐ | ☐ | ☐ | T1 (Inter / Outfit) + T4 (AnimatedMoneyText) |
| 2 | Home → assets list → asset detail; Hero icon / name / value transitions smoothly | ☐ | ☐ | ☐ | T6. Desktop disables Hero in master-detail (asserted by widget test) |
| 3 | Asset detail chart: long-press drag shows crosshair + glass tooltip + haptic | ☐ | ☐ | ☐ | T5. Haptic only on mobile + desktop trackpad |
| 4 | Tap AI floating pill → half-screen sheet; type "我的持仓" → returns a holdings table widget, not raw JSON | ☐ | ☐ | ☐ | T7 (pill) + T8 (in-stream chart widgets) |
| 5 | `Cmd+K` → "fire" → navigates to FIRE page; `Cmd+B` collapses sidebar (desktop only) | n/a | ☐ | ☐ | T9. Mobile has no sidebar — record n/a, not a tick |
| 6 | Toggle dark / light / colorblind from Settings: every chart + chip recolours, no hardcoded emerald / crimson leaks through | ☐ | ☐ | ☐ | Asserted at unit level by `market_colors_test.dart`; this row is the visual confirmation |
| 7 | System font scale → 200%: home Hero number doesn't overflow its card | ☐ | ☐ | ☐ | FittedBox + clampTextScale; record as PNG |
| 8 | Airplane mode → enter a trade in the form; sheet closes immediately and the list updates | ☐ | ☐ | ☐ | Local-first regression check; pre-existing capability, just confirm it still works |
| 9 | `flutter test test/golden --tags=golden` is green on `main` | ☐ | ☐ | ☐ | Single tick once the golden-regression CI job is consistently green for 3+ runs |

### Naming convention for archived screenshots

`walkthrough/NN-<shell>-<short-slug>.png` — e.g. `walkthrough/01-mobile-hero-countup.png`,
`walkthrough/04-desktop-ai-pill.png`. Keep them under 500 KB each; Apple "Screenshot" defaults are
fine, no need for a specific tool.

---

## Files in this directory

- `README.md` — this file.
- `walkthrough/` — manual cross-end verification screenshots (populated as the §10 boxes get ticked).
