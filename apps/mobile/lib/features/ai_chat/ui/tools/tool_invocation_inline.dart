/// Inline tool step for the conversation timeline.
///
/// Always a quiet one-line attribution; body (domain renderer or compact
/// summary) expands on tap. No card chrome in the stream — raw JSON lives
/// behind long-press debug.
library;

import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../../../../core/ai/visual/visual.dart';
import '../../../../design_system/design_system.dart';
import '../../../../l10n/gen/app_localizations.dart';
import '../../domain/chat_models.dart';
import 'renderers/tool_invocation_renderers.dart';
import 'tool_invocation_card.dart';

class ToolInvocationInline extends StatefulWidget {
  const ToolInvocationInline({
    super.key,
    required this.invocation,
    this.initiallyExpanded = false,
    this.showAsPrimary = false,
  });

  final ToolInvocation invocation;

  /// When true, body starts open (e.g. single-tool turns with a chart).
  final bool initiallyExpanded;

  /// When true, render as a primary answer artifact (no collapsible chrome).
  final bool showAsPrimary;

  static Widget pick(ToolInvocation invocation) {
    return ToolInvocationInline(invocation: invocation);
  }

  @override
  State<ToolInvocationInline> createState() => _ToolInvocationInlineState();
}

class _ToolInvocationInlineState extends State<ToolInvocationInline> {
  late bool _expanded = widget.initiallyExpanded || widget.showAsPrimary;

  @override
  void didUpdateWidget(ToolInvocationInline oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initiallyExpanded != widget.initiallyExpanded &&
        widget.initiallyExpanded) {
      _expanded = true;
    }
    if (oldWidget.showAsPrimary != widget.showAsPrimary &&
        widget.showAsPrimary) {
      _expanded = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final invocation = widget.invocation;
    final pending = invocation.status.isPending;
    final label = friendlyToolName(l10n, invocation.name);
    final body = invocation.output == null
        ? null
        : renderToolOutput(context, invocation.name, invocation.output);
    final hasBody = body != null || invocation.output != null;
    final success =
        !pending && invocation.status == ToolInvocationStatus.completed;

    if (widget.showAsPrimary && body != null && !pending) {
      return Padding(
        padding: const EdgeInsets.only(
          top: AppSpacing.s4,
          bottom: AppSpacing.s6,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  toolIcon(invocation.name),
                  size: AppIconSizes.xs,
                  color: AiTone.muted(context),
                ),
                const SizedBox(width: AppSpacing.s6),
                Flexible(
                  child: Text(
                    label,
                    style: AiType.meta(
                      context,
                    ).copyWith(color: AiTone.muted(context)),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.s8),
            body,
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.s4, bottom: AppSpacing.s2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onLongPress: () => _openDebugSheet(context),
            behavior: HitTestBehavior.opaque,
            child: AppTappable(
              onPress: hasBody && !pending
                  ? () => setState(() => _expanded = !_expanded)
                  : null,
              child: Row(
                children: [
                  AnimatedSwitcher(
                    duration: AppMotionPolicy.duration(context, Motion.fast),
                    child: Icon(
                      pending
                          ? FLucideIcons.hourglass
                          : success
                          ? FLucideIcons.circleCheck
                          : toolIcon(invocation.name),
                      key: ValueKey(pending ? 'pending' : 'done'),
                      size: AppIconSizes.xs,
                      color: pending
                          ? AiTone.active(context)
                          : AiTone.muted(context),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.s6),
                  Flexible(
                    child: Text(
                      label,
                      style: AiType.meta(context).copyWith(
                        color: pending
                            ? AiTone.active(context)
                            : AiTone.muted(context),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (hasBody && !pending) ...[
                    const SizedBox(width: AppSpacing.s4),
                    AnimatedRotation(
                      turns: _expanded ? 0.5 : 0,
                      duration: AppMotionPolicy.duration(context, Motion.fast),
                      curve: Motion.standardDecelerate,
                      child: Icon(
                        FLucideIcons.chevronDown,
                        size: AppIconSizes.xs,
                        color: AiTone.muted(context),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: AppMotionPolicy.duration(context, Motion.medium),
            curve: Motion.standardDecelerate,
            alignment: Alignment.topCenter,
            child: !_expanded || pending
                ? const SizedBox(width: double.infinity)
                : Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.s6),
                    child:
                        body ??
                        (invocation.output != null
                            ? _CompactOutput(output: invocation.output)
                            : const SizedBox.shrink()),
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
            children: [ToolInvocationCard(invocation: widget.invocation)],
          ),
        ),
      ),
    );
  }
}

/// Truncated plain-text dump for tools without a domain renderer.
class _CompactOutput extends StatelessWidget {
  const _CompactOutput({required this.output});

  final Object? output;

  @override
  Widget build(BuildContext context) {
    final text = _preview(output);
    return ToolResultSurface(
      padding: const EdgeInsets.all(AppSpacing.s10),
      child: Text(
        text,
        style: context.captionStyle.copyWith(
          color: AiTone.muted(context),
          height: 1.4,
          fontFamily: 'monospace',
        ),
        maxLines: 6,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  String _preview(Object? value) {
    try {
      final encoded = const JsonEncoder.withIndent('  ').convert(value);
      if (encoded.length <= 400) return encoded;
      return '${encoded.substring(0, 400)}…';
    } catch (_) {
      final raw = value.toString();
      if (raw.length <= 400) return raw;
      return '${raw.substring(0, 400)}…';
    }
  }
}
