import 'package:naviwealth/l10n/gen/app_localizations.dart';

import '../domain/knowledge_models.dart';

/// Localized labels for KnowledgeOS status enums (blueprint §9.1: wire
/// values never render — `status.wire` is the sync format, not copy).
///
/// `decisionStatusLabel` (the 7-state lifecycle) lives next to its sheet in
/// `_decision_lifecycle_sheet.dart`; these cover the remaining families.
String decisionStatusLabelOf(AppLocalizations l10n, DecisionStatus s) =>
    switch (s) {
      DecisionStatus.draft => l10n.knowledgeDecisionStatusDraft,
      DecisionStatus.active => l10n.knowledgeDecisionStatusActive,
      DecisionStatus.paused => l10n.knowledgeDecisionStatusPaused,
      DecisionStatus.expired => l10n.knowledgeDecisionStatusExpired,
      DecisionStatus.verified => l10n.knowledgeDecisionStatusVerified,
      DecisionStatus.falsified => l10n.knowledgeDecisionStatusFalsified,
      DecisionStatus.superseded => l10n.knowledgeDecisionStatusSuperseded,
    };

String principleStatusLabel(AppLocalizations l10n, PrincipleStatus s) =>
    switch (s) {
      PrincipleStatus.active => l10n.knowledgeStatusActive,
      PrincipleStatus.paused => l10n.knowledgeStatusPaused,
      PrincipleStatus.retired => l10n.knowledgeStatusRetired,
    };

String assumptionStatusLabel(AppLocalizations l10n, AssumptionStatus s) =>
    switch (s) {
      AssumptionStatus.active => l10n.knowledgeStatusActive,
      AssumptionStatus.weakened => l10n.knowledgeStatusWeakened,
      AssumptionStatus.falsified => l10n.knowledgeStatusFalsified,
      AssumptionStatus.retired => l10n.knowledgeStatusRetired,
    };

String experimentStatusLabel(AppLocalizations l10n, ExperimentStatus s) =>
    switch (s) {
      ExperimentStatus.planned => l10n.knowledgeStatusPlanned,
      ExperimentStatus.running => l10n.knowledgeStatusRunning,
      ExperimentStatus.done => l10n.knowledgeStatusDone,
      ExperimentStatus.abandoned => l10n.knowledgeStatusAbandoned,
    };

String routineStatusLabel(AppLocalizations l10n, RoutineStatus s) =>
    switch (s) {
      RoutineStatus.active => l10n.knowledgeStatusActive,
      RoutineStatus.paused => l10n.knowledgeStatusPaused,
      RoutineStatus.archived => l10n.knowledgeStatusArchived,
    };

/// Localize a status *wire* string of any knowledge family — for surfaces
/// that carry statuses as strings (library view models, facet chips).
/// Unknown values fall back to the raw string rather than crashing on
/// future wire additions.
String knowledgeStatusWireLabel(AppLocalizations l10n, String wire) =>
    switch (wire) {
      'active' => l10n.knowledgeStatusActive,
      'paused' => l10n.knowledgeStatusPaused,
      'retired' => l10n.knowledgeStatusRetired,
      'weakened' => l10n.knowledgeStatusWeakened,
      'falsified' => l10n.knowledgeStatusFalsified,
      'planned' => l10n.knowledgeStatusPlanned,
      'running' => l10n.knowledgeStatusRunning,
      'done' => l10n.knowledgeStatusDone,
      'abandoned' => l10n.knowledgeStatusAbandoned,
      'archived' => l10n.knowledgeStatusArchived,
      'draft' => l10n.knowledgeDecisionStatusDraft,
      'expired' => l10n.knowledgeDecisionStatusExpired,
      'verified' => l10n.knowledgeDecisionStatusVerified,
      'superseded' => l10n.knowledgeDecisionStatusSuperseded,
      _ => wire,
    };
