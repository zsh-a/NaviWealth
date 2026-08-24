import '../../core/ai/contracts/interaction.dart';

typedef VoiceInteractionResponseDecoder =
    AiInteractionResponse? Function(
      AiInteractionEnvelope interaction,
      String transcript,
    );

/// Converts only unambiguous, non-typed voice responses into the existing HITL
/// contract. Typed confirmation deliberately returns null so the host keeps
/// the required on-screen confirmation path.
AiInteractionResponse? decodeVoiceInteractionResponse(
  AiInteractionEnvelope interaction,
  String transcript,
) {
  if (interaction.mode == AiInteractionMode.typed) return null;

  final normalized = transcript.trim().toLowerCase();
  if (normalized.isEmpty) return null;

  switch (interaction.kind) {
    case AiInteractionKind.approval:
      if (_approvalWords.contains(normalized)) {
        return AiInteractionResponse(
          interactionId: interaction.interactionId,
          action: AiInteractionAction.approve,
          value: true,
          respondedAt: DateTime.now().toUtc(),
          respondedBy: 'voice',
        );
      }
      if (_rejectionWords.contains(normalized)) {
        return AiInteractionResponse(
          interactionId: interaction.interactionId,
          action: AiInteractionAction.reject,
          value: false,
          respondedAt: DateTime.now().toUtc(),
          respondedBy: 'voice',
        );
      }
      return null;
    case AiInteractionKind.choice:
      for (final option in interaction.options) {
        if (normalized == option.id.toLowerCase() ||
            normalized == option.label.trim().toLowerCase()) {
          return AiInteractionResponse(
            interactionId: interaction.interactionId,
            action: AiInteractionAction.submit,
            value: option.id,
            respondedAt: DateTime.now().toUtc(),
            respondedBy: 'voice',
          );
        }
      }
      return null;
    case AiInteractionKind.input:
      return AiInteractionResponse(
        interactionId: interaction.interactionId,
        action: AiInteractionAction.submit,
        value: transcript.trim(),
        respondedAt: DateTime.now().toUtc(),
        respondedBy: 'voice',
      );
  }
}

const _approvalWords = <String>{
  '确认',
  '确定',
  '同意',
  '批准',
  '确认执行',
  'yes',
  'confirm',
  'approve',
};

const _rejectionWords = <String>{
  '取消',
  '拒绝',
  '不要',
  '不执行',
  'no',
  'reject',
  'cancel',
};
