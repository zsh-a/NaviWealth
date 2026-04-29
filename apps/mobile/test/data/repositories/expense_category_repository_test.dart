import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/sync/drift_sync_storage.dart';
import 'package:naviwealth/core/sync/op.dart';
import 'package:naviwealth/data/db/app_database.dart';
import 'package:naviwealth/data/repositories/expense_category_repository.dart';

import '../db/test_database.dart';
import '_stub_stamper.dart';

void main() {
  late AppDatabase db;
  late InMemoryOutboxStore outbox;
  late ExpenseCategoryRepository repo;

  setUp(() {
    db = makeTestDatabase();
    outbox = InMemoryOutboxStore();
    repo = ExpenseCategoryRepository(
      db: db,
      outbox: outbox,
      stamper: makeStubStamper(),
    );
  });

  tearDown(() async {
    await db.close();
  });

  test('create writes a row and queues an insert op', () async {
    final cat = await repo.create(
      name: '咖啡',
      icon: 'local_cafe',
      color: '#6F4E37',
    );

    expect(cat.name, '咖啡');
    expect(cat.icon, 'local_cafe');
    expect(cat.color, '#6F4E37');
    expect(cat.archivedAt, isNull);

    final op = (await outbox.peekBatch()).single;
    expect(op.tableName, 'expense_categories');
    expect(op.opType, OpType.insert);
    expect(op.fieldsDiff!['name'], '咖啡');
    expect(op.fieldsDiff!['icon'], 'local_cafe');
  });

  test('update only diffs the changed columns', () async {
    final cat = await repo.create(name: '运动');
    await outbox.ack((await outbox.peekBatch()).map((o) => o.opId).toList());

    final updated = await repo.update(cat.id, name: '健身', color: '#FFAA00');
    expect(updated.name, '健身');
    expect(updated.color, '#FFAA00');

    final op = (await outbox.peekBatch()).single;
    expect(op.opType, OpType.update);
    final diff = op.fieldsDiff!;
    expect(diff['name'], '健身');
    expect(diff['color'], '#FFAA00');
    expect(diff.containsKey('icon'), isFalse);
    expect(diff.containsKey('parent_id'), isFalse);
  });

  test('archive sets archivedAt without tombstoning', () async {
    final cat = await repo.create(name: '订阅');
    await outbox.ack((await outbox.peekBatch()).map((o) => o.opId).toList());

    final archived = await repo.archive(cat.id);
    expect(archived.archivedAt, isNotNull);
    expect(archived.sync.deletedAt, isNull);

    final op = (await outbox.peekBatch()).single;
    expect(op.opType, OpType.update);
    expect(op.fieldsDiff!['archived_at'], isA<String>());

    // listActive hides archived rows; listAllExceptDeleted still returns them.
    expect(await repo.listActive(), isEmpty);
    expect((await repo.listAllExceptDeleted()).map((c) => c.id), [cat.id]);
  });

  test('unarchive clears archivedAt', () async {
    final cat = await repo.create(name: '宠物');
    await repo.archive(cat.id);
    await outbox.ack((await outbox.peekBatch()).map((o) => o.opId).toList());

    final restored = await repo.unarchive(cat.id);
    expect(restored.archivedAt, isNull);

    final diff = (await outbox.peekBatch()).single.fieldsDiff!;
    expect(diff.containsKey('archived_at'), isTrue);
    expect(diff['archived_at'], isNull);
  });

  test('softDelete writes a tombstone and queues a delete op', () async {
    final cat = await repo.create(name: '一次性');
    await outbox.ack((await outbox.peekBatch()).map((o) => o.opId).toList());

    await repo.softDelete(cat.id);
    final reloaded = await repo.findById(cat.id);
    expect(reloaded!.sync.deletedAt, isNotNull);

    final op = (await outbox.peekBatch()).single;
    expect(op.opType, OpType.delete);
    expect(op.fieldsDiff, isNull);
  });

  test('seedDefaults seeds the canonical 12 categories on first run',
      () async {
    final inserted = await repo.seedDefaults();
    expect(inserted, ExpenseCategoryRepository.defaultSeeds.length);

    final active = await repo.listActive();
    expect(
      active.map((c) => c.name).toList(),
      ExpenseCategoryRepository.defaultSeeds.map((s) => s.name).toList(),
    );

    // Each seeded row must use the deterministic id prefix so peers
    // converge on the same primary key.
    expect(
      active.every(
        (c) => c.id.startsWith('expense-cat-default:'),
      ),
      isTrue,
    );

    // Every seed row also produces a queued insert op.
    expect(
      await outbox.depth(),
      ExpenseCategoryRepository.defaultSeeds.length,
    );
  });

  test('seedDefaults is idempotent — re-running inserts nothing', () async {
    await repo.seedDefaults();
    await outbox.ack((await outbox.peekBatch()).map((o) => o.opId).toList());

    final secondRun = await repo.seedDefaults();
    expect(secondRun, 0);
    expect(await outbox.depth(), 0);
    expect(
      (await repo.listActive()).length,
      ExpenseCategoryRepository.defaultSeeds.length,
    );
  });

  test('seedDefaults does not resurrect a user-deleted default', () async {
    await repo.seedDefaults();
    final foodId = ExpenseCategoryRepository.defaultIdFor('food');
    await repo.softDelete(foodId);
    await outbox.ack((await outbox.peekBatch()).map((o) => o.opId).toList());

    final secondRun = await repo.seedDefaults();
    expect(secondRun, 0, reason: 'tombstoned defaults must not be re-inserted');

    final foodRow = await repo.findById(foodId);
    expect(foodRow!.sync.deletedAt, isNotNull);
  });

  test('listActive orders by sortOrder then name', () async {
    final last = await repo.create(name: 'zzz', sortOrder: 99);
    final first = await repo.create(name: 'aaa', sortOrder: 0);
    final mid = await repo.create(name: 'mmm', sortOrder: 1);

    final ordered = await repo.listActive();
    expect(ordered.map((c) => c.id), [first.id, mid.id, last.id]);
  });
}
