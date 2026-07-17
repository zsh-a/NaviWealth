import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/auth/domain_scope.dart';
import 'package:naviwealth/core/auth/providers.dart' as auth;
import 'package:naviwealth/features/settings/ui/domains_settings_page.dart';

import 'support/app_harness.dart';
import 'support/page_objects.dart';

void main() {
  testWidgets('Task: Enable optional domain user enables KnowledgeOS', (
    tester,
  ) async {
    await bootApp(tester);
    final shell = AppShell(tester)..expectMounted();
    await shell.openSettings();

    final settings = SettingsPageObject(tester)..expectLanded();
    await settings.openDomains();
    final domains = DomainsPageObject(tester)..expectLanded();
    await domains.enable('KnowledgeOS');

    final container = ProviderScope.containerOf(
      tester.element(find.byType(DomainsSettingsPage)),
    );
    expect(
      container
          .read(auth.domainOptInsProvider)
          .requireValue
          .contains(DomainScope.knowledge),
      isTrue,
    );
    expect(
      find.text(
        'Inbox, Library, Review, AI tools, and Memory indexing are enabled',
      ),
      findsOneWidget,
    );
    await closeApp(tester);
  }, tags: 'flow');
}
