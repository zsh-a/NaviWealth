part of 'knowledge_object_detail_page.dart';

class _ConceptGraphPanel extends StatelessWidget {
  const _ConceptGraphPanel({
    required this.concept,
    required this.relatedConcepts,
    required this.onConceptPress,
  });

  final KnowledgeConcept concept;
  final List<KnowledgeConcept> relatedConcepts;
  final ValueChanged<KnowledgeConcept> onConceptPress;

  @override
  Widget build(BuildContext context) {
    final shown = relatedConcepts.take(8).toList(growable: false);
    final hiddenCount = relatedConcepts.length - shown.length;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : 320.0;
        const height = 192.0;
        final center = Offset(width / 2, height / 2);
        const centerNodeWidth =
            AppSpacing.s64 + AppSpacing.s64 + AppSpacing.s32 + AppSpacing.s4;
        const centerNodeHeight = AppSpacing.s48;
        const relatedNodeWidth =
            AppSpacing.s56 + AppSpacing.s56 + AppSpacing.s4;
        const relatedNodeHeight = AppSpacing.s40 + AppSpacing.s2;
        final nodeCenters = _conceptGraphNodeCenters(
          center: center,
          count: shown.length,
          width: width,
        );
        return Semantics(
          container: true,
          child: SoftCard.flat(
            key: const ValueKey('knowledge-concept-graph'),
            padding: EdgeInsets.zero,
            child: SizedBox(
              height: height,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: IgnorePointer(
                      child: CustomPaint(
                        painter: _ConceptGraphPainter(
                          center: center,
                          related: nodeCenters,
                          color: context.appTheme.categorical
                              .adapt(KnowledgeTypeColors.concept)
                              .withValues(alpha: AppOpacity.medium),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: center.dx - centerNodeWidth / 2,
                    top: center.dy - centerNodeHeight / 2,
                    width: centerNodeWidth,
                    height: centerNodeHeight,
                    child: _ConceptNodeChip(label: concept.name, active: true),
                  ),
                  for (var i = 0; i < shown.length; i++)
                    Positioned(
                      left: nodeCenters[i].dx - relatedNodeWidth / 2,
                      top: nodeCenters[i].dy - relatedNodeHeight / 2,
                      width: relatedNodeWidth,
                      height: relatedNodeHeight,
                      child: _ConceptNodeChip(
                        label: shown[i].name,
                        onPress: () => onConceptPress(shown[i]),
                      ),
                    ),
                  if (hiddenCount > 0)
                    Positioned(
                      right: AppSpacing.s12,
                      bottom: AppSpacing.s12,
                      child: Text('+$hiddenCount', style: context.captionStyle),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

List<Offset> _conceptGraphNodeCenters({
  required Offset center,
  required int count,
  required double width,
}) {
  if (count == 0) return const <Offset>[];
  final radiusX = math.min(width * 0.34, 150.0);
  const radiusY = 62.0;
  return [
    for (var i = 0; i < count; i++)
      Offset(
        center.dx +
            radiusX * math.cos((-math.pi / 2) + (2 * math.pi * i / count)),
        center.dy +
            radiusY * math.sin((-math.pi / 2) + (2 * math.pi * i / count)),
      ),
  ];
}

class _ConceptGraphPainter extends CustomPainter {
  const _ConceptGraphPainter({
    required this.center,
    required this.related,
    required this.color,
  });

  final Offset center;
  final List<Offset> related;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = AppStroke.thin
      ..style = PaintingStyle.stroke;
    for (final node in related) {
      canvas.drawLine(center, node, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _ConceptGraphPainter oldDelegate) {
    return oldDelegate.center != center ||
        oldDelegate.related != related ||
        oldDelegate.color != color;
  }
}

class _ConceptNodeChip extends StatelessWidget {
  const _ConceptNodeChip({
    required this.label,
    this.active = false,
    this.onPress,
  });

  final String label;
  final bool active;
  final VoidCallback? onPress;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final foreground = active ? colors.primary : colors.foreground;
    Widget child = KnowledgeCardSurface(
      level: active ? SoftCardLevel.raised : SoftCardLevel.flat,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s8),
      child: Align(
        alignment: Alignment.center,
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: (active ? context.labelStyle : context.captionStyle).copyWith(
            color: foreground,
          ),
        ),
      ),
    );
    final onPress = this.onPress;
    if (onPress == null) return child;
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onPress,
        child: child,
      ),
    );
  }
}
