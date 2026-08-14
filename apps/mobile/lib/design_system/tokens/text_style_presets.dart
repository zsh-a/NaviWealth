import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

/// Preset text styles that combine a ForUI typography token with the
/// muted foreground colour. These are the most commonly copy-pasted
/// style expressions in the codebase (43+ occurrences).
///
/// Usage:
/// ```dart
/// // Before:
/// Text(sub, style: typography.body.xs.copyWith(color: colors.mutedForeground))
/// // After:
/// Text(sub, style: context.captionStyle)
/// ```
extension AppTextStyles on BuildContext {
  /// `typography.body.xs` + `colors.mutedForeground` — the "caption" style
  /// used for metadata, timestamps, and secondary labels.
  TextStyle get captionStyle =>
      theme.typography.body.xs.copyWith(color: theme.colors.mutedForeground);

  /// `typography.body.sm` + `colors.mutedForeground` — the "body caption"
  /// style used for slightly larger secondary text.
  TextStyle get bodyCaptionStyle =>
      theme.typography.body.sm.copyWith(color: theme.colors.mutedForeground);

  /// `bodyCaptionStyle` + semibold — subdued section headings.
  TextStyle get bodyCaptionStrongStyle =>
      bodyCaptionStyle.copyWith(fontWeight: FontWeight.w600);

  /// `typography.body.xs2` + `colors.mutedForeground` — the smallest
  /// caption style used for badges and micro-labels.
  TextStyle get microCaptionStyle =>
      theme.typography.body.xs2.copyWith(color: theme.colors.mutedForeground);

  /// `captionStyle` + medium — secondary units and selected tab captions.
  TextStyle get captionMediumStyle =>
      captionStyle.copyWith(fontWeight: FontWeight.w500);

  /// `typography.body.sm` + semibold — compact row labels and card subtitles.
  TextStyle get labelStyle =>
      theme.typography.body.sm.copyWith(fontWeight: FontWeight.w600);

  /// `typography.body.sm` + strong — compact emphasized values.
  TextStyle get strongLabelStyle =>
      theme.typography.body.sm.copyWith(fontWeight: FontWeight.w700);

  /// `typography.body.sm` + medium — unselected navigation labels and quiet text.
  TextStyle get mediumLabelStyle =>
      theme.typography.body.sm.copyWith(fontWeight: FontWeight.w500);

  /// `typography.body.sm` + semibold + muted — subdued compact labels.
  TextStyle get mutedLabelStyle =>
      labelStyle.copyWith(color: theme.colors.mutedForeground);

  /// `typography.body.xs` + semibold — compact emphasis labels and mini chips.
  TextStyle get captionLabelStyle =>
      theme.typography.body.xs.copyWith(fontWeight: FontWeight.w600);

  /// `typography.body.xs` + strong — selected mini labels.
  TextStyle get captionStrongStyle =>
      theme.typography.body.xs.copyWith(fontWeight: FontWeight.w700);

  /// `typography.body.xs2` + semibold — dense status tags and overlines.
  TextStyle get microLabelStyle =>
      theme.typography.body.xs2.copyWith(fontWeight: FontWeight.w600);

  /// `typography.body.xs` + medium — regular pill badge labels.
  TextStyle get badgeLabelStyle =>
      theme.typography.body.xs.copyWith(fontWeight: FontWeight.w500);

  /// `typography.body.xs2` + medium — compact pill badge labels.
  TextStyle get compactBadgeLabelStyle =>
      theme.typography.body.xs2.copyWith(fontWeight: FontWeight.w500);

  /// Search/query highlight overlay for spans that keep their base size.
  TextStyle get searchHighlightStyle =>
      TextStyle(color: theme.colors.primary, fontWeight: FontWeight.w700);

  /// `typography.body.md` + semibold — primary row titles and compact section
  /// headings.
  TextStyle get rowTitleStyle =>
      theme.typography.body.md.copyWith(fontWeight: FontWeight.w600);

  /// `typography.body.md` + strong — emphasized row values.
  TextStyle get strongRowTitleStyle =>
      theme.typography.body.md.copyWith(fontWeight: FontWeight.w700);

  /// `typography.body.lg` + semibold — page-local hero values/headlines.
  TextStyle get titleLabelStyle =>
      theme.typography.body.lg.copyWith(fontWeight: FontWeight.w600);

  /// `typography.body.lg` + strong — primary numeric values inside compact cards.
  TextStyle get strongTitleStyle =>
      theme.typography.body.lg.copyWith(fontWeight: FontWeight.w700);

  /// `typography.body.xl` + strong — local hero verdicts and compact headlines.
  TextStyle get strongHeadlineStyle =>
      theme.typography.body.xl.copyWith(fontWeight: FontWeight.w700);

  /// `typography.body.xl2` + semibold — empty-state and page hero titles.
  TextStyle get displayTitleStyle =>
      theme.typography.body.xl2.copyWith(fontWeight: FontWeight.w600);

  /// [displayTitleStyle] with tight leading — Today brief greeting titles.
  TextStyle get briefGreetingTitleStyle =>
      displayTitleStyle.copyWith(height: 1.05);
}
