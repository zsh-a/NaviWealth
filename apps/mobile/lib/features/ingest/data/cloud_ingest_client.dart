/// §5.10.10 / S5b-vision — mobile → backend cloud Vision client.
///
/// Posts a base64 receipt image / statement PDF to `POST /ingest/parse`
/// and maps the structured reply to [ParsedTransaction]s. The backend
/// is stateless (image discarded in-request); dedup + the draft queue
/// + confirmation all stay on-device. The privacy gate (S5b-gate) has
/// already decided this call is permitted before we get here.
library;

import 'package:dio/dio.dart';

import '../../../core/auth/auth_session.dart';
import '../domain/ingest_models.dart';

class CloudIngestException implements Exception {
  CloudIngestException(this.message);
  final String message;
  @override
  String toString() => 'CloudIngestException: $message';
}

abstract class CloudIngestClient {
  Future<List<ParsedTransaction>> parse({
    required AuthSession session,
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

class DioCloudIngestClient implements CloudIngestClient {
  DioCloudIngestClient({required Dio dio, this.protocolVersion = '1'})
    : _dio = dio;

  final Dio _dio;
  final String protocolVersion;

  @override
  Future<List<ParsedTransaction>> parse({
    required AuthSession session,
    required IngestSourceKind kind,
    required String mime,
    required String contentBase64,
    String? currencyHint,
  }) async {
    final Response<Object?> res;
    try {
      res = await _dio.post<Object?>(
        '/ingest/parse',
        data: <String, Object?>{
          'kind': cloudIngestKindWire(kind),
          'mime': mime,
          'content_base64': contentBase64,
          if (currencyHint != null && currencyHint.isNotEmpty)
            'currency_hint': currencyHint,
        },
        options: Options(
          headers: <String, Object>{
            'Content-Type': 'application/json; charset=utf-8',
            'Authorization': 'Bearer ${session.accessToken}',
            'Sync-Protocol-Version': protocolVersion,
          },
          validateStatus: (_) => true,
        ),
      );
    } on DioException catch (e) {
      throw CloudIngestException('网络错误：${e.message ?? e.type.name}');
    }

    final status = res.statusCode ?? 0;
    final data = res.data;
    if (status < 200 || status >= 300) {
      final msg = data is Map && data['message'] is String
          ? data['message'] as String
          : 'HTTP $status';
      throw CloudIngestException(msg);
    }
    if (data is! Map) {
      throw CloudIngestException('响应格式异常');
    }
    return parseCloudIngestResponse(
      data.map((k, v) => MapEntry(k.toString(), v)),
    );
  }
}
