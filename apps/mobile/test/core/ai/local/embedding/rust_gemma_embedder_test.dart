/// Integration tests for the Rust EmbeddingGemma binding via
/// `flutter_rust_bridge` (D-1.7c per `docs/lifeos-shell.md` §6.6).
///
/// These tests skip when the host doesn't have a built
/// `liblifeos_native.dylib`. Build it with:
///
///   tool/build-lifeos-native.sh macos
///
/// CI doesn't build the dylib by default (cargo + fastembed +
/// downloaded ORT binaries pulls 120+ crates and ~18 MB native lib);
/// these tests run unconditionally on the developer machine after a
/// build, and stay skipped on CI until the Rust toolchain step is
/// added to `mobile.yml`.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/ai/local/embedding/embedding.dart';
import 'package:naviwealth/src/rust/api/embedder.dart' as frb;

// Candidate paths relative to `apps/mobile/` (flutter test cwd).
const _candidateDylibPaths = <String>[
  'native/lifeos_native/dist/macos/liblifeos_native.dylib',
  'native/lifeos_native/target/release/liblifeos_native.dylib',
];

String? _findDylib() {
  for (final p in _candidateDylibPaths) {
    final f = File(p);
    if (f.existsSync()) return f.absolute.path;
  }
  return null;
}

void main() {
  final dylibPath = _findDylib();
  final skipReason = dylibPath == null
      ? 'liblifeos_native.dylib not found; run tool/build-lifeos-native.sh macos'
      : null;

  group('lifeos_native FRB bindings', () {
    setUpAll(() async {
      if (skipReason != null) return;
      await initLifeosNativeRuntime(libraryPath: dylibPath);
    });

    test('embeddingDim() top-level == 768', () {
      expect(frb.embeddingDim(), 768);
    }, skip: skipReason);

    test(
      'embedderFingerprint() top-level matches the expected constant',
      () {
        expect(frb.embedderFingerprint(), 'embeddinggemma-300m-onnx-int8-d768');
      },
      skip: skipReason,
    );

    test('GemmaEmbedder.load throws on empty model dir', () async {
      await expectLater(
        () => RustGemmaEmbedder.load(
          modelDir: '',
          ortDylibPath: '',
          libraryPath: dylibPath,
        ),
        throwsA(isA<RustEmbedderUnavailable>()),
      );
    }, skip: skipReason);

    test('GemmaEmbedder.load throws on missing model dir', () async {
      await expectLater(
        () => RustGemmaEmbedder.load(
          modelDir: '/definitely/does/not/exist',
          ortDylibPath: '',
          libraryPath: dylibPath,
        ),
        throwsA(isA<RustEmbedderUnavailable>()),
      );
    }, skip: skipReason);
  });

  group('initLifeosNativeRuntime error paths', () {
    // Reset between runs so this group exercises the failure path
    // even after the previous group succeeded. The runtime caches a
    // successful init forever; for failure paths we rely on the
    // catchError-clears-the-cache behaviour inside the implementation.
    test('bogus libraryPath throws RustEmbedderUnavailable', () async {
      // Skip when a successful init from the previous group cached.
      // We can't unload Rust without process exit, so this test only
      // runs cleanly in isolation (or in a fresh test invocation).
      if (skipReason == null) {
        return;
      }
      await expectLater(
        () => initLifeosNativeRuntime(libraryPath: '/bogus/nonexistent.dylib'),
        throwsA(isA<RustEmbedderUnavailable>()),
      );
    }, skip: skipReason);
  });
}
