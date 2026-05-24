/// Wave 35 / 36 / 39 — `AiSourceMark`: micro-prefix for AI-modified
/// fields, plus the consumer wrapper [AiTouchMark] that reads from the
/// `ai_touched_entities` side table (Wave 39) and shows the mark only
/// when the entity was actually touched by an AI proposal.
///
/// Use [AiTouchMark] from detail pages; [AiSourceMark] alone is for
/// callers that already know an entity is AI-touched (e.g. inside a
/// proposal preview where context is unambiguous).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../visual/visual.dart';
import 'providers.dart';

class AiSourceMark extends StatelessWidget {
  const AiSourceMark({super.key, this.tooltipZh = '由 AI 提议修改', this.size = 12});

  final String tooltipZh;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltipZh,
      waitDuration: const Duration(milliseconds: 400),
      child: AiSparkle(size: size),
    );
  }
}

/// Wave 39 — bound version of [AiSourceMark]. Watches
/// `aiTouchedAtProvider((entityType, entityId))`; renders nothing when
/// the entity has no recent touch. Detail pages drop this in next to
/// any field they want to flag — the widget itself decides when to
/// surface.
///
/// **Threshold**: 30 days by default. After that the mark fades — the
/// affordance is meant to signal "this might have been AI-created
/// recently", not perpetual provenance.
class AiTouchMark extends ConsumerWidget {
  const AiTouchMark({
    super.key,
    required this.entityType,
    required this.entityId,
    this.staleAfter = const Duration(days: 30),
    this.size = 12,
  });

  /// Matches `ProposalApplyState.appliedTable` — currently one of
  /// `journal_entries`, `accounts`, `assets`. See
  /// `ProposalApplier._applyXxx` for the source of truth.
  final String entityType;
  final String entityId;
  final Duration staleAfter;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (entityId.isEmpty) return const SizedBox.shrink();
    final touch = ref
        .watch(
          aiTouchedAtProvider((entityType: entityType, entityId: entityId)),
        )
        .value;
    if (touch == null) return const SizedBox.shrink();
    final age = DateTime.now().toUtc().difference(touch.touchedAt);
    if (age > staleAfter) return const SizedBox.shrink();
    final tooltip = touch.kindLabel == null
        ? '由 AI 提议修改'
        : '由 AI 提议修改（${touch.kindLabel}）';
    return AiSourceMark(tooltipZh: tooltip, size: size);
  }
}
