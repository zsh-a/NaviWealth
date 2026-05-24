import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter_test/flutter_test.dart' show autoUpdateGoldenFiles;
import 'package:golden_toolkit/golden_toolkit.dart';

/// Test config that scopes [GoldenToolkit] defaults for `test/golden/`.
///
/// Two things matter here:
///
///  1. **Skip golden assertion off Linux.** Goldens are byte-compared PNGs;
///     macOS, Windows, and Linux all rasterise text and gradients
///     differently, so a baseline captured on one OS will *never* match on
///     another. CI runs on Ubuntu (`mobile.yml` → `analyze-and-test`,
///     `ubuntu-latest`); the baseline checked into the repo is the Linux
///     baseline. Devs on macOS or Windows should still be able to run
///     `flutter test --tags=golden` and get a green bar — they just won't
///     get a real visual regression check until the PR hits CI.
///
///  2. **Lock font fallback** so we don't depend on whatever the host OS
///     happens to call "sans-serif". The app's Inter / Outfit subsets are
///     gitignored build artifacts (see `tool/build-latin-fonts.sh`); in
///     CI they are stubbed empty by `mobile.yml`. We force-load `Roboto`
///     from `flutter_test`'s embedded asset bundle in
///     `_golden_setup.dart#loadGoldenFonts` so the surface is reproducible
///     even when the woff2 stubs decode as zero glyphs.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  return GoldenToolkit.runWithConfiguration(
    () async {
      await testMain();
    },
    config: GoldenToolkitConfiguration(
      // Off-Linux runs still execute the test (so the page actually
      // pumps and we surface render-time exceptions) but skip the PNG
      // diff. The image is still *written* under `--update-goldens` so
      // a maintainer regenerating the baseline from a Linux box (CI or
      // a Docker container locally) gets the expected `goldens/*.png`
      // files. Without the `autoUpdateGoldenFiles` clause, golden_toolkit
      // would short-circuit the matcher entirely and never emit a file.
      skipGoldenAssertion: () => !Platform.isLinux && !autoUpdateGoldenFiles,
      enableRealShadows: true,
    ),
  );
}
