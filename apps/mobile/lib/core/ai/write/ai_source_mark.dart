/// Wave 35 — `AiSourceMark`: micro-prefix for AI-modified fields.
///
/// Calm Intelligence (§5.6): 12-pixel outlined sparkle in
/// `onSurfaceVariant` tone, no background, optional tooltip. Sized to
/// sit inline before / after a value without taking layout space.
///
/// Usage:
///   Row(children: [const AiSourceMark(), const SizedBox(width: 4), valueText])
///
/// Detail pages add this prefix next to a field when it was last
/// modified by an AI proposal — the trace links it to the underlying
/// invocation (Wave 33). The primitive ships here; consumer pages
/// adopt incrementally.
library;

import 'package:flutter/material.dart';

class AiSourceMark extends StatelessWidget {
  const AiSourceMark({
    super.key,
    this.tooltipZh = '由 AI 提议修改',
    this.size = 12,
  });

  final String tooltipZh;

  /// Override the icon size. Default 12 keeps the mark below body font.
  final double size;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurfaceVariant;
    return Tooltip(
      message: tooltipZh,
      waitDuration: const Duration(milliseconds: 400),
      child: Icon(
        Icons.auto_awesome_outlined,
        size: size,
        color: color,
      ),
    );
  }
}
