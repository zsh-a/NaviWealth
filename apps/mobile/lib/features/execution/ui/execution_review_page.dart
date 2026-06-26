import 'package:flutter/material.dart' show RefreshIndicator;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../../app/shell_chrome.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../data/providers.dart';
import '../domain/execution_models.dart';
import 'execution_widgets.dart';

class ExecutionReviewPage extends ConsumerWidget {
  const ExecutionReviewPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return ShellTabScaffold(
      title: l10n.executionReviewTitle,
      child: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(executionRecentProgressProvider);
          await ref.read(executionRecentProgressProvider.future);
        },
        child: _ReviewBody(),
      ),
    );
  }
}

class _ReviewBody extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final progressAsync = ref.watch(executionRecentProgressProvider);
    return progressAsync.when(
      loading: () => const Center(child: FCircularProgress()),
      error: (e, _) => ExecutionStateView(
        icon: FLucideIcons.circleX,
        title: l10n.commonError,
        message: '$e',
      ),
      data: (entries) {
        if (entries.isEmpty) {
          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: shellTabContentPadding(context),
            children: [
              ExecutionStateView(
                icon: FLucideIcons.clipboardCheck,
                title: l10n.executionReviewEmptyTitle,
                message: l10n.executionReviewEmptyBody,
              ),
            ],
          );
        }
        return ListView.separated(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: shellTabContentPadding(context),
          itemCount: entries.length,
          separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.s8),
          itemBuilder: (context, index) => _ProgressCard(entry: entries[index]),
        );
      },
    );
  }
}

class _ProgressCard extends StatelessWidget {
  const _ProgressCard({required this.entry});

  final ExecutionProgressEntry entry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SoftCard(
      padding: const EdgeInsets.all(AppSpacing.s12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppIconTile(
            icon: _icon(entry.kind),
            color: context.theme.colors.primary,
            size: 32,
            iconSize: AppIconSizes.h18,
            backgroundOpacity: AppOpacity.whisper,
            foregroundOpacity: 1,
          ),
          const SizedBox(width: AppSpacing.s10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_kindLabel(l10n, entry.kind), style: context.labelStyle),
                const SizedBox(height: AppSpacing.s4),
                Text(entry.note, style: context.bodyCaptionStyle),
                const SizedBox(height: AppSpacing.s6),
                Text(
                  executionDate(context, entry.createdAt),
                  style: context.captionStyle,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  IconData _icon(ExecutionProgressKind kind) {
    return switch (kind) {
      ExecutionProgressKind.blocker => FLucideIcons.octagonAlert,
      ExecutionProgressKind.completion => FLucideIcons.checkCheck,
      ExecutionProgressKind.dropped => FLucideIcons.archive,
      ExecutionProgressKind.scopeChange => FLucideIcons.gitBranch,
      ExecutionProgressKind.checkin => FLucideIcons.messageSquareText,
    };
  }

  String _kindLabel(AppLocalizations l10n, ExecutionProgressKind kind) {
    return switch (kind) {
      ExecutionProgressKind.blocker => l10n.executionProgressKindBlocker,
      ExecutionProgressKind.completion => l10n.executionProgressKindCompletion,
      ExecutionProgressKind.dropped => l10n.executionProgressKindDropped,
      ExecutionProgressKind.scopeChange => l10n.executionProgressKindScope,
      ExecutionProgressKind.checkin => l10n.executionProgressKindCheckin,
    };
  }
}
