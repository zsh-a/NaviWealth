/// Shared KnowledgeOS UI atoms.
///
/// Centralised so the 4 KnowledgeOS pages don't each grow their own
/// `_CardShell` / `_Section` / `_Shell` and 2 different `_StatusBadge`
/// definitions (the audit on 2026-05-28 caught all four). Adding a new
/// surface? Reach for these first; only define a local variant if the
/// shape genuinely doesn't fit.
///
/// **Padding rule** (use the named constructors, don't pass raw
/// EdgeInsets):
///
/// - `KnowledgeSection.item` — `s12` padding. Use for list item cards
///   (Decision / Note / Concept / Experiment rows in Library, Inbox
///   note cards, AI Suggestions per-note groups).
/// - `KnowledgeSection.group` — `s16` padding. Use for grouped /
///   section cards that wrap a title + multiple children (Review
///   tab cards, AI Suggestions outer shell, Decision detail
///   sub-sections).
///
/// The rule mirrors how the rest of the app uses SoftCard: dense
/// scannable lists tighten to s12, summary panels relax to s16.
library;

import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../../../core/ai/visual/ai_markdown.dart';
import '../../../core/format/formatters.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';

export '../domain/knowledge_text.dart';

/// Max items a Review-tab summary card lists per section. Kept here so the
/// three cards (Routines / Decisions / Assumptions) stay in agreement.
const int kReviewCardMaxItems = 5;

/// Locale-aware KnowledgeOS date display. Use this instead of slicing
/// ISO strings in UI code.
String knowledgeDate(BuildContext context, DateTime date, {bool long = false}) {
  final formatter = AppFormatters(locale: Localizations.localeOf(context));
  final local = date.toLocal();
  return long ? formatter.longDate(local) : formatter.date(local);
}

String knowledgeDateFromIso(
  BuildContext context,
  String value, {
  bool long = false,
}) {
  final parsed = DateTime.tryParse(value);
  if (parsed == null) {
    final datePrefix = RegExp(r'^\d{4}-\d{2}-\d{2}').firstMatch(value);
    return datePrefix?.group(0) ?? value;
  }
  return knowledgeDate(context, parsed, long: long);
}

String knowledgeMonthDayFromIso(BuildContext context, String value) {
  final parsed = DateTime.tryParse(value);
  final locale = Localizations.localeOf(context);
  if (parsed != null) {
    return _knowledgeMonthDay(locale, parsed.toLocal());
  }

  final match = RegExp(r'^\d{4}-(\d{2})-(\d{2})').firstMatch(value);
  if (match == null) return value;
  final month = int.tryParse(match.group(1) ?? '');
  final day = int.tryParse(match.group(2) ?? '');
  if (month == null || day == null) return value;
  return _knowledgeMonthDay(locale, DateTime(2000, month, day));
}

String _knowledgeMonthDay(Locale locale, DateTime date) {
  if (locale.languageCode == 'zh') {
    return '${date.month}月${date.day}日';
  }
  return '${date.month}/${date.day}';
}

enum KnowledgeStateDensity { page, section }

enum KnowledgeSelectionMode { checkbox, radio }

const Duration _kKnowledgeFloatingActionMotionDuration = Motion.medium;

/// Mixin for pages that hide/show a FAB on scroll direction.
///
/// Provides [fabHidden] and [onScrollUpdate]. The concrete [State] must
/// call [onScrollUpdate] from a [NotificationListener<ScrollUpdateNotification>]
/// and pass [fabHidden] to [KnowledgeFloatingActionMotion.hidden].
mixin KnowledgeFabScrollHideMixin<T extends StatefulWidget> on State<T> {
  bool fabHidden = false;

  bool onScrollUpdate(ScrollUpdateNotification notification) {
    if (notification.metrics.axis != Axis.vertical) return false;
    final delta = notification.scrollDelta ?? 0;
    if (delta > 4 && !fabHidden) {
      setState(() => fabHidden = true);
    } else if (delta < -4 && fabHidden) {
      setState(() => fabHidden = false);
    }
    return false;
  }
}

/// Shared hide/show motion for KnowledgeOS floating create actions.
class KnowledgeFloatingActionMotion extends StatelessWidget {
  const KnowledgeFloatingActionMotion({
    super.key,
    required this.hidden,
    required this.child,
  });

