library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../persistence/providers.dart';
import 'personal_profile_snapshot.dart';
import 'personal_profile_store.dart';

final activePersonalProfileDomainScopesProvider = Provider<Set<String>>(
  (ref) => const <String>{},
);

final personalProfileStoreProvider = FutureProvider<PersonalProfileStore>((
  ref,
) async {
  final db = await ref.watch(appDatabaseProvider.future);
  return SqlitePersonalProfileStore(db);
});

final personalProfileSnapshotBuilderProvider =
    FutureProvider<PersonalProfileSnapshotBuilder>((ref) async {
      return PersonalProfileSnapshotBuilder(
        await ref.watch(personalProfileStoreProvider.future),
      );
    });
