import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../auth/current_user.dart';
import '../persistence/providers.dart';
import 'developer_issue.dart';

/// Last domain-owned route, retained while the full-screen Settings tree is
/// open so a report still points at the product surface that prompted it.
final developerIssueContextProvider = StateProvider<DeveloperIssueContext?>(
  (_) => null,
);

final developerIssueStoreProvider = FutureProvider<DeveloperIssueStore>((
  ref,
) async {
  final db = await ref.watch(appDatabaseProvider.future);
  return SqliteDeveloperIssueStore(db);
});

final developerIssuesProvider =
    FutureProvider.autoDispose<List<DeveloperIssue>>((ref) async {
      final ownerUserId = await ref.watch(currentUserIdProvider)();
      final store = await ref.watch(developerIssueStoreProvider.future);
      return store.list(ownerUserId: ownerUserId);
    });
