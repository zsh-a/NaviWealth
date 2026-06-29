import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/app/agent_runtime_catalog.dart';
import 'package:naviwealth/app/agent_runtime_native_bridge.dart';

void main() {
  test(
    'FfiAgentRuntimeNativeBridge initializes once and decodes JSON',
    () async {
      final initCalls = <String?>[];
      final api = _FakeNativeApi();
      final bridge = FfiAgentRuntimeNativeBridge(
        api: api,
        libraryPath: '/tmp/liblifeos_native.dylib',
        initRuntime: ({String? libraryPath}) async {
          initCalls.add(libraryPath);
        },
      );

      expect(await bridge.protocolVersion(), 'agent.v1');
      expect(await bridge.catalogVersion(), 'agent_catalog.v1');

      final summary = await bridge.catalogSummary(const <String, Object?>{
        'protocol_version': 'agent.v1',
        'catalog_version': 'agent_catalog.v1',
        'agents': <Object?>[],
        'tools': <Object?>[],
      });

      expect(summary, containsPair('agent_count', 0));
      final step = await bridge.startRunStep(
        catalog: const <String, Object?>{
          'protocol_version': 'agent.v1',
          'catalog_version': 'agent_catalog.v1',
        },
        request: const <String, Object?>{
          'protocol_version': 'agent.v1',
          'input': <String, Object?>{},
        },
        agentId: 'execution_review',
      );
      expect(step, containsPair('status', 'completed'));
      expect(initCalls, ['/tmp/liblifeos_native.dylib']);
      expect(
        api.catalogPayloads.single,
        contains('"protocol_version":"agent.v1"'),
      );
    },
  );

  test(
    'agentRuntimeNativeCatalogSummaryProvider sends active catalog',
    () async {
      final bridge = _FakeBridge();
      final container = ProviderContainer(
        overrides: [
          agentRuntimeCatalogProvider.overrideWithValue(
            AgentRuntimeCatalog(
              generatedAt: DateTime.utc(2026, 6, 28, 9, 12, 31),
              activeDomains: const <String>['finance'],
              agents: const <AgentRuntimeAgentSpec>[],
              tools: const <AgentRuntimeToolSpec>[],
              proposalKinds: const <AgentRuntimeProposalKindSpec>[],
              promptBlocks: const <AgentRuntimePromptBlockSpec>[],
            ),
          ),
          agentRuntimeNativeBridgeProvider.overrideWithValue(bridge),
        ],
      );
      addTearDown(container.dispose);

      final summary = await container.read(
        agentRuntimeNativeCatalogSummaryProvider.future,
      );

      expect(summary['protocol_version'], 'agent.v1');
      expect(summary['active_domains'], ['finance']);
      expect(bridge.catalogs.single['catalog_version'], 'agent_catalog.v1');
    },
  );
}

class _FakeNativeApi implements AgentRuntimeNativeApi {
  final catalogPayloads = <String>[];

  @override
  Future<String> protocolVersion() async => 'agent.v1';

  @override
  Future<String> catalogVersion() async => 'agent_catalog.v1';

  @override
  Future<String> catalogSummary({required String catalogJson}) async {
    catalogPayloads.add(catalogJson);
    final catalog = jsonDecode(catalogJson) as Map<String, Object?>;
    return jsonEncode(<String, Object?>{
      'protocol_version': catalog['protocol_version'],
      'catalog_version': catalog['catalog_version'],
      'agent_count': (catalog['agents'] as List<Object?>).length,
      'tool_count': (catalog['tools'] as List<Object?>).length,
    });
  }

  @override
  Future<String> validateRunRequest({required String requestJson}) async {
    return requestJson;
  }

  @override
  Future<String> validateToolSpec({required String toolJson}) async {
    return toolJson;
  }

  @override
  Future<String> validateTrace({required String traceJson}) async {
    return traceJson;
  }

  @override
  Future<String> startRunStep({
    required String catalogJson,
    required String requestJson,
    required String agentId,
  }) async {
    final request = jsonDecode(requestJson) as Map<String, Object?>;
    return jsonEncode(<String, Object?>{
      'protocol_version': 'agent.v1',
      'agent_id': agentId,
      'status': request['input'] == null ? 'failed' : 'completed',
    });
  }
}

class _FakeBridge implements AgentRuntimeNativeBridge {
  final catalogs = <Map<String, Object?>>[];

  @override
  Future<String> protocolVersion() async => 'agent.v1';

  @override
  Future<String> catalogVersion() async => 'agent_catalog.v1';

  @override
  Future<Map<String, Object?>> catalogSummary(
    Map<String, Object?> catalog,
  ) async {
    catalogs.add(catalog);
    return <String, Object?>{
      'protocol_version': catalog['protocol_version'],
      'active_domains': catalog['active_domains'],
    };
  }

  @override
  Future<Map<String, Object?>> validateRunRequest(
    Map<String, Object?> request,
  ) async {
    return request;
  }

  @override
  Future<Map<String, Object?>> validateToolSpec(
    Map<String, Object?> tool,
  ) async {
    return tool;
  }

  @override
  Future<Map<String, Object?>> validateTrace(Map<String, Object?> trace) async {
    return trace;
  }

  @override
  Future<Map<String, Object?>> startRunStep({
    required Map<String, Object?> catalog,
    required Map<String, Object?> request,
    required String agentId,
  }) async {
    return <String, Object?>{
      'protocol_version': 'agent.v1',
      'agent_id': agentId,
      'status': 'completed',
    };
  }
}
