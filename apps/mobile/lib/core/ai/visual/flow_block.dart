/// Vertical flow-diagram renderer for structured AI content.
///
/// When the LLM produces a ` ```flow ` fenced block inside polished
/// markdown, [AiMarkdown] routes it here instead of rendering as a
/// code block. The result is a compact, card-based vertical flowchart
/// with connector lines and optional decision branches.
///
/// ## DSL syntax
///
/// ```flow
/// step: 确认需求
/// step: 设计方案
/// decision: 方案可行?
///   yes: 编码实现
///   no: 回到设计
/// step: 测试验证
/// ```
///
/// Supported node types:
/// - `step` — action step (primary accent)
/// - `decision` — binary branch (yes/no sub-flows)
/// - `info` — informational note (muted)
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

import '../../../design_system/design_system.dart';
import 'ai_tone.dart';
import 'ai_typography.dart' show AiType;

// ─── Data model ──────────────────────────────────────────────────────────────

/// A single node in a flow diagram.
sealed class FlowNode {
  const FlowNode({required this.id, required this.label});
  final String id;
  final String label;
}

/// An action step in the flow.
class FlowStepNode extends FlowNode {
  const FlowStepNode({required super.id, required super.label});
}

/// A binary decision point with yes/no branches.
class FlowDecisionNode extends FlowNode {
  const FlowDecisionNode({
    required super.id,
    required super.label,
    required this.yesBranch,
    required this.noBranch,
  });
  final FlowBranch yesBranch;
  final FlowBranch noBranch;
}

/// An informational note — context, warnings, or tips.
class FlowInfoNode extends FlowNode {
  const FlowInfoNode({required super.id, required super.label});
}

/// A branch from a decision node.
class FlowBranch {
  const FlowBranch({required this.label, required this.nodes});
  final String label;
  final List<FlowNode> nodes;
}

/// A complete flow diagram — the root model.
class FlowDiagram {
  const FlowDiagram({required this.nodes});
  final List<FlowNode> nodes;
}

// ─── Parser ──────────────────────────────────────────────────────────────────

/// Parses the DSL inside a ` ```flow ` fenced block into a [FlowDiagram].
///
/// Returns `null` on parse failure so the caller can fall back to
/// rendering as a plain code block.
class FlowParser {
  FlowParser._();

  static final RegExp _stepRe = RegExp(r'^\s*step:\s*(.+)$');
  static final RegExp _decisionRe = RegExp(r'^\s*decision:\s*(.+)$');
  static final RegExp _infoRe = RegExp(r'^\s*info:\s*(.+)$');
  static final RegExp _yesRe = RegExp(r'^\s{2,}yes:\s*(.+)$');
  static final RegExp _noRe = RegExp(r'^\s{2,}no:\s*(.+)$');

