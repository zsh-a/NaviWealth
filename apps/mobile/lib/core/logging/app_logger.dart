import 'dart:async';
import 'dart:convert';

import 'package:talker/talker.dart';
import 'package:uuid/uuid.dart';

import '../config/app_config.dart';
import 'crash_reporter.dart';

/// Thin wrapper over the `talker` package that:
///   * filters verbosity per [AppEnvironment] (dev = verbose, staging = info,
///     prod = warning),
///   * forwards `warning` and above to the registered [CrashReporter] so a
///     single call site emits both a console log and a crash breadcrumb,
///   * emits privacy-safe structured events and timed operation stages,
///   * never throws — logging must not be load-bearing.
///
/// Construct one instance per app (see `loggerProvider`). Call
/// [AppLogger.bootstrap] at startup to install the global default used by code
/// paths that run before Riverpod is ready (e.g. zone error handlers).
Talker createAppTalker() {
  return Talker(
    settings: TalkerSettings(
      useConsoleLogs: true,
      useHistory: true,
      maxHistoryItems: 1000,
      timeFormat: TimeFormat.timeAndSeconds,
    ),
  );
}

class AppLogger {
  AppLogger({
    required AppEnvironment environment,
    CrashReporter? crashReporter,
    Talker? talker,
  }) : _environment = environment,
       _crashReporter = crashReporter ?? const NoopCrashReporter(),
       _talker = talker ?? createAppTalker();

  final AppEnvironment _environment;
  final CrashReporter _crashReporter;
  final Talker _talker;

  AppEnvironment get environment => _environment;

  /// Expose the underlying [Talker] for downstream use (Dio interceptors,
  /// TalkerScreen, route observer).
  Talker get talker => _talker;

  static AppLogger _instance = AppLogger(environment: AppEnvironment.dev);

  /// Globally accessible logger for code that runs before DI is set up.
  /// Inside the widget tree, prefer `ref.read(loggerProvider)`.
  static AppLogger get instance => _instance;

  /// Replace the global [instance] — call once during bootstrap.
  static void bootstrap(AppLogger logger) {
    _instance = logger;
  }

  void t(Object? message) {
    if (_environment != AppEnvironment.dev) return;
    _safe(() => _talker.verbose(message));
  }

  void d(Object? message) {
    if (_environment != AppEnvironment.dev) return;
    _safe(() => _talker.debug(message));
  }

  void i(Object? message) {
    if (_environment == AppEnvironment.prod) return;
    _safe(() => _talker.info(message));
  }

  void w(Object? message, {Object? error, StackTrace? stackTrace}) {
    _safe(() => _talker.warning(message, error, stackTrace));
    _safe(
      () => _crashReporter.recordBreadcrumb(
        message: '$message',
        level: BreadcrumbLevel.warning,
      ),
    );
  }

  void e(Object? message, {Object? error, StackTrace? stackTrace}) {
    _safe(() => _talker.error(message, error, stackTrace));
    if (error != null) {
      _safe(
        () => _crashReporter.captureError(
          error,
          stackTrace: stackTrace,
          hint: '$message',
        ),
      );
    } else {
      _safe(
        () => _crashReporter.captureMessage(
          '$message',
          level: BreadcrumbLevel.error,
        ),
      );
    }
  }

  /// Emits a JSON event after applying the global diagnostic field policy.
  ///
  /// Arbitrary business objects and free-form strings are intentionally not
  /// accepted. Unsafe keys or values are dropped before Talker, crash
  /// breadcrumbs, and export surfaces can observe them.
  void event(
    String name, {
    String? operationId,
    AppLogLevel level = AppLogLevel.info,
    Map<String, Object?> fields = const {},
    Object? error,
    StackTrace? stackTrace,
  }) {
    final safeName = _safeToken(name, fallback: 'diagnostic.invalid_event');
    final safeFields = _sanitizeDiagnosticFields(fields);
    final errorType = error == null
        ? null
        : _safeToken(error.runtimeType.toString(), fallback: 'unknown_error');
    final payload = <String, Object?>{'event': safeName, ...safeFields};
    if (operationId != null) {
      payload['operation_id'] = _safeToken(operationId, fallback: 'invalid');
    }
    if (errorType != null) payload['error_type'] = errorType;
    final message = jsonEncode(payload);
    final errorCode = safeFields['error_code'];
    final safeError = errorType == null
        ? null
        : DiagnosticLogError(
            type: errorType,
            code: errorCode is String ? errorCode : null,
          );
    switch (level) {
      case AppLogLevel.debug:
        d(message);
      case AppLogLevel.info:
        i(message);
      case AppLogLevel.warning:
        w(message, error: safeError, stackTrace: stackTrace);
      case AppLogLevel.error:
        e(message, error: safeError, stackTrace: stackTrace);
    }
  }

