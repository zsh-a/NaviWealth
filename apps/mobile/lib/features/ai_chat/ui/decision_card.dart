/// Renders an `ask_user` [DecisionRequest] as an interactive choice card
/// (Claude-Code / Codex style): title + context + 2–4 option tiles with
/// pros / cons / a recommended badge. Tapping an option writes the pick
/// back as the next user turn via [onSelect]; when [interactive] is false
/// (an older, already-answered decision) the tiles render read-only.
///
/// When [DecisionRequest.allowCustom] is true, an inline free-form field
/// lets the user submit their own option instead of the canned set.
library;

import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../../../core/ai/visual/visual.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import 'decision_request.dart';

class DecisionCard extends StatefulWidget {
  const DecisionCard({
    super.key,
    required this.request,
    required this.interactive,
    this.selectedOptionId,
    required this.onSelect,
  });

  final DecisionRequest request;

  /// Only the trailing turn's decision is actionable; past ones render
  /// read-only so a scroll-back can't re-fire a stale choice.
  final bool interactive;
  final String? selectedOptionId;

  /// Called with the natural-language reply to send as the next user turn.
  final void Function(DecisionOption option, String reply) onSelect;

  /// Structured-but-natural reply written back to the conversation so the
  /// agent continues under the chosen constraint.
  static String replyFor(AppLocalizations l10n, DecisionOption o) =>
      l10n.aiChatDecisionReply(o.label);

  @override
  State<DecisionCard> createState() => _DecisionCardState();
}

class _DecisionCardState extends State<DecisionCard> {
  final TextEditingController _customCtrl = TextEditingController();
  bool _submitting = false;
  String? _localSelectedId;

  DecisionRequest get request => widget.request;
  bool get interactive => widget.interactive && !_submitting;
  String? get selectedOptionId => _localSelectedId ?? widget.selectedOptionId;

  @override
  void dispose() {
    _customCtrl.dispose();
    super.dispose();
  }

  void _pick(DecisionOption option, String reply) {
    if (!interactive) return;
    setState(() {
      _submitting = true;
      _localSelectedId = option.id;
    });
    // Haptics come from the tappable layer: option tiles use AppTappable
    // (select) and the custom submit button signals commit, so both entry
    // points into this handler are already covered.
    widget.onSelect(option, reply);
  }

