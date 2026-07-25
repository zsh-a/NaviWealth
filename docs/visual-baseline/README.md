# Visual baseline

Final acceptance for the "premium UI" epic. Three deliverables:

1. **Golden screenshot regression** — locks the rendered look of the mobile task surfaces and AI visual primitives against drift.
2. **Figma mock baseline** — three-breakpoint mocks, kept in sync with the Dart `design_tokens/tokens.json`.
3. **Cross-end walkthrough** — manual verification of "Golden Path", with screenshots archived under `walkthrough/`.

README product screenshots are a separate curated output. They render
production widgets with deterministic marketing fixtures and are stored under
`docs/assets/readme/generated/`; they are not copied from regression goldens.

```bash
cd apps/mobile
./tool/update-readme-screenshots.sh           # verify committed screenshots
./tool/update-readme-screenshots.sh --update  # regenerate them
```

`docs/assets/readme/manifest.json` pins each image's dimensions, locale,
theme, and description. Pull requests render a review artifact and warn on
visual drift without blocking unrelated UI work. After UI changes land on
`main`, `.github/workflows/readme-screenshots.yml` opens or refreshes a dedicated
screenshot PR when the canonical Linux-rendered assets change.

---

## 1. Golden screenshot regression

### What's locked

| Page | File | Variants |
|------|------|----------|
| Home (dashboard) | `apps/mobile/test/golden/home_page_golden_test.dart` | dark / colorblind |
| Asset detail (skeleton) | `apps/mobile/test/golden/asset_detail_page_golden_test.dart` | dark / colorblind |
| FIRE (unconfigured) | `apps/mobile/test/golden/fire_page_golden_test.dart` | dark / colorblind |
| AI Chat (login required) | `apps/mobile/test/golden/ai_chat_page_golden_test.dart` | dark / colorblind |
| Settings | `apps/mobile/test/golden/settings_page_golden_test.dart` | dark / colorblind |
| Account activity / Wealth / Accounts | `apps/mobile/test/golden/account_activity_golden_test.dart` | dark / colorblind |
| Cashflow / Dividend Center / Corporate Action Entry | `apps/mobile/test/golden/cashflow_golden_test.dart` | dark / colorblind |
| Portfolio Hub | `apps/mobile/test/golden/portfolio_hub_page_golden_test.dart` | dark / colorblind |
| Watchlist | `apps/mobile/test/golden/watchlist_page_golden_test.dart` | dark / colorblind |
| DCA simulator | `apps/mobile/test/golden/dca_simulator_page_golden_test.dart` | dark / colorblind |
| Compact action sheet | `apps/mobile/test/golden/action_sheet_compact_golden_test.dart` | component-scoped light surface |
| Target allocation editor sheet | `apps/mobile/test/golden/target_allocation_editor_sheet_golden_test.dart` | dark / colorblind |
| Asset FX PnL card | `apps/mobile/test/golden/asset_fx_pnl_card_golden_test.dart` | dark / colorblind |
| FIRE OS cards | `apps/mobile/test/golden/fire_os_cards_golden_test.dart` | dark / colorblind |
| Sync status diagnostics | `apps/mobile/test/golden/sync_status_page_golden_test.dart` | dark / colorblind |
| AI visual primitives / renderers | `apps/mobile/test/golden/ai_surfaces_golden_test.dart` | component-scoped light surfaces |
| Task flows (Ingest, forms, Undo, Rebalance) | `apps/mobile/test/golden/task_flow_responsive_golden_test.dart` | dark responsive N / W / T matrix |

17 test files produce **68 PNG baselines** under
`apps/mobile/test/golden/goldens/`: the 47-PNG page/component matrix (including
the compact action sheet) plus a 14-PNG dark responsive task-flow matrix. Light-mode page variants were
dropped — see *Variant choice* below — but AI primitive/component goldens keep
their own minimal light surfaces to isolate the visual language from app
chrome.

The responsive profiles mirror production platform behavior: N (`390×844
@2x`, text scale 1) and T (the N canvas at text scale 2.0) use the dark iOS
touch theme with non-compact Material density; W (`1280×900 @1x`, text scale
1) uses the dark Linux desktop theme with compact density. The 14 dark
baselines are:

- `task_flow_ingest_n.png`, `task_flow_ingest_w.png`, `task_flow_ingest_t.png`
- `task_flow_account_n.png`, `task_flow_expense_n.png`
- `task_flow_transfer_w.png`, `task_flow_transfer_t.png`
- `task_flow_trade_n.png`
- `task_flow_persistent_undo_n.png`, `task_flow_persistent_undo_t.png`
- `task_flow_rebalance_n.png`, `task_flow_rebalance_offline_n.png`,
  `task_flow_rebalance_w.png`, `task_flow_rebalance_t.png`

### Variant choice

