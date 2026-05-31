/// Finance-domain override for `chatRailContentProvider`
/// (`docs/lifeos-shell.md` §4, D-1.6).
///
/// The chat rail used to be wired directly in
/// `features/ai_chat/ui/ai_action_cards_rail.dart` and reached into
/// `features/home/` to read `dashboardInsightsProvider` + render its
/// `InsightItem` model. Phase D-1.6 inverts the dependency: the rail
/// reads a domain-neutral `List<ChatRailContent>` from
/// `core/ai/composition/`, and each domain provides its own list.
///
/// This file is the FinanceOS contribution. Phase D-2 will land a
/// `features/health/composition/health_chat_rail_provider.dart`
/// alongside; `bootstrap.dart` will merge both.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ai/composition/chat_rail_content.dart';
import '../../../core/ai/composition/chat_rail_provider.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../data/dashboard_insights_provider.dart';
import '../domain/insight_models.dart';
import '../ui/insight_feed_strings.dart';

ChatRailTone? _mapTone(InsightTone? tone) => switch (tone) {
      InsightTone.success => ChatRailTone.success,
      InsightTone.warning => ChatRailTone.warning,
      InsightTone.danger => ChatRailTone.danger,
      InsightTone.info => ChatRailTone.info,
      null => null,
    };

/// Maps the home-domain `InsightItem` list into the cross-domain
/// `ChatRailContent` model the shell consumes.
List<ChatRailContent> financeChatRailContent({
  required List<InsightItem> insights,
  required AppLocalizations l10n,
}) {
  return insights
      .map((item) => ChatRailContent(
            id: 'finance:${item.kind.name}:${item.route ?? ''}',
            headline: insightHeadline(l10n, item),
            detail: insightDetail(l10n, item),
            icon: item.icon,
            tone: _mapTone(item.tone),
            route: item.route,
          ))
      .toList(growable: false);
}

/// FinanceOS implementation of [ChatRailContentSelector]. Watches the
/// home insights feed and projects each `InsightItem` into the
/// cross-domain `ChatRailContent` shape.
///
/// Override [chatRailContentSelectorProvider] with this provider in
/// `bootstrap.dart` so the chat surface picks up Finance content.
final financeChatRailContentSelectorProvider =
    Provider<ChatRailContentSelector>((ref) {
  final insights = ref.watch(dashboardInsightsProvider);
  return (l10n) => financeChatRailContent(insights: insights, l10n: l10n);
});