  void _submitCustom() {
    final text = _customCtrl.text.trim();
    if (text.isEmpty || !interactive) return;
    final option = DecisionOption(
      id: 'custom',
      label: text,
      description: '',
      recommended: false,
      pros: const [],
      cons: const [],
    );
    _pick(option, DecisionCard.replyFor(AppLocalizations.of(context), option));
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final l10n = AppLocalizations.of(context);
    final answered = selectedOptionId != null && !widget.interactive;

    if (answered) {
      DecisionOption? selected;
      for (final o in request.options) {
        if (o.id == selectedOptionId) {
          selected = o;
          break;
        }
      }
      final label = selected?.label ?? selectedOptionId!;
      return Padding(
        padding: const EdgeInsets.only(top: AppSpacing.s4),
        child: Row(
          children: [
            Icon(
              FLucideIcons.circleCheck,
              size: AppIconSizes.xs,
              color: colors.primary,
            ),
            const SizedBox(width: AppSpacing.s6),
            Expanded(
              child: Text(
                l10n.aiChatDecisionSelected(label),
                style: AiType.meta(context).copyWith(color: colors.primary),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      );
    }

    return SoftCard.raised(
      padding: const EdgeInsets.all(AppSpacing.s12),
      borderRadius: AppRadius.md,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                FLucideIcons.listChecks,
                size: AppIconSizes.sm,
                color: colors.primary,
              ),
              const SizedBox(width: AppSpacing.s8),
              Expanded(child: Text(request.title, style: context.labelStyle)),
              if (_submitting)
                const SizedBox(
                  width: AppIconSizes.sm,
                  height: AppIconSizes.sm,
                  child: FCircularProgress(),
                ),
            ],
          ),
          if (request.context.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.s4),
            Text(request.context, style: context.captionStyle),
          ],
          const SizedBox(height: AppSpacing.s10),
          for (var i = 0; i < request.options.length; i++) ...[
            if (i > 0) const SizedBox(height: AppSpacing.s8),
            _OptionTile(
              option: request.options[i],
              selected: request.options[i].id == selectedOptionId,
              enabled: interactive,
              dimmed:
                  selectedOptionId != null &&
                  request.options[i].id != selectedOptionId,
              onTap: interactive
                  ? () {
                      final option = request.options[i];
                      _pick(option, DecisionCard.replyFor(l10n, option));
                    }
                  : null,
            ),
          ],
          if (request.allowCustom && interactive) ...[
            const SizedBox(height: AppSpacing.s12),
            Text(l10n.aiChatDecisionAllowCustom, style: context.captionStyle),
            const SizedBox(height: AppSpacing.s6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: FTextField(
                    control: FTextFieldControl.managed(controller: _customCtrl),
                    hint: l10n.aiChatDecisionCustomHint,
                    minLines: 1,
                    maxLines: 3,
                    enabled: interactive,
                  ),
                ),
                const SizedBox(width: AppSpacing.s8),
                ListenableBuilder(
                  listenable: _customCtrl,
                  builder: (context, _) {
                    final canSend = _customCtrl.text.trim().isNotEmpty;
                    return FButton.icon(
                      variant: FButtonVariant.primary,
                      onPress: AppInteraction.wrap(
                        canSend ? _submitCustom : null,
                      ),
                      child: const Icon(FLucideIcons.arrowUp),
                    );
                  },
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _OptionTile extends StatelessWidget {
  const _OptionTile({
    required this.option,
    required this.selected,
    required this.enabled,
    required this.dimmed,
    required this.onTap,
  });

  final DecisionOption option;
  final bool selected;
  final bool enabled;
  final bool dimmed;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final borderColor = selected
        ? colors.primary
        : (option.recommended
              ? colors.primary.withValues(alpha: AppOpacity.scrim)
              : colors.border);
    final opacity = dimmed ? AppOpacity.disabled : 1.0;

    return Opacity(
      opacity: opacity,
      child: AppTappable(
        onPress: onTap,
        child: AnimatedContainer(
          duration: AppMotionPolicy.duration(context, Motion.fast),
          curve: Motion.standardDecelerate,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.s12,
            vertical: AppSpacing.s10,
          ),
          decoration: BoxDecoration(
            color: selected
                ? colors.primary.withValues(alpha: AppOpacity.subtle)
                : colors.background,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(
              color: borderColor,
              width: selected ? AppStroke.medium : AppStroke.hairline,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (option.recommended)
                    Container(
                      width: 3,
                      height: 16,
                      margin: const EdgeInsets.only(right: AppSpacing.s8),
                      decoration: BoxDecoration(
                        color: colors.primary,
                        borderRadius: BorderRadius.circular(AppRadius.full),
                      ),
                    ),
                  Expanded(
                    child: Text(
                      option.label,
                      style: context.labelStyle.copyWith(
                        color: colors.foreground,
                      ),
                    ),
                  ),
                  if (option.recommended)
                    AppBadge(
                      label: AppLocalizations.of(context)
                          .aiChatRecommendedBadge,
                      tone: AppBadgeTone.accent,
                      size: AppBadgeSize.compact,
                    ),
                  if (selected) ...[
                    const SizedBox(width: AppSpacing.s4),
                    Icon(
                      FLucideIcons.check,
                      size: AppIconSizes.xs,
                      color: colors.primary,
                    ),
                  ] else if (enabled) ...[
                    const SizedBox(width: AppSpacing.s4),
                    Icon(
                      FLucideIcons.arrowRight,
                      size: AppIconSizes.xs,
                      color: colors.mutedForeground,
                    ),
                  ],
                ],
              ),
              if (option.description.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.s4),
                Text(option.description, style: context.captionStyle),
              ],
              for (final pro in option.pros)
                _Tradeoff(text: pro, positive: true),
              for (final con in option.cons)
                _Tradeoff(text: con, positive: false),
            ],
          ),
        ),
      ),
    );
  }
}

class _Tradeoff extends StatelessWidget {
  const _Tradeoff({required this.text, required this.positive});

  final String text;
  final bool positive;

  @override
  Widget build(BuildContext context) {
    final color = positive
        ? context.theme.colors.primary
        : context.theme.colors.mutedForeground;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.s4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            positive ? FLucideIcons.plus : FLucideIcons.minus,
            size: AppIconSizes.xs,
            color: color,
          ),
          const SizedBox(width: AppSpacing.s6),
          Expanded(
            child: Text(
              text,
              style: context.captionStyle.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }
}
