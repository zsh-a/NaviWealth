import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/ai/contracts/interaction.dart';

void main() {
  test('choice interaction round-trips the Rust wire contract', () {
    final interaction = AiInteractionEnvelope(
      interactionId: 'interaction_1',
      kind: AiInteractionKind.choice,
      mode: AiInteractionMode.oneTap,
      status: AiInteractionStatus.pending,
      title: 'Choose',
      prompt: 'Pick one',
      options: const <AiInteractionOption>[
        AiInteractionOption(id: 'a', label: 'A'),
        AiInteractionOption(id: 'b', label: 'B'),
      ],
      responseSchema: const <String, Object?>{'type': 'object'},
      metadata: const <String, Object?>{'allow_custom': false},
      resumeKind: AiInteractionResumeKind.chatTurn,
      resumeToken: 'turn_1',
      createdAt: DateTime.utc(2026, 7, 23),
    );

    final restored = AiInteractionEnvelope.tryParse(interaction.toJson());

    expect(restored, isNotNull);
    expect(restored?.kind, AiInteractionKind.choice);
    expect(restored?.mode, AiInteractionMode.oneTap);
    expect(restored?.options.map((option) => option.id), ['a', 'b']);
    expect(restored?.resumeKind, AiInteractionResumeKind.chatTurn);
  });

  test('typed interaction fails closed without confirmation rules', () {
    final malformed = <String, Object?>{
      'protocol_version': 'agent.v1',
      'interaction_id': 'interaction_1',
      'kind': 'approval',
      'mode': 'typed',
      'status': 'pending',
      'title': 'Approve',
      'response_schema': const <String, Object?>{},
      'payload': const <String, Object?>{},
      'metadata': const <String, Object?>{},
      'resume': const <String, Object?>{'kind': 'proposal_apply'},
      'created_at': '2026-07-23T00:00:00Z',
    };

    expect(AiInteractionEnvelope.tryParse(malformed), isNull);
  });

  test('response serializes the generic resume payload', () {
    final response = AiInteractionResponse(
      interactionId: 'interaction_1',
      action: AiInteractionAction.approve,
      value: const <String, Object?>{'accepted': true},
      confirmationText: '确认',
      respondedBy: 'user-1',
      respondedAt: DateTime.utc(2026, 7, 23, 1),
    ).toJson();

    expect(response['protocol_version'], 'agent.v1');
    expect(response['action'], 'approve');
    expect(response['confirmation_text'], '确认');
  });
}
