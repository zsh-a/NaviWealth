import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:naviwealth/core/persistence/app_database.dart';
import 'package:naviwealth/core/sync/mutation_context.dart';
import 'package:naviwealth/core/sync/op_outbox.dart';
import 'package:uuid/uuid.dart';

import '../domain/financial_decision.dart';
import '../domain/life_event_scenario.dart';

class FinancialDecisionRepository {
  FinancialDecisionRepository({
    required AppDatabase db,
    required OutboxStore outbox,
    required MutationStamper stamper,
    Uuid uuid = const Uuid(),
  }) : _db = db,
       _outbox = outbox,
       _stamper = stamper,
       _uuid = uuid;

  static const _tableName = 'financial_decisions';
  final AppDatabase _db;
  final OutboxStore _outbox;
  final MutationStamper _stamper;
  final Uuid _uuid;

  Stream<List<FinancialDecision>> watchAll() async* {
    final owner = await _stamper.currentUserId();
    final query = _db.select(_db.financialDecisions)
      ..where(
        (table) => table.ownerUserId.equals(owner) & table.deletedAt.isNull(),
      )
      ..orderBy([
        (table) =>
            OrderingTerm(expression: table.decidedAt, mode: OrderingMode.desc),
      ]);
    yield* query.watch().map(
      (rows) => rows.map(_fromRow).toList(growable: false),
    );
  }

  Future<FinancialDecision> create({
    required LifeEventTemplate template,
    required LifeEventVariant selectedVariant,
    required LifeEventBaseline baseline,
    required LifeEventAssumptions assumptions,
    required LifeEventOutcome outcome,
    required DateTime now,
  }) async {
    final stamp = await _stamper.stamp();
    final id = _uuid.v4();
    await _db.transaction(() async {
      await _db
          .into(_db.financialDecisions)
          .insert(
            FinancialDecisionsCompanion.insert(
              id: id,
              template: template.name,
              selectedVariant: selectedVariant.name,
              calculatorVersion: LifeEventScenarioEngine.calculatorVersion,
              baselineJson: jsonEncode(baseline.toJson()),
              assumptionsJson: jsonEncode(assumptions.toJson()),
              selectedOutcomeJson: jsonEncode(outcome.toJson()),
              decidedAt: now,
              reviewDate: now.add(const Duration(days: 90)),
              ownerUserId: stamp.ownerUserId,
              updatedAt: stamp.now,
              updatedByDevice: stamp.deviceId,
              hlc: stamp.hlc,
            ),
          );
      await _outbox.enqueue(table: _tableName, rowId: id);
    });
    return (await _find(id))!;
  }

  Future<void> review({
    required String id,
    required LifeEventOutcome actualOutcome,
    required FinancialDecisionReviewEvidence evidence,
    required DateTime now,
  }) async {
    final stamp = await _stamper.stamp();
    await _db.transaction(() async {
      await (_db.update(_db.financialDecisions)..where(
            (table) =>
                table.id.equals(id) &
                table.ownerUserId.equals(stamp.ownerUserId),
          ))
          .write(
            FinancialDecisionsCompanion(
              actualOutcomeJson: Value(jsonEncode(actualOutcome.toJson())),
              reviewEvidenceJson: Value(jsonEncode(evidence.toJson())),
              reviewedAt: Value(now),
              status: const Value('reviewed'),
              updatedAt: Value(stamp.now),
              updatedByDevice: Value(stamp.deviceId),
              hlc: Value(stamp.hlc),
            ),
          );
      await _outbox.enqueue(table: _tableName, rowId: id);
    });
  }

  Future<FinancialDecision?> _find(String id) async {
    final owner = await _stamper.currentUserId();
    final row =
        await (_db.select(_db.financialDecisions)..where(
              (table) => table.id.equals(id) & table.ownerUserId.equals(owner),
            ))
            .getSingleOrNull();
    return row == null ? null : _fromRow(row);
  }

  FinancialDecision _fromRow(FinancialDecisionRow row) => FinancialDecision(
    id: row.id,
    template: LifeEventTemplate.values.byName(row.template),
    selectedVariant: LifeEventVariant.values.byName(row.selectedVariant),
    calculatorVersion: row.calculatorVersion,
    baseline: LifeEventBaseline.fromJson(
      Map<String, Object?>.from(jsonDecode(row.baselineJson) as Map),
    ),
    assumptions: LifeEventAssumptions.fromJson(
      Map<String, Object?>.from(jsonDecode(row.assumptionsJson) as Map),
    ),
    selectedOutcome: LifeEventOutcome.fromJson(
      Map<String, Object?>.from(jsonDecode(row.selectedOutcomeJson) as Map),
    ),
    decidedAt: row.decidedAt,
    reviewDate: row.reviewDate,
    actualOutcome: row.actualOutcomeJson == null
        ? null
        : LifeEventOutcome.fromJson(
            Map<String, Object?>.from(
              jsonDecode(row.actualOutcomeJson!) as Map,
            ),
          ),
    reviewEvidence: row.reviewEvidenceJson == null
        ? null
        : FinancialDecisionReviewEvidence.fromJson(
            Map<String, Object?>.from(
              jsonDecode(row.reviewEvidenceJson!) as Map,
            ),
          ),
    reviewedAt: row.reviewedAt,
  );
}
