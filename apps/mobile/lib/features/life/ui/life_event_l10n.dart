import 'package:naviwealth/features/life/data/life_events_provider.dart';
import 'package:naviwealth/features/life/domain/life_event.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

/// Resolves [LifeEvent] copy for the signal timeline.
extension LifeEventL10n on LifeEvent {
  String localizedTitle(AppLocalizations l10n) {
    switch (template) {
      case LifeEventTemplate.financeDaySummary:
        final n = params.isNotEmpty ? params.first : '0';
        return l10n.lifeSignalFinanceDayTitle(n);
      case LifeEventTemplate.recoveryAlert:
        return l10n.lifeSignalRecoveryTitle;
      case LifeEventTemplate.executionBlocked:
        final n = params.isNotEmpty ? params.first : '0';
        return l10n.lifeSignalExecBlockedTitle(n);
      case LifeEventTemplate.executionDue:
        final n = params.isNotEmpty ? params.first : '0';
        return l10n.lifeSignalExecDueTitle(n);
      case LifeEventTemplate.knowledgeInbox:
        final n = params.isNotEmpty ? params.first : '0';
        return l10n.lifeSignalKnowledgeTitle(n);
      case LifeEventTemplate.agentResult:
        final t = params.isNotEmpty ? params.first.trim() : '';
        return t.isEmpty ? l10n.lifeSignalAgentTitle : t;
    }
  }

  String localizedSubtitle(AppLocalizations l10n) {
    switch (template) {
      case LifeEventTemplate.financeDaySummary:
        final expense = params.length > 1 ? params[1] : '0';
        final income = params.length > 2 ? params[2] : '0';
        return l10n.lifeSignalFinanceDaySubtitle(expense, income);
      case LifeEventTemplate.recoveryAlert:
        return l10n.lifeSignalRecoverySubtitle;
      case LifeEventTemplate.executionBlocked:
        return l10n.lifeSignalExecBlockedSubtitle;
      case LifeEventTemplate.executionDue:
        return l10n.lifeSignalExecDueSubtitle;
      case LifeEventTemplate.knowledgeInbox:
        return l10n.lifeSignalKnowledgeSubtitle;
      case LifeEventTemplate.agentResult:
        return l10n.lifeSignalAgentSubtitle;
    }
  }
}

extension LifeHeroSummaryL10n on LifeHeroSummary {
  String localizedHeadline(AppLocalizations l10n) {
    if (highPriorityCount > 0) {
      return l10n.lifeHeroHeadlineAttention(highPriorityCount);
    }
    if (signalCount > 0) {
      return l10n.lifeHeroHeadlineSignals(signalCount);
    }
    return l10n.lifeHeroHeadlineCalm;
  }

  String localizedBody(AppLocalizations l10n) {
    return l10n.lifeHeroBody(domainCount);
  }
}
