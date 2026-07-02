import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/app/agent_runtime/agent_runtime_headless_tool_host.dart';
import 'package:naviwealth/app/domain_packs.dart';
import 'package:naviwealth/core/auth/domain_scope.dart';

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
}
