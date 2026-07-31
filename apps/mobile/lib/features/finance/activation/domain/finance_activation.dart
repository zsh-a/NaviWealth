import '../../runway/domain/money_runway.dart';

enum FinanceActivationStage { addData, reviewData, reviewRunway, complete }

final class FinanceActivationSnapshot {
  const FinanceActivationSnapshot({
    required this.stage,
    required this.hasLedgerData,
    required this.pendingReviewCount,
    required this.runway,
  });

  final FinanceActivationStage stage;
  final bool hasLedgerData;
  final int pendingReviewCount;
  final MoneyRunwaySnapshot? runway;

  bool get reviewIsClear => hasLedgerData && pendingReviewCount == 0;
  bool get runwayIsReady => runway?.hasData ?? false;
  bool get isComplete => stage == FinanceActivationStage.complete;

  int get completedSteps =>
      (hasLedgerData ? 1 : 0) +
      (reviewIsClear ? 1 : 0) +
      (runwayIsReady ? 1 : 0);

  static const totalSteps = 3;
}

FinanceActivationSnapshot buildFinanceActivation({
  required bool hasLedgerData,
  required int pendingReviewCount,
  required MoneyRunwaySnapshot? runway,
}) {
  final stage = !hasLedgerData && pendingReviewCount == 0
      ? FinanceActivationStage.addData
      : pendingReviewCount > 0 || !hasLedgerData
      ? FinanceActivationStage.reviewData
      : !(runway?.hasData ?? false)
      ? FinanceActivationStage.reviewRunway
      : FinanceActivationStage.complete;
  return FinanceActivationSnapshot(
    stage: stage,
    hasLedgerData: hasLedgerData,
    pendingReviewCount: pendingReviewCount,
    runway: runway,
  );
}
