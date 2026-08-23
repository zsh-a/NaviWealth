import 'dart:convert';
import 'dart:io';

const _outputPath = 'docs/architecture/agent-runtime-capabilities.json';

void main(List<String> arguments) {
  final root = _findRepositoryRoot();
  final runtime = Directory('${root.path}/third_party/agent-runtime');
  if (!runtime.existsSync()) {
    stderr.writeln('Missing pinned runtime at ${runtime.path}');
    exitCode = 2;
    return;
  }

  final manifest = _buildManifest(runtime);
  final rendered = '${const JsonEncoder.withIndent('  ').convert(manifest)}\n';
  final output = File('${root.path}/$_outputPath');
  if (arguments.contains('--check')) {
    if (!output.existsSync() || output.readAsStringSync() != rendered) {
      stderr.writeln(
        '$_outputPath is stale; run '
        '`rtk dart run tool/generate_agent_runtime_capabilities.dart`.',
      );
      exitCode = 1;
    }
    return;
  }
  output.writeAsStringSync(rendered);
}

Map<String, Object?> _buildManifest(Directory runtime) {
  final commit = _runGit(runtime, <String>['rev-parse', 'HEAD']);
  final core = _read(runtime, 'crates/agent-core/src/lib.rs');
  final embedded = _read(runtime, 'crates/agent-core/src/embedded.rs');
  final chatSnapshot = _read(runtime, 'crates/agent-chat/src/snapshot.rs');
  final tsPackage =
      jsonDecode(_read(runtime, 'bindings/ts/package.json')) as Map;
  return <String, Object?>{
    'schema_version': 1,
    'runtime_commit': commit,
    'protocol': <String, Object?>{
      'wire': _capture(
        core,
        RegExp(r'pub const PROTOCOL_VERSION: &str = "([^"]+)"'),
      ),
      'embedded_snapshot': int.parse(
        _capture(
          embedded,
          RegExp(r'pub const EMBEDDED_SNAPSHOT_VERSION: u32 = (\d+)'),
        ),
      ),
      'chat_turn_snapshot': int.parse(
        _capture(
          chatSnapshot,
          RegExp(r'pub const CHAT_TURN_SNAPSHOT_VERSION: u32 = (\d+)'),
        ),
      ),
    },
    'bindings': <String, Object?>{
      'rust_crates': true,
      'typescript': <String, Object?>{
        'available': File('${runtime.path}/bindings/ts/src/index.ts')
            .existsSync(),
        'package': tsPackage['name'],
        'version': tsPackage['version'],
        'http_client': File('${runtime.path}/bindings/ts/src/http-client.ts')
            .existsSync(),
        'structured_output': File(
          '${runtime.path}/bindings/ts/src/generate-object.ts',
        ).existsSync(),
      },
      'dart': <String, Object?>{'available': false},
    },
    'transports': <String, Object?>{
      'rust_library': true,
      'cli': File('${runtime.path}/crates/agent-cli/src/main.rs').existsSync(),
      'http': File('${runtime.path}/openapi/agent-runtime-api.yaml')
          .existsSync(),
      'stdio': File('${runtime.path}/crates/agent-cli/src/interfaces/server.rs')
          .existsSync(),
      'flutter_frb': <String, Object?>{
        'runtime_owned': false,
        'host_adapter': 'apps/mobile/native/lifeos_native',
      },
    },
    'stores': <String, Object?>{
      'in_memory': true,
      'file': true,
      'sqlite_feature': _read(
        runtime,
        'crates/agent-store/Cargo.toml',
      ).contains('sqlite = ["dep:sqlx"]'),
    },
    'llm_providers': <String>[
      for (final provider in <String>['mock', 'openai', 'anthropic', 'ollama'])
        if (File(
          provider == 'mock'
              ? '${runtime.path}/crates/agent-llm/src/mock.rs'
              : '${runtime.path}/crates/agent-llm/src/providers/$provider.rs',
        ).existsSync())
          provider,
    ],
    'authoritative_inputs': <String>[
      'crates/agent-core/src/lib.rs',
      'crates/agent-core/src/embedded.rs',
      'crates/agent-chat/src/snapshot.rs',
      'crates/agent-store/Cargo.toml',
      'bindings/ts/package.json',
      'bindings/ts/src/http-client.ts',
      'bindings/ts/src/generate-object.ts',
      'openapi/agent-runtime-api.yaml',
    ],
  };
}

Directory _findRepositoryRoot() {
  var current = Directory.current.absolute;
  while (true) {
    if (Directory('${current.path}/third_party/agent-runtime').existsSync() &&
        File('${current.path}/pubspec.yaml').existsSync() == false) {
      return current;
    }
    final parent = current.parent;
    if (parent.path == current.path) {
      throw StateError('Could not locate NaviWealth repository root.');
    }
    current = parent;
  }
}

String _read(Directory runtime, String relativePath) =>
    File('${runtime.path}/$relativePath').readAsStringSync();

String _capture(String input, RegExp pattern) {
  final match = pattern.firstMatch(input);
  if (match == null) throw StateError('Capability source pattern not found.');
  return match.group(1)!;
}

String _runGit(Directory runtime, List<String> arguments) {
  final result = Process.runSync('git', <String>[
    '-C',
    runtime.path,
    ...arguments,
  ]);
  if (result.exitCode != 0) {
    throw StateError('git failed: ${result.stderr}');
  }
  return (result.stdout as String).trim();
}
