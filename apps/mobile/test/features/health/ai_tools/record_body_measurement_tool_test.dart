import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/app/tool_descriptor_catalog.dart';
import 'package:naviwealth/core/ai/contracts/intent.dart';
import 'package:naviwealth/core/ai/contracts/tool_descriptor.dart';
import 'package:naviwealth/core/ai/runtime/device/anthropic/anthropic_wire.dart';
import 'package:naviwealth/core/ai/runtime/device/device_session.dart';
import 'package:naviwealth/core/ai/runtime/device/tools/device_tool.dart';
import 'package:naviwealth/core/persistence/app_database.dart';
import 'package:naviwealth/core/persistence/providers.dart';
import 'package:naviwealth/core/sync/drift_sync_storage.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/core/sync/mutation_context.dart';
import 'package:naviwealth/core/sync/outbox_provider.dart';
import 'package:naviwealth/features/health/ai_tools/record_body_measurement_tool.dart';
import 'package:naviwealth/features/health/data/providers.dart';
import 'package:naviwealth/features/health/domain/health_metric_kind.dart';

import '../../../core/persistence/test_database.dart';

const _owner = 'u-ai';
const _device = 'dev-ai';

MutationStamper _fakeStamper({int startMillis = 1_700_000_000_000}) {
  var counter = 0;
  return MutationStamper(
    currentUserId: () async => _owner,
    deviceId: () async => _device,
    stampHlc: () async =>
        Hlc(wallMillis: startMillis + counter++, counter: 0, nodeId: _device),
  );
}

Future<T> _withRef<T>(ProviderContainer c, Future<T> Function(Ref ref) body) {
  final probe = FutureProvider<T>((ref) => body(ref));
  c.listen(probe, (_, _) {});
  return c.read(probe.future);
}

Future<Map<String, Object?>> _invoke(
  ProviderContainer container,
  Map<String, Object?> input,
) {
  const tool = RecordBodyMeasurementTool();
  return _withRef(container, (ref) async {
    final out = await tool.invoke(
      DeviceToolContext(
        ref: ref,
        session: DeviceSession(messages: const <AnthropicChatMessage>[]),
      ),
      input,
    );
    return (out! as Map).cast<String, Object?>();
  });
}

void main() {
  group('RecordBodyMeasurementTool', () {
    late AppDatabase db;
    late InMemoryOutboxStore outbox;
    late ProviderContainer container;

    setUp(() {
      db = makeTestDatabase();
      outbox = InMemoryOutboxStore();
      container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWith((ref) async => db),
          outboxStoreProvider.overrideWith((ref) async => outbox),
          mutationStamperProvider.overrideWith((ref) async => _fakeStamper()),
        ],
      );
    });

    tearDown(() async {
      container.dispose();
      await db.close();
    });

    test('descriptor requires confirmation for local write', () {
      const tool = RecordBodyMeasurementTool();
      expect(tool.name, 'record_body_measurement');
      expect(tool.inputSchema['required'], <String>['kind', 'value']);
      final d = lookupToolDescriptor('record_body_measurement');
      expect(d, isNotNull);
      expect(d!.access, Access.propose);
      expect(d.risk, RiskLevel.commit);
      expect(d.requiresConfirmation, Confirmation.oneTap);
      expect(d.sideEffect, SideEffect.deviceLocalWrite);
      expect(d.domain, kDomainHealth);
    });

    test('records AI body fat as canonical health metric', () async {
      final out = await _invoke(container, const {
        'kind': 'body_fat',
        'value': 18.5,
        'date_iso': '2026-05-30',
        'note': 'morning scale',
      });

      expect(out['ok'], isTrue);
      expect(out['id'], 'manual:body_fat:$_owner:2026-05-30');
      expect(out['kind'], 'body_fat');
      expect(out['value'], closeTo(0.185, 1e-9));
      expect(out['unit'], 'fraction');
      expect(out['source'], 'ai');

      final repo = await container.read(healthMetricRepositoryProvider.future);
      final row = await repo.findById('manual:body_fat:$_owner:2026-05-30');
      expect(row, isNotNull);
      expect(row!.kind, HealthMetricKind.bodyFat);
      expect(row.sourceDevice, 'ai');
      expect(row.payloadJson, contains('morning scale'));
      expect(await outbox.depth(), 1);
    });

    test('rejects invalid body fat value', () async {
      final out = await _invoke(container, const {
        'kind': 'body_fat',
        'value': 118,
      });

      expect(out['code'], 'bad_request');
      expect(await outbox.depth(), 0);
    });
  });
}
