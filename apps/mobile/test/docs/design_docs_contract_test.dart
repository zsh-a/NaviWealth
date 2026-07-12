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

  test('rust runtime MVP doc tracks snapshot-only execution contracts', () {
    final root = _repoRoot();
    final text = File(
      '${root.path}/docs/architecture/rust-agent-runtime-mvp.md',
    ).readAsStringSync();

    expect(text, contains('The only embedded execution contract'));
    expect(text, contains('requires the snapshot execution'));
    expect(text, contains('Native FRB snapshot continuations validate'));
    expect(text, isNot(contains('agentRuntimeStartRunStep')));
    expect(text, isNot(contains('agentRuntimeContinueRunStep')));
    expect(text, isNot(contains('compatibility fallback')));
    for (final marker in <String>[
      'effect_id',
      'catalog-bound tool names',
      'typed continuation state',
      'historical effect results',
      'JSON-RPC effect response envelopes',
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
