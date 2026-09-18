import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/ai/runtime/device/device_tool_session.dart';
import 'package:naviwealth/core/ai/runtime/device/tools/device_tool.dart';
import 'package:naviwealth/core/ai/runtime/device/tools/device_tool_registry.dart';

void main() {
  test(
    'readAsync waits for loading, accepts null and releases its listener',
    () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final events = StreamController<int?>();
      addTearDown(events.close);
      var disposed = false;
      final data = StreamProvider.autoDispose<int?>((ref) {
        ref.onDispose(() => disposed = true);
        return events.stream;
      });
      final probe = FutureProvider((ref) async {
        final ctx = DeviceToolContext(
          ref: ref,
          session: const DeviceToolSession(),
        );
        try {
          return await ctx.readAsync(data);
        } finally {
          ctx.dispose();
        }
      });
      var completed = false;
      final result = container.read(probe.future).then((value) {
        completed = true;
        return value;
      });
      await container.pump();
      expect(completed, isFalse);
      events.add(null);
      expect(await result, isNull);
      await container.pump();
      expect(disposed, isTrue);
    },
  );

  test('readAsync preserves the underlying error', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final error = StateError('database_unavailable');
    final data = Provider<AsyncValue<int>>(
      (_) => AsyncError(error, StackTrace.current),
    );
    final probe = FutureProvider((ref) async {
      final ctx = DeviceToolContext(
        ref: ref,
        session: const DeviceToolSession(),
      );
      try {
        return await ctx.readAsync(data);
      } finally {
        ctx.dispose();
      }
    });
    await expectLater(container.read(probe.future), throwsA(same(error)));
  });

  test(
    'readAsync captures a synchronous projection failure without a zone error',
    () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final data = Provider<AsyncValue<int>>(
        (_) => throw StateError('projection_failed'),
      );
      final probe = FutureProvider((ref) async {
        final ctx = DeviceToolContext(
          ref: ref,
          session: const DeviceToolSession(),
        );
        try {
          return await ctx.readAsync(data);
        } finally {
          ctx.dispose();
        }
      });
      await expectLater(
        container.read(probe.future),
        throwsA(
          predicate<Object>(
            (error) => error.toString().contains('projection_failed'),
          ),
        ),
      );
    },
  );

  test('readAsync does not return stale data during a refresh', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final ready = Completer<int>();
    var calls = 0;
    final data = FutureProvider<int>(
      (_) => calls++ == 0 ? Future.value(1) : ready.future,
    );
    container.listen(data, (_, _) {});
    expect(await container.read(data.future), 1);
    container.invalidate(data);
    final probe = Provider(
      (ref) => DeviceToolContext(ref: ref, session: const DeviceToolSession()),
    );
    final ctx = container.read(probe);
    final pending = ctx.readAsync(data);
    var completed = false;
    unawaited(pending.then((_) => completed = true));
    await container.pump();
    expect(completed, isFalse);
    ready.complete(2);
    expect(await pending, 2);
    ctx.dispose();
  });

  test(
    'one-shot cold stream stays alive until its first value then releases',
    () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      var disposed = false;
      final data = StreamProvider.autoDispose<int>((ref) async* {
        ref.onDispose(() => disposed = true);
        await Future<void>.delayed(const Duration(milliseconds: 30));
        yield 42;
      });
      final probe = FutureProvider((ref) async {
        final ctx = DeviceToolContext(
          ref: ref,
          session: const DeviceToolSession(),
        );
        try {
          return await ctx.readFuture(data.future);
        } finally {
          ctx.dispose();
        }
      });
      expect(await container.read(probe.future), 42);
      await container.pump();
      expect(disposed, isTrue);
    },
  );

  test('dispatcher timeout releases a pending stream subscription', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    var disposed = false;
    final stream = StreamController<int>();
    addTearDown(stream.close);
    final data = StreamProvider.autoDispose<int>((ref) {
      ref.onDispose(() => disposed = true);
      return stream.stream;
    });
    final probe = FutureProvider(
      (ref) => DriftDeviceToolDispatcher(
        ref: ref,
        registry: DeviceToolRegistry([_ReadTool(data)]),
        perToolTimeout: const Duration(milliseconds: 30),
      ).dispatch(const DeviceToolSession(), 'cold_read', {}),
    );
    final result = await container.read(probe.future) as Map;
    expect(result['code'], 'tool_timeout');
    await container.pump();
    expect(disposed, isTrue);
  });
}

class _ReadTool implements DeviceTool {
  _ReadTool(this.provider);
  final StreamProvider<int> provider;
  @override
  String get name => 'cold_read';
  @override
  String get description => 'Read';
  @override
  Map<String, Object?> get inputSchema => {'type': 'object'};
  @override
  Future<Object?> invoke(DeviceToolContext ctx, Map<String, Object?> input) =>
      ctx.readFuture(provider.future);
}
