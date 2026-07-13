import 'package:flutter/foundation.dart';

import '../../../core/auth/domain_scope.dart';

/// Domain-neutral life stream event (Phase G).
///
/// Presentation localizes [template] (+ optional [title]/[params]) so this
/// model stays free of BuildContext / ARB coupling.
@immutable
class LifeEvent {
  const LifeEvent({
    required this.id,
    required this.at,
    required this.domain,
    required this.template,
    this.title = '',
    this.params = const <String>[],
    this.routePath,
    this.kind = LifeEventKind.note,
  });

  final String id;
  final DateTime at;
  final DomainScope domain;
  final LifeEventTemplate template;

  /// User-authored or entity title (note / action / narration).
  final String title;

  /// Ordered placeholders for subtitle templates.
  final List<String> params;
  final String? routePath;
  final LifeEventKind kind;
}

enum LifeEventKind { finance, health, knowledge, execution, agent, note }

/// Stable copy templates resolved in the Life UI layer.
enum LifeEventTemplate {
  netWorth,
  recovery,
  knowledgeCapture,
  executionAction,
  financeActivity,
}
