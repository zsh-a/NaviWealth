part of '_widgets.dart';

/// Unified KnowledgeOS loading placeholder.
class KnowledgeLoadingState extends StatelessWidget {
  const KnowledgeLoadingState({
    super.key,
    this.density = KnowledgeStateDensity.page,
  });

  final KnowledgeStateDensity density;

  @override
  Widget build(BuildContext context) {
    return switch (density) {
      KnowledgeStateDensity.page => const _KnowledgePageSkeleton(),
      KnowledgeStateDensity.section => const _KnowledgeSectionSkeleton(),
    };
  }
}

class _KnowledgePageSkeleton extends StatelessWidget {
  const _KnowledgePageSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.all(AppSpacing.s16),
      itemCount: 5,
      separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.s8),
      itemBuilder: (context, index) => const SkeletonCard(
        padding: EdgeInsets.all(AppSpacing.s12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: SkeletonBox(height: 18, radius: AppRadius.xs)),
                SizedBox(width: AppSpacing.s16),
                SkeletonBox(width: 64, height: 22, radius: AppRadius.sm),
              ],
            ),
            SizedBox(height: AppSpacing.s10),
            SkeletonBox(height: 14, radius: AppRadius.xs),
            SizedBox(height: AppSpacing.s6),
            SkeletonBox(width: 220, height: 14, radius: AppRadius.xs),
          ],
        ),
      ),
    );
  }
}

class _KnowledgeSectionSkeleton extends StatelessWidget {
  const _KnowledgeSectionSkeleton();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: AppSpacing.s4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SkeletonBox(height: 14, radius: AppRadius.xs),
          SizedBox(height: AppSpacing.s8),
          SkeletonBox(width: 220, height: 14, radius: AppRadius.xs),
          SizedBox(height: AppSpacing.s8),
          SkeletonBox(width: 160, height: 14, radius: AppRadius.xs),
        ],
      ),
    );
  }
}

/// Consistent selectable row for KnowledgeOS sheets.
class KnowledgeSelectableRow extends StatelessWidget {
  const KnowledgeSelectableRow({
    super.key,
    required this.label,
    required this.selected,
    required this.onPress,
    this.detail,
    this.mode = KnowledgeSelectionMode.checkbox,
    this.enabled = true,
    this.maxLines = 3,
  });

  final String label;
  final String? detail;
  final bool selected;
  final VoidCallback onPress;
  final KnowledgeSelectionMode mode;
  final bool enabled;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    final typography = context.theme.typography;
    final control = switch (mode) {
      KnowledgeSelectionMode.checkbox => FCheckbox(
        value: selected,
        onChange: enabled ? (_) => onPress() : null,
      ),
      KnowledgeSelectionMode.radio => FRadio(
        value: selected,
        onChange: enabled ? (_) => onPress() : null,
        semanticsLabel: label,
      ),
    };
    return FTappable(
      onPress: enabled ? onPress : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.s6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.s2),
              child: control,
            ),
            const SizedBox(width: AppSpacing.s8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: enabled
                        ? typography.body.sm
                        : context.bodyCaptionStyle,
                    maxLines: maxLines,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (detail != null) ...[
                    const SizedBox(height: AppSpacing.s2),
                    Text(
                      detail!,
                      style: context.captionStyle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Text with a lightweight query highlight for KnowledgeOS search results.
class KnowledgeHighlightedText extends StatelessWidget {
  const KnowledgeHighlightedText({
    super.key,
    required this.text,
    required this.query,
    required this.style,
    this.highlightStyle,
    this.maxLines,
    this.overflow = TextOverflow.ellipsis,
  });

  final String text;
  final String query;
  final TextStyle style;
  final TextStyle? highlightStyle;
  final int? maxLines;
  final TextOverflow overflow;

  @override
  Widget build(BuildContext context) {
    final normalizedQuery = query.trim().toLowerCase();
    if (normalizedQuery.isEmpty) {
      return Text(text, style: style, maxLines: maxLines, overflow: overflow);
    }

    final lower = text.toLowerCase();
    final spans = <TextSpan>[];
    var cursor = 0;
    while (cursor < text.length) {
      final match = lower.indexOf(normalizedQuery, cursor);
      if (match < 0) {
        spans.add(TextSpan(text: text.substring(cursor), style: style));
        break;
      }
      if (match > cursor) {
        spans.add(TextSpan(text: text.substring(cursor, match), style: style));
      }
      final end = match + normalizedQuery.length;
      spans.add(
        TextSpan(
          text: text.substring(match, end),
          style: highlightStyle ?? style.merge(context.searchHighlightStyle),
        ),
      );
      cursor = end;
    }
    return RichText(
      text: TextSpan(style: style, children: spans),
      maxLines: maxLines,
      overflow: overflow,
    );
  }
}

/// Unified KnowledgeOS empty placeholder. Page density delegates to the
/// design-system empty state; section density keeps the same icon/message
/// language inside summary cards without taking over the full viewport.
class KnowledgeEmptyState extends StatelessWidget {
  const KnowledgeEmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.density = KnowledgeStateDensity.page,
  });

  final IconData icon;
  final String title;
  final String? message;
  final KnowledgeStateDensity density;

  @override
  Widget build(BuildContext context) {
    if (density == KnowledgeStateDensity.page) {
      return AppEmptyState(icon: icon, title: title, message: message);
    }
    return _KnowledgeStateRow(
      icon: icon,
      title: title,
      message: message,
      tone: AppEmptyStateTone.neutral,
    );
  }
}

/// Unified KnowledgeOS load-failure placeholder with optional retry.
class KnowledgeErrorState extends StatelessWidget {
  const KnowledgeErrorState({
    super.key,
    required this.title,
    this.message,
    this.onRetry,
    this.density = KnowledgeStateDensity.page,
  });

  final String title;
  final String? message;
  final VoidCallback? onRetry;
  final KnowledgeStateDensity density;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final retryButton = onRetry == null
        ? null
        : FButton(
            variant: FButtonVariant.ghost,
            prefix: const Icon(FLucideIcons.refreshCw, size: AppIconSizes.xs),
            onPress: onRetry,
            child: Text(l10n.commonRetry),
          );
    if (density == KnowledgeStateDensity.page) {
      return AppEmptyState.error(
        title: title,
        message: message,
        action: retryButton,
      );
    }
    return _KnowledgeStateRow(
      icon: FLucideIcons.circleX,
      title: title,
      message: message,
      action: retryButton,
      tone: AppEmptyStateTone.error,
    );
  }
}

class _KnowledgeStateRow extends StatelessWidget {
  const _KnowledgeStateRow({
    required this.icon,
    required this.title,
    this.message,
    this.action,
    required this.tone,
  });

  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;
  final AppEmptyStateTone tone;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final iconColor = switch (tone) {
      AppEmptyStateTone.neutral => colors.primary,
      AppEmptyStateTone.error => colors.destructive,
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.s4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.s2),
            child: Icon(icon, size: AppIconSizes.sm, color: iconColor),
          ),
          const SizedBox(width: AppSpacing.s8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: context.labelStyle),
                if (message != null) ...[
                  const SizedBox(height: AppSpacing.s2),
                  Text(message!, style: context.captionStyle),
                ],
                if (action != null) ...[
                  const SizedBox(height: AppSpacing.s8),
                  action!,
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
