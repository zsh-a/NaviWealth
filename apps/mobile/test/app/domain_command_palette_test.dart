import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/app/domain_packs.dart';
import 'package:naviwealth/core/command_palette/command_palette_entry.dart';
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
    final all = <CommandPaletteEntry>[
      for (final pack in kAllDomainPacks)
        ...?pack.commandPaletteEntriesBuilder?.call(l10n),
    ];
    final ids = all.map((e) => e.id).toList();
    expect(ids.toSet().length, ids.length, reason: 'duplicate entry id: $ids');
  });

  test('health + knowledge entries navigate to their domain routes', () {
    final health = kHealthPack.commandPaletteEntriesBuilder!(l10n);
    expect(health.map((e) => e.id), contains('nav.health.today'));

    final knowledge = kKnowledgePack.commandPaletteEntriesBuilder!(l10n);
    expect(knowledge.map((e) => e.id), contains('nav.knowledge.inbox'));
  });
}
