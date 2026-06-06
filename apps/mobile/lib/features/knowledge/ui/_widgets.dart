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
    return value.length > 10 ? value.substring(0, 10) : value;
  }
  return knowledgeDate(context, parsed, long: long);
}

enum KnowledgeStateDensity { page, section }

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
      KnowledgeStateDensity.page => const Center(child: FProgress()),
      KnowledgeStateDensity.section => const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.s8),
        child: FProgress(),
      ),
    };
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
