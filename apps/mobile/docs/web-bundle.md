# Web bundle size baseline

This is the regression baseline for `flutter build web --release` output.
The v1 target from FIR-39 is **`main.dart.js` gzip ≤ 800 KB** on first paint.

The numbers below are what we ship today; the deferred-imports infrastructure
landed in FIR-39 lets future heavy routes (FIR-22 AI assistant, FIR-7/8
analytics, FIR-8 rebalance) be split off without touching `main.dart.js`.

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

## Baseline (FIR-39, 2026-04-28)

Build flags: `--release --tree-shake-icons --no-source-maps`
Renderer: CanvasKit (default; loaded from canvaskit/ alongside `main.dart.js`).

### First-paint critical path (`main.dart.js`)

| File              | Raw (B)     | Gzip-9 (B) | Notes                                                    |
| ----------------- | ----------- | ---------- | -------------------------------------------------------- |
| `main.dart.js`    | 2,959,991   | 840,200    | Framework, Material, riverpod, go_router, drift, l10n, design system, home page, router shell |
| `flutter.js`      | 9,553       | 3,679      | Loader, ships unchanged from Flutter SDK                 |
| `flutter_bootstrap.js` | 9,975  | 3,852      | Per-app bootstrap (canvaskit/skwasm probe)               |
| **First-paint JS total** | **2,979,519** | **847,731** | ≈ 828 KB gzip                                            |

`main.dart.js` alone is **~821 KB gzip**, vs. the ≤ 800 KB v1 target. That's
~3 % over the target with placeholder feature pages still in the tree; the
gap closes once placeholders shrink and we lazy-load the heavy routes. See
[Where the bundle weight is](#where-the-bundle-weight-is) for the next levers.

### Deferred (per-route) parts

`go_router`'s feature tabs are loaded the first time the user navigates to them.
Home is *not* deferred — it ships in `main.dart.js` so the first paint after
the user authenticates needs no extra round-trip.

| Route        | Part file                  | Raw (B) | Gzip-9 (B) | Trigger                                |
| ------------ | -------------------------- | ------- | ---------- | -------------------------------------- |
| `/analytics` | `main.dart.js_2.part.js`   | 734     | 502        | Tap "Analytics" tab                    |
| `/assets`    | `main.dart.js_1.part.js`   | 8,550   | 3,480      | Tap "Assets" tab                       |
| `/settings`  | `main.dart.js_3.part.js`   | 62,296  | 20,167     | Tap "Settings" tab                     |
| **Sum**      |                            | 71,580  | 24,149     |                                        |

> The numeric suffix dart2js assigns to part files is not stable across builds;
> identify parts by content (or by the entry file in
> `lib/app/router.dart`) when comparing across CI runs.

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

What's *not* a meaningful share today: the four feature pages. Splitting
placeholder pages saved ~12 KB gzip. The big wins come later, when:

- the AI assistant route lands (drag-and-drop, markdown rendering, streaming
  client) — defer.
- the analytics route lands (`fl_chart`, multi-series breakdowns) — defer.
- the rebalance route lands (optimization, transaction preview) — defer.

These are already wired through `DeferredRoute` in `lib/app/router.dart`, so
adding them only requires writing the page; no router or build-config
changes.

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
