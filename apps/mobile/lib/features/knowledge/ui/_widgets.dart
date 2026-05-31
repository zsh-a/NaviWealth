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
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';

/// Max items a Review-tab summary card lists per section. Kept here so the
/// three cards (Routines / Decisions / Assumptions) stay in agreement.
const int kReviewCardMaxItems = 5;

/// Max chars shown for a body / summary / rationale excerpt in a list card.
const int kKnowledgeExcerptMaxChars = 200;

/// Truncate [text] to [max] chars with a trailing ellipsis. Shared by the
/// Library + Inbox list cards (was an inline `length > 200 ? substring …`
/// repeated per card type).
String knowledgeExcerpt(String text, {int max = kKnowledgeExcerptMaxChars}) =>
    text.length > max ? '${text.substring(0, max)}…' : text;

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
  });

  /// Dense list-item card: s12 padding, no header by convention
  /// (callers usually inline their own row layout).
  const KnowledgeSection.item({
    Key? key,
    String? title,
    List<Widget> children = const <Widget>[],
    Widget? trailing,
  }) : this(
         key: key,
         title: title,
         children: children,
         padding: const EdgeInsets.all(AppSpacing.s12),
         trailing: trailing,
       );

  /// Grouped section card: s16 padding, expects a title.
  const KnowledgeSection.group({
    Key? key,
    required String title,
    required List<Widget> children,
    Widget? trailing,
  }) : this(
         key: key,
         title: title,
         children: children,
         padding: const EdgeInsets.all(AppSpacing.s16),
         trailing: trailing,
       );

  final String? title;
  final TextStyle? titleStyle;
  final List<Widget> children;
  final EdgeInsets padding;

  /// Optional trailing widget in the title row (e.g. a status badge).
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final typography = context.theme.typography;
    final t = title;
    return SoftCard(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (t != null) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Text(
                    t,
                    style:
                        titleStyle ??
                        typography.md.copyWith(fontWeight: FontWeight.w600),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (trailing != null) ...[
                  const SizedBox(width: AppSpacing.s8),
                  trailing!,
                ],
              ],
            ),
            const SizedBox(height: AppSpacing.s8),
          ],
          ...children,
        ],
      ),
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
class KnowledgeStatusBadge extends StatelessWidget {
  const KnowledgeStatusBadge({super.key, required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s8,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: colors.muted,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: colors.border),
      ),
      child: Text(
        label,
        style: context.theme.typography.xs.copyWith(
          color: colors.mutedForeground,
        ),
      ),
    );
  }
}
