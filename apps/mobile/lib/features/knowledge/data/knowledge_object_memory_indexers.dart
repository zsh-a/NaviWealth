/// KnowledgeOS object → Memory indexers for the non-Decision object types
/// (`docs/domains/knowledgeos-domain.md` §3 — "写一份,索引两次").
///
/// Decision has its own file because its payload / status semantics are
/// richer. This library owns the shared Memory source catalogue plus the
/// lightweight object indexers for Note, Principle, Assumption, Concept,
/// Experiment, and Routine.
///
/// kind picked per §3 / Memory Layer semantics:
///
/// - Note        → episodic — captured moment, has a `createdAt` anchor
/// - Principle   → semantic — long-term worldview primitive
/// - Assumption  → semantic — falsifiable belief; carries `confidence`
/// - Concept     → semantic — definition / vocabulary node
/// - Experiment  → episodic — timeline event with a `startedAt` anchor
/// - Routine     → episodic — recurring commitment with a `nextDueAt` anchor
///
/// All indexers gate on `domainOptInsProvider.contains(DomainScope.knowledge)`
/// — same gate as the Decision indexer.
library;

import 'dart:async';
import 'dart:ui' show Locale, PlatformDispatcher;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ai/contracts/context_evidence.dart';
import '../../../core/ai/contracts/event_record.dart';
import '../../../core/ai/contracts/memory_record.dart';
import '../../../core/ai/contracts/source_identity.dart';
import '../../../core/ai/local/memory/memory_runtime.dart';
import '../../../core/ai/local/memory/providers.dart';
import '../../../core/auth/current_user.dart';
import '../../../core/auth/domain_scope.dart';
import '../../../core/auth/providers.dart' as core_auth;
import '../../../design_system/preferences/theme_preferences.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../domain/knowledge_models.dart';
import '../domain/knowledge_text.dart';
import 'knowledge_repository.dart';
import 'providers.dart';

part 'knowledge_assumption_memory_indexer.dart';
part 'knowledge_concept_memory_indexer.dart';
part 'knowledge_experiment_memory_indexer.dart';
part 'knowledge_memory_indexer_subscription.dart';
part 'knowledge_note_memory_indexer.dart';
part 'knowledge_object_memory_sources.dart';
part 'knowledge_principle_memory_indexer.dart';
part 'knowledge_routine_memory_indexer.dart';
