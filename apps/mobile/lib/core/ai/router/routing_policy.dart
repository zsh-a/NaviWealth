/// Pure routing decision function.
///
/// All policy lives here as a single switch over [Capability] +
/// [SideEffectScope] + online/sensitivity/device flags. Keeping it
/// pure (no I/O, no provider reads) is what makes the matrix testable
/// and the AiTrace stable.
library;

import '../contracts/contracts.dart';
import 'routing_decision.dart';
import 'routing_inputs.dart';

RoutingDecision decideRouting(RoutingInputs inputs) {
  final intent = inputs.intent;

  switch (intent.capability) {
    case Capability.classify:
      return _device(
        intent,
        BudgetTier.small,
        'classify_local',
        confirmation: Confirmation.none,
      );

    case Capability.search:
      return _device(
        intent,
        BudgetTier.small,
        'search_local',
        confirmation: Confirmation.none,
      );

    case Capability.summarize:
      if (inputs.deviceLlmReady) {
        return _device(
          intent,
          BudgetTier.standard,
          'summarize_device_llm',
          confirmation: Confirmation.none,
        );
      }
      return _device(
        intent,
        BudgetTier.small,
        'summarize_template',
        confirmation: Confirmation.none,
      );

    case Capability.analyze:
      return _decideAnalyze(inputs, intent);

    case Capability.plan:
      return _decidePlan(inputs, intent);

    case Capability.write:
      return _decideWrite(inputs, intent);
  }
}

RoutingDecision _decideAnalyze(RoutingInputs inputs, IntentHint intent) {
  if (!inputs.online) {
    if (inputs.deviceLlmReady) {
      return _device(
        intent,
        BudgetTier.small,
        'analyze_offline_device_llm',
        confirmation: Confirmation.none,
      );
    }
    return _device(
      intent,
      BudgetTier.small,
      'analyze_offline_template',
      confirmation: Confirmation.none,
    );
  }
  if (inputs.sensitivity == PrivacySensitivity.strict) {
    return _device(
      intent,
      BudgetTier.small,
      'analyze_strict_local',
      confirmation: Confirmation.none,
    );
  }
  return _hybrid(
    intent,
    BudgetTier.standard,
    'analyze_hybrid',
    confirmation: Confirmation.none,
  );
}

RoutingDecision _decidePlan(RoutingInputs inputs, IntentHint intent) {
  if (!inputs.online) {
    return _unsupported(
      intent,
      reason: const RoutingReason(
        code: 'plan_requires_online',
        messageZh: '深度规划需要联网，本次仅做本地概览。',
      ),
    );
  }
  if (inputs.sensitivity == PrivacySensitivity.strict) {
    return _unsupported(
      intent,
      reason: const RoutingReason(
        code: 'plan_strict_disabled',
        messageZh: '当前隐私模式不允许云端规划。',
      ),
    );
  }
  return _hybrid(
    intent,
    BudgetTier.large,
    'plan_cloud',
    confirmation: intent.risk == RiskLevel.propose
        ? Confirmation.oneTap
        : Confirmation.none,
  );
}

RoutingDecision _decideWrite(RoutingInputs inputs, IntentHint intent) {
  // A write intent without a side-effect declaration is treated as
  // cross-cutting — the safer assumption.
  final scope = intent.sideEffect ?? SideEffectScope.crossCutting;
  switch (scope) {
    case SideEffectScope.local:
      // Local writes never leave the device. Confirmation depends on
      // whether the surface staged a proposal (oneTap) or asked the
      // router to apply an undoable mutation directly (none).
      return _device(
        intent,
        BudgetTier.small,
        'write_local',
        confirmation: intent.risk == RiskLevel.propose
            ? Confirmation.oneTap
            : Confirmation.none,
      );

    case SideEffectScope.crossCutting:
      if (!inputs.online) {
        return _unsupported(
          intent,
          reason: const RoutingReason(
            code: 'write_cross_cutting_requires_online',
            messageZh: '跨账户调整需要联网。',
          ),
        );
      }
      return _hybrid(
        intent,
        BudgetTier.standard,
        'write_cross_cutting_cloud',
        confirmation: Confirmation.oneTap,
      );

    case SideEffectScope.external:
      if (!inputs.online) {
        return _unsupported(
          intent,
          reason: const RoutingReason(
            code: 'write_external_requires_online',
            messageZh: '外部操作需要联网且必须二次确认。',
          ),
        );
      }
      return _hybrid(
        intent,
        BudgetTier.standard,
        'write_external_typed',
        confirmation: Confirmation.typed,
      );
  }
}

RoutingDecision _device(
  IntentHint intent,
  BudgetTier tier,
  String code, {
  required Confirmation confirmation,
}) => RoutingDecision(
  intent: intent,
  backend: Backend.device,
  budgetTier: tier,
  confirmation: confirmation,
  reason: RoutingReason(code: code),
  supported: true,
);

RoutingDecision _hybrid(
  IntentHint intent,
  BudgetTier tier,
  String code, {
  required Confirmation confirmation,
}) => RoutingDecision(
  intent: intent,
  backend: Backend.hybrid,
  budgetTier: tier,
  confirmation: confirmation,
  reason: RoutingReason(code: code),
  supported: true,
);

RoutingDecision _unsupported(
  IntentHint intent, {
  required RoutingReason reason,
}) => RoutingDecision(
  intent: intent,
  backend: Backend.device,
  budgetTier: BudgetTier.small,
  confirmation: Confirmation.none,
  reason: reason,
  supported: false,
);
