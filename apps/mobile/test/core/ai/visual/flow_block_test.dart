// Tests for `FlowParser` — the DSL parser that converts ```flow fenced
// block content into a FlowDiagram model.

import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/ai/visual/flow_block.dart';

void main() {
  group('FlowParser.parse', () {
    test('returns null for empty input', () {
      expect(FlowParser.parse(''), isNull);
      expect(FlowParser.parse('   \n  \n '), isNull);
    });

    test('parses a single step', () {
      final d = FlowParser.parse('step: Start');
      expect(d, isNotNull);
      expect(d!.nodes, hasLength(1));
      expect(d.nodes.first, isA<FlowStepNode>());
      expect(d.nodes.first.label, 'Start');
    });

    test('parses multiple linear steps', () {
      final d = FlowParser.parse('step: A\nstep: B\nstep: C');
      expect(d, isNotNull);
      expect(d!.nodes, hasLength(3));
      expect(d.nodes.map((n) => n.label), ['A', 'B', 'C']);
    });

    test('parses an info node', () {
      final d = FlowParser.parse('info: Note this');
      expect(d, isNotNull);
      expect(d!.nodes.first, isA<FlowInfoNode>());
      expect(d.nodes.first.label, 'Note this');
    });

    test('parses a decision with yes/no branches', () {
      const input = '''
step: Prepare
decision: Ready?
  yes: Execute
  no: Revise
step: Done
''';
      final d = FlowParser.parse(input);
      expect(d, isNotNull);
      expect(d!.nodes, hasLength(3));

      expect(d.nodes[0], isA<FlowStepNode>());
      expect(d.nodes[0].label, 'Prepare');

      expect(d.nodes[1], isA<FlowDecisionNode>());
      final dec = d.nodes[1] as FlowDecisionNode;
      expect(dec.label, 'Ready?');
      expect(dec.yesBranch.nodes, hasLength(1));
      expect(dec.yesBranch.nodes.first.label, 'Execute');
      expect(dec.noBranch.nodes, hasLength(1));
      expect(dec.noBranch.nodes.first.label, 'Revise');

      expect(d.nodes[2], isA<FlowStepNode>());
      expect(d.nodes[2].label, 'Done');
    });

    test('parses decision with multiple branch nodes', () {
      const input = '''
decision: Check?
  yes: Step A
  yes: Step B
  no: Fix A
  no: Fix B
''';
      final d = FlowParser.parse(input);
      expect(d, isNotNull);
      final dec = d!.nodes.first as FlowDecisionNode;
      expect(dec.yesBranch.nodes, hasLength(2));
      expect(dec.yesBranch.nodes.map((n) => n.label), ['Step A', 'Step B']);
      expect(dec.noBranch.nodes, hasLength(2));
      expect(dec.noBranch.nodes.map((n) => n.label), ['Fix A', 'Fix B']);
    });

    test('parses decision with only yes branch', () {
      const input = 'decision: Proceed?\n  yes: Go ahead';
      final d = FlowParser.parse(input);
      expect(d, isNotNull);
      final dec = d!.nodes.first as FlowDecisionNode;
      expect(dec.yesBranch.nodes, hasLength(1));
      expect(dec.noBranch.nodes, isEmpty);
    });

    test('parses decision with only no branch', () {
      const input = 'decision: Safe?\n  no: Abort';
      final d = FlowParser.parse(input);
      expect(d, isNotNull);
      final dec = d!.nodes.first as FlowDecisionNode;
      expect(dec.yesBranch.nodes, isEmpty);
      expect(dec.noBranch.nodes, hasLength(1));
    });

    test('ignores blank lines', () {
      const input = '\nstep: A\n\n\nstep: B\n';
      final d = FlowParser.parse(input);
      expect(d, isNotNull);
      expect(d!.nodes, hasLength(2));
    });

    test('skips unrecognised lines', () {
      const input = 'step: A\nrandom garbage\nstep: B';
      final d = FlowParser.parse(input);
      expect(d, isNotNull);
      expect(d!.nodes, hasLength(2));
    });

    test('trims whitespace from labels', () {
      final d = FlowParser.parse('step:   Hello World   ');
      expect(d, isNotNull);
      expect(d!.nodes.first.label, 'Hello World');
    });

    test('assigns unique ids to nodes', () {
      const input = 'step: A\nstep: B\ndecision: C?\n  yes: D\n  no: E';
      final d = FlowParser.parse(input);
      expect(d, isNotNull);
      final ids = d!.nodes.map((n) => n.id).toSet();
      // All top-level ids should be unique
      expect(ids.length, d.nodes.length);
    });

    test('parses mixed node types', () {
      const input = '''
info: Context
step: First action
decision: Is it good?
  yes: Ship it
  no: Iterate
step: Final step
''';
      final d = FlowParser.parse(input);
      expect(d, isNotNull);
      expect(d!.nodes, hasLength(4));
      expect(d.nodes[0], isA<FlowInfoNode>());
      expect(d.nodes[1], isA<FlowStepNode>());
      expect(d.nodes[2], isA<FlowDecisionNode>());
      expect(d.nodes[3], isA<FlowStepNode>());
    });

    test('handles label with colon', () {
      // "step: Do this: that" should parse label as "Do this: that"
      final d = FlowParser.parse('step: Do this: that');
      expect(d, isNotNull);
      expect(d!.nodes.first.label, 'Do this: that');
    });

    test('handles Chinese labels', () {
      final d = FlowParser.parse(
        'step: 确认需求\ndecision: 方案可行?\n  yes: 实现\n  no: 重新设计',
      );
      expect(d, isNotNull);
      expect(d!.nodes, hasLength(2));
      expect(d.nodes[0].label, '确认需求');
      final dec = d.nodes[1] as FlowDecisionNode;
      expect(dec.label, '方案可行?');
      expect(dec.yesBranch.nodes.first.label, '实现');
      expect(dec.noBranch.nodes.first.label, '重新设计');
    });
  });
}
