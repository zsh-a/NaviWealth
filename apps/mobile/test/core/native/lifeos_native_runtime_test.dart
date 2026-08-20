import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/native/lifeos_native_runtime.dart';

void main() {
  test('concurrent callers share the first native initialization', () async {
    final gate = Completer<void>();
    final paths = <String?>[];
    final runtime = LifeosNativeRuntime(
      loader: ({String? libraryPath}) {
        paths.add(libraryPath);
        return gate.future;
      },
    );

    final first = runtime.initialize(libraryPath: '/native/first');
    final second = runtime.initialize(libraryPath: '/native/second');

    expect(identical(first, second), isTrue);
    expect(paths, ['/native/first']);

    gate.complete();
    await Future.wait([first, second]);
    await runtime.initialize(libraryPath: '/native/third');

    expect(paths, ['/native/first']);
  });

  test('failed native initialization can be retried', () async {
    var attempts = 0;
    final runtime = LifeosNativeRuntime(
      loader: ({String? libraryPath}) async {
        attempts += 1;
        if (attempts == 1) throw StateError('native library unavailable');
      },
    );

    await expectLater(runtime.initialize(), throwsStateError);
    await runtime.initialize();

    expect(attempts, 2);
  });
}
