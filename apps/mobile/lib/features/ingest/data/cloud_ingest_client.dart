/// §5.10.10 / S5b-vision — Vision ingest client surface.
///
/// W-D7 deleted the cloud Vision relay (`POST /ingest/parse`) together
/// with the rest of the cloud AI backend. Vision parsing now runs
/// device-direct ([DeviceVisionIngestClient]); when no on-device
/// runtime exists the [CloudIngestClient] slot is the
/// [UnavailableCloudIngestClient] stub, which fails with a clear
/// "configure a key" message instead of hitting a dead endpoint. The
/// pure wire mappers below are retained — the device path reuses them.
library;

import '../domain/ingest_models.dart';

class CloudIngestException implements Exception {
  CloudIngestException(this.message);
  final String message;
  @override
  String toString() => 'CloudIngestException: $message';
}

abstract class CloudIngestClient {
  Future<List<ParsedTransaction>> parse({
    required IngestSourceKind kind,
    required String mime,
    required String contentBase64,
    String? currencyHint,
  });
}

/// Wire name the backend's `validate_kind` expects (snake_case, distinct
/// from `IngestSourceKind.wire` which is the Dart enum name).
String cloudIngestKindWire(IngestSourceKind kind) => switch (kind) {
  IngestSourceKind.receiptImage => 'receipt_image',
  IngestSourceKind.statementPdf => 'statement_pdf',
  // Device-parsable / email never reach the cloud Vision route.
  _ => kind.name,
};

/// Pure: one wire row → [ParsedTransaction]. Returns null when the row
/// lacks the fields the draft/confirm path needs (mirrors the backend's
/// own skip-malformed-rows stance).
ParsedTransaction? parsedTransactionFromWire(Map<String, Object?> row) {
  final amount = (row['amount_minor'] as num?)?.toInt();
  final currency = (row['currency'] as String?)?.trim();
  final occurredRaw = (row['occurred_at'] as String?)?.trim();
  if (amount == null || amount == 0) return null;
  if (currency == null || currency.isEmpty) return null;
  if (occurredRaw == null || occurredRaw.isEmpty) return null;
  final parsedDate = DateTime.tryParse(occurredRaw);
  if (parsedDate == null) return null;
  // Backend sends date-only `YYYY-MM-DD`; pin to the UTC calendar day
  // (same convention as csv_ingest_parser) so a +08:00 runner doesn't
  // shift it to the previous day.
  final occurredAt = DateTime.utc(
    parsedDate.year,
    parsedDate.month,
    parsedDate.day,
  );

  final hint = (row['category_hint'] as String?)?.trim();
  return ParsedTransaction(
    description: ((row['description'] as String?) ?? '').trim().isEmpty
        ? '未命名交易'
        : (row['description'] as String).trim(),
    // S5b backend already follows the expense-negative convention; keep
    // it regardless so dedup matches the device path's sign.
    amountMinor: -amount.abs(),
    currency: currency.toUpperCase(),
    occurredAt: occurredAt.toUtc(),
    categoryHint: (hint == null || hint.isEmpty) ? null : hint,
    confidence: (row['confidence'] as num?)?.toDouble() ?? 0.6,
  );
}

/// Pure: full `{model, drafts:[...]}` response → parsed list.
List<ParsedTransaction> parseCloudIngestResponse(Map<String, Object?> body) {
  final raw = body['drafts'];
  if (raw is! List) return const <ParsedTransaction>[];
  final out = <ParsedTransaction>[];
  for (final row in raw) {
    if (row is Map) {
      final parsed = parsedTransactionFromWire(
        row.map((k, v) => MapEntry(k.toString(), v)),
      );
      if (parsed != null) out.add(parsed);
    }
  }
  return out;
}

/// W-D7 replacement for the deleted `DioCloudIngestClient`. The cloud
/// Vision relay is gone; with no on-device runtime, Vision ingest is
/// simply unavailable. `IngestController._ingestCloud` catches
/// [CloudIngestException] and surfaces `message` as the rejected
/// reason — so the user gets actionable guidance, not a dead request.
class UnavailableCloudIngestClient implements CloudIngestClient {
  const UnavailableCloudIngestClient();

  @override
  Future<List<ParsedTransaction>> parse({
    required IngestSourceKind kind,
    required String mime,
    required String contentBase64,
    String? currencyHint,
  }) async {
    throw CloudIngestException(
      '图像/PDF 解析需要在设置中配置自带 API Key 后启用（本机直连模型）；'
      'Web 端暂不支持。也可改用 CSV / 文本粘贴导入。',
    );
  }
}
