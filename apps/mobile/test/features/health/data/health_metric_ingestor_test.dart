import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/persistence/app_database.dart';
import 'package:naviwealth/core/sync/drift_sync_storage.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/core/sync/mutation_context.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:naviwealth/features/health/data/health_metric_ingestor.dart';
import 'package:naviwealth/features/health/data/health_metric_repository.dart';
import 'package:naviwealth/features/health/domain/health_metric.dart';
import 'package:naviwealth/features/health/domain/health_metric_kind.dart';

import '../../../core/persistence/test_database.dart';

const _userId = 'u-health';
const _deviceId = 'dev-health';

MutationStamper _stamper() {
  var counter = 0;
  return MutationStamper(
    currentUserId: () async => _userId,
    deviceId: () async => _deviceId,
    stampHlc: () async {
      final hlc = Hlc(
        wallMillis: 1_700_000_000_000 + counter,
        counter: 0,
        nodeId: _deviceId,
      );
      counter++;
      return hlc;
    },
  );
}

HealthMetric _metric({
  required String id,
  required double value,
  DateTime? capturedAt,
}) {
  return HealthMetric(
    id: id,
    capturedAt: capturedAt ?? DateTime.utc(2026, 6, 1),
    kind: HealthMetricKind.hrvDaily,
    value: value,
    unit: 'ms',
    sync: SyncMeta(
      ownerUserId: '',
      updatedAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      updatedByDevice: '',
      hlc: Hlc.zero('placeholder'),
    ),
  );
}

void main() {
  late AppDatabase db;
  late InMemoryOutboxStore outbox;
  late HealthMetricRepository repo;
  late HealthMetricIngestor ingestor;

  setUp(() {
    db = makeTestDatabase();
    outbox = InMemoryOutboxStore();
    repo = HealthMetricRepository(db: db, outbox: outbox);
    ingestor = HealthMetricIngestor(repository: repo, stamper: _stamper());
  });

  tearDown(() => db.close());

  test('empty ingest is a no-op', () async {
    final result = await ingestor.ingest(const <HealthMetric>[]);

    expect(result.total, 0);
    expect(result.upserted, 0);
    expect(result.unchanged, 0);
    expect(await outbox.depth(), 0);
  });

  test(
    'same-batch duplicate id is stamped once when payload is identical',
    () async {
      final result = await ingestor.ingest([
        _metric(id: 'hrv:2026-06-01', value: 48),
        _metric(id: 'hrv:2026-06-01', value: 48),
      ]);

      expect(result.total, 2);
      expect(result.upserted, 1);
      expect(result.unchanged, 1);
      expect(await outbox.depth(), 1);

      final row = await repo.findById('hrv:2026-06-01');
      expect(row, isNotNull);
      expect(row!.value, 48);
      expect(row.sync.ownerUserId, _userId);
    },
  );

  test('re-ingesting unchanged rows does not enqueue outbox entries', () async {
    final first = await ingestor.ingest([
      _metric(id: 'hrv:2026-06-01', value: 48),
      _metric(id: 'hrv:2026-06-02', value: 52),
    ]);
    expect(first.upserted, 2);
    expect(await outbox.depth(), 2);

    final second = await ingestor.ingest([
      _metric(id: 'hrv:2026-06-01', value: 48),
      _metric(id: 'hrv:2026-06-02', value: 52),
    ]);

    expect(second.total, 2);
    expect(second.upserted, 0);
    expect(second.unchanged, 2);
    expect(await outbox.depth(), 2);
  });

  test('same-batch correction preserves ordered last-write-wins', () async {
    final result = await ingestor.ingest([
      _metric(id: 'hrv:2026-06-01', value: 48),
      _metric(id: 'hrv:2026-06-01', value: 51),
    ]);

    expect(result.total, 2);
    expect(result.upserted, 2);
    expect(result.unchanged, 0);
    expect(await outbox.depth(), 2);

    final row = await repo.findById('hrv:2026-06-01');
    expect(row!.value, 51);
  });
}
