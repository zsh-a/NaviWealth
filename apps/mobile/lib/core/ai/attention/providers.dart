import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../persistence/providers.dart';
import 'attention_store.dart';

final attentionDecisionStoreProvider = FutureProvider<AttentionDecisionStore>((
  ref,
) async {
  final db = await ref.watch(appDatabaseProvider.future);
  return SqliteAttentionDecisionStore(db: db);
});

final attentionDecisionServiceProvider =
    FutureProvider<AttentionDecisionService>((ref) async {
      final store = await ref.watch(attentionDecisionStoreProvider.future);
      return AttentionDecisionService(store: store);
    });
