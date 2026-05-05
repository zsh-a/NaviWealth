import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/db/providers.dart';
import '../sync/drift_sync_storage.dart';
import '../sync/providers.dart';
import 'backup_codec.dart';
import 'backup_service.dart';

final backupCodecProvider = Provider<BackupCodec>((ref) {
  return BackupCodec();
});

final backupServiceProvider = FutureProvider<BackupService>((ref) async {
  final db = await ref.watch(appDatabaseProvider.future);
  final codec = ref.watch(backupCodecProvider);
  final outbox = DriftOutboxStore(db);
  final deviceId = await ref.watch(deviceIdProviderProvider).getOrCreate();
  final engine = await ref.watch(syncEngineProvider.future);
  return BackupService(
    db: db,
    codec: codec,
    outbox: outbox,
    deviceId: deviceId,
    stampHlc: engine.stampHlc,
  );
});
