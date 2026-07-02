/// KnowledgeOS Library writers.
///
/// This file is the public sheet-entry facade. Concrete form widgets live in
/// object-specific parts so Principle / Assumption / Concept / Experiment /
/// Note changes stay localized.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import '../../../core/sync/mutation_context.dart';
import '../../../core/sync/sync_meta.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../data/providers.dart';
import '../domain/knowledge_models.dart';
import '_widgets.dart';

part 'knowledge_principle_writer.dart';
part 'knowledge_assumption_writer.dart';
part 'knowledge_concept_writer.dart';
part 'knowledge_experiment_writer.dart';
part 'knowledge_note_writer.dart';

Future<void> showNewPrincipleSheet(BuildContext context, WidgetRef _) =>
    showAppFormSheet<void>(
      context: context,
      builder: (_) => const _PrincipleWriter(),
    );

Future<void> showEditPrincipleSheet(
  BuildContext context,
  WidgetRef _,
  KnowledgePrinciple principle,
) => showAppFormSheet<void>(
  context: context,
  builder: (_) => _PrincipleWriter(initial: principle),
);

Future<void> showNewAssumptionSheet(BuildContext context, WidgetRef _) =>
    showAppFormSheet<void>(
      context: context,
      builder: (_) => const _AssumptionWriter(),
    );

Future<void> showEditAssumptionSheet(
  BuildContext context,
  WidgetRef _,
  KnowledgeAssumption assumption,
) => showAppFormSheet<void>(
  context: context,
  builder: (_) => _AssumptionWriter(initial: assumption),
);

Future<void> showNewConceptSheet(BuildContext context, WidgetRef _) =>
    showAppFormSheet<void>(
      context: context,
      builder: (_) => const _ConceptWriter(),
    );

Future<void> showEditConceptSheet(
  BuildContext context,
  WidgetRef _,
  KnowledgeConcept concept,
) => showAppFormSheet<void>(
  context: context,
  builder: (_) => _ConceptWriter(initial: concept),
);

Future<void> showNewExperimentSheet(BuildContext context, WidgetRef _) =>
    showAppFormSheet<void>(
      context: context,
      builder: (_) => const _ExperimentWriter(),
    );

Future<void> showEditExperimentSheet(
  BuildContext context,
  WidgetRef _,
  KnowledgeExperiment experiment,
) => showAppFormSheet<void>(
  context: context,
  builder: (_) => _ExperimentWriter(initial: experiment),
);

Future<void> showEditNoteSheet(
  BuildContext context,
  WidgetRef _,
  KnowledgeNote note,
) => showAppFormSheet<void>(
  context: context,
  builder: (_) => _NoteWriter(initial: note),
);
