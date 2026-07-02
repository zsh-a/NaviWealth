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

part 'knowledge_create_widgets.dart';
part 'knowledge_editor_widgets.dart';
part 'knowledge_motion_widgets.dart';
part 'knowledge_section_widgets.dart';
part 'knowledge_state_widgets.dart';

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
  final formatter = AppFormatters(locale: Localizations.localeOf(context));
  if (parsed != null) {
    return formatter.monthDay(parsed.toLocal());
  }

  final match = RegExp(r'^\d{4}-(\d{2})-(\d{2})').firstMatch(value);
  if (match == null) return value;
  final month = int.tryParse(match.group(1) ?? '');
  final day = int.tryParse(match.group(2) ?? '');
  if (month == null || day == null) return value;
  return formatter.monthDay(DateTime(2000, month, day));
}

enum KnowledgeStateDensity { page, section }

enum KnowledgeSelectionMode { checkbox, radio }
