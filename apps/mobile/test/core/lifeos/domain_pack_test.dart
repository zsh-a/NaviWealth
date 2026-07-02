/// LifeOS DomainPack registration seam — the single source of truth
/// for "which domains are active in this build" that the four shell
/// aggregators (device tools / prompt blocks / agents / shell specs)
/// derive from.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/ai/runtime/device/tools/device_tool.dart';
import 'package:naviwealth/core/auth/domain_scope.dart';
import 'package:naviwealth/core/auth/providers.dart' as auth;
import 'package:naviwealth/core/lifeos/domain_pack.dart';
import 'package:naviwealth/core/persistence/app_database.dart';
import 'package:naviwealth/core/persistence/providers.dart';

import '../persistence/test_database.dart';

const _financePack = DomainPack(scope: DomainScope.finance);
const _healthPack = DomainPack(scope: DomainScope.health);
const _knowledgePack = DomainPack(scope: DomainScope.knowledge);

ProviderContainer _container({
  required AppDatabase db,
  List<DomainPack> registry = const <DomainPack>[],
}) {
  return ProviderContainer(
    overrides: [
      appDatabaseProvider.overrideWith((ref) async => db),
      domainPackRegistryProvider.overrideWith((ref) => registry),
    ],
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DomainPack class', () {
    test('default values are empty contributions', () {
      const empty = DomainPack(scope: DomainScope.finance);
      expect(empty.deviceTools, <DeviceTool>[]);
      expect(empty.systemPromptBlock, '');
      expect(empty.shellSpecBuilder, isNull);
      expect(empty.agentBuilder, isNull);
      expect(empty.memoryBootstrapBuilder, isNull);
      expect(empty.backgroundBootstrapBuilder, isNull);
      expect(empty.settingsSpec, isNull);
    });
  });

  group('domainPackRegistryProvider', () {
    test('default is empty', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      expect(c.read(domainPackRegistryProvider), isEmpty);
    });
  });

  group('activeDomainPacksProvider', () {
    test('empty registry → empty active', () async {
      final db = makeTestDatabase();
      addTearDown(db.close);
      final c = _container(db: db);
      addTearDown(c.dispose);
      await c.read(auth.domainOptInsProvider.future);
      expect(c.read(activeDomainPacksProvider), isEmpty);
    });

    test('finance pack always present on a fresh install', () async {
      final db = makeTestDatabase();
      addTearDown(db.close);
      final c = _container(
        db: db,
        registry: const [_financePack, _healthPack, _knowledgePack],
      );
      addTearDown(c.dispose);
      await c.read(auth.domainOptInsProvider.future);
      expect(c.read(activeDomainPacksProvider).map((p) => p.scope), [
        DomainScope.finance,
      ]);
    });

    test('opt-in registers the domain', () async {
      final db = makeTestDatabase();
      addTearDown(db.close);
      final c = _container(
        db: db,
        registry: const [_financePack, _healthPack, _knowledgePack],
      );
      addTearDown(c.dispose);
      await c.read(auth.domainOptInsProvider.future);
      await c
          .read(auth.domainOptInsProvider.notifier)
          .setEnabled(DomainScope.health, true);
      expect(c.read(activeDomainPacksProvider).map((p) => p.scope), [
        DomainScope.finance,
        DomainScope.health,
      ]);
    });

    test('opted-in domain whose pack is not registered is ignored', () async {
      final db = makeTestDatabase();
      addTearDown(db.close);
      final c = _container(db: db, registry: const [_financePack, _healthPack]);
      addTearDown(c.dispose);
      await c.read(auth.domainOptInsProvider.future);
      await c
          .read(auth.domainOptInsProvider.notifier)
          .setEnabled(DomainScope.knowledge, true);
      expect(c.read(activeDomainPacksProvider).map((p) => p.scope), [
        DomainScope.finance,
      ]);
    });

    test('preserves registry order', () async {
      final db = makeTestDatabase();
      addTearDown(db.close);
      final c = _container(
        db: db,
        // Reversed: knowledge, health, finance.
        registry: const [_knowledgePack, _healthPack, _financePack],
      );
      addTearDown(c.dispose);
      await c.read(auth.domainOptInsProvider.future);
      await c
          .read(auth.domainOptInsProvider.notifier)
          .setEnabled(DomainScope.health, true);
      await c
          .read(auth.domainOptInsProvider.notifier)
          .setEnabled(DomainScope.knowledge, true);
      expect(c.read(activeDomainPacksProvider).map((p) => p.scope), [
        DomainScope.knowledge,
        DomainScope.health,
        DomainScope.finance,
      ]);
    });
  });
}
