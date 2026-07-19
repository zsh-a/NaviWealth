import '../../runway/domain/money_runway.dart';

enum FinanceActivationStage { importData, reviewImport, reviewRunway, complete }

final class FinanceActivationSnapshot {
  const FinanceActivationSnapshot({
    required this.stage,
    required this.confirmedImportCount,
    required this.pendingReviewCount,
    required this.runway,
  });

  final FinanceActivationStage stage;
  final int confirmedImportCount;
  final int pendingReviewCount;
  final MoneyRunwaySnapshot? runway;

  bool get hasConfirmedImport => confirmedImportCount > 0;
  bool get reviewIsClear => hasConfirmedImport && pendingReviewCount == 0;
  bool get runwayIsReady => runway?.hasData ?? false;
  bool get isComplete => stage == FinanceActivationStage.complete;

  int get completedSteps =>
      (hasConfirmedImport ? 1 : 0) +
      (reviewIsClear ? 1 : 0) +
      (runwayIsReady ? 1 : 0);

  static const totalSteps = 3;
}

FinanceActivationSnapshot buildFinanceActivation({
  required int confirmedImportCount,
  required int pendingReviewCount,
  required MoneyRunwaySnapshot? runway,
}) {
  final hasConfirmedImport = confirmedImportCount > 0;
  final stage = !hasConfirmedImport && pendingReviewCount == 0
      ? FinanceActivationStage.importData
      : pendingReviewCount > 0 || !hasConfirmedImport
      ? FinanceActivationStage.reviewImport
      : !(runway?.hasData ?? false)
      ? FinanceActivationStage.reviewRunway
      : FinanceActivationStage.complete;
  return FinanceActivationSnapshot(
    stage: stage,
    confirmedImportCount: confirmedImportCount,
    pendingReviewCount: pendingReviewCount,
    runway: runway,
  );
}
