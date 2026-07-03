part of 'allocation_detail_panel.dart';

class _AllocationDonut extends StatelessWidget {
  const _AllocationDonut({
    required this.groups,
    required this.total,
    required this.currencyCode,
  });

  final List<_AllocationGroup> groups;
  final double total;
  final String currencyCode;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: AppChartHeights.allocationDonut,
      child: Stack(
        alignment: Alignment.center,
        children: [
          RepaintBoundary(
            child: CustomPaint(
              size: const Size.square(220),
              painter: _DonutPainter(
                groups: groups,
                total: total,
                trackColor: context.theme.colors.border.withValues(
                  alpha: AppOpacity.light,
                ),
              ),
            ),
          ),
          SizedBox(
            width: AppControlWidths.donutCenterLabel,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                MoneyText(
                  amount: total,
                  currencyCode: currencyCode,
                  compact: true,
                  style: context.strongTitleStyle,
                ),
                Text(
                  AppLocalizations.of(context).assetsAppBarTitle,
                  style: context.captionStyle,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DonutPainter extends CustomPainter {
  _DonutPainter({
    required this.groups,
    required this.total,
    required this.trackColor,
  });

  final List<_AllocationGroup> groups;
  final double total;
  final Color trackColor;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final stroke = math.min(size.width, size.height) * 0.13;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = trackColor;

    canvas.drawArc(rect.deflate(stroke / 2), 0, math.pi * 2, false, track);
    if (total <= 0) return;
    var start = -math.pi / 2;
    for (final group in groups) {
      final sweep = (group.value / total) * math.pi * 2;
      paint.color = group.color;
      canvas.drawArc(rect.deflate(stroke / 2), start, sweep, false, paint);
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter oldDelegate) {
    return oldDelegate.groups != groups || oldDelegate.total != total;
  }
}
