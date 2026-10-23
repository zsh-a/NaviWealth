import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/app/domain_packs.dart';
import 'package:naviwealth/core/auth/current_user.dart';
import 'package:naviwealth/core/lifeos/domain_pack.dart';
import 'package:naviwealth/core/persistence/providers.dart';
import 'package:naviwealth/design_system/preferences/theme_preferences.dart';
import 'package:naviwealth/features/finance/ui/settings/finance_settings_page.dart';
import 'package:naviwealth/features/settings/ui/domains_settings_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/persistence/test_database.dart';
import '_golden_setup.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  const profiles = [
    (name: '320', width: 320.0, scale: 1.0),
    (name: '390', width: 390.0, scale: 1.0),
    (name: 'large_text', width: 390.0, scale: 2.0),
  ];
  const pages = [
    (name: 'domains_settings', child: DomainsSettingsPage()),
    (name: 'finance_settings', child: FinanceSettingsPage()),
  ];
  for (final page in pages) {
    for (final profile in profiles) {
      testVisualGolden('${page.name} — ${profile.name}', (tester) async {
        final prefs = await SharedPreferences.getInstance();
        final database = makeTestDatabase();
        addTearDown(database.close);
        await pumpAndSnapshotResponsive(
          tester,
          name: '${page.name}_${profile.name}',
          profile: ResponsiveGoldenProfile.narrow,
          logicalSizeOverride: Size(profile.width, 844),
          textScalerOverride: TextScaler.linear(profile.scale),
          overrides: [
            appDatabaseProvider.overrideWith((_) async => database),
            sharedPreferencesProvider.overrideWithValue(prefs),
            currentUserIdProvider.overrideWithValue(
              () async => kLocalOnlyUserId,
            ),
            domainPackRegistryProvider.overrideWithValue(kAllDomainPacks),
          ],
          child: page.child,
        );
        if (page.child is DomainsSettingsPage) {
          for (final label in [
            'FinanceOS',
            'HealthOS',
            'KnowledgeOS',
            'ExecutionOS',
          ]) {
            expect(find.text(label).hitTestable(), findsOneWidget);
          }
        }
      }, tags: const ['golden', 'responsive-golden']);
    }
  }
}
