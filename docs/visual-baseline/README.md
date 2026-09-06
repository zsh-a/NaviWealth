# Visual baseline

This document describes the checked-in Flutter golden regression suite for
FinanceOS, the optional domains, and shared AI/design-system surfaces.

README product screenshots are a separate curated output. They render
production widgets with deterministic marketing fixtures and live under
`docs/assets/readme/generated/`.

```bash
cd apps/mobile
./tool/update-readme-screenshots.sh           # verify committed screenshots
./tool/update-readme-screenshots.sh --update  # regenerate them
```

`docs/assets/readme/manifest.json` pins each image's dimensions, locale,
theme, and description. CI uploads refreshed images and fails when committed
screenshots are stale; review and commit the generated images with UI changes.

## Golden screenshot regression

### What's locked

| Page / surface | Test file | Variants |
|---|---|---|
| Home dashboard | `apps/mobile/test/golden/home_page_golden_test.dart` | light / dark / colorblind |
| Asset detail skeleton | `apps/mobile/test/golden/asset_detail_page_golden_test.dart` | light / dark / colorblind |
| FIRE (unconfigured) | `apps/mobile/test/golden/fire_page_golden_test.dart` | light / dark / colorblind |
| AI Chat (login required) | `apps/mobile/test/golden/ai_chat_page_golden_test.dart` | light / dark / colorblind |
| Settings | `apps/mobile/test/golden/settings_page_golden_test.dart` | light / dark / colorblind |
| Account activity / Wealth / Accounts | `apps/mobile/test/golden/account_activity_golden_test.dart` | light / dark / colorblind |
| Cashflow / Dividend Center / Corporate Action Entry | `apps/mobile/test/golden/cashflow_golden_test.dart` | light / dark / colorblind |
| Portfolio Hub | `apps/mobile/test/golden/portfolio_hub_page_golden_test.dart` | light / dark / colorblind |
| Plan Hub | `apps/mobile/test/golden/plan_hub_page_golden_test.dart` | light / dark / colorblind |
| Watchlist | `apps/mobile/test/golden/watchlist_page_golden_test.dart` | light / dark / colorblind |
| DCA simulator | `apps/mobile/test/golden/dca_simulator_page_golden_test.dart` | light / dark / colorblind |
| Compact action sheet | `apps/mobile/test/golden/action_sheet_compact_golden_test.dart` | component-scoped light surface |
| Target allocation editor sheet | `apps/mobile/test/golden/target_allocation_editor_sheet_golden_test.dart` | light / dark / colorblind |
| Asset FX PnL card | `apps/mobile/test/golden/asset_fx_pnl_card_golden_test.dart` | light / dark / colorblind |
| FIRE OS cards | `apps/mobile/test/golden/fire_os_cards_golden_test.dart` | light / dark / colorblind |
| Sync status diagnostics | `apps/mobile/test/golden/sync_status_page_golden_test.dart` | light / dark / colorblind |
| AI visual primitives / renderers | `apps/mobile/test/golden/ai_surfaces_golden_test.dart` | component-scoped light surfaces |
| Adaptive layout matrix | `apps/mobile/test/golden/adaptive_layout_matrix_golden_test.dart` | narrow / medium / expanded / wide / extra-wide / text-scale |
| App glass surface | `apps/mobile/test/golden/app_glass_surface_golden_test.dart` | light / dark / colorblind |
| Health / Knowledge / Execution pages | `apps/mobile/test/golden/domain_pages_golden_test.dart` | light / dark / colorblind |
| Task flows (Ingest, forms, Undo, Rebalance) | `apps/mobile/test/golden/task_flow_responsive_golden_test.dart` | dark responsive N / W / T matrix |

There are currently 21 golden test files and **108 PNG baselines** under
`apps/mobile/test/golden/goldens/`: 93 page/component baselines plus 15 dark
responsive task-flow baselines. Theme-matrix pages run light, dark, and
dark-colorblind variants; AI primitives keep their minimal light surfaces so
the visual language is isolated from app chrome.

The responsive profiles mirror production behavior: N (`390×844 @2x`, text
scale 1) and T (the N canvas at text scale 2.0) use the dark iOS touch theme
with non-compact Material density. W (`1280×900 @1x`, text scale 1) uses the
dark Linux desktop theme with compact density. The 15 task-flow baselines are:

- `task_flow_ingest_n.png`, `task_flow_ingest_w.png`, `task_flow_ingest_t.png`
- `task_flow_account_n.png`, `task_flow_expense_n.png`
- `task_flow_transfer_n.png`, `task_flow_transfer_w.png`, `task_flow_transfer_t.png`
- `task_flow_trade_n.png`
- `task_flow_persistent_undo_n.png`, `task_flow_persistent_undo_t.png`
- `task_flow_rebalance_n.png`, `task_flow_rebalance_offline_n.png`,
  `task_flow_rebalance_w.png`, `task_flow_rebalance_t.png`

The 93 page/component baselines keep the dark red-up-green-down and
dark-colorblind blue-plus-orange regimes. The task-flow matrix is dark-only so
its budget is spent on width and text-scale coverage.

### Where the baselines come from

Goldens are byte-compared PNGs and depend on the rasteriser. **Linux is the
source of truth** — the `golden regression (mobile)` job in `mobile.yml` runs
on `ubuntu-latest` and asserts against the checked-in PNGs.

`testVisualGolden` fixes the clock to 09:30 so time-of-day atmosphere colors
do not depend on the runner's local time. README captures use the same clock;
each domain in the side-by-side showcase has its own active router, and the
test unmounts provider scopes before closing its in-memory database.

`apps/mobile/test/golden/flutter_test_config.dart` skips PNG comparison on
non-Linux hosts. The responsive harness still pumps the full surface and
fails on render-time exceptions. `--update-goldens` writes files regardless
of platform, so only commit baselines generated with the Linux rasteriser.

### Workflow

```bash
cd apps/mobile

# Regenerate the responsive task-flow baseline on Linux:
flutter test test/golden/task_flow_responsive_golden_test.dart \
  --tags=responsive-golden --update-goldens

# PR verification (responsive task flows only):
flutter test test/golden/task_flow_responsive_golden_test.dart \
  --tags=responsive-golden

# Main verification (all page/component and responsive goldens):
flutter test test/golden --tags=golden
```

In CI, ordinary unit/widget tests run in four shards. Pull requests run the
independent responsive task-flow job; `main` runs the full golden regression
and compares all 108 baselines. On failure, diff PNGs in
`apps/mobile/test/golden/failures/` are uploaded as a workflow artifact.

### Adding a new golden

1. Add a test file under `apps/mobile/test/golden/`. Theme-matrix tests use
   `pumpAndSnapshotMobile` + `runAllVariants`; responsive tests use
   `pumpAndSnapshotResponsive` + `runResponsiveGolden` and carry the
   corresponding tags.
2. Override every provider that would otherwise reach the real Drift DB
   (`appDatabaseProvider`, `outboxStoreProvider`, and `syncEngineProvider`
   can leave stream-query timers dangling at scope dispose).
3. Run with `--update-goldens` on Linux and commit the resulting
   `goldens/<name>_<variant>.png` files.

If regeneration is needed from a non-Linux machine, use the same Linux
Flutter container as CI, then run `flutter test test/golden --tags=golden
--update-goldens` inside it. Do not commit macOS or Windows raster output.
