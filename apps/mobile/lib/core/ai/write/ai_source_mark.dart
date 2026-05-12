/// Wave 35 / 36 — `AiSourceMark`: micro-prefix for AI-modified fields.
///
/// Wave 36 refactor — single sparkle primitive from `core/ai/visual/`.
/// Detail pages add this before / after a value when the field was
/// last modified by an AI proposal.
library;

import 'package:flutter/material.dart';

import '../visual/visual.dart';

class AiSourceMark extends StatelessWidget {
  const AiSourceMark({
    super.key,
    this.tooltipZh = '由 AI 提议修改',
    this.size = 12,
  });

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
