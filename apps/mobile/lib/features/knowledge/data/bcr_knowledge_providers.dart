import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/current_user.dart';
import '../../../core/logging/http_diagnostics_interceptor.dart';
import '../../../core/logging/providers.dart';
import '../../../core/persistence/providers.dart';
import '../domain/bcr_knowledge_connection.dart';
import '../domain/bcr_knowledge_source.dart';
import 'bcr_github_client.dart';
import 'bcr_github_credentials.dart';
import 'bcr_knowledge_repository.dart';
import 'bcr_knowledge_sync_service.dart';
import 'providers.dart';

final bcrKnowledgeRepositoryProvider = FutureProvider<BcrKnowledgeRepository>((
  ref,
) async {
  return BcrKnowledgeRepository(await ref.watch(appDatabaseProvider.future));
});

final bcrKnowledgeSourcesProvider =
    StreamProvider.autoDispose<List<BcrKnowledgeSource>>((ref) async* {
      final owner = await ref.watch(knowledgeOwnerUserIdProvider.future);
      final repository = await ref.watch(bcrKnowledgeRepositoryProvider.future);
      yield* repository.watchSources(owner);
    });

final bcrKnowledgeConnectionsProvider =
    StreamProvider.autoDispose<List<BcrKnowledgeConnection>>((ref) async* {
      final owner = await ref.watch(knowledgeOwnerUserIdProvider.future);
      final repository = await ref.watch(bcrKnowledgeRepositoryProvider.future);
      yield* repository.watchConnections(owner);
    });

final bcrGithubCredentialsProvider = Provider<BcrGithubCredentials>(
  (ref) => BcrGithubCredentials(
    ref.watch(secureKeyStoreProvider),
    persistent: !kIsWeb,
  ),
);

final bcrGithubClientProvider = Provider<BcrGithubClient>((ref) {
  final dio = Dio();
  dio.interceptors.add(
    HttpDiagnosticsInterceptor(
      logger: ref.read(loggerProvider),
      service: 'bcr_github',
    ),
  );
  ref.onDispose(() => dio.close(force: true));
  return BcrGithubClient(dio);
});

final bcrKnowledgeSyncServiceProvider =
    FutureProvider.autoDispose<BcrKnowledgeSyncService>((ref) async {
      final owner = await ref.watch(knowledgeOwnerUserIdProvider.future);
      final repository = await ref.watch(bcrKnowledgeRepositoryProvider.future);
      final service = BcrKnowledgeSyncService(
        owner: owner,
        repository: repository,
        credentials: ref.watch(bcrGithubCredentialsProvider),
        client: ref.watch(bcrGithubClientProvider),
        currentOwner: () => ref.read(currentUserIdProvider)(),
      );
      ref.onDispose(service.dispose);
      return service;
    });

final bcrKnowledgeSyncStatusProvider =
    StreamProvider.autoDispose<Map<String, BcrSyncStatus>>((ref) async* {
      final service = await ref.watch(bcrKnowledgeSyncServiceProvider.future);
      yield* service.statuses;
    });
