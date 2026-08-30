import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../../../../design_system/design_system.dart';
import '../../../../l10n/gen/app_localizations.dart';
import '../../domain/knowledge_models.dart';
import '../knowledge_decision_review_sheet.dart';

/// Visual mapping for a [DecisionStatus]: the icon and [AppBadgeTone] every
/// status surface (detail header, review section, library rows) should share.
class KnowledgeDecisionStatusStyle {
  const KnowledgeDecisionStatusStyle({required this.icon, required this.tone});

  final IconData icon;
  final AppBadgeTone tone;
}

/// Single source of truth for `DecisionStatus` → (icon, tone). Labels stay
/// with [knowledgeDecisionStatusLabel] so all three attributes travel
/// together at call sites.
KnowledgeDecisionStatusStyle knowledgeDecisionStatusStyle(
  DecisionStatus status,
) => switch (status) {
  DecisionStatus.draft => const KnowledgeDecisionStatusStyle(
    icon: FLucideIcons.filePenLine,
    tone: AppBadgeTone.neutral,
  ),
  DecisionStatus.active => const KnowledgeDecisionStatusStyle(
    icon: FLucideIcons.play,
    tone: AppBadgeTone.info,
  ),
  DecisionStatus.paused => const KnowledgeDecisionStatusStyle(
    icon: FLucideIcons.pause,
    tone: AppBadgeTone.warning,
  ),
  DecisionStatus.expired => const KnowledgeDecisionStatusStyle(
    icon: FLucideIcons.clockAlert,
    tone: AppBadgeTone.warning,
  ),
  DecisionStatus.verified => const KnowledgeDecisionStatusStyle(
    icon: FLucideIcons.badgeCheck,
    tone: AppBadgeTone.success,
  ),
  DecisionStatus.falsified => const KnowledgeDecisionStatusStyle(
    icon: FLucideIcons.badgeX,
    tone: AppBadgeTone.error,
  ),
  DecisionStatus.superseded => const KnowledgeDecisionStatusStyle(
    icon: FLucideIcons.replace,
    tone: AppBadgeTone.neutral,
  ),
};

/// Toned status badge for a [KnowledgeDecision].
class KnowledgeDecisionStatusBadge extends StatelessWidget {
  const KnowledgeDecisionStatusBadge({
    super.key,
    required this.status,
    this.size = AppBadgeSize.regular,
  });

  final DecisionStatus status;
  final AppBadgeSize size;

  @override
  Widget build(BuildContext context) {
    final style = knowledgeDecisionStatusStyle(status);
    return AppBadge(
      label: knowledgeDecisionStatusLabel(AppLocalizations.of(context), status),
      tone: style.tone,
      icon: style.icon,
      size: size,
    );
  }
}
