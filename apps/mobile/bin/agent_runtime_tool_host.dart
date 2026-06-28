import 'dart:convert';
import 'dart:io';

/// Minimal process entry for the Rust `--tool-host` bridge.
///
/// This entry is intentionally pure Dart so `dart run` can execute it without
/// loading Flutter plugins or native FFI dependencies. It provides a safe
/// unavailable-tool response for protocol smoke tests and a shell-only mode for
/// DB-free tools such as `ask_user`. The app-backed headless adapter lives in
/// `bin/agent_runtime_tool_host_headless.dart`.
Future<void> main(List<String> args) async {
  if (args.contains('--shell')) {
    await _runShell();
    return;
  }
  if (args.isEmpty ||
      args.contains('--unavailable') ||
      args.contains('--safe')) {
    await _runUnavailable();
    return;
  }

  stderr.writeln(
    'Usage: dart run bin/agent_runtime_tool_host.dart '
    '[--unavailable|--safe|--shell]',
  );
  exitCode = 64;
}

Future<void> _runUnavailable() async {
  await for (final line
      in stdin.transform(utf8.decoder).transform(const LineSplitter())) {
    if (line.trim().isEmpty) continue;
    stdout.writeln(_handleUnavailable(line));
  }
}

Future<void> _runShell() async {
  await for (final line
      in stdin.transform(utf8.decoder).transform(const LineSplitter())) {
    if (line.trim().isEmpty) continue;
    stdout.writeln(_handleShell(line));
  }
}

String _handleUnavailable(String line) {
  return _handleLine(line, unavailable: true);
}

String _handleShell(String line) {
  return _handleLine(line, unavailable: false);
}

String _handleLine(String line, {required bool unavailable}) {
  final Object? decoded;
  try {
    decoded = jsonDecode(line);
  } catch (e) {
    return jsonEncode(_error(null, -32700, 'parse error: $e'));
  }
  if (decoded is! Map<String, Object?>) {
    return jsonEncode(_error(null, -32600, 'request must be an object'));
  }
  final id = decoded['id'];
  if (decoded['method'] != 'tool.call') {
    return jsonEncode(_error(id, -32601, 'method not found'));
  }
  final params = decoded['params'];
  final tool = params is Map<String, Object?> ? params['name'] : null;
  final input = params is Map<String, Object?> ? params['input'] : null;
  if (!unavailable && tool == 'ask_user') {
    return jsonEncode(_result(id, _handleAskUser(input)));
  }
  return jsonEncode(
    _result(id, <String, Object?>{
      'error': 'tool_unavailable',
      'code': 'tool_unavailable',
      'tool': tool,
      'message': 'Dart process host is running in unavailable safe mode.',
    }),
  );
}

Map<String, Object?> _handleAskUser(Object? input) {
  final args = input is Map
      ? input.map((key, value) => MapEntry(key.toString(), value))
      : const <String, Object?>{};
  final title = (args['title'] as String?)?.trim() ?? '';
  final rawOptions = args['options'];
  if (title.isEmpty || rawOptions is! List) {
    return const <String, Object?>{
      'error': 'title 必填,options 必须是数组。',
      'code': 'bad_request',
    };
  }

  final options = <Map<String, Object?>>[];
  for (final option in rawOptions) {
    if (option is! Map) continue;
    final map = option.map((key, value) => MapEntry(key.toString(), value));
    final label = (map['label'] as String?)?.trim();
    if (label == null || label.isEmpty) continue;
    options.add(<String, Object?>{
      'id': (map['id'] as String?)?.trim().isNotEmpty == true
          ? (map['id'] as String).trim()
          : label,
      'label': label,
      'description': (map['description'] as String?)?.trim() ?? '',
      'pros': _stringList(map['pros']),
      'cons': _stringList(map['cons']),
      'recommended': map['recommended'] == true,
    });
  }
  if (options.length < 2) {
    return const <String, Object?>{
      'error': '至少需要 2 个有效 options(每个含非空 label)。',
      'code': 'bad_request',
    };
  }
  if (options.length > 4) {
    return const <String, Object?>{
      'error': 'options 最多 4 个。',
      'code': 'bad_request',
    };
  }

  return <String, Object?>{
    'type': 'decision_request',
    'title': title,
    'context': (args['context'] as String?)?.trim() ?? '',
    'options': options,
    'allow_custom': args['allow_custom'] != false,
    'awaiting_user': true,
    'domain': 'shell',
  };
}

List<String> _stringList(Object? value) => value is List
    ? value
          .whereType<String>()
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty)
          .toList()
    : const <String>[];

Map<String, Object?> _result(Object? id, Object? result) {
  final response = <String, Object?>{'jsonrpc': '2.0', 'result': result};
  if (id != null) response['id'] = id;
  return response;
}

Map<String, Object?> _error(Object? id, int code, String message) {
  final response = <String, Object?>{
    'jsonrpc': '2.0',
    'error': <String, Object?>{'code': code, 'message': message},
  };
  if (id != null) response['id'] = id;
  return response;
}
