import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/app/production_ai_catalog.dart';
import 'package:naviwealth/core/ai/contracts/interaction.dart';
import 'package:naviwealth/core/ai/contracts/memory_candidate.dart';
import 'package:naviwealth/core/ai/contracts/tool_descriptor.dart';
import 'package:naviwealth/core/ai/local/embedding/embedder.dart';
import 'package:naviwealth/core/ai/local/memory/event_store.dart';
import 'package:naviwealth/core/ai/local/memory/memory_candidate_store.dart';
import 'package:naviwealth/core/ai/local/memory/memory_runtime.dart';
import 'package:naviwealth/core/ai/local/memory/memory_store.dart';
import 'package:naviwealth/core/ai/local/memory/providers.dart';
import 'package:naviwealth/core/ai/runtime/device/device_tool_session.dart';
import 'package:naviwealth/core/ai/runtime/device/tools/device_tool.dart';
import 'package:naviwealth/core/ai/runtime/device/tools/propose_memory_tool.dart';
import 'package:naviwealth/core/auth/auth_session.dart';
import 'package:naviwealth/core/auth/providers.dart';
import 'package:naviwealth/core/persistence/app_database.dart';

import '../../../../../core/persistence/test_database.dart';

const _owner = 'user-1';

void main() {
  group('ProposeMemoryTool', () {
    late AppDatabase db;
    late MemoryRuntime runtime;
    late SqliteMemoryCandidateStore candidateStore;
    late ProviderContainer container;

    setUp(() {
      db = makeTestDatabase();
      runtime = MemoryRuntime(
        embedder: StubEmbedder(),
        memoryStore: SqliteMemoryStore(db: db),
        eventStore: SqliteEventStore(db: db),
      );
      candidateStore = SqliteMemoryCandidateStore(db: db);
      container = ProviderContainer(
        overrides: [
          authSessionProvider.overrideWithValue(
            AuthSession(
              accessToken: '',
              userId: _owner,
              deviceId: 'device-1',
              expiresAt: DateTime.utc(2100),
            ),
          ),
          memoryRuntimeProvider.overrideWith((ref) async => runtime),
          memoryCandidateStoreProvider.overrideWith(
            (ref) async => candidateStore,
          ),
        ],
      );
    });

    tearDown(() async {
      container.dispose();
      await db.close();
    });

    test('descriptor requires a confirmed local proposal', () {
      final descriptor = productionToolDescriptors['propose_memory'];
      expect(descriptor, isNotNull);
      expect(descriptor?.access, Access.propose);
      expect(descriptor?.requiresConfirmation, Confirmation.oneTap);
      expect(descriptor?.sideEffect, SideEffect.deviceLocalWrite);
    });

    test('stages candidate but does not write formal memory', () async {
      final output = await _invoke(container, const <String, Object?>{
        'operation': 'create',
        'memory_kind': 'semantic',
        'title': '本地优先',
        'summary': '用户明确偏好本地优先。',
        'scope': '*',
        'entities': <String>['local-first'],
        'payload': <String, Object?>{'statement': 'local first'},
        'importance': 0.9,
        'reason': '这是一项长期偏好',
      });

      expect(output['status'], 'ready');
      expect(output['kind'], 'memory_change');
      final interaction = AiInteractionEnvelope.tryParse(output['interaction']);
      expect(interaction?.kind, AiInteractionKind.approval);
      expect(interaction?.mode, AiInteractionMode.confirmDiff);
      expect(interaction?.resumeKind, AiInteractionResumeKind.proposalApply);
      final payload = (output['payload']! as Map).cast<String, Object?>();
      final candidate = await candidateStore.findById(
        ownerUserId: _owner,
        candidateId: payload['candidate_id']! as String,
      );
      expect(candidate?.status, MemoryCandidateStatus.pending);
      expect(candidate?.proposalId, output['proposal_id']);
      expect(
        await runtime.memoryStore.readMemory(payload['memory_id']! as String),
        isNull,
      );
    });

    test('forget requires an owned memory id', () async {
      final output = await _invoke(container, const <String, Object?>{
        'operation': 'forget',
        'target_memory_id': 'missing',
        'reason': '用户要求忘记',
      });

      expect(output['code'], 'not_found');
      expect(await candidateStore.listPending(_owner), isEmpty);
    });
  });
}

Future<Map<String, Object?>> _invoke(
  ProviderContainer container,
  Map<String, Object?> input,
) {
  final probe = FutureProvider<Map<String, Object?>>((ref) async {
    final output = await const ProposeMemoryTool().invoke(
      DeviceToolContext(ref: ref, session: const DeviceToolSession()),
      input,
    );
    return (output! as Map).cast<String, Object?>();
  });
  container.listen(probe, (_, _) {});
  return container.read(probe.future);
}
