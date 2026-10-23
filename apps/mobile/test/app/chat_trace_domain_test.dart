import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/app/agent_runtime/overrides/agent_runtime_app_overrides.dart';
import 'package:naviwealth/core/ai/composition/ai_context.dart';
import 'package:naviwealth/core/ai/composition/chat_trace_prep.dart';
import 'package:naviwealth/core/ai/contracts/ai_domain.dart';
import 'package:naviwealth/core/ai/llm_credentials/providers.dart' as llm;
import 'package:naviwealth/design_system/preferences/theme_preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  for (final scope in <DomainScope?>[...DomainScope.values, null]) {
    test(
      'chat trace follows ${scope?.wire ?? 'global'} context ownership',
      () async {
        SharedPreferences.setMockInitialValues({});
        final container = ProviderContainer(
          overrides: [
            ...agentRuntimeAppProviderOverrides(),
            aiContextProvider.overrideWith(
              (_) => AiContext(
                path: scope == null ? '/life' : '/${scope.wire}/today',
                domain: scope,
              ),
            ),
            llm.deviceLlmAvailableProvider.overrideWithValue(false),
            sharedPreferencesProvider.overrideWithValue(
              await SharedPreferences.getInstance(),
            ),
          ],
        );
        addTearDown(container.dispose);
        final result = await container.read(chatTracePrepProvider)!(
          requestId: 'domain-turn',
          userMessage: 'question',
        );
        expect(result.traceSeed!.intent.domain, AiDomain.fromScope(scope));
        expect(
          result.traceSeed!.intent.toJson()['domain'],
          scope?.wire ?? 'global',
        );
      },
    );
  }
}
