# Web bundle size baseline

This is the regression baseline for `flutter build web --release` output.
The first-paint target is **`main.dart.js` gzip <= 800 KB**.

The numbers below are what we ship today; the deferred-imports infrastructure
keeps heavy secondary routes out of the initial `main.dart.js` payload.

## How to measure

```bash
cd apps/mobile
flutter pub get
tool/setup-drift-web.sh              # materializes sqlite3.wasm + drift_worker.dart.js
flutter build web --release --tree-shake-icons --no-source-maps

# Per-file gzip-9 sizes (what a CDN with brotli/gzip will serve)
for f in build/web/main.dart.js build/web/main.dart.js_*.part.js \
         build/web/flutter.js build/web/flutter_bootstrap.js; do
  raw=$(stat -f "%z" "$f" 2>/dev/null || stat -c "%s" "$f")
  gz=$(gzip -c -9 "$f" | wc -c)
  printf "%-40s %10d B raw   %10d B gzip\n" "$(basename "$f")" "$raw" "$gz"
done
```

`--no-source-maps` is what production should use — see
[Source maps](#source-maps) below for the rationale.

## Baseline (2026-04-28)

Build flags: `--release --tree-shake-icons --no-source-maps`
Renderer: CanvasKit (default; loaded from canvaskit/ alongside `main.dart.js`).

### First-paint critical path (`main.dart.js`)

| File              | Raw (B)     | Gzip-9 (B) | Notes                                                    |
| ----------------- | ----------- | ---------- | -------------------------------------------------------- |
| `main.dart.js`    | 2,959,991   | 840,200    | Framework, Material, riverpod, go_router, drift, l10n, design system, home page, router shell |
| `flutter.js`      | 9,553       | 3,679      | Loader, ships unchanged from Flutter SDK                 |
| `flutter_bootstrap.js` | 9,975  | 3,852      | Per-app bootstrap (canvaskit/skwasm probe)               |
| **First-paint JS total** | **2,979,519** | **847,731** | ≈ 828 KB gzip                                            |

`main.dart.js` alone is **~821 KB gzip**, vs. the <= 800 KB target. That's
~3 % over the target. See
[Where the bundle weight is](#where-the-bundle-weight-is) for the next levers.

### Deferred (per-route) parts

`go_router`'s feature tabs are loaded the first time the user navigates to them.
Home is *not* deferred — it ships in `main.dart.js` so the first paint after
the user authenticates needs no extra round-trip.

| Current route     | Entry file / feature                         | Trigger                    |
| ----------------- | -------------------------------------------- | -------------------------- |
| `/portfolio`      | `features/finance/investment/presentation/portfolio_hub_page.dart` | Open Investment Portfolio  |
| `/plan/analytics` | `features/finance/analytics/analytics_page.dart` | Open Planning > Analytics  |
| `/plan/fire`      | `features/finance/fire/presentation/fire_page.dart` | Open Planning > FIRE       |
| `/plan/rebalance` | `features/finance/rebalance/ui/rebalance_page.dart` | Open Planning > Rebalance  |
| `/ai`             | `features/ai_chat/ui/ai_chat_page.dart`      | Open AI assistant          |
| `/settings`       | `features/settings/ui/settings_page.dart`    | Open Settings              |

> The numeric suffix dart2js assigns to part files is not stable across builds;
> identify parts by content (or by the entry file in
> `lib/app/routing/router.dart`) when comparing across CI runs.

`/settings` is heavy relative to its 149-line source because the page pulls
in `SegmentedButton` + `PopupMenuButton` + theme-preference Riverpod
notifiers that nothing else in main yet uses; once another route references
those, dart2js will hoist them back into `main.dart.js` and the part will
shrink.

### Out-of-band assets (not on critical path)

These are fetched by Flutter's loader after `main.dart.js` boots, or only on
demand. Sizes shown to make the full picture explicit, but they don't count
against the 800 KB target.

| Asset                       | Raw (B)   | Gzip-9 (B) | When fetched                          |
| --------------------------- | --------- | ---------- | ------------------------------------- |
| `canvaskit/canvaskit.wasm`  | 7,155,824 | 2,870,188  | Renderer init (CDN-cached, versioned) |
| `canvaskit/canvaskit.js`    | 86,859    | 27,473     | Renderer init                         |
| `sqlite3.wasm`              | 730,989   | 347,931    | First DB open (drift_wasm)            |
| `drift_worker.dart.js`      | 354,117   | 106,935    | First DB open                         |
| `assets/MaterialIcons-Regular.otf` | 11,344 | n/a (binary) | Tree-shaken to glyphs the app uses |

CanvasKit and `sqlite3.wasm` are versioned and aggressively cached; the user
pays for them on the cold first visit only.

## Where the bundle weight is

`main.dart.js` is dominated, in rough order, by:

1. Flutter framework (Material widgets, animation, gesture, painting).
2. `dart:ui_web` + CanvasKit JS bindings.
3. `drift` runtime (SQL parser, query builder, executor) — even though the
   actual DB lives in a worker, the API surface is in main.
4. `flutter_riverpod`, `go_router`, `intl`, `shared_preferences`,
   `flutter_secure_storage`.
5. l10n delegates (en + zh-CN).
6. The design system (theme, market colors, money/delta widgets).

What's *not* a meaningful share today: the lightweight route shell. The big
wins come from keeping expensive feature dependencies deferred:

- the AI assistant route (streaming client, chat history, markdown rendering).
- the analytics route (`fl_chart`, multi-series breakdowns).
- the rebalance route (optimization and transaction preview).

These are already wired through `DeferredRoute` in
`lib/app/routing/router.dart`, so route-level bundle boundaries should stay
visible during future changes.

## Source maps

The `mobile.yml` CI workflow currently builds with `--source-maps` so the
artifact uploaded to the run can be symbolicated when debugging a release
crash. **Production deploys should pass `--no-source-maps`** (or strip
`*.map` before serving):

- The maps don't change `main.dart.js` itself, but each `*.map` is roughly
  the same size as the JS it describes; serving them blindly multiplies
  egress.
- Browsers only fetch a `.map` when DevTools is open *and* the
  `sourceMappingURL=` comment is present, so leaving them on the CDN is a
  silent footgun once a curious user opens DevTools on prod.
- Symbolication for crash reports works fine offline against the CI artifact;
  it doesn't need the maps to be public.

CI keeps `--source-maps` for the artifact upload. The deploy step (when it
exists) should either re-run `flutter build web --release --no-source-maps`
or `find build/web -name '*.map' -delete` before publishing.

## Regression policy

When `main.dart.js` gzip-9 grows by **> 50 KB** in a single PR, treat it as
a code-review blocker and either:

1. find what got pulled into main (often: a previously-deferred package
   referenced from main accidentally), and push it back out;
2. add a new `deferred as` import for the new heavy module; or
3. update this doc with the new baseline and a one-line note explaining the
   cause.

Run the measurement snippet from [How to measure](#how-to-measure) locally
or in CI to compare before merging.

## CN web font budget (first-paint @font-face)

`apps/mobile/tool/build-cn-fonts.sh` subsets Noto Sans SC into two woff2
tiers that `flutter build web` loads via `@font-face`:

- `app-cn-base.woff2` — **first-paint** subset, fetched on the first request.
  Holds every CJK glyph that literally appears in first-paint UI/l10n
  (`lib/**` Dart string literals + `*.arb`), plus ASCII and punctuation.
- `app-cn-ext.woff2` — the rest of GB 2312, lazy-loaded only when a glyph
  outside `base` is first needed (server text, free input, the deferred
  `/ai` route).

woff2 is already brotli-compressed, so the on-disk size *is* the wire size.
It is **not** part of the `main.dart.js` 800 KB target above — it is a
separate first-paint asset, HTTP-cached after the cold visit.

**Budget: `BASE_BUDGET_BYTES` = 315,000 B (~308 KiB).** This is a tripwire,
not a hard limit: the build fails when `base` exceeds it so a human looks at
*why* it grew before the line moves.

Raised from the original ~250 KiB on 2026-05-17 after the device-AI wave.
That work added a few hundred hanzi, but ~90% were finance vocabulary the UI
already needed; the genuinely new tail was LLM-prompt / tool-schema /
regression-fixture text that does **not** paint on web (the device AI
runtime is `!kIsWeb`-gated — see `docs/ai/ai-architecture.md` §4.6). Two
changes landed together:

1. `tool/cn_font_chars.py` scopes device AI plus feature `ai_tools`, `agents`,
   `data`, `domain`, and `composition` trees out of the *base* scan
   (model-facing or non-UI; `ext` still covers deferred text).
2. The budget was raised to ~308 KiB on 2026-07-18 when the old per-file
   CN-literal allowlist was retired. The structural scan includes all actual
   UI source and ARB copy without coupling font generation to a lint baseline.
3. The resulting budget gives the legitimate, ever-growing l10n/UI corpus
   headroom without nuisance CI failures per feature.

When the build fails on this budget:

1. Find what grew — the `base set: N code points` line plus a per-file
   scan of unique hanzi pinpoint the source.
2. If it's model-facing or web-dead (AI prompts, tool descriptions, test
   fixtures), scope it out in `cn_font_chars.py` — don't ship it to web.
3. If it's real first-paint UI/l10n growth, raise `BASE_BUDGET_BYTES` and
   update this section with the new number and a one-line reason.

Bigger structural lever, deferred: the subset preserves the full Noto Sans
SC variable `wght` axis (100–900) though the app uses only 400/500/600/700.
Instancing the axis would cut size far more than glyph-count triage —
tracked separately (real vs. synthetic weight quality tradeoff).
