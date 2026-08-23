/// Provider-neutral context blocks consumed by the shared Rust Agent Runtime.
///
/// Flutter owns retrieval and domain policy. The runtime owns validation,
/// budgeting, rendering, hashing, snapshots, and compaction. Context data is
/// untrusted by default; only the three instruction kinds are rendered as
/// instructions by the runtime.
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../contracts/context_evidence.dart';

enum AgentRuntimeContextBlockKind {
  runtimeInstructions('runtime_instructions'),
  agentInstructions('agent_instructions'),
  commandInstructions('command_instructions'),
  profile('profile'),
  memory('memory'),
  compactionSummary('compaction_summary'),
  message('message'),
  toolSchema('tool_schema'),
  resource('resource'),
  metadata('metadata');

  const AgentRuntimeContextBlockKind(this.wire);

  final String wire;
}

class AgentRuntimeContextEvidence {
  const AgentRuntimeContextEvidence({
    required this.authority,
    required this.provenance,
    this.validFrom,
    this.validUntil,
    this.supersedes,
  });

  final EvidenceAuthority authority;
  final EvidenceProvenance provenance;
  final DateTime? validFrom;
  final DateTime? validUntil;
  final String? supersedes;

  Map<String, Object?> toJson() => <String, Object?>{
    'authority': authority.wire,
    'provenance': provenance.toJson(),
    if (validFrom != null) 'valid_from': validFrom!.toUtc().toIso8601String(),
    if (validUntil != null)
      'valid_until': validUntil!.toUtc().toIso8601String(),
    if (supersedes != null) 'supersedes': supersedes,
  };
}

class AgentRuntimeContextBlock {
  AgentRuntimeContextBlock({
    required this.id,
    required this.kind,
    required this.source,
    required this.content,
    this.priority = 0,
    this.metadata = const <String, Object?>{},
    this.evidence,
  }) : assert(id != ''),
       assert(source != '');

  final String id;
  final AgentRuntimeContextBlockKind kind;
  final String source;
  final Object? content;
  final int priority;
  final Map<String, Object?> metadata;
  final AgentRuntimeContextEvidence? evidence;

  Map<String, Object?> toJson() {
    final encoded = jsonEncode(content);
    return <String, Object?>{
      'block_id': id,
      'kind': kind.wire,
      'source': source,
      'priority': priority,
      // Runtime recomputes both values before planning and snapshotting. The
      // host hash keeps the wire contract self-describing and helps diagnose
      // accidental adapter changes.
      'token_estimate': 0,
      'content_hash': 'sha256:${sha256.convert(utf8.encode(encoded))}',
      'content': content,
      if (evidence != null) 'evidence': evidence!.toJson(),
      'metadata': metadata,
    };
  }
}

class AgentRuntimeContextPolicy {
  const AgentRuntimeContextPolicy({
    required this.maxInputTokens,
    required this.reserveOutputTokens,
    required this.preserveRecentMessages,
    this.compactWhenOverBudget = true,
  });

  final int maxInputTokens;
  final int reserveOutputTokens;
  final int preserveRecentMessages;
  final bool compactWhenOverBudget;

  Map<String, Object?> toJson() => <String, Object?>{
    'max_input_tokens': maxInputTokens,
    'reserve_output_tokens': reserveOutputTokens,
    'preserve_recent_messages': preserveRecentMessages,
    'compact_when_over_budget': compactWhenOverBudget,
  };
}
