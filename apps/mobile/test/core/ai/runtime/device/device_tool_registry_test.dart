import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/ai/composition/tool_descriptor_lookup.dart';
import 'package:naviwealth/core/ai/contracts/intent.dart';
import 'package:naviwealth/core/ai/contracts/privacy_budget.dart';
import 'package:naviwealth/core/ai/contracts/tool_descriptor.dart';
import 'package:naviwealth/core/ai/runtime/device/device_session.dart';
import 'package:naviwealth/core/ai/runtime/device/tools/device_tool.dart';
import 'package:naviwealth/core/ai/runtime/device/tools/device_tool_registry.dart';

DeviceSession _session() => DeviceSession(messages: []);

class _EchoTool implements DeviceTool {
  const _EchoTool(this.name);

  @override
  final String name;

  @override
  String get description => 'Echo $name';

  @override
  Map<String, Object?> get inputSchema => const {'type': 'object'};

  @override
  Future<Object?> invoke(DeviceToolContext ctx, Map<String, Object?> input) {
    return Future<Object?>.value(input);
  }
}

class _ThrowingTool implements DeviceTool {
  @override
  String get name => 'boom';

  @override
  String get description => 'Throws';

  @override
  Map<String, Object?> get inputSchema => const {'type': 'object'};

  @override
  Future<Object?> invoke(DeviceToolContext ctx, Map<String, Object?> input) {
    throw StateError('kaboom');
  }
}

class _SlowTool implements DeviceTool {
  @override
  String get name => 'slow';

  @override
  String get description => 'Slow';

  @override
  Map<String, Object?> get inputSchema => const {'type': 'object'};

  @override
  Future<Object?> invoke(
    DeviceToolContext ctx,
    Map<String, Object?> input,
  ) async {
    await Future<void>.delayed(const Duration(seconds: 1));
    return {'ok': true};
  }
}

Future<T> _withRef<T>(ProviderContainer c, Future<T> Function(Ref ref) body) {
  final probe = FutureProvider<T>((ref) => body(ref));
  c.listen(probe, (_, _) {});
  return c.read(probe.future);
}

void main() {
  group('DeviceToolRegistry', () {
    test('schemas are sorted and lookup resolves by name', () {
      final reg = DeviceToolRegistry(const [
        _EchoTool('z_tool'),
        _EchoTool('a_tool'),
      ]);

      expect(reg.schemas().map((s) => s.name), ['a_tool', 'z_tool']);
      expect(reg.lookup('a_tool'), isNotNull);
      expect(reg.lookup('missing'), isNull);
    });
  });

  group('DriftDeviceToolDispatcher error envelopes', () {
    test(
      'descriptor proposal authority does not depend on tool prefix',
      () async {
        const descriptor = ToolDescriptor(
          name: 'queue_work',
          access: Access.propose,
          risk: RiskLevel.propose,
          requiresConfirmation: Confirmation.oneTap,
          allowedContextTier: BudgetTier.small,
          sideEffect: SideEffect.deviceLocalWrite,
        );
        final c = ProviderContainer(
          overrides: [
            toolDescriptorLookupProvider.overrideWith(
              (ref) =>
                  (name) => name == descriptor.name ? descriptor : null,
            ),
          ],
        );
        addTearDown(c.dispose);

        final out = await _withRef(
          c,
          (ref) => DriftDeviceToolDispatcher(
            ref: ref,
            registry: DeviceToolRegistry(const [_EchoTool('queue_work')]),
          ).dispatch(_session(), 'queue_work', const {'value': 1}),
        );

        expect(out, const <String, Object?>{'value': 1});
      },
    );

    test('a propose prefix cannot bypass descriptor write policy', () async {
      const descriptor = ToolDescriptor(
        name: 'propose_unsafe',
        access: Access.read,
        risk: RiskLevel.info,
        requiresConfirmation: Confirmation.oneTap,
        allowedContextTier: BudgetTier.small,
        sideEffect: SideEffect.deviceLocalWrite,
      );
      final c = ProviderContainer(
        overrides: [
          toolDescriptorLookupProvider.overrideWith(
            (ref) =>
                (name) => name == descriptor.name ? descriptor : null,
          ),
        ],
      );
      addTearDown(c.dispose);

      final out = await _withRef(
        c,
        (ref) => DriftDeviceToolDispatcher(
          ref: ref,
          registry: DeviceToolRegistry(const [_EchoTool('propose_unsafe')]),
        ).dispatch(_session(), 'propose_unsafe', const {}),
      );

      final result = out! as Map;
      expect(result['policy_denied'], true);
      expect((result['error'] as Map)['policy'], 'confirmation_required');
    });

    test('unknown tool returns policy_denied envelope', () async {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final out = await _withRef(
        c,
        (ref) => DriftDeviceToolDispatcher(
          ref: ref,
          registry: DeviceToolRegistry(const []),
        ).dispatch(_session(), 'ghost', const {}),
      );

      final m = out! as Map;
      expect(m['policy_denied'], true);
      expect((m['error'] as Map)['code'], 'policy_denied');
      expect((m['error'] as Map)['policy'], 'unknown_tool');
      expect((m['error'] as Map)['tool'], 'ghost');
    });

    test('throwing tool returns tool_error', () async {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final out = await _withRef(
        c,
        (ref) => DriftDeviceToolDispatcher(
          ref: ref,
          registry: DeviceToolRegistry([_ThrowingTool()]),
        ).dispatch(_session(), 'boom', const {}),
      );

      final m = out! as Map;
      expect(m['code'], 'tool_error');
      expect(m['error'], contains('kaboom'));
    });

    test('slow tool returns tool_timeout', () async {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final out = await _withRef(
        c,
        (ref) => DriftDeviceToolDispatcher(
          ref: ref,
          registry: DeviceToolRegistry([_SlowTool()]),
          perToolTimeout: const Duration(milliseconds: 20),
        ).dispatch(_session(), 'slow', const {}),
      );

      final m = out! as Map;
      expect(m['code'], 'tool_timeout');
      expect(m['tool'], 'slow');
      expect(m['error'], contains('timed out after 20ms'));
    });
  });
}
