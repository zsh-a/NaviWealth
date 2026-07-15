import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('project docs describe the current IA without historical issue tags', () {
    final root = _repoRoot();
    final markdownFiles = <File>[
      File('${root.path}/README.md'),
      File('${root.path}/docs/ai/ai-architecture.md'),
      File('${root.path}/docs/architecture/lifeos-architecture-northstar.md'),
      File('${root.path}/docs/architecture/lifeos-shell.md'),
      File('${root.path}/docs/development/web-compat-matrix.md'),
      File('${root.path}/docs/development/web-routing.md'),
    ];

    final legacyTopLevelRoute = RegExp(
      r'''(^|[\s`'"(\[{>])/(assets|accounts|expenses|analytics|fire|rebalance|me|more|transactions)(?=$|/|[\s`'"),\].<])''',
      multiLine: true,
    );

    for (final file in markdownFiles) {
      final text = file.readAsStringSync();
      expect(text, isNot(contains('FIR-')), reason: file.path);
      expect(text, isNot(legacyTopLevelRoute), reason: file.path);
    }
  });

  test('current rust runtime doc tracks snapshot execution contracts', () {
    final root = _repoRoot();
    final text = File(
      '${root.path}/docs/architecture/agent-runtime-current.md',
    ).readAsStringSync();

    for (final marker in <String>[
      'agent_runtime_tool_host.dart',
      'embedded checkpoints',
      'snapshot_version: 1',
      'effect_recorded',
      'host effects',
      'JSON-RPC',
    ]) {
      expect(text, contains(marker), reason: marker);
    }
  });
}

Directory _repoRoot() {
  var current = Directory.current.absolute;
  while (true) {
    if (Directory('${current.path}/.git').existsSync() &&
        File('${current.path}/README.md').existsSync() &&
        Directory('${current.path}/docs').existsSync() &&
        Directory('${current.path}/apps/mobile').existsSync()) {
      return current;
    }
    final parent = current.parent;
    if (parent.path == current.path) {
      throw StateError('Could not locate NaviWealth repository root');
    }
    current = parent;
  }
}
