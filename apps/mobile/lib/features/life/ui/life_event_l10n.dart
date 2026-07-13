import 'package:naviwealth/features/health/ui/recovery_verdict.dart';
import 'package:naviwealth/features/life/domain/life_event.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

/// Resolves [LifeEvent] copy for the timeline UI.
extension LifeEventL10n on LifeEvent {
  String localizedTitle(AppLocalizations l10n) {
    switch (template) {
      case LifeEventTemplate.netWorth:
        return l10n.lifeEventNetWorthTitle;
      case LifeEventTemplate.recovery:
        final verdict = params.isNotEmpty ? params.first : 'insufficient_data';
        return l10n.lifeEventRecoveryTitle(
          RecoveryVerdict.label(verdict, l10n),
        );
      case LifeEventTemplate.knowledgeCapture:
        return title.trim().isEmpty ? l10n.lifeEventKnowledgeUntitled : title;
      case LifeEventTemplate.executionAction:
        return title.trim().isEmpty ? l10n.lifeEventExecutionUntitled : title;
      case LifeEventTemplate.financeActivity:
        return title.trim().isEmpty ? l10n.lifeEventActivityUntitled : title;
    }
  }

  String localizedSubtitle(AppLocalizations l10n) {
    switch (template) {
      case LifeEventTemplate.netWorth:
        final currency = params.isNotEmpty ? params.first : '';
        return l10n.lifeEventNetWorthSubtitle(currency);
      case LifeEventTemplate.recovery:
        if (params.length >= 2) {
          return l10n.lifeEventRecoverySubtitleWithScore(params[1]);
        }
        return l10n.lifeEventRecoverySubtitle;
      case LifeEventTemplate.knowledgeCapture:
        return l10n.lifeEventKnowledgeSubtitle;
      case LifeEventTemplate.executionAction:
        final status = params.isNotEmpty ? params.first : '';
        return l10n.lifeEventExecutionSubtitle(_executionStatus(l10n, status));
      case LifeEventTemplate.financeActivity:
        return l10n.lifeEventActivitySubtitle;
    }
  }

  static String _executionStatus(AppLocalizations l10n, String wire) {
    return switch (wire) {
      'todo' => l10n.executionStatusTodo,
      'doing' => l10n.executionStatusDoing,
      'blocked' => l10n.executionStatusBlocked,
      'done' => l10n.executionStatusDone,
      'dropped' => l10n.executionStatusDropped,
      _ => wire,
    };
  }
}
