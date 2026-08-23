/// Presentation metadata for registered LifeOS agents.
///
/// Concrete agents still live in feature domains. This contract lets a
/// DomainPack describe how each active agent should appear in shared UI such
/// as Settings without forcing UI layers to infer labels, icons, or placement
/// from the agent id.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../auth/domain_scope.dart';

enum AgentResultPlacement { domainHome, domainReview, settingsOnly }

class AgentPresentationSpec {
  const AgentPresentationSpec({
    required this.agentId,
    required this.domain,
    required this.icon,
    required this.label,
    required this.description,
    this.userToggleable = true,
    this.placement = AgentResultPlacement.domainHome,
  });

  final String agentId;
  final DomainScope domain;
  final IconData icon;
  final String Function(AppLocalizations l10n) label;
  final String Function(AppLocalizations l10n) description;
  final bool userToggleable;
  final AgentResultPlacement placement;
}

final agentPresentationSpecsProvider =
    Provider<Map<String, AgentPresentationSpec>>((ref) {
      return const <String, AgentPresentationSpec>{};
    });
