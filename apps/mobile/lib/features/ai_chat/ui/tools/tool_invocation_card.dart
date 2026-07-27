import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../../../core/ai/contracts/evidence_anchor.dart';
import '../../../../core/shell/entity_route_resolver.dart';
import '../../../../design_system/design_system.dart';
import '../../../../l10n/gen/app_localizations.dart';
import '../../domain/chat_models.dart';
import '../ai_navigation.dart';
import 'renderers/tool_invocation_renderers.dart';

part 'jumps.dart';
part 'json.dart';

/// Collapsible card surfacing one tool invocation. Header shows the
/// human-friendly tool name + a one-line summary; the body (when
/// expanded) renders pretty-printed JSON for the input and output
/// payloads so the user can see exactly what the model queried.
///
/// When the tool's output references known entities (asset_id,
/// journal_entry_id, account_id), we surface a "跳到资产" / ledger
/// chip so the user can jump straight to the relevant detail page.
class ToolInvocationCard extends StatefulWidget {
  const ToolInvocationCard({
    super.key,
    required this.invocation,
    this.routeResolver,
  });

  final ToolInvocation invocation;
  final EntityRouteResolver? routeResolver;

  @override
  State<ToolInvocationCard> createState() => _ToolInvocationCardState();
}

class _ToolInvocationCardState extends State<ToolInvocationCard> {
  bool _expanded = false;
  bool _showRawJson = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final invocation = widget.invocation;
    final pending = invocation.status.isPending;
    final friendlyName = friendlyToolName(l10n, invocation.name);
    final summary = _summarizeInput(invocation.input);
    final jumps = _extractJumps(l10n, invocation.output);

    final colors = context.theme.colors;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.s8),
      child: Container(
        decoration: BoxDecoration(
          color: colors.muted,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          border: Border.all(color: colors.border, width: AppStroke.hairline),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppTappable(
              key: const Key('tool-invocation-card-header'),
              onPress: () => setState(() => _expanded = !_expanded),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.s12,
                  vertical: AppSpacing.s8,
                ),
                child: Row(
                  children: [
                    Icon(
                      pending
                          ? FLucideIcons.hourglass
                          : FLucideIcons.circleCheck,
                      size: AppIconSizes.sm,
                      color: pending ? colors.mutedForeground : colors.primary,
                    ),
                    const SizedBox(width: AppSpacing.s8),
                    Expanded(
                      child: Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: friendlyName,
                              style: context.theme.typography.body.sm.copyWith(
                                color: context.theme.colors.foreground,
                              ),
                            ),
                            if (summary != null) ...[
                              TextSpan(
                                text: '  ·  ',
                                style: context.captionStyle,
                              ),
                              TextSpan(
                                text: summary,
                                style: context.captionStyle,
                              ),
                            ],
                          ],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Icon(
                      _expanded
                          ? FLucideIcons.chevronUp
                          : FLucideIcons.chevronDown,
                      size: AppIconSizes.h18,
                      color: context.theme.colors.mutedForeground,
                    ),
                  ],
                ),
              ),
            ),
            if (jumps.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.s12,
                  0,
                  AppSpacing.s12,
                  AppSpacing.s8,
                ),
                child: Wrap(
                  spacing: AppSpacing.s8,
                  runSpacing: AppSpacing.s4,
                  children: [
                    for (final jump in jumps)
                      FButton(
                        variant: FButtonVariant.outline,
                        onPress: () => _navigate(context, jump),
                        child: Text(jump.label),
                      ),
                  ],
                ),
              ),
            if (_expanded)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.s12,
                  0,
                  AppSpacing.s12,
                  AppSpacing.s12,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _kvBlock(
                      context,
                      l10n.aiChatToolInputLabel,
                      invocation.input,
                    ),
                    if (invocation.output != null) ...[
                      const SizedBox(height: AppSpacing.s8),
                      _resultBlock(context, l10n, invocation),
                    ],
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _navigate(BuildContext context, _Jump jump) {
    final location = _entityRouteResolver(context)(_routeRefFor(jump));
    if (location == null) return;
    pushFromAiSurface(context, location);
  }

  EntityRouteResolver _entityRouteResolver(BuildContext context) {
    final explicit = widget.routeResolver;
    if (explicit != null) return explicit;
    try {
      return ProviderScope.containerOf(
        context,
        listen: false,
      ).read(entityRouteResolverProvider);
    } on Object {
      return (_) => null;
    }
  }

  /// Renders the tool's output. Tries a tool-specific renderer first; falls
  /// back to pretty-printed JSON when no renderer is registered or when the
  /// renderer threw. The user can always toggle into raw JSON for debugging,
  /// and we force the raw view when the payload is too large for the inline
  /// renderer to be useful (see [isOversizedToolPayload]).
  Widget _resultBlock(
    BuildContext context,
    AppLocalizations l10n,
    ToolInvocation invocation,
  ) {
    final oversized = isOversizedToolPayload(
      invocation.name,
      invocation.output,
    );
    final body = (oversized || _showRawJson)
        ? null
        : renderToolOutput(context, invocation.name, invocation.output);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(l10n.aiChatToolOutputLabel, style: context.microCaptionStyle),
            const Spacer(),
            if (body != null)
              AppTappable(
                onPress: () => setState(() => _showRawJson = true),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.s4,
                    vertical: AppSpacing.s2,
                  ),
                  child: Text(
                    l10n.aiChatToolShowRawJson,
                    style: context.theme.typography.body.xs2.copyWith(
                      color: context.theme.colors.primary,
                    ),
                  ),
                ),
              )
            else if (_showRawJson &&
                renderToolOutput(context, invocation.name, invocation.output) !=
                    null)
              AppTappable(
                onPress: () => setState(() => _showRawJson = false),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.s4,
                    vertical: AppSpacing.s2,
                  ),
                  child: Text(
                    l10n.aiChatToolShowCompactView,
                    style: context.theme.typography.body.xs2.copyWith(
                      color: context.theme.colors.primary,
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.s4),
        if (body != null)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppSpacing.s8),
            decoration: BoxDecoration(
              color: context.theme.colors.background,
              borderRadius: BorderRadius.circular(AppRadius.sm),
              border: Border.all(
                color: context.theme.colors.border.withValues(
                  alpha: AppOpacity.disabled,
                ),
              ),
            ),
            child: body,
          )
        else
          _rawJsonView(context, invocation.output),
      ],
    );
  }

  Widget _rawJsonView(BuildContext context, Object? value) {
    return _CodeBlock(text: _prettyJson(value));
  }

  Widget _kvBlock(BuildContext context, String label, Object? value) {
    final colors = context.theme.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TypographyTokens.labelSmallMedium.copyWith(
            height: 1.2,
            color: colors.mutedForeground,
          ),
        ),
        const SizedBox(height: AppSpacing.s4),
        _CodeBlock(text: _prettyJson(value)),
      ],
    );
  }
}
