import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/app/domain_composition.dart';
import 'package:naviwealth/app/domain_packs.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

/// Guards the D-1.8 follow-up: every active LifeOS domain contributes
/// Cmd-K entries through `DomainPack.commandPaletteEntriesBuilder`, so
/// HealthOS / KnowledgeOS are no longer palette dead zones (only Finance
/// used to be wired). The shell merges them via `activeDomainPacksProvider`
/// the same way it merges device tools.
void main() {
  final l10n = lookupAppLocalizations(const Locale('en'));

  test('every production domain pack contributes palette entries', () {
    for (final pack in kAllDomainPacks) {
      expect(
        pack.commandPaletteEntriesBuilder,
        isNotNull,
        reason: '${pack.scope} should wire a command palette builder',
      );
      final entries = pack.commandPaletteEntriesBuilder!(l10n);
      expect(entries, isNotEmpty, reason: '${pack.scope} entries');
    }
  });

  test('aggregated entries across all domains have unique ids', () {
    final all = domainCommandPaletteEntries(kAllDomainPacks, l10n);
    final ids = all.map((e) => e.id).toList();
    expect(ids.toSet().length, ids.length, reason: 'duplicate entry id: $ids');
  });

  test('health + knowledge entries navigate to their domain routes', () {
    final health = kHealthPack.commandPaletteEntriesBuilder!(l10n);
    expect(health.map((e) => e.id), contains('nav.health.today'));

    final knowledge = kKnowledgePack.commandPaletteEntriesBuilder!(l10n);
    expect(knowledge.map((e) => e.id), contains('nav.knowledge.inbox'));
  });

  test('health entries are searchable by metrics and sync actions', () {
    final health = kHealthPack.commandPaletteEntriesBuilder!(l10n);

    expect(
      health.where((entry) => entry.matches('vo2')).map((entry) => entry.id),
      contains('nav.health.trend'),
    );
    expect(
      health.where((entry) => entry.matches('sleep')).map((entry) => entry.id),
      contains('nav.health.trend'),
    );
    expect(
      health.where((entry) => entry.matches('garmin')).map((entry) => entry.id),
      contains('nav.health.today'),
    );
  });

  test('corporate actions use one command with dividend keywords', () {
    final finance = kFinancePack.commandPaletteEntriesBuilder!(l10n);
    final corporateActions = finance.where(
      (entry) => entry.id == 'action.corporateAction',
    );

    expect(corporateActions, hasLength(1));
    expect(
      finance.map((entry) => entry.id),
      isNot(contains('action.newDividend')),
    );
    expect(corporateActions.single.matches('dividend'), isTrue);
  });
}
