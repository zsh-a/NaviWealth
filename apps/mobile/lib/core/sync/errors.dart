/// Error envelope returned by the backend (`docs/sync/sync-v2.md` §5).
class SyncErrorBody {
  const SyncErrorBody({required this.code, this.message});
  final String code;
  final String? message;

  static SyncErrorBody fromJson(Object? raw) {
    if (raw is Map) {
      final code = (raw['code'] as String?) ?? 'unknown';
      final message = raw['message'] as String?;
      return SyncErrorBody(code: code, message: message);
    }
    return const SyncErrorBody(code: 'unknown');
  }

  @override
  String toString() =>
      'SyncErrorBody($code${message == null ? '' : ': $message'})';
}

/// Categorises sync failures the engine reacts to differently.
enum SyncErrorKind {
  /// `401` — re-authenticate then retry.
  unauthorized,

  /// `400` family — request is malformed; ops should be dropped, NOT retried.
  badRequest,

  /// `413 payload_too_large` — split the batch.
  payloadTooLarge,

  /// `426` — protocol version mismatch; surface "update required".
  protocolVersion,

  /// `429` — honour `Retry-After`.
  rateLimited,

  /// `5xx` — exponential backoff.
  server,

  /// IOException / SocketException — network-layer.
  network,

  /// Anything else.
  unknown,
}

class SyncException implements Exception {
  SyncException(
    this.kind, {
    this.code,
    this.message,
    this.statusCode,
    this.retryAfter,
    this.cause,
  });

  final SyncErrorKind kind;
  final String? code;
  final String? message;
  final int? statusCode;
  final Duration? retryAfter;
  final Object? cause;

  bool get isRetryable {
    switch (kind) {
      case SyncErrorKind.network:
      case SyncErrorKind.server:
      case SyncErrorKind.rateLimited:
      case SyncErrorKind.unauthorized:
        return true;
      case SyncErrorKind.payloadTooLarge:
      case SyncErrorKind.badRequest:
      case SyncErrorKind.protocolVersion:
      case SyncErrorKind.unknown:
        return false;
    }
  }

  @override
  String toString() =>
      'SyncException(kind=$kind, code=$code, '
      'status=$statusCode, msg=$message)';
}
