import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/core/ai/contracts/context_evidence.dart';
import 'package:naviwealth/core/auth/current_user.dart';
import 'package:naviwealth/core/lifeos/personal_profile/personal_profile_fact.dart';
import 'package:naviwealth/core/lifeos/personal_profile/personal_profile_store.dart';
import 'package:naviwealth/core/lifeos/personal_profile/providers.dart';
import 'package:naviwealth/features/settings/ui/ai/personal_memory_page.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

import '../../core/persistence/test_database.dart';

void main() {
  testWidgets('shows current facts and marks inactive-domain facts', (
    tester,
  ) async {
    final db = makeTestDatabase();
    addTearDown(db.close);
    final store = SqlitePersonalProfileStore(db);
    final now = DateTime.now().toUtc();
    await store.create(
      PersonalProfileFact(
        id: 'health-sleep-goal',
        ownerUserId: 'user-1',
        kind: PersonalProfileFactKind.goal,
        key: 'sleep_hours',
        value: 8,
        summary: 'Sleep eight hours.',
        domainScope: 'health',
        authority: EvidenceAuthority.userConfirmed,
        provenance: EvidenceProvenance(
          source: 'settings_profile',
          observedAt: now,
        ),
        confidence: 1,
        confirmedAt: now,
        validFrom: now,
        createdAt: now,
        updatedAt: now,
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentUserIdProvider.overrideWithValue(() async => 'user-1'),
          personalProfileStoreProvider.overrideWith((ref) async => store),
          activePersonalProfileDomainScopesProvider.overrideWith(
            (ref) => const <String>{'finance'},
          ),
        ],
        child: MaterialApp(
          theme: ThemeData.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: FTheme(
            data: FTheme.neutral.light.desktop,
            child: const PersonalMemoryPage(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Personal memory'), findsOneWidget);
    expect(find.text('Sleep eight hours.'), findsOneWidget);
    expect(
      find.textContaining('Kept locally; excluded from AI'),
      findsOneWidget,
    );
    expect(find.text('Add profile fact'), findsOneWidget);
  });
}
