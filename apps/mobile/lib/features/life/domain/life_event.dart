import 'package:flutter/foundation.dart';

import '../../../core/auth/domain_scope.dart';

/// Cross-domain attention signal for the Life hub.
///
/// Not a ledger feed. Each item answers "what needs attention across
/// domains?" — summaries and alerts only, never raw journal rows.
@immutable
class LifeEvent {
  const LifeEvent({
    required this.id,
    required this.at,
    required this.domain,
    required this.template,
    this.params = const <String>[],
    this.routePath,
    this.priority = LifeSignalPriority.normal,
  });

  final String id;
  final DateTime at;
  final DomainScope domain;
  final LifeEventTemplate template;
  final List<String> params;
  final String? routePath;
  final LifeSignalPriority priority;
}

enum LifeSignalPriority { high, normal }

/// Signal templates resolved in the Life UI layer.
enum LifeEventTemplate {
  /// Today: N entries · net cash movement summary.
  financeDaySummary,

  /// Recovery is strained (or similar alert).
  recoveryAlert,

  /// N blocked execution actions.
  executionBlocked,

  /// N due / overdue open actions.
  executionDue,

  /// Knowledge inbox has open notes needing review.
  knowledgeInbox,

  /// A recent agent artifact is ready to open.
  agentResult,
}