  /// Parse [source] (the content between ` ```flow ` and ` ``` `) into
  /// a [FlowDiagram]. Returns `null` if the input is empty or contains
  /// no recognisable nodes.
  static FlowDiagram? parse(String source) {
    final lines = source.split('\n');
    final topLevel = <FlowNode>[];
    var nodeCounter = 0;

    // Pending decision state — set when we encounter a `decision:` line,
    // cleared when we hit the next top-level node.
    String? pendingDecisionId;
    String? pendingDecisionLabel;
    List<FlowNode>? pendingYesNodes;
    List<FlowNode>? pendingNoNodes;

    void flushDecision() {
      if (pendingDecisionId != null) {
        topLevel.add(
          FlowDecisionNode(
            id: pendingDecisionId!,
            label: pendingDecisionLabel!,
            yesBranch: FlowBranch(label: 'Yes', nodes: pendingYesNodes ?? []),
            noBranch: FlowBranch(label: 'No', nodes: pendingNoNodes ?? []),
          ),
        );
        pendingDecisionId = null;
        pendingDecisionLabel = null;
        pendingYesNodes = null;
        pendingNoNodes = null;
      }
    }

    for (final raw in lines) {
      // Blank lines are ignored.
      if (raw.trim().isEmpty) continue;

      // Branch lines (indented yes/no) — must be checked before
      // top-level patterns so they aren't misclassified.
      final yesMatch = _yesRe.firstMatch(raw);
      if (yesMatch != null && pendingDecisionId != null) {
        final list = pendingYesNodes ??= <FlowNode>[];
        list.add(
          FlowStepNode(
            id: 'n${nodeCounter++}',
            label: yesMatch.group(1)!.trim(),
          ),
        );
        continue;
      }
      final noMatch = _noRe.firstMatch(raw);
      if (noMatch != null && pendingDecisionId != null) {
        final list = pendingNoNodes ??= <FlowNode>[];
        list.add(
          FlowStepNode(
            id: 'n${nodeCounter++}',
            label: noMatch.group(1)!.trim(),
          ),
        );
        continue;
      }

      // Top-level nodes — flush any pending decision first.
      final stepMatch = _stepRe.firstMatch(raw);
      if (stepMatch != null) {
        flushDecision();
        topLevel.add(
          FlowStepNode(
            id: 'n${nodeCounter++}',
            label: stepMatch.group(1)!.trim(),
          ),
        );
        continue;
      }

      final decMatch = _decisionRe.firstMatch(raw);
      if (decMatch != null) {
        flushDecision();
        pendingDecisionId = 'n${nodeCounter++}';
        pendingDecisionLabel = decMatch.group(1)!.trim();
        continue;
      }

      final infoMatch = _infoRe.firstMatch(raw);
      if (infoMatch != null) {
        flushDecision();
        topLevel.add(
          FlowInfoNode(
            id: 'n${nodeCounter++}',
            label: infoMatch.group(1)!.trim(),
          ),
        );
        continue;
      }

      // Unrecognised line — skip silently (tolerant of future extensions).
    }

    flushDecision();

    if (topLevel.isEmpty) return null;
    return FlowDiagram(nodes: topLevel);
  }
}

// ─── Widget ──────────────────────────────────────────────────────────────────

/// Renders a [FlowDiagram] as a vertical card-based flowchart.
///
/// Each node is a rounded card connected by thin vertical lines.
/// Decision branches render as a secondary "no" card indented below
/// the decision, while the "yes" path continues inline.
class FlowDiagramWidget extends StatelessWidget {
  const FlowDiagramWidget({super.key, required this.diagram});
  final FlowDiagram diagram;

  @override
  Widget build(BuildContext context) {
    final nodes = diagram.nodes;
    final children = <Widget>[];

    for (var i = 0; i < nodes.length; i++) {
      final node = nodes[i];
      final isLast = i == nodes.length - 1;

      children.add(_buildNode(context, node));

      // Connector line after each node (except the last).
      if (!isLast) {
        children.add(_Connector(color: AiTone.outline(context)));
      }
    }

    return Semantics(
      container: true,
      label: 'Flow diagram, ${nodes.length} steps',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }

  Widget _buildNode(BuildContext context, FlowNode node) {
    return switch (node) {
      FlowStepNode() => _StepCard(node: node),
      FlowDecisionNode() => _DecisionBlock(node: node),
      FlowInfoNode() => _InfoCard(node: node),
    };
  }
}

// ─── Node cards ──────────────────────────────────────────────────────────────

/// Vertical connector line between nodes.
class _Connector extends StatelessWidget {
  const _Connector({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: AppSpacing.s16,
      child: Center(
        child: Container(width: AppStroke.medium, color: color),
      ),
    );
  }
}

/// A step node — the workhorse of the flow.
class _StepCard extends StatelessWidget {
  const _StepCard({required this.node});
  final FlowStepNode node;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.theme.colors.card,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(
          color: AiTone.outline(context).withValues(alpha: AppOpacity.light),
        ),
      ),
      child: Row(
        children: [
          // Accent bar
          Container(
            width: AppStroke.accent,
            height: 40,
            decoration: BoxDecoration(
              color: AiTone.active(context),
              borderRadius: const BorderRadius.horizontal(
                left: Radius.circular(AppRadius.md),
              ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.s12,
                vertical: AppSpacing.s10,
              ),
              child: Text(node.label, style: AiType.body(context)),
            ),
          ),
        ],
      ),
    );
  }
}

