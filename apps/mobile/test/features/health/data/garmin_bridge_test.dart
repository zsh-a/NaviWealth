import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/features/health/data/garmin/garmin_bridge.dart';
import 'package:naviwealth/src/rust/api/health.dart' as rust;

void main() {
  test('cold-start sync initializes lifeos_native before Garmin API', () async {
    final events = <String>[];
    String? initializedPath;
    final nativeApi = _FakeGarminNativeApi(events);
    final bridge = GarminBridge(
      nativeApi: nativeApi,
      libraryPath: '/native/lifeos',
      initRuntime: ({String? libraryPath}) async {
        initializedPath = libraryPath;
        events.add('runtime.init');
      },
    );

    await bridge
        .syncRangeWithProgress(
          DateTime.utc(2026, 8, 1),
          DateTime.utc(2026, 8, 2),
        )
        .toList();

    expect(initializedPath, '/native/lifeos');
    expect(events, ['runtime.init', 'garmin.syncRangeWithProgress']);
  });

  test('concurrent Garmin calls share runtime initialization', () async {
    final gate = Completer<void>();
    var initCount = 0;
    final events = <String>[];
    final bridge = GarminBridge(
      nativeApi: _FakeGarminNativeApi(events),
      initRuntime: ({String? libraryPath}) {
        initCount += 1;
        return gate.future;
      },
    );

    final authState = bridge.authState();
    final cursors = bridge.syncCursors();
    await Future<void>.delayed(Duration.zero);

    expect(initCount, 1);
    expect(events, isEmpty);

    gate.complete();
    await Future.wait<Object?>([authState, cursors]);

    expect(events, ['garmin.authState', 'garmin.syncCursors']);
  });

  test('Garmin bridge retries after runtime initialization failure', () async {
    var initCount = 0;
    final events = <String>[];
    final bridge = GarminBridge(
      nativeApi: _FakeGarminNativeApi(events),
      initRuntime: ({String? libraryPath}) async {
        initCount += 1;
        if (initCount == 1) throw StateError('native runtime unavailable');
      },
    );

    await expectLater(bridge.authState(), throwsStateError);
    expect(events, isEmpty);

    final state = await bridge.authState();

    expect(state, GarminAuthState.unauthenticated);
    expect(initCount, 2);
    expect(events, ['garmin.authState']);
  });
}

final class _FakeGarminNativeApi implements GarminNativeApi {
  _FakeGarminNativeApi(this.events);

  final List<String> events;

  @override
  Future<Object?> initialize({
    String? storedTokenJson,
    required bool isCn,
  }) async {
    events.add('garmin.initialize');
    return '"Unauthenticated"';
  }

  @override
  Future<Object?> authenticate({
    required String email,
    required String password,
  }) async {
    events.add('garmin.authenticate');
    return '{"result":"Authenticated","state":{"Authenticated":null}}';
  }

  @override
  Future<Object?> submitMfa({required String code}) async {
    events.add('garmin.submitMfa');
    return '{"result":"Authenticated","state":{"Authenticated":null}}';
  }

  @override
  Future<Object?> authState() async {
    events.add('garmin.authState');
    return '"Unauthenticated"';
  }

  @override
  Future<Object?> syncRange({required String from, required String to}) async {
    events.add('garmin.syncRange');
    return '[]';
  }

  @override
  Stream<rust.GarminSyncProgress> syncRangeWithProgress({
    required String from,
    required String to,
  }) {
    events.add('garmin.syncRangeWithProgress');
    return const Stream<rust.GarminSyncProgress>.empty();
  }

  @override
  Future<void> cancelSync() async {
    events.add('garmin.cancelSync');
  }

  @override
  Future<Object?> syncCursors() async {
    events.add('garmin.syncCursors');
    return '{}';
  }

  @override
  Future<void> logout() async {
    events.add('garmin.logout');
  }

  @override
  Future<Object?> exportSession() async {
    events.add('garmin.exportSession');
    return null;
  }
}
