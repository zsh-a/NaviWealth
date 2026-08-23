/// Local-only developer-mode issue capture for the NaviWealth dogfood loop.
///
/// Reports are inert records. Creating one never sends data, creates a remote
/// issue, or invokes an Agent. Export is a separate, explicit user action.
library;

import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../ai/contracts/contracts.dart';
import '../config/app_version.dart';
import '../persistence/app_database.dart';

const int kDeveloperIssueToolErrorLimit = 5;

class DeveloperIssueContext {
  const DeveloperIssueContext({required this.route, this.domain});

  final String route;
  final String? domain;
}

class DeveloperIssueToolError {
  const DeveloperIssueToolError({
    required this.traceId,
    required this.toolName,
    required this.errorCode,
  });

  final String traceId;
  final String toolName;
  final String errorCode;

  Map<String, Object?> toJson() => <String, Object?>{
    'trace_id': traceId,
    'tool_name': toolName,
    'error_code': errorCode,
  };

  factory DeveloperIssueToolError.fromJson(Map<String, Object?> json) {
    return DeveloperIssueToolError(
      traceId: json['trace_id']! as String,
      toolName: json['tool_name']! as String,
      errorCode: json['error_code']! as String,
    );
  }
}

class DeveloperIssue {
  const DeveloperIssue({
    required this.id,
    required this.ownerUserId,
    required this.description,
    required this.route,
    required this.appVersion,
    required this.buildNumber,
    required this.commitSha,
    required this.toolErrors,
    required this.createdAt,
    this.domain,
    this.traceId,
    this.screenshotPath,
    this.exportedAt,
  });

  final String id;
  final String ownerUserId;
  final String description;
  final String route;
  final String? domain;
  final String appVersion;
  final String buildNumber;
  final String commitSha;
  final String? traceId;
  final List<DeveloperIssueToolError> toolErrors;
  final String? screenshotPath;
  final DateTime createdAt;
  final DateTime? exportedAt;

  Map<String, Object?> toExportJson() => <String, Object?>{
    'schema': 'naviwealth.developer_issue.v1',
    'id': id,
    'description': description,
    'context': <String, Object?>{
      'route': route,
      if (domain != null) 'domain': domain,
    },
    'build': <String, Object?>{
      'version': appVersion,
      'number': buildNumber,
      'commit': commitSha,
    },
    if (traceId != null) 'latest_trace_id': traceId,
    if (toolErrors.isNotEmpty)
      'recent_tool_errors': toolErrors
          .map((error) => error.toJson())
          .toList(growable: false),
    'has_screenshot': screenshotPath != null,
    'created_at': createdAt.toUtc().toIso8601String(),
  };

  String toExportText() =>
      const JsonEncoder.withIndent('  ').convert(toExportJson());

  DeveloperIssue copyWith({DateTime? exportedAt}) => DeveloperIssue(
    id: id,
    ownerUserId: ownerUserId,
    description: description,
    route: route,
    domain: domain,
    appVersion: appVersion,
    buildNumber: buildNumber,
    commitSha: commitSha,
    traceId: traceId,
    toolErrors: toolErrors,
    screenshotPath: screenshotPath,
    createdAt: createdAt,
    exportedAt: exportedAt ?? this.exportedAt,
  );
}

abstract interface class DeveloperIssueStore {
  Future<DeveloperIssue> create(DeveloperIssue issue);

  Future<List<DeveloperIssue>> list({
    required String ownerUserId,
    int limit = 20,
  });

  Future<void> markExported({
    required String ownerUserId,
    required String issueId,
    required DateTime at,
  });
}

class SqliteDeveloperIssueStore implements DeveloperIssueStore {
  const SqliteDeveloperIssueStore(this._db);

  final AppDatabase _db;

  @override
  Future<DeveloperIssue> create(DeveloperIssue issue) async {
    await _db.customStatement(
      '''
      INSERT INTO developer_issues (
        id, owner_user_id, description, route, domain, app_version,
        build_number, commit_sha, trace_id, tool_errors_json,
        screenshot_path, created_at, exported_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ''',
      <Object?>[
        issue.id,
        issue.ownerUserId,
        issue.description,
        issue.route,
        issue.domain,
        issue.appVersion,
        issue.buildNumber,
        issue.commitSha,
        issue.traceId,
        jsonEncode(
          issue.toolErrors
              .map((error) => error.toJson())
              .toList(growable: false),
        ),
        issue.screenshotPath,
        issue.createdAt.millisecondsSinceEpoch,
        issue.exportedAt?.millisecondsSinceEpoch,
      ],
    );
    return issue;
  }

