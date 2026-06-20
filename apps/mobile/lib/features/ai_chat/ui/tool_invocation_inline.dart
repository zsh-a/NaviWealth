/// Inline tool attribution + domain renderer (no card chrome).
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

import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../../../core/ai/visual/visual.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
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
      padding: const EdgeInsets.only(
        top: AppSpacing.s10,
        bottom: AppSpacing.s4,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _AttributionRow(invocation: invocation),
          const SizedBox(height: AppSpacing.s6),
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
    final l10n = AppLocalizations.of(context);
    // Long-press to view raw I/O was an invisible power-user gesture —
    // we keep it for muscle memory, but a tiny info icon at the end of
    // the row makes the affordance discoverable for everyone else.
    return GestureDetector(
      onLongPress: () => _openDebugSheet(context),
      behavior: HitTestBehavior.opaque,
      child: Row(
        children: [
          // Per-tool icon picked from `toolIcon` — gives the row a
          // glanceable identity (chart vs flag vs subscription) that
          // the generic sparkle previously washed out.
          Icon(
            toolIcon(invocation.name),
            size: AppIconSizes.xs,
            color: AiTone.muted(context),
          ),
          const SizedBox(width: AppSpacing.s6),
          Flexible(
            child: Text(
              _friendly(invocation.name),
              style: AiType.meta(context).copyWith(fontFamily: 'monospace'),
            ),
          ),
          const SizedBox(width: AppSpacing.s6),
          FTooltip(
            tipBuilder: (_, _) => Text(l10n.aiChatToolDebugTooltip),
            child: FTappable(
              onPress: () => _openDebugSheet(context),
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.s2),
                child: Icon(
                  FLucideIcons.info,
                  size: 12,
                  color: AiTone.muted(context),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _openDebugSheet(BuildContext context) {
    showAppFormSheet<void>(
      context: context,
      builder: (_) => AppSheetSurface(
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.7,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.s16,
              AppSpacing.s0,
              AppSpacing.s16,
              AppSpacing.s24,
            ),
            children: [
              // Reuse the existing card — it ships its own chevron / JSON
              // viewer. From inside the bottom sheet the chrome reads as
              // "developer detail", which is exactly what long-press
              // promised.
              ToolInvocationCard(invocation: invocation),
            ],
          ),
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
