library;

import 'dart:convert';

enum GarminSyncIssueSeverity { info, warning, error }

enum GarminSyncIssueAction { none, retry, retryLater, reconnect }

class GarminSyncIssue {
  const GarminSyncIssue({
    required this.code,
    required this.severity,
    required this.message,
    this.endpoint,
    this.detail,
    this.retryable = false,
    this.action = GarminSyncIssueAction.none,
  });

  final String code;
  final GarminSyncIssueSeverity severity;
  final String message;
  final String? endpoint;
  final String? detail;
  final bool retryable;
  final GarminSyncIssueAction action;

  bool get isFatal => severity == GarminSyncIssueSeverity.error;
  bool get requiresReconnect =>
      code == 'auth_expired' || action == GarminSyncIssueAction.reconnect;

  factory GarminSyncIssue.persistFailed(Object error) => GarminSyncIssue(
    code: 'persist_failed',
    severity: GarminSyncIssueSeverity.error,
    message: 'Garmin snapshot could not be saved',
    detail: error.toString(),
    retryable: true,
    action: GarminSyncIssueAction.retry,
  );

  factory GarminSyncIssue.noSnapshot() => const GarminSyncIssue(
    code: 'snapshot_missing',
    severity: GarminSyncIssueSeverity.error,
    message: 'Garmin sync produced metrics but no snapshot',
    retryable: true,
    action: GarminSyncIssueAction.retry,
  );

  factory GarminSyncIssue.notPersisted() => const GarminSyncIssue(
    code: 'snapshot_not_persisted',
    severity: GarminSyncIssueSeverity.error,
    message: 'Garmin snapshot was not persisted',
    retryable: true,
    action: GarminSyncIssueAction.retry,
  );

  factory GarminSyncIssue.unsupportedSnapshot() => const GarminSyncIssue(
    code: 'snapshot_unsupported',
    severity: GarminSyncIssueSeverity.error,
    message: 'Garmin snapshot did not contain supported HealthSnapshot rows',
    retryable: false,
    action: GarminSyncIssueAction.none,
  );

  factory GarminSyncIssue.fromRaw(String raw) {
    final trimmed = raw.trim();
    if (trimmed.startsWith('{')) {
      try {
        final decoded = jsonDecode(trimmed);
        final map = _asStringMap(decoded);
        if (map != null) {
          if (map['source'] == 'healthos.garmin') {
            return GarminSyncIssue(
              code: _string(map['code']) ?? 'unknown',
              severity: _severity(_string(map['severity'])),
              endpoint: _string(map['endpoint']),
              message: _string(map['message']) ?? 'Garmin sync issue',
              detail: _string(map['detail']),
              retryable: map['retryable'] == true,
              action: _action(_string(map['action'])),
            );
          }
        }
      } catch (_) {
        // Fall through to legacy string classification.
      }
    }
    return GarminSyncIssue.fromLegacyMessage(raw);
  }

  factory GarminSyncIssue.fromLegacyMessage(String message) {
    final lower = message.toLowerCase();
    if (lower.contains('di token refresh failed') ||
        lower.contains('401 unauthorized') ||
        lower.contains('token expired') ||
        lower.contains('token may be expired') ||
        lower.contains('garmin auth failed')) {
      return GarminSyncIssue(
        code: 'auth_expired',
        severity: GarminSyncIssueSeverity.error,
        message: 'Garmin session expired',
        detail: message,
        retryable: false,
        action: GarminSyncIssueAction.reconnect,
      );
    }
    if (lower.contains('404 not found') ||
        lower.contains('garmin api error: 404')) {
      return GarminSyncIssue(
        code: 'endpoint_unavailable',
        severity: GarminSyncIssueSeverity.warning,
        message: 'Garmin endpoint is unavailable for this account or region',
        endpoint: _legacyEndpoint(message),
        detail: message,
        retryable: true,
        action: GarminSyncIssueAction.none,
      );
    }
    return GarminSyncIssue(
      code: 'sync_failed',
      severity: GarminSyncIssueSeverity.error,
      message: 'Garmin sync failed',
      detail: message,
      retryable: true,
      action: GarminSyncIssueAction.retry,
    );
  }

  String get logLabel {
    final endpointPart = endpoint == null ? '' : ' endpoint=$endpoint';
    final detailPart = detail == null ? '' : ' detail=$detail';
    return 'code=$code severity=${severity.name}$endpointPart action=${action.name}$detailPart';
  }
}

extension GarminSyncIssueListX on Iterable<GarminSyncIssue> {
  List<GarminSyncIssue> get fatal =>
      where((issue) => issue.isFatal).toList(growable: false);

  List<GarminSyncIssue> get warnings => where(
    (issue) => issue.severity == GarminSyncIssueSeverity.warning,
  ).toList(growable: false);

  bool get requiresReconnect => any((issue) => issue.requiresReconnect);

  GarminSyncIssue? get primary {
    final fatalIssues = fatal;
    if (fatalIssues.isNotEmpty) return fatalIssues.first;
    final warningIssues = warnings;
    if (warningIssues.isNotEmpty) return warningIssues.first;
    return null;
  }
}

List<GarminSyncIssue> parseGarminSyncIssues(Iterable<String> raw) {
  final issues = raw.map(GarminSyncIssue.fromRaw);
  final seen = <String>{};
  return [
    for (final issue in issues)
      if (seen.add(
        '${issue.code}:${issue.endpoint ?? ''}:${issue.detail ?? ''}',
      ))
        issue,
  ];
}

GarminSyncIssueSeverity _severity(String? value) {
  switch (value) {
    case 'info':
      return GarminSyncIssueSeverity.info;
    case 'warning':
      return GarminSyncIssueSeverity.warning;
    case 'error':
      return GarminSyncIssueSeverity.error;
    default:
      return GarminSyncIssueSeverity.error;
  }
}

GarminSyncIssueAction _action(String? value) {
  switch (value) {
    case 'retry':
      return GarminSyncIssueAction.retry;
    case 'retry_later':
      return GarminSyncIssueAction.retryLater;
    case 'reconnect':
      return GarminSyncIssueAction.reconnect;
    default:
      return GarminSyncIssueAction.none;
  }
}

String? _string(Object? value) {
  if (value == null) return null;
  if (value is String) return value;
  return value.toString();
}

String? _legacyEndpoint(String message) {
  final lower = message.toLowerCase();
  final match = RegExp(
    r'(activities|hrv|stress|summary|sleep|spo2|respiration|heart_rate|rhr|steps)',
  ).firstMatch(lower);
  return match?.group(1);
}

Map<String, Object?>? _asStringMap(Object? value) {
  if (value is Map<String, Object?>) return value;
  if (value is Map<Object?, Object?>) {
    return value.map<String, Object?>(
      (Object? key, Object? value) => MapEntry(key.toString(), value),
    );
  }
  return null;
}