  AppLogOperation startOperation(
    String name, {
    Map<String, Object?> fields = const {},
    String? operationId,
  }) {
    return AppLogOperation._(
      logger: this,
      name: _safeToken(name, fallback: 'diagnostic.operation'),
      operationId: operationId ?? const Uuid().v4(),
      fields: fields,
    );
  }

  void _safe(void Function() action) {
    try {
      action();
    } catch (_) {
      // Logging must never alter the business operation it describes.
    }
  }
}

enum AppLogLevel { debug, info, warning, error }

/// A privacy-safe, correlated operation with timed child stages.
final class AppLogOperation {
  AppLogOperation._({
    required AppLogger logger,
    required this.name,
    required this.operationId,
    required Map<String, Object?> fields,
  }) : _logger = logger,
       _fields = Map.unmodifiable(fields),
       _stopwatch = Stopwatch()..start() {
    _logger.event(
      '$name.started',
      operationId: operationId,
      fields: {..._fields, 'outcome': 'started'},
    );
  }

  final AppLogger _logger;
  final Map<String, Object?> _fields;
  final Stopwatch _stopwatch;
  final String name;
  final String operationId;
  bool _terminal = false;

  bool get isTerminal => _terminal;

  Future<T> step<T>(
    String stage,
    FutureOr<T> Function() action, {
    Map<String, Object?> fields = const {},
    Duration slowThreshold = const Duration(seconds: 2),
    AppLogLevel failureLevel = AppLogLevel.warning,
  }) async {
    final safeStage = _safeToken(stage, fallback: 'unknown_stage');
    final stopwatch = Stopwatch()..start();
    _logger.event(
      '$name.stage.started',
      operationId: operationId,
      level: AppLogLevel.debug,
      fields: {..._fields, ...fields, 'stage': safeStage, 'outcome': 'started'},
    );
    Timer? slowTimer;
    if (slowThreshold > Duration.zero) {
      slowTimer = Timer(slowThreshold, () {
        _logger.event(
          '$name.stage.slow',
          operationId: operationId,
          level: AppLogLevel.warning,
          fields: {
            ..._fields,
            ...fields,
            'stage': safeStage,
            'outcome': 'running',
            'duration_ms': stopwatch.elapsedMilliseconds,
          },
        );
      });
    }
    try {
      final result = await Future<T>.sync(action);
      _logger.event(
        '$name.stage.completed',
        operationId: operationId,
        level: AppLogLevel.debug,
        fields: {
          ..._fields,
          ...fields,
          'stage': safeStage,
          'outcome': 'success',
          'duration_ms': stopwatch.elapsedMilliseconds,
        },
      );
      return result;
    } catch (error, stackTrace) {
      _logger.event(
        '$name.stage.failed',
        operationId: operationId,
        level: failureLevel,
        fields: {
          ..._fields,
          ...fields,
          'stage': safeStage,
          'outcome': 'failed',
          'duration_ms': stopwatch.elapsedMilliseconds,
          'error_code': diagnosticErrorCode(error),
        },
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    } finally {
      slowTimer?.cancel();
      stopwatch.stop();
    }
  }

  void complete({
    String outcome = 'success',
    Map<String, Object?> fields = const {},
  }) {
    if (_terminal) return;
    _terminal = true;
    _stopwatch.stop();
    _logger.event(
      '$name.completed',
      operationId: operationId,
      fields: {
        ..._fields,
        ...fields,
        'outcome': outcome,
        'duration_ms': _stopwatch.elapsedMilliseconds,
      },
    );
  }

  void fail(
    Object error, {
    StackTrace? stackTrace,
    String? stage,
    String? errorCode,
    bool retryable = false,
    Map<String, Object?> fields = const {},
    AppLogLevel level = AppLogLevel.error,
  }) {
    if (_terminal) return;
    _terminal = true;
    _stopwatch.stop();
    final terminalFields = <String, Object?>{
      ..._fields,
      ...fields,
      'outcome': 'failed',
      'duration_ms': _stopwatch.elapsedMilliseconds,
      'error_code': errorCode ?? diagnosticErrorCode(error),
      'retryable': retryable,
    };
    if (stage != null) terminalFields['stage'] = stage;
    _logger.event(
      '$name.failed',
      operationId: operationId,
      level: level,
      fields: terminalFields,
      error: error,
      stackTrace: stackTrace,
    );
  }

  void cancel({String? stage}) {
    if (_terminal) return;
    complete(
      outcome: 'cancelled',
      fields: stage == null ? const {} : {'stage': stage},
    );
  }
}

final class DiagnosticLogError implements Exception {
  const DiagnosticLogError({required this.type, this.code});

