/// Provider-neutral, durable human-in-the-loop contract.
///
/// This mirrors `agent-core::InteractionEnvelope`. Domain payloads remain
/// opaque; the shell/runtime own lifecycle, confirmation mode, expiry,
/// subject identity, and resume routing.
library;

enum AiInteractionKind { input, choice, approval }

enum AiInteractionMode { oneTap, confirmDiff, typed }

enum AiInteractionStatus { pending, resolved, rejected, cancelled, expired }

enum AiInteractionAction { submit, approve, reject, cancel }

enum AiInteractionResumeKind { chatTurn, proposalApply, host, none }

extension AiInteractionModeWire on AiInteractionMode {
  String get wire => switch (this) {
    AiInteractionMode.oneTap => 'one_tap',
    AiInteractionMode.confirmDiff => 'confirm_diff',
    AiInteractionMode.typed => 'typed',
  };

  static AiInteractionMode parse(Object? value) => switch (value) {
    'one_tap' => AiInteractionMode.oneTap,
    'confirm_diff' => AiInteractionMode.confirmDiff,
    'typed' => AiInteractionMode.typed,
    _ => AiInteractionMode.typed,
  };
}

final class AiInteractionOption {
  const AiInteractionOption({
    required this.id,
    required this.label,
    this.description = '',
    this.metadata = const <String, Object?>{},
  });

  final String id;
  final String label;
  final String description;
  final Map<String, Object?> metadata;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'label': label,
    'description': description,
    'metadata': metadata,
  };

  static AiInteractionOption? tryParse(Object? value) {
    if (value is! Map) return null;
    final map = value.map((key, value) => MapEntry('$key', value));
    final id = (map['id'] as String?)?.trim() ?? '';
    final label = (map['label'] as String?)?.trim() ?? '';
    if (id.isEmpty || label.isEmpty) return null;
    return AiInteractionOption(
      id: id,
      label: label,
      description: (map['description'] as String?)?.trim() ?? '',
      metadata: _object(map['metadata']),
    );
  }
}

final class AiInteractionConfirmation {
  const AiInteractionConfirmation({
    required this.requiredText,
    this.caseSensitive = false,
  });

  final String requiredText;
  final bool caseSensitive;

  Map<String, Object?> toJson() => <String, Object?>{
    'required_text': requiredText,
    'case_sensitive': caseSensitive,
  };

  static AiInteractionConfirmation? tryParse(Object? value) {
    if (value is! Map) return null;
    final requiredText = (value['required_text'] as String?)?.trim() ?? '';
    if (requiredText.isEmpty) return null;
    return AiInteractionConfirmation(
      requiredText: requiredText,
      caseSensitive: value['case_sensitive'] == true,
    );
  }
}

final class AiInteractionEnvelope {
  const AiInteractionEnvelope({
    required this.interactionId,
    required this.kind,
    required this.mode,
    required this.status,
    required this.title,
    required this.createdAt,
    required this.resumeKind,
    this.prompt = '',
    this.options = const <AiInteractionOption>[],
    this.confirmation,
    this.subjectKind,
    this.subjectId,
    this.responseSchema = const <String, Object?>{},
    this.payload = const <String, Object?>{},
    this.metadata = const <String, Object?>{},
    this.resumeToken,
    this.expiresAt,
  });

  final String interactionId;
  final AiInteractionKind kind;
  final AiInteractionMode mode;
  final AiInteractionStatus status;
  final String title;
  final String prompt;
  final List<AiInteractionOption> options;
  final AiInteractionConfirmation? confirmation;
  final String? subjectKind;
  final String? subjectId;
  final Map<String, Object?> responseSchema;
  final Map<String, Object?> payload;
  final Map<String, Object?> metadata;
  final AiInteractionResumeKind resumeKind;
  final String? resumeToken;
  final DateTime createdAt;
  final DateTime? expiresAt;

  Map<String, Object?> toJson() => <String, Object?>{
    'protocol_version': 'agent.v1',
    'interaction_id': interactionId,
    'kind': kind.name,
    'mode': mode.wire,
    'status': status.name,
    'title': title,
    'prompt': prompt,
    if (options.isNotEmpty)
      'options': [for (final option in options) option.toJson()],
    if (confirmation != null) 'confirmation': confirmation!.toJson(),
    if (subjectKind != null && subjectId != null)
      'subject': <String, Object?>{
        'kind': subjectKind,
        'id': subjectId,
        'metadata': const <String, Object?>{},
      },
    'response_schema': responseSchema,
    'payload': payload,
    'metadata': metadata,
    'resume': <String, Object?>{
      'kind': _resumeWire(resumeKind),
      if (resumeToken != null) 'token': resumeToken,
    },
    'created_at': createdAt.toUtc().toIso8601String(),
    if (expiresAt != null) 'expires_at': expiresAt!.toUtc().toIso8601String(),
  };

