/// On-device Vision parse — schema / prompt / message builder /
/// extractor (§4.6 W-D5).
///
/// Verbatim Dart port of `apps/backend/src/ai/ingest/parse.rs` so a
/// receipt/statement parsed on-device (user's own key, straight to the
/// provider) yields the **same** structured rows the cloud
/// `/ingest/parse` route would. Pure — no Riverpod, no HTTP — so the
/// schema/prompt/extraction can be parity-tested against the Rust unit
/// tests (§10 drift rule: a backend change to parse.rs mirrors here in
/// the same PR).
library;

import 'anthropic/anthropic_wire.dart';

/// The single tool the model is forced (by the system prompt) to call.
const String kVisionEmitTool = 'emit_parsed_transactions';

/// Hard cap on rows accepted from one parse — bounds a hostile/confused
/// model and the response size. Mirrors `MAX_PARSED_DRAFTS`.
const int kVisionMaxParsedDrafts = 200;

/// JSON Schema for [kVisionEmitTool]. Verbatim from `parse_tool_schema`.
AnthropicToolSchema visionParseToolSchema() => const AnthropicToolSchema(
  name: kVisionEmitTool,
  description:
      'Emit every transaction found in the document. Call exactly '
      'once. amount_minor is signed integer minor units (cents); '
      'expenses are negative. occurred_at is YYYY-MM-DD. currency is '
      'an ISO-4217 code. If the document is unreadable, emit an empty '
      'list — never invent rows.',
  inputSchema: {
    'type': 'object',
    'properties': {
      'transactions': {
        'type': 'array',
        'items': {
          'type': 'object',
          'properties': {
            'description': {'type': 'string'},
            'amount_minor': {'type': 'integer'},
            'currency': {'type': 'string'},
            'occurred_at': {'type': 'string'},
            'category_hint': {
              'type': ['string', 'null'],
            },
            'confidence': {'type': 'number'},
          },
          'required': [
            'description',
            'amount_minor',
            'currency',
            'occurred_at',
          ],
        },
      },
    },
    'required': ['transactions'],
  },
);

/// Verbatim from `parse::system_prompt`.
const String kVisionSystemPrompt =
    'You are a precise financial-statement parser. Read the attached '
    'receipt or bank/credit-card statement and extract every individual '
    'transaction. Respond ONLY by calling the emit_parsed_transactions '
    'tool exactly once. Rules: amount_minor is a signed integer in the '
    "currency's minor unit (e.g. cents); money the user spent is "
    'negative; refunds/credits are positive. occurred_at is the '
    'transaction date as YYYY-MM-DD. currency is the ISO-4217 code you '
    'see on the document (fall back to the provided hint). Never '
    'fabricate values you cannot read — omit an uncertain row rather '
    'than guess. If nothing is readable, call the tool with an empty '
    'transactions list.';

/// Build the single user turn: a base64 doc block + a short
/// instruction. PDF → `document` block, everything else → `image`
/// (verbatim from `parse::build_messages`).
List<AnthropicChatMessage> buildVisionMessages({
  required String mime,
  required String contentB64,
  String? currencyHint,
}) {
  final mediaType = mime.trim().isEmpty
      ? 'application/octet-stream'
      : mime.trim();
  final source = <String, Object?>{
    'type': 'base64',
    'media_type': mediaType,
    'data': contentB64,
  };
  final docBlock = mediaType == 'application/pdf'
      ? <String, Object?>{'type': 'document', 'source': source}
      : <String, Object?>{'type': 'image', 'source': source};
  final hint = (currencyHint != null && currencyHint.isNotEmpty)
      ? " The user's primary currency is $currencyHint; prefer it when ambiguous."
      : '';
  return [
    AnthropicChatMessage(
      role: 'user',
      content: [
        docBlock,
        {
          'type': 'text',
          'text':
              'Extract every transaction from this document and call '
              'emit_parsed_transactions.$hint',
        },
      ],
    ),
  ];
}

/// Thrown when the model returned no `emit_parsed_transactions` block
/// at all. Mirrors the backend `vision_no_extraction` (422) — an empty
/// transactions list is a *valid* "nothing readable" answer, a missing
/// tool call is not.
class VisionNoExtraction implements Exception {
  const VisionNoExtraction();
  @override
  String toString() => 'VisionNoExtraction';
}

/// Pull the forced tool call out of the model reply and return the raw
/// `transactions` rows (capped at [kVisionMaxParsedDrafts]). Row→model
/// mapping + per-row validation is done by the existing mobile
/// `parsedTransactionFromWire` (shared with the cloud path), so device
/// and cloud produce identical [ParsedTransaction]s for the same model
/// JSON. Mirrors `parse::extract_drafts`' tool-presence contract.
List<Map<String, Object?>> extractVisionDraftRows(List<Object?> content) {
  Object? toolInput;
  for (final block in content) {
    if (block is! Map) continue;
    if (block['type'] != 'tool_use') continue;
    if (block['name'] != kVisionEmitTool) continue;
    toolInput = block['input'];
    break;
  }
  if (toolInput == null) throw const VisionNoExtraction();

  final rows = (toolInput is Map ? toolInput['transactions'] : null);
  if (rows is! List) return const [];
  return [
    for (final row in rows.take(kVisionMaxParsedDrafts))
      if (row is Map) row.map((k, v) => MapEntry(k.toString(), v)),
  ];
}