The 49 page/component baselines keep their existing harness: dark
(red-up-green-down) and dark-colorblind (blue+orange). Both exercise
`MarketColors`, `GlassTokens`, and the type ramp under different accent
regimes. The 14 responsive task-flow baselines are dark-only so the matrix
spends its budget on width and 2× text rather than repeating accent coverage.

### Where the baselines come from

Goldens are byte-compared PNGs and depend on the rasteriser. **Linux is the source of truth** — `mobile.yml`'s `golden regression (mobile)` job runs on `ubuntu-latest` and asserts against the checked-in PNGs.

`apps/mobile/test/golden/flutter_test_config.dart` skips the PNG matcher
off-Linux so macOS / Windows do not compare incompatible raster output. The
responsive harness still pumps the full surface and separately fails on any
render-time exception before reaching that policy. `--update-goldens` invokes
the matcher and writes regardless of platform.

### Workflow

```bash
cd apps/mobile

# Regenerate only the responsive baseline on Linux. This leaves the legacy
# 48 PNGs byte-for-byte unchanged:
flutter test test/golden/task_flow_responsive_golden_test.dart \
  --tags=responsive-golden --update-goldens

# PR verification (responsive task flows only):
flutter test test/golden/task_flow_responsive_golden_test.dart \
  --tags=responsive-golden

# Main verification (all legacy + responsive goldens):
flutter test test/golden --tags=golden
```

In CI:

- Four test shards run `flutter test --coverage --exclude-tags=golden` for the
  unit/widget suite, followed by the Codecov upload job.
- Pull requests run the independent `responsive task-flow goldens` job, which
  needs `prepare-font-assets` and runs only the double-tagged responsive file.
- Main runs `golden regression (mobile)` with `--tags=golden`, so it compares
  all 63 baselines. On failure the diff PNGs
  (`apps/mobile/test/golden/failures/`) are uploaded as a workflow artifact.

### Adding a new golden

1. Add a test file under `apps/mobile/test/golden/`. Legacy theme-matrix tests
   use `pumpAndSnapshotMobile` + `runAllVariants(name, body)`. Responsive tests
   use the separate `pumpAndSnapshotResponsive` + `runResponsiveGolden` path
   and carry both `golden` and `responsive-golden` tags.
2. Override every `StreamProvider` / `FutureProvider` that would otherwise reach the real Drift DB (`appDatabaseProvider` / `outboxStoreProvider` / `syncEngineProvider` leave a stream-query timer dangling at scope dispose). When in doubt, copy the override block from a sibling page test.
3. Run with `--update-goldens` on a Linux box (locally or via a "regenerate goldens" PR) and commit the resulting `goldens/<name>_<variant>.png`.

If you need to regenerate from a non-Linux machine, use Docker:

```bash
# Run from the repository root. The container mirrors CI's Linux rasteriser.
# It installs python3.12-venv because the font-subset scripts create local
# fonttools virtualenvs, then chowns generated files back to the host user.
docker run --rm \
  -e HOME=/root \
  -e HOST_UID="$(id -u)" \
  -e HOST_GID="$(id -g)" \
  -v "$PWD:/work" \
  -w /work/apps/mobile \
  ghcr.io/cirruslabs/flutter:stable \
  bash -lc 'trap "chown -R $HOST_UID:$HOST_GID /work/apps/mobile/.dart_tool /work/apps/mobile/assets/fonts /work/apps/mobile/test/golden 2>/dev/null || true" EXIT; \
    git config --global --add safe.directory /sdks/flutter && \
    git config --global --add safe.directory /work/apps/mobile && \
    apt-get update && \
    apt-get install -y python3.12-venv && \
    rm -rf .dart_tool/cn_fonts/venv .dart_tool/latin_fonts/venv && \
    flutter pub get && \
    tool/build-cn-fonts.sh && \
    tool/build-latin-fonts.sh && \
    flutter test test/golden/task_flow_responsive_golden_test.dart --tags=responsive-golden --update-goldens --reporter=expanded'
```

Do not commit goldens generated directly on macOS or Windows; those platforms
skip byte comparison locally and do not match CI's Linux PNG output.

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

The Figma library covers each
critical path at **all three** breakpoints:

| Path | Mobile | Tablet | Desktop |
|------|--------|--------|---------|
| Home / dashboard | ✓ | ✓ | ✓ |
| Asset detail | ✓ | ✓ | ✓ (master-detail right pane) |
| AI Chat sheet (floating pill) | ✓ | ✓ | ✓ |
| Command palette | n/a | ✓ | ✓ |
| Master-Detail layout | n/a | ✓ | ✓ |

The Figma library URL and the per-frame links go in this README once design publishes the v1
library — replace the placeholder URL above and add a `Figma frames` table mapping each path to a
Figma node id.

---

## 3. Cross-end walkthrough — Golden Path

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
