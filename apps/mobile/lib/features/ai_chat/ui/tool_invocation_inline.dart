/// Wave 37 — inline tool attribution + domain renderer (no card chrome).
///
/// Replaces the card-shaped `ToolInvocationCard` for tools that have a
/// domain renderer registered in `tool_invocation_renderers.dart`.
/// The card chrome (border, chevron, JSON viewer) becomes a long-press
/// affordance that pops a sheet with the full debug view.
///
/// Tools *without* a domain renderer continue to use the legacy card —
/// raw JSON is what's actually useful for them, and the card chrome
/// is the only way to surface the chevron + raw toggle.
///
/// Result: a chat turn that called `get_holdings` + `get_asset_allocation`
/// reads as a continuous answer with two embedded visualisations,
/// rather than two collapsible Postman-style cards stacked between
/// text segments.
library;

import 'package:flutter/material.dart';

import '../../../core/ai/visual/visual.dart';
import '../domain/chat_models.dart';
import 'tool_invocation_card.dart';
import 'tool_invocation_renderers.dart';

class ToolInvocationInline extends StatelessWidget {
  const ToolInvocationInline({super.key, required this.invocation});

  final ToolInvocation invocation;

  /// Pick the cleanest rendering: inline when a domain renderer is
  /// available, fall back to the legacy card otherwise.
  static Widget pick(ToolInvocation invocation) {
    return _InlineDispatcher(invocation: invocation);
  }

  @override
  Widget build(BuildContext context) {
    return _InlineDispatcher(invocation: invocation);
  }
}

class _InlineDispatcher extends StatelessWidget {
  const _InlineDispatcher({required this.invocation});

  final ToolInvocation invocation;

  @override
  Widget build(BuildContext context) {
    // Probe for a domain renderer. We only switch to inline mode when
    // the renderer succeeds — otherwise the card with the JSON viewer
    // remains the best fallback.
    final body = invocation.output == null
        ? null
        : renderToolOutput(context, invocation.name, invocation.output);
    if (body == null) {
      return ToolInvocationCard(invocation: invocation);
    }
    return _InlineLayout(invocation: invocation, body: body);
  }
}

class _InlineLayout extends StatelessWidget {
  const _InlineLayout({required this.invocation, required this.body});

  final ToolInvocation invocation;
  final Widget body;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _AttributionRow(invocation: invocation),
          const SizedBox(height: 6),
          body,
        ],
      ),
    );
  }
}

/// The single muted line under the assistant's prose that tells the
/// user "the model used this tool". Typography-only: sparkle + tool
/// name in monospace + nothing else. Long-press pops the legacy debug
/// card so power users / bug reports can still see raw IO.
class _AttributionRow extends StatelessWidget {
  const _AttributionRow({required this.invocation});

  final ToolInvocation invocation;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onLongPress: () => _openDebugSheet(context),
      behavior: HitTestBehavior.opaque,
      child: Row(
        children: [
          const AiSparkle(),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              _friendly(invocation.name),
              style: AiType.meta(context).copyWith(
                fontFamily: 'monospace',
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _openDebugSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        expand: false,
        builder: (_, controller) => ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          children: [
            // Reuse the existing card — it ships its own chevron / JSON
            // viewer. From inside the bottom sheet the chrome reads as
            // "developer detail", which is exactly what long-press
            // promised.
            ToolInvocationCard(invocation: invocation),
          ],
        ),
      ),
    );
  }
}

/// Friendly tool name. Keeps the monospace identifier for trace-able
/// debugging — UX research showed users do *learn* tool names from
/// chat, and obscuring them with translated labels makes follow-up
/// questions ("did you check holdings?") harder.
String _friendly(String name) => name;
