import 'package:dio/dio.dart';
import 'package:naviwealth/features/knowledge/data/bcr_github_client.dart';
import 'package:naviwealth/features/knowledge/data/bcr_knowledge_archive.dart';
import 'package:naviwealth/features/knowledge/domain/bcr_github_target.dart';

import 'bcr_test_fixture.dart';

class BcrTestRequest {
  const BcrTestRequest({
    required this.repository,
    required this.token,
    required this.branch,
    required this.knownHead,
    required this.hasCachedSnapshot,
    required this.cancelToken,
  });
  final String repository;
  final String token;
  final String branch;
  final String? knownHead;
  final bool hasCachedSnapshot;
  final CancelToken? cancelToken;
}

class FakeBcrGithubClient extends BcrGithubClient {
  FakeBcrGithubClient() : super(Dio());
  final calls = <BcrTestRequest>[];
  Future<BcrGithubRead> Function(BcrTestRequest request)? onRead;
  BcrKnowledgeArchive snapshot = makeBcrArchive();
  String head = 'a' * 40;

  @override
  Future<BcrGithubRead> read({
    required String repository,
    required String token,
    String branch = '',
    String? knownHead,
    bool hasCachedSnapshot = false,
    CancelToken? cancelToken,
  }) async {
    final request = BcrTestRequest(
      repository: repository,
      token: token,
      branch: branch,
      knownHead: knownHead,
      hasCachedSnapshot: hasCachedSnapshot,
      cancelToken: cancelToken,
    );
    calls.add(request);
    if (onRead case final handler?) return handler(request);
    return reply(request);
  }

  BcrGithubRead reply(BcrTestRequest request) {
    final parsed = BcrGithubTarget.parseRepository(request.repository);
    return BcrGithubRead(
      target: BcrGithubTarget(
        owner: parsed.owner,
        repository: parsed.repository,
        branch: request.branch.isEmpty ? 'main' : request.branch,
      ),
      head: head,
      snapshot: request.hasCachedSnapshot && request.knownHead == head
          ? null
          : snapshot,
    );
  }
}