  final bool hidden;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: hidden,
      child: AnimatedSlide(
        duration: _kKnowledgeFloatingActionMotionDuration,
        curve: Motion.standardDecelerate,
        offset: hidden ? const Offset(0, 1.25) : Offset.zero,
        child: AnimatedOpacity(
          duration: _kKnowledgeFloatingActionMotionDuration,
          curve: Motion.standardDecelerate,
          opacity: hidden ? 0 : 1,
          child: child,
        ),
      ),
    );
  }
}

/// Visual shell for primary floating KnowledgeOS actions.
///
/// Borderless, primary-tinted surface with a soft shadow. No
/// platform-specific FAB dependency — the child [FButton] owns
/// the press interaction.
class KnowledgeFloatingActionSurface extends StatelessWidget {
  const KnowledgeFloatingActionSurface({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final isDark =
        MediaQuery.platformBrightnessOf(context) == Brightness.dark;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.primary,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        boxShadow: [
          BoxShadow(
            color: colors.primary.withValues(
              alpha: isDark ? AppOpacity.muted : 0.30,
            ),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: child,
    );
  }
}

/// Pull-to-refresh wrapper with Forui [FProgress] indicator.
///
/// Uses [NotificationListener] to track overscroll drag and triggers
/// [onRefresh] when the drag exceeds the threshold. The indicator
/// scales in from the top as the user pulls.
const double _kRefreshTriggerExtent = 80;

class KnowledgePullToRefresh extends StatefulWidget {
  const KnowledgePullToRefresh({
    super.key,
    required this.onRefresh,
    required this.child,
  });

  final Future<void> Function() onRefresh;
  final Widget child;

  @override
  State<KnowledgePullToRefresh> createState() => _KnowledgePullToRefreshState();
}

class _KnowledgePullToRefreshState extends State<KnowledgePullToRefresh> {
  double _dragExtent = 0;
  bool _refreshing = false;

  bool _onNotification(ScrollNotification notification) {
    final metrics = notification.metrics;
    if (metrics.axis != Axis.vertical) return false;

    if (notification is ScrollUpdateNotification &&
        notification.dragDetails != null &&
        metrics.pixels <= metrics.minScrollExtent) {
      final delta = notification.scrollDelta ?? 0;
      if (delta < 0) {
        setState(() {
          _dragExtent =
              (_dragExtent - delta).clamp(0, _kRefreshTriggerExtent);
        });
      }
    }

    if (notification is OverscrollNotification &&
        notification.dragDetails != null &&
        notification.overscroll < 0) {
      setState(() {
        _dragExtent = (_dragExtent - notification.overscroll)
            .clamp(0, _kRefreshTriggerExtent);
      });
    }

    if (notification is ScrollEndNotification) {
      if (_dragExtent >= _kRefreshTriggerExtent && !_refreshing) {
        _refresh();
      } else if (!_refreshing && _dragExtent != 0) {
        setState(() => _dragExtent = 0);
      }
    }
    return false;
  }

  Future<void> _refresh() async {
    setState(() {
      _refreshing = true;
      _dragExtent = _kRefreshTriggerExtent;
    });
    try {
      await widget.onRefresh();
    } finally {
      if (mounted) {
        setState(() {
          _refreshing = false;
          _dragExtent = 0;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final visible = _refreshing || _dragExtent > 0;
    final progress =
        (_dragExtent / _kRefreshTriggerExtent).clamp(0.0, 1.0);
    return Stack(
      children: [
        NotificationListener<ScrollNotification>(
          onNotification: _onNotification,
          child: widget.child,
        ),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: IgnorePointer(
            child: AnimatedOpacity(
              duration: Motion.fast,
              opacity: visible ? 1 : 0,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.s12),
                  child: Transform.scale(
                    scale: _refreshing ? 1 : progress,
                    child: const FCircularProgress(
                      size: FCircularProgressSizeVariant.xs,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

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
    final colors = context.theme.colors;
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
                    style: typography.sm.copyWith(
                      color: enabled ? null : colors.mutedForeground,
                    ),
                    maxLines: maxLines,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (detail != null) ...[
                    const SizedBox(height: AppSpacing.s2),
                    Text(
                      detail!,
                      style: typography.xs.copyWith(
                        color: colors.mutedForeground,
                      ),
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
          style:
              highlightStyle ??
              style.copyWith(
                color: context.theme.colors.primary,
                fontWeight: FontWeight.w700,
              ),
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
    final typography = context.theme.typography;
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
                Text(
                  title,
                  style: typography.sm.copyWith(fontWeight: FontWeight.w600),
                ),
                if (message != null) ...[
                  const SizedBox(height: AppSpacing.s2),
                  Text(
                    message!,
                    style: typography.xs.copyWith(
                      color: colors.mutedForeground,
                    ),
                  ),
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

/// SoftCard with optional title and a children column.
///
/// Use [KnowledgeSection.item] for dense list rows and
/// [KnowledgeSection.group] for section / summary cards — the named
/// constructors encode the s12 / s16 padding rule documented above.
/// The raw constructor exists for the rare case where a custom
/// padding really is needed.
class KnowledgeSection extends StatelessWidget {
  const KnowledgeSection({
    super.key,
    this.title,
    this.titleStyle,
    required this.children,
    this.padding = const EdgeInsets.all(AppSpacing.s16),
    this.trailing,
    this.onPress,
  });

  /// Dense list-item card: s12 padding, no header by convention
  /// (callers usually inline their own row layout).
  const KnowledgeSection.item({
    Key? key,
    String? title,
    List<Widget> children = const <Widget>[],
    Widget? trailing,
    VoidCallback? onPress,
  }) : this(
         key: key,
         title: title,
         children: children,
         padding: const EdgeInsets.all(AppSpacing.s12),
         trailing: trailing,
         onPress: onPress,
       );

  /// Grouped section card: s16 padding, expects a title.
  const KnowledgeSection.group({
    Key? key,
    required String title,
    required List<Widget> children,
    Widget? trailing,
    VoidCallback? onPress,
  }) : this(
         key: key,
         title: title,
         children: children,
         padding: const EdgeInsets.all(AppSpacing.s16),
         trailing: trailing,
         onPress: onPress,
       );

  final String? title;
  final TextStyle? titleStyle;
  final List<Widget> children;
  final EdgeInsets padding;

  /// Optional trailing widget in the title row (e.g. a status badge).
  final Widget? trailing;
  final VoidCallback? onPress;

  @override
  Widget build(BuildContext context) {
    return AppSection(
      title: title,
      titleStyle: titleStyle,
      padding: padding,
      trailing: trailing,
      onPress: onPress,
      children: children,
    );
  }
}

/// Edit/Preview toggle for a Markdown text field.
///
/// Use anywhere a user authors free-form markdown that the rest of the
/// app will render via [AiMarkdown] — the toggle lets them check the
/// rendered output before submitting. Currently driving the Note body,
/// Decision rationale, Principle rationale, Concept summary and
/// Experiment method fields; that's the entire markdown-write surface
/// in KnowledgeOS.
///
/// Owns the segmented control's mode state; the caller owns the
/// text [controller].
class MarkdownEditorWithPreview extends StatefulWidget {
  const MarkdownEditorWithPreview({
    super.key,
    required this.controller,
    this.label,
    this.hint,
    this.minLines = 3,
    this.maxLines = 6,
  });

  final TextEditingController controller;

  /// Optional label rendered above the toggle. Pass `null` when the
  /// surrounding sheet already labels the field.
  final String? label;

  final String? hint;
  final int minLines;
  final int maxLines;

  @override
  State<MarkdownEditorWithPreview> createState() =>
      _MarkdownEditorWithPreviewState();
}

enum _MarkdownMode { edit, preview }

class _MarkdownEditorWithPreviewState extends State<MarkdownEditorWithPreview> {
  _MarkdownMode _mode = _MarkdownMode.edit;

  @override
  Widget build(BuildContext context) {
    final typography = context.theme.typography;
    final colors = context.theme.colors;
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.label != null) ...[
          Text(
            widget.label!,
            style: typography.sm.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: AppSpacing.s4),
        ],
        SegmentedRow<_MarkdownMode>(
          options: _MarkdownMode.values,
          value: _mode,
          labelOf: (m) => switch (m) {
            _MarkdownMode.edit => l10n.knowledgeMarkdownEdit,
            _MarkdownMode.preview => l10n.knowledgeMarkdownPreview,
          },
          onChanged: (m) => setState(() => _mode = m),
        ),
        const SizedBox(height: AppSpacing.s8),
        if (_mode == _MarkdownMode.edit)
          FTextField(
            control: FTextFieldControl.managed(controller: widget.controller),
            hint: widget.hint,
            minLines: widget.minLines,
            maxLines: widget.maxLines,
          )
        else
          Container(
            constraints: const BoxConstraints(minHeight: 96),
            padding: const EdgeInsets.all(AppSpacing.s12),
            decoration: BoxDecoration(
              color: colors.muted,
              borderRadius: BorderRadius.circular(AppRadius.sm),
              border: Border.all(color: colors.border),
            ),
            child: widget.controller.text.trim().isEmpty
                ? Text(
                    l10n.knowledgeMarkdownPreviewEmpty,
                    style: typography.sm.copyWith(
                      color: colors.mutedForeground,
                    ),
                  )
                : AiMarkdown(text: widget.controller.text),
          ),
      ],
    );
  }
}

/// Pill badge for status labels (Decision lifecycle, Experiment state, …).
///
/// Replaces the two byte-identical `_StatusBadge` / `_Badge` definitions
/// that lived in `knowledge_library_page.dart` and
/// `knowledge_decision_detail_page.dart`.
class KnowledgeStatusLabel extends StatelessWidget {
  const KnowledgeStatusLabel({super.key, required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return AppBadge(label: label, outlined: true);
  }
}

/// Section shell for KnowledgeOS writer sheets.
///
/// Keeps dense forms scannable without turning every field into its own card.
/// Use [collapsible] for optional/reference-heavy sections.
class KnowledgeWriterSection extends StatefulWidget {
  const KnowledgeWriterSection({
    super.key,
    required this.title,
    required this.children,
    this.subtitle,
    this.trailing,
    this.collapsible = false,
    this.initiallyExpanded = true,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;
  final bool collapsible;
  final bool initiallyExpanded;
  final List<Widget> children;

  @override
  State<KnowledgeWriterSection> createState() => _KnowledgeWriterSectionState();
}

class _KnowledgeWriterSectionState extends State<KnowledgeWriterSection> {
  late bool _expanded = widget.initiallyExpanded || !widget.collapsible;

  @override
  void didUpdateWidget(covariant KnowledgeWriterSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.collapsible && !_expanded) {
      _expanded = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final typography = context.theme.typography;
    final header = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.title,
                style: typography.sm.copyWith(fontWeight: FontWeight.w600),
              ),
              if (widget.subtitle != null) ...[
                const SizedBox(height: AppSpacing.s2),
                Text(
                  widget.subtitle!,
                  style: typography.xs.copyWith(color: colors.mutedForeground),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ),
        if (widget.trailing != null) ...[
          const SizedBox(width: AppSpacing.s8),
          widget.trailing!,
        ],
        if (widget.collapsible) ...[
          const SizedBox(width: AppSpacing.s8),
          Icon(
            _expanded ? FLucideIcons.chevronUp : FLucideIcons.chevronDown,
            size: AppIconSizes.xs,
            color: colors.mutedForeground,
          ),
        ],
      ],
    );
    return Container(
      padding: const EdgeInsets.all(AppSpacing.s12),
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.collapsible)
            FTappable(
              onPress: () => setState(() => _expanded = !_expanded),
              child: header,
            )
          else
            header,
          AnimatedSwitcher(
            duration: Motion.fast,
            child: _expanded
                ? Column(
                    key: const ValueKey<String>('expanded'),
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(height: AppSpacing.s12),
                      for (var i = 0; i < widget.children.length; i++) ...[
                        if (i > 0) const SizedBox(height: AppSpacing.s12),
                        widget.children[i],
                      ],
                    ],
                  )
                : const SizedBox.shrink(key: ValueKey<String>('collapsed')),
          ),
        ],
      ),
    );
  }
}
