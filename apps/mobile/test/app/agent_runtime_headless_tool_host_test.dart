import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/app/agent_runtime/catalog/agent_runtime_catalog.dart';
import 'package:naviwealth/app/agent_runtime/tools/agent_runtime_headless_tool_host.dart';
import 'package:naviwealth/app/domain_packs.dart';
import 'package:naviwealth/core/auth/domain_scope.dart';
import 'package:naviwealth/core/auth/providers.dart' as auth;
import 'package:naviwealth/core/lifeos/domain_pack.dart';

void main() {
  test('parseHeadlessDomains supports finance, lists, and all', () {
    expect(parseHeadlessDomains(null), [DomainScope.finance]);
    expect(parseHeadlessDomains('finance'), [DomainScope.finance]);
    expect(parseHeadlessDomains('knowledge,execution'), [
      DomainScope.finance,
      DomainScope.knowledge,
      DomainScope.execution,
    ]);
    final productionDomains = [for (final pack in kAllDomainPacks) pack.scope];
    expect(parseHeadlessDomains('all'), productionDomains);
    expect(
      () => parseHeadlessDomains('finance,unknown'),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('headless host dispatches through the production tool graph', () async {
    final headless = await createAgentRuntimeHeadlessToolHost(
      domains: parseHeadlessDomains('all'),
    );
    addTearDown(headless.dispose);

    final responseLine = await headless.host.handleLine(
      jsonEncode(<String, Object?>{
        'jsonrpc': '2.0',
        'id': 'decision',
        'method': 'tool.call',
        'params': <String, Object?>{
          'name': 'ask_user',
          'input': <String, Object?>{
            'title': 'Pick a runtime path',
            'options': <Object?>[
              <String, Object?>{'label': 'Embedded'},
              <String, Object?>{'label': 'Process'},
            ],
          },
        },
      }),
    );

    final response = jsonDecode(responseLine) as Map<String, Object?>;
    final result = response['result'] as Map<String, Object?>;
    expect(response['id'], 'decision');
    expect(result['type'], 'decision_request');
    expect(result['awaiting_user'], true);
  });

  test(
    'headless composition derives registry and catalog from active packs',
    () async {
      final headless = await createAgentRuntimeHeadlessToolHost(
        domains: parseHeadlessDomains('knowledge,execution'),
      );
      addTearDown(headless.dispose);

      const expectedScopes = <DomainScope>[
        DomainScope.finance,
        DomainScope.knowledge,
        DomainScope.execution,
      ];
      expect(
        headless.container
            .read(domainPackRegistryProvider)
            .map((pack) => pack.scope),
        expectedScopes,
      );
      expect(
        headless.container
            .read(activeDomainPacksProvider)
            .map((pack) => pack.scope),
        expectedScopes,
      );
      expect(
        headless.container.read(auth.authTokenDomainsProvider),
        expectedScopes.map((scope) => scope.wire).toList()..sort(),
      );
      expect(
        headless.container.read(agentRuntimeCatalogProvider).activeDomains,
        expectedScopes.map((scope) => scope.wire),
      );
    },
  );
}