/// An info node — muted, with a subtle left accent.
class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.node});
  final FlowInfoNode node;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AiTone.surfaceTint(context).withValues(alpha: AppOpacity.faint),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(
          color: AiTone.outline(context).withValues(alpha: AppOpacity.whisper),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: AppStroke.accent,
            height: 36,
            decoration: BoxDecoration(
              color: AiTone.muted(context),
              borderRadius: const BorderRadius.horizontal(
                left: Radius.circular(AppRadius.md),
              ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.s12,
                vertical: AppSpacing.s8,
              ),
              child: Text(
                node.label,
                style: AiType.body(context).copyWith(
                  color: AiTone.muted(context),
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A decision node with yes/no branches.
///
/// The decision itself is rendered as a card with a diamond indicator.
/// The "no" branch appears as a secondary card below, while the "yes"
/// path continues inline (implied as the main flow).
class _DecisionBlock extends StatelessWidget {
  const _DecisionBlock({required this.node});
  final FlowDecisionNode node;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];

    // Decision card with diamond indicator.
    children.add(
      Container(
        decoration: BoxDecoration(
          color: AiTone.active(context).withValues(alpha: AppOpacity.faint),
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(
            color: AiTone.active(context).withValues(alpha: AppOpacity.muted),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.s12,
            vertical: AppSpacing.s10,
          ),
          child: Row(
            children: [
              // Diamond indicator
              Transform.rotate(
                angle: math.pi / 4,
                child: Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: AiTone.active(context),
                      width: AppStroke.medium,
                    ),
                    borderRadius: BorderRadius.circular(AppRadius.xxs),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.s10),
              Expanded(
                child: Text(node.label, style: AiType.bodyStrong(context)),
              ),
            ],
          ),
        ),
      ),
    );

    // "Yes" branch — inline continuation.
    if (node.yesBranch.nodes.isNotEmpty) {
      children.add(const _Connector(color: Colors.transparent));
      children.add(
        _BranchBlock(
          label: node.yesBranch.label,
          nodes: node.yesBranch.nodes,
          accent: AiTone.active(context),
        ),
      );
    }

    // "No" branch — secondary, indented.
    if (node.noBranch.nodes.isNotEmpty) {
      children.add(const _Connector(color: Colors.transparent));
      children.add(
        _BranchBlock(
          label: node.noBranch.label,
          nodes: node.noBranch.nodes,
          accent: AiTone.error(context),
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }
}

/// A branch sub-flow (yes or no) with a label header.
class _BranchBlock extends StatelessWidget {
  const _BranchBlock({
    required this.label,
    required this.nodes,
    required this.accent,
  });
  final String label;
  final List<FlowNode> nodes;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];

    // Branch label chip
    children.add(
      Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.s8,
              vertical: AppSpacing.s2,
            ),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: AppOpacity.subtle),
              borderRadius: BorderRadius.circular(AppRadius.xs),
            ),
            child: Text(
              label,
              style: AiType.metaStrong(context).copyWith(color: accent),
            ),
          ),
          const SizedBox(width: AppSpacing.s8),
          Expanded(
            child: Container(
              height: AppStroke.hairline,
              color: accent.withValues(alpha: AppOpacity.light),
            ),
          ),
        ],
      ),
    );

    children.add(const SizedBox(height: AppSpacing.s6));

    // Branch nodes
    for (var i = 0; i < nodes.length; i++) {
      final node = nodes[i];
      children.add(_buildBranchNode(context, node));
      if (i < nodes.length - 1) {
        children.add(
          SizedBox(
            height: AppSpacing.s8,
            child: Center(
              child: Container(
                width: AppStroke.hairline,
                color: accent.withValues(alpha: AppOpacity.light),
              ),
            ),
          ),
        );
      }
    }

    return Container(
      margin: const EdgeInsets.only(left: AppSpacing.s16),
      padding: const EdgeInsets.all(AppSpacing.s8),
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(
            color: accent.withValues(alpha: AppOpacity.muted),
            width: AppStroke.branch,
          ),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }

  Widget _buildBranchNode(BuildContext context, FlowNode node) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s10,
        vertical: AppSpacing.s6,
      ),
      decoration: BoxDecoration(
        color: context.theme.colors.card,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Text(node.label, style: AiType.body(context)),
    );
  }
}