  @override
  Future<List<DeveloperIssue>> list({
    required String ownerUserId,
    int limit = 20,
  }) async {
    if (limit <= 0) return const <DeveloperIssue>[];
    final rows = await _db
        .customSelect(
          '''
          SELECT * FROM developer_issues
          WHERE owner_user_id = ?
          ORDER BY created_at DESC, id DESC
          LIMIT ?
          ''',
          variables: <Variable<Object>>[
            Variable.withString(ownerUserId),
            Variable.withInt(limit),
          ],
        )
        .get();
    return rows.map(_developerIssueFromRow).toList(growable: false);
  }

  @override
  Future<void> markExported({
    required String ownerUserId,
    required String issueId,
    required DateTime at,
  }) async {
    await _db.customStatement(
      'UPDATE developer_issues SET exported_at = ? '
      'WHERE owner_user_id = ? AND id = ?',
      <Object?>[at.toUtc().millisecondsSinceEpoch, ownerUserId, issueId],
    );
  }
}

class DeveloperIssueCaptureService {
  DeveloperIssueCaptureService({
    required DeveloperIssueStore store,
    Uuid uuid = const Uuid(),
  }) : _store = store,
       _uuid = uuid;

  final DeveloperIssueStore _store;
  final Uuid _uuid;

  Future<DeveloperIssue> capture({
    required String ownerUserId,
    required String description,
    required DeveloperIssueContext context,
    required AppVersionInfo version,
    required List<AiTrace> recentTraces,
    String? screenshotPath,
    DateTime? at,
  }) async {
    final normalizedDescription = description.trim();
    if (normalizedDescription.isEmpty) {
      throw ArgumentError.value(description, 'description', 'is empty');
    }
    final traceId = recentTraces.firstOrNull?.requestId;
    final toolErrors = <DeveloperIssueToolError>[];
    for (final trace in recentTraces) {
      for (final span in trace.toolSpans) {
        if (!span.isError ||
            toolErrors.length >= kDeveloperIssueToolErrorLimit) {
          continue;
        }
        toolErrors.add(
          DeveloperIssueToolError(
            traceId: trace.requestId,
            toolName: span.name,
            errorCode: span.errorCode ?? 'unknown_tool_error',
          ),
        );
      }
      if (toolErrors.length >= kDeveloperIssueToolErrorLimit) break;
    }
    return _store.create(
      DeveloperIssue(
        id: _uuid.v4(),
        ownerUserId: ownerUserId,
        description: normalizedDescription,
        route: context.route,
        domain: context.domain,
        appVersion: version.version,
        buildNumber: version.buildNumber,
        commitSha: version.commitSha,
        traceId: traceId,
        toolErrors: toolErrors,
        screenshotPath: screenshotPath,
        createdAt: (at ?? DateTime.now()).toUtc(),
      ),
    );
  }
}

DeveloperIssue _developerIssueFromRow(QueryRow row) {
  final rawErrors = jsonDecode(row.read<String>('tool_errors_json'));
  final errors = <DeveloperIssueToolError>[
    if (rawErrors case final List<Object?> values)
      for (final value in values)
        if (value case final Map<Object?, Object?> fields)
          DeveloperIssueToolError.fromJson(
            fields.map<String, Object?>(
              (key, item) => MapEntry(key.toString(), item),
            ),
          ),
  ];
  final exportedMillis = row.read<int?>('exported_at');
  return DeveloperIssue(
    id: row.read<String>('id'),
    ownerUserId: row.read<String>('owner_user_id'),
    description: row.read<String>('description'),
    route: row.read<String>('route'),
    domain: row.read<String?>('domain'),
    appVersion: row.read<String>('app_version'),
    buildNumber: row.read<String>('build_number'),
    commitSha: row.read<String>('commit_sha'),
    traceId: row.read<String?>('trace_id'),
    toolErrors: errors,
    screenshotPath: row.read<String?>('screenshot_path'),
    createdAt: DateTime.fromMillisecondsSinceEpoch(
      row.read<int>('created_at'),
      isUtc: true,
    ),
    exportedAt: exportedMillis == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(exportedMillis, isUtc: true),
  );
}
