import 'life_event_scenario.dart';

final class FinancialDecision {
  const FinancialDecision({
    required this.id,
    required this.template,
    required this.assumptions,
    required this.selectedOutcome,
    required this.decidedAt,
    required this.reviewDate,
    this.actualOutcome,
    this.reviewedAt,
  });

  final String id;
  final LifeEventTemplate template;
  final LifeEventAssumptions assumptions;
  final LifeEventOutcome selectedOutcome;
  final DateTime decidedAt;
  final DateTime reviewDate;
  final LifeEventOutcome? actualOutcome;
  final DateTime? reviewedAt;

  Map<String, Object?> toJson() => {
    'id': id,
    'template': template.name,
    'assumptions': assumptions.toJson(),
    'selectedOutcome': selectedOutcome.toJson(),
    'decidedAt': decidedAt.toUtc().toIso8601String(),
    'reviewDate': reviewDate.toUtc().toIso8601String(),
    'actualOutcome': actualOutcome?.toJson(),
    'reviewedAt': reviewedAt?.toUtc().toIso8601String(),
  };

  factory FinancialDecision.fromJson(Map<String, Object?> json) =>
      FinancialDecision(
        id: json['id']! as String,
        template: LifeEventTemplate.values.byName(json['template']! as String),
        assumptions: LifeEventAssumptions.fromJson(
          Map<String, Object?>.from(json['assumptions']! as Map),
        ),
        selectedOutcome: LifeEventOutcome.fromJson(
          Map<String, Object?>.from(json['selectedOutcome']! as Map),
        ),
        decidedAt: DateTime.parse(json['decidedAt']! as String),
        reviewDate: DateTime.parse(json['reviewDate']! as String),
        actualOutcome: json['actualOutcome'] == null
            ? null
            : LifeEventOutcome.fromJson(
                Map<String, Object?>.from(json['actualOutcome']! as Map),
              ),
        reviewedAt: json['reviewedAt'] == null
            ? null
            : DateTime.parse(json['reviewedAt']! as String),
      );
}