  final String type;
  final String? code;

  @override
  String toString() => code == null
      ? 'DiagnosticLogError(type=$type)'
      : 'DiagnosticLogError(type=$type, code=$code)';
}

/// Optional contract for domain errors that expose a stable, privacy-safe
/// diagnostic code without making the logging layer import domain types.
abstract interface class DiagnosticError {
  String get diagnosticErrorCode;
}

String diagnosticErrorCode(Object error) {
  if (error is TimeoutException) return 'timeout';
  final source = error is DiagnosticError
      ? error.diagnosticErrorCode
      : error.runtimeType.toString();
  final snake = source
      .replaceAllMapped(
        RegExp(r'([a-z0-9])([A-Z])'),
        (match) => '${match.group(1)}_${match.group(2)}',
      )
      .toLowerCase();
  return _safeToken(snake, fallback: 'unknown_error');
}

/// Final defense for copy/share surfaces that may contain legacy free-form
/// logs emitted before structured diagnostic events were adopted.
String sanitizeDiagnosticExport(String input) {
  var output = input;
  output = output.replaceAll(
    RegExp(r'bearer\s+[a-z0-9._~+/-]+=*', caseSensitive: false),
    'Bearer <redacted>',
  );
  output = output.replaceAll(
    RegExp(r'eyJ[a-zA-Z0-9_-]+\.[a-zA-Z0-9_-]+\.[a-zA-Z0-9_-]+'),
    '<redacted-jwt>',
  );
  output = output.replaceAllMapped(
    RegExp(
      r'(access_token|api_key|token)(["\s:=]+)([^\s,}\]]+)',
      caseSensitive: false,
    ),
    (match) => '${match.group(1)}${match.group(2)}<redacted>',
  );
  output = output.replaceAll(
    RegExp(r'[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}', caseSensitive: false),
    '<redacted-email>',
  );
  return output;
}

Map<String, Object?> _sanitizeDiagnosticFields(Map<String, Object?> fields) {
  final result = <String, Object?>{};
  for (final entry in fields.entries) {
    final key = _safeToken(entry.key, fallback: '');
    if (key.isEmpty || !_isAllowedDiagnosticKey(key)) continue;
    final value = entry.value;
    if (value is bool || value is num) {
      result[key] = value;
    } else if (value is String && _safeValuePattern.hasMatch(value)) {
      result[key] = value.length <= 80 ? value : value.substring(0, 80);
    } else if (value is Enum) {
      result[key] = _safeToken(value.name, fallback: 'unknown');
    }
  }
  return result;
}

bool _isAllowedDiagnosticKey(String key) {
  if (_allowedDiagnosticKeys.contains(key)) return true;
  return key.startsWith('has_') ||
      key.startsWith('is_') ||
      key.endsWith('_count') ||
      key.endsWith('_ms') ||
      key.endsWith('_type') ||
      key.endsWith('_code') ||
      key.endsWith('_status') ||
      key.endsWith('_outcome') ||
      key.endsWith('_source') ||
      key.endsWith('_version');
}

String _safeToken(String value, {required String fallback}) {
  final normalized = value.trim().toLowerCase().replaceAll(' ', '_');
  return _safeValuePattern.hasMatch(normalized) ? normalized : fallback;
}

final RegExp _safeValuePattern = RegExp(r'^[a-z0-9_.:-]{1,128}$');

const Set<String> _allowedDiagnosticKeys = {
  'operation_id',
  'parent_operation_id',
  'domain',
  'stage',
  'outcome',
  'attempt',
  'retryable',
  'timed_out',
  'provider',
  'endpoint',
  'market',
  'currency',
  'batch_size',
  'availability',
};
