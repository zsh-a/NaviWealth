import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

import '../../../core/ai/composition/chat_rail_content.dart';
import '../../../core/ai/composition/chat_rail_provider.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';

/// Horizontal rail of "next action" cards rendered between the AI
/// context summary and the chat conversation.
///
/// Phase D-1.6 — the rail reads the cross-domain
/// [chatRailContentProvider] rather than reaching into
/// `features/home/`. Each domain (Finance today, HealthOS in D-2)
/// overrides the provider in `bootstrap.dart`.
class AiActionCardsRail extends ConsumerWidget {
  const AiActionCardsRail({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final selector = ref.watch(chatRailContentSelectorProvider);
    final items = selector(l10n);
    if (items.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, AppSpacing.s8, 0, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.s20, 0, AppSpacing.s16, AppSpacing.s8),
            child: Text(
              l10n.aiActionCardsTitle,
              style: context.theme.typography.xs.copyWith(
                color: context.theme.colors.mutedForeground,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          SizedBox(
            height: 132,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s16),
              itemCount: items.length,
              separatorBuilder: (_, _) => const SizedBox(width: 10),
              itemBuilder: (context, i) =>
                  _ActionCard(item: items[i], l10n: l10n),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({required this.item, required this.l10n});

  final ChatRailContent item;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final sem = SemanticColors.of(context);
    final tint = switch (item.tone) {
      ChatRailTone.success => sem.success,
      ChatRailTone.warning => sem.warning,
      ChatRailTone.danger => sem.danger,
      ChatRailTone.info => sem.info,
      null => colors.primary,
    };
    final route = item.route;
    return SizedBox(
      width: 240,
      child: SoftCard(
        onPress: route == null ? null : () => context.push(route),
        padding: const EdgeInsets.all(AppSpacing.s14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: tint.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  alignment: Alignment.center,
                  child: Icon(item.icon, size: AppIconSizes.xs, color: tint),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    item.headline,
                    style: context.theme.typography.sm.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
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
                style: context.theme.typography.xs.copyWith(
                  color: colors.mutedForeground,
                  height: 1.4,
                ),
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (route != null)
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  l10n.aiActionCardsOpen,
                  style: context.theme.typography.xs.copyWith(
                    color: colors.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
