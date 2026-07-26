import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

import '../../../core/ai/composition/ask_ai.dart';
import '../../../core/ai/composition/chat_rail_content.dart';
import '../../../core/ai/composition/chat_rail_provider.dart';
import '../../../core/async/deferred_provider_snapshot.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';

/// Horizontal rail of "next action" cards rendered between the AI
/// context summary and the chat conversation.
///
/// Reads cross-domain [chatRailContentProvider] output rather than reaching
/// into a specific domain's home surface. Domain packs contribute content
/// through the app composition bundle.
class AiActionCardsRail extends ConsumerWidget {
  const AiActionCardsRail({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DeferredProviderSnapshot<ChatRailContentSelector>(
      provider: chatRailContentSelectorProvider,
      initialValue: (_) => const <ChatRailContent>[],
      builder: _buildRail,
    );
  }

  Widget _buildRail(BuildContext context, ChatRailContentSelector selector) {
    final l10n = AppLocalizations.of(context);
    final items = selector(l10n);
    if (items.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.s0,
        AppSpacing.s8,
        AppSpacing.s0,
        AppSpacing.s0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.s20,
              AppSpacing.s0,
              AppSpacing.s16,
              AppSpacing.s8,
            ),
            child: Text(
              l10n.aiActionCardsTitle,
              style: context.mutedLabelStyle,
            ),
          ),
          SizedBox(
            height: AppChartHeights.compact,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s16),
              itemCount: items.length,
              separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.s10),
              itemBuilder: (context, i) =>
                  _ActionCard(item: items[i], l10n: l10n),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionCard extends ConsumerWidget {
  const _ActionCard({required this.item, required this.l10n});

  final ChatRailContent item;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.theme.colors;
    final status = context.appTheme.status;
    final tint = switch (item.tone) {
      ChatRailTone.success => status.success.fg,
      ChatRailTone.warning => status.warning.fg,
      ChatRailTone.danger => status.danger.fg,
      ChatRailTone.info => status.info.fg,
      null => colors.primary,
    };
    final route = item.route;
    final intent = item.intent;
    final onPress = route != null
        ? () => context.push(route)
        : intent == null
        ? null
        : () => askAi(
            context,
            ref,
            intent: intent,
            object: item.object,
            objectLabel: item.objectLabel,
            attrs: item.attrs,
            source: item.source,
          );
    return SizedBox(
      width: AppControlWidths.aiActionCard,
      child: SoftCard.raised(
        onPress: onPress,
        padding: AppPageRhythm.cardPadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: tint.withValues(alpha: AppOpacity.medium),
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  alignment: Alignment.center,
                  child: Icon(item.icon, size: AppIconSizes.xs, color: tint),
                ),
                const SizedBox(width: AppSpacing.s8),
                Expanded(
                  child: Text(
                    item.headline,
                    style: context.labelStyle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.s8),
            Expanded(
              child: Text(
                item.detail,
                style: context.captionStyle.copyWith(height: 1.4),
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (onPress != null)
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  l10n.aiActionCardsOpen,
                  style: context.captionLabelStyle.copyWith(
                    color: colors.primary,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
