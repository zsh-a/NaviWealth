import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';

import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../data/bcr_github_client.dart';
import '../data/bcr_knowledge_repository.dart';
import '../data/bcr_knowledge_sync_service.dart';

String bcrKnowledgeFailureMessage(BuildContext context, Object error) {
  final l10n = AppLocalizations.of(context);
  if (error is DioException && CancelToken.isCancel(error)) {
    return l10n.knowledgeBcrCancelled;
  }
  return switch (error) {
    BcrKnowledgeCacheFailure.changed => l10n.knowledgeBcrChanged,
    BcrKnowledgeCacheFailure.capacity => l10n.knowledgeBcrCapacity,
    BcrSyncLocalFailure.credentials => l10n.knowledgeBcrTokenNeeded,
    BcrSyncLocalFailure.cancelled => l10n.knowledgeBcrCancelled,
    BcrGithubFailure(:final code) => switch (code) {
      BcrGithubFailureCode.network => l10n.knowledgeBcrNetwork,
      BcrGithubFailureCode.unauthorized => l10n.knowledgeBcrUnauthorized,
      BcrGithubFailureCode.forbidden => l10n.knowledgeBcrForbidden,
      BcrGithubFailureCode.notFound => l10n.knowledgeBcrNotFound,
      BcrGithubFailureCode.rateLimited => l10n.knowledgeBcrRateLimited,
      BcrGithubFailureCode.invalidRepository =>
        l10n.knowledgeBcrInvalidRepository,
      BcrGithubFailureCode.invalidData => l10n.knowledgeBcrInvalid,
    },
    FormatException() => l10n.knowledgeBcrRequired,
    _ => userSafeErrorMessage(context, error),
  };
}
