/// KnowledgeOS Library writers.
///
/// This file is the public sheet-entry facade. Concrete form widgets live in
/// object-specific parts so Principle / Assumption / Concept / Experiment /
/// Note changes stay localized.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import '../../../core/forms/form_dirty_guard.dart';
import '../../../core/sync/mutation_context.dart';
import '../../../core/sync/sync_meta.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../data/providers.dart';
import '../domain/knowledge_models.dart';
import '_widgets.dart';
import 'knowledge_status_labels.dart';

part 'knowledge_principle_writer.dart';
part 'knowledge_assumption_writer.dart';
part 'knowledge_concept_writer.dart';
part 'knowledge_experiment_writer.dart';
part 'knowledge_note_writer.dart';

Future<void> showNewPrincipleSheet(BuildContext context, WidgetRef _) =>
    showGuardedFormSheet<void>(
      context: context,
      builder: (_, dirty) => _PrincipleWriter(dirty: dirty),
    );

Future<void> showEditPrincipleSheet(
  BuildContext context,
  WidgetRef _,
  KnowledgePrinciple principle,
) => showGuardedFormSheet<void>(
  context: context,
  builder: (_, dirty) => _PrincipleWriter(initial: principle, dirty: dirty),
);

Future<void> showNewAssumptionSheet(BuildContext context, WidgetRef _) =>
    showGuardedFormSheet<void>(
      context: context,
      builder: (_, dirty) => _AssumptionWriter(dirty: dirty),
    );

Future<void> showEditAssumptionSheet(
  BuildContext context,
  WidgetRef _,
  KnowledgeAssumption assumption,
) => showGuardedFormSheet<void>(
  context: context,
  builder: (_, dirty) => _AssumptionWriter(initial: assumption, dirty: dirty),
);

Future<void> showNewConceptSheet(BuildContext context, WidgetRef _) =>
    showGuardedFormSheet<void>(
      context: context,
      builder: (_, dirty) => _ConceptWriter(dirty: dirty),
    );

Future<void> showEditConceptSheet(
  BuildContext context,
  WidgetRef _,
  KnowledgeConcept concept,
) => showGuardedFormSheet<void>(
  context: context,
  builder: (_, dirty) => _ConceptWriter(initial: concept, dirty: dirty),
);

Future<void> showNewExperimentSheet(BuildContext context, WidgetRef _) =>
    showGuardedFormSheet<void>(
      context: context,
      builder: (_, dirty) => _ExperimentWriter(dirty: dirty),
    );

Future<void> showEditExperimentSheet(
  BuildContext context,
  WidgetRef _,
  KnowledgeExperiment experiment, {
  bool focusEvidence = false,
}) => showGuardedFormSheet<void>(
  context: context,
  builder: (_, dirty) => _ExperimentWriter(
    initial: experiment,
    dirty: dirty,
    focusEvidence: focusEvidence,
  ),
);

Future<void> showEditNoteSheet(
  BuildContext context,
  WidgetRef _,
  KnowledgeNote note,
) => showGuardedFormSheet<void>(
  context: context,
  builder: (_, dirty) => _NoteWriter(initial: note, dirty: dirty),
);
