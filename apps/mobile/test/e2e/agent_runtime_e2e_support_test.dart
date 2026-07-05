import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/ai/contracts/contracts.dart';
import 'package:naviwealth/core/ai/runtime/device/tools/device_tool.dart';
import 'package:naviwealth/core/auth/domain_scope.dart';
import 'package:naviwealth/core/lifeos/domain_pack.dart';

import 'agent_runtime_e2e_support.dart';

void main() {
  group('RealLlmE2eConfig', () {
    test(
      'keeps provider-backed E2E disabled unless flag and key are present',
      () {
        final disabled = RealLlmE2eConfig.fromMap(const <String, String>{});
        expect(disabled.enabled, false);
        expect(disabled.notEnabledReason, 'RUN_REAL_LLM_E2E is not enabled');

        final missingKey = RealLlmE2eConfig.fromMap(const <String, String>{
          'RUN_REAL_LLM_E2E': 'yes',
        });
        expect(missingKey.enabled, false);
        expect(missingKey.notEnabledReason, 'E2E_LLM_API_KEY is empty');
      },
    );

    test('reads provider profile and bounded runtime options from env', () {
      final config = RealLlmE2eConfig.fromMap(const <String, String>{
        'RUN_REAL_LLM_E2E': 'true',
        'E2E_LLM_API_KEY': 'test-key',
        'E2E_LLM_PROVIDER': 'openai',
        'E2E_LLM_MODEL': ' gpt-test ',
        'E2E_LLM_BASE_URL': ' https://example.test/v1 ',
        'RUST_EMBEDDER_LIBRARY_PATH': '/tmp/native.dylib',
        'E2E_LLM_MAX_TOOL_ROUNDS': '5',
        'E2E_LLM_TIMEOUT_SECONDS': '45',
      });

      expect(config.enabled, true);
      expect(config.provider.wire, 'openai');
      expect(config.model, 'gpt-test');
      expect(config.baseUrl, 'https://example.test/v1');
      expect(config.nativeLibraryPath, '/tmp/native.dylib');
      expect(config.maxToolRounds, 5);
      expect(config.timeout, const Duration(seconds: 45));
      expect(config.profile.apiKey, 'test-key');
    });
  });

  group('domainPackE2eToolSpecs', () {
    test('exports selected tools with DomainPack descriptor metadata', () {
      final specs = domainPackE2eToolSpecs(
        packs: [
          _pack(
            DomainScope.finance,
            const _FakeTool('get_budget'),
            domain: 'finance',
          ),
          _pack(
            DomainScope.execution,
            const _FakeTool('propose_action'),
            domain: 'execution',
            access: Access.propose,
            confirmation: Confirmation.oneTap,
          ),
        ],
        selectedNames: const <String>{'propose_action'},
      );

      expect(specs, hasLength(1));
      expect(specs.single['name'], 'propose_action');
      expect(specs.single['risk'], 'medium');
      final metadata = specs.single['metadata'] as Map<String, Object?>;
      expect(metadata['domain'], 'execution');
      expect(metadata['access'], 'propose');
      expect(metadata['requires_confirmation'], 'one_tap');
    });

    test('fails fast when a selected tool is not in the packs', () {
      expect(
        () => domainPackE2eToolSpecs(
          packs: [_pack(DomainScope.finance, const _FakeTool('get_budget'))],
          selectedNames: const <String>{'missing_tool'},
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('missing_tool'),
          ),
        ),
      );
    });

    test('fails fast when packs expose duplicate selected tool names', () {
      expect(
        () => domainPackE2eToolSpecs(
          packs: [
            _pack(DomainScope.finance, const _FakeTool('shared_tool')),
            _pack(DomainScope.execution, const _FakeTool('shared_tool')),
          ],
          selectedNames: const <String>{'shared_tool'},
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('Duplicate DomainPack E2E tools: shared_tool'),
          ),
        ),
      );
    });
  });
}

DomainPack _pack(
  DomainScope scope,
  DeviceTool tool, {
  String domain = 'finance',
  Access access = Access.read,
  Confirmation confirmation = Confirmation.none,
}) {
  return DomainPack(
    scope: scope,
    deviceTools: [tool],
    toolDescriptors: <String, ToolDescriptor>{
      tool.name: ToolDescriptor(
        name: tool.name,
        access: access,
        risk: access == Access.propose ? RiskLevel.propose : RiskLevel.info,
        requiresConfirmation: confirmation,
        allowedContextTier: BudgetTier.small,
        domain: domain,
      ),
    },
  );
}

final class _FakeTool implements DeviceTool {
  const _FakeTool(this.name);

  @override
  final String name;

  @override
  String get description => 'Fake E2E tool';

  @override
  Map<String, Object?> get inputSchema => const <String, Object?>{
    'type': 'object',
  };

  @override
  Future<Object?> invoke(
    DeviceToolContext ctx,
    Map<String, Object?> input,
  ) async {
    return const <String, Object?>{'ok': true};
  }
}