  static AiInteractionEnvelope? tryParse(Object? value) {
    if (value is! Map) return null;
    final map = value.map((key, value) => MapEntry('$key', value));
    if (map['protocol_version'] != 'agent.v1') return null;
    final interactionId = (map['interaction_id'] as String?)?.trim() ?? '';
    final title = (map['title'] as String?)?.trim() ?? '';
    final createdAt = DateTime.tryParse(map['created_at'] as String? ?? '');
    final kind = _kind(map['kind']);
    final status = _status(map['status']);
    final resume = _object(map['resume']);
    final resumeKind = _resumeKind(resume['kind']);
    if (interactionId.isEmpty ||
        title.isEmpty ||
        createdAt == null ||
        kind == null ||
        status == null ||
        resumeKind == null) {
      return null;
    }
    final options = switch (map['options']) {
      final List<Object?> values =>
        values
            .map(AiInteractionOption.tryParse)
            .nonNulls
            .toList(growable: false),
      _ => const <AiInteractionOption>[],
    };
    final mode = AiInteractionModeWire.parse(map['mode']);
    final confirmation = AiInteractionConfirmation.tryParse(
      map['confirmation'],
    );
    if (kind == AiInteractionKind.choice && options.length < 2 ||
        mode == AiInteractionMode.typed && confirmation == null) {
      return null;
    }
    final subject = _object(map['subject']);
    return AiInteractionEnvelope(
      interactionId: interactionId,
      kind: kind,
      mode: mode,
      status: status,
      title: title,
      prompt: (map['prompt'] as String?) ?? '',
      options: options,
      confirmation: confirmation,
      subjectKind: subject['kind'] as String?,
      subjectId: subject['id'] as String?,
      responseSchema: _object(map['response_schema']),
      payload: _object(map['payload']),
      metadata: _object(map['metadata']),
      resumeKind: resumeKind,
      resumeToken: resume['token'] as String?,
      createdAt: createdAt.toUtc(),
      expiresAt: DateTime.tryParse(map['expires_at'] as String? ?? '')?.toUtc(),
    );
  }
}

final class AiInteractionResponse {
  const AiInteractionResponse({
    required this.interactionId,
    required this.action,
    required this.value,
    required this.respondedAt,
    this.confirmationText,
    this.respondedBy,
    this.metadata = const <String, Object?>{},
  });

  final String interactionId;
  final AiInteractionAction action;
  final Object? value;
  final String? confirmationText;
  final String? respondedBy;
  final DateTime respondedAt;
  final Map<String, Object?> metadata;

  Map<String, Object?> toJson() => <String, Object?>{
    'protocol_version': 'agent.v1',
    'interaction_id': interactionId,
    'action': action.name,
    'value': value,
    if (confirmationText != null) 'confirmation_text': confirmationText,
    if (respondedBy != null) 'responded_by': respondedBy,
    'responded_at': respondedAt.toUtc().toIso8601String(),
    'metadata': metadata,
  };

  static AiInteractionResponse? tryParse(Object? value) {
    if (value is! Map || value['protocol_version'] != 'agent.v1') return null;
    final interactionId = (value['interaction_id'] as String?)?.trim() ?? '';
    final action = _action(value['action']);
    final respondedAt = DateTime.tryParse(
      value['responded_at'] as String? ?? '',
    );
    if (interactionId.isEmpty || action == null || respondedAt == null) {
      return null;
    }
    return AiInteractionResponse(
      interactionId: interactionId,
      action: action,
      value: value['value'],
      confirmationText: value['confirmation_text'] as String?,
      respondedBy: value['responded_by'] as String?,
      respondedAt: respondedAt.toUtc(),
      metadata: _object(value['metadata']),
    );
  }
}

Map<String, Object?> _object(Object? value) => value is Map
    ? value.map((key, value) => MapEntry('$key', value))
    : const <String, Object?>{};

AiInteractionKind? _kind(Object? value) => switch (value) {
  'input' => AiInteractionKind.input,
  'choice' => AiInteractionKind.choice,
  'approval' => AiInteractionKind.approval,
  _ => null,
};

AiInteractionStatus? _status(Object? value) => switch (value) {
  'pending' => AiInteractionStatus.pending,
  'resolved' => AiInteractionStatus.resolved,
  'rejected' => AiInteractionStatus.rejected,
  'cancelled' => AiInteractionStatus.cancelled,
  'expired' => AiInteractionStatus.expired,
  _ => null,
};

AiInteractionAction? _action(Object? value) => switch (value) {
  'submit' => AiInteractionAction.submit,
  'approve' => AiInteractionAction.approve,
  'reject' => AiInteractionAction.reject,
  'cancel' => AiInteractionAction.cancel,
  _ => null,
};

AiInteractionResumeKind? _resumeKind(Object? value) => switch (value) {
  'chat_turn' => AiInteractionResumeKind.chatTurn,
  'proposal_apply' => AiInteractionResumeKind.proposalApply,
  'host' => AiInteractionResumeKind.host,
  'none' => AiInteractionResumeKind.none,
  _ => null,
};

String _resumeWire(AiInteractionResumeKind value) => switch (value) {
  AiInteractionResumeKind.chatTurn => 'chat_turn',
  AiInteractionResumeKind.proposalApply => 'proposal_apply',
  AiInteractionResumeKind.host => 'host',
  AiInteractionResumeKind.none => 'none',
};
