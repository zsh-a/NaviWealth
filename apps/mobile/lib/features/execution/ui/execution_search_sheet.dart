import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../composition/execution_route_paths.dart';
import '../data/execution_repository.dart';
import '../data/providers.dart';

Future<void> showExecutionSearchSheet({required BuildContext context}) {
  return showAppSheet<void>(
    context: context,
    title: AppLocalizations.of(context).executionSearchTitle,
    builder: (_) => const _ExecutionSearchBody(),
  );
}

class _ExecutionSearchBody extends ConsumerStatefulWidget {
  const _ExecutionSearchBody();

  @override
  ConsumerState<_ExecutionSearchBody> createState() =>
      _ExecutionSearchBodyState();
}

class _ExecutionSearchBodyState extends ConsumerState<_ExecutionSearchBody> {
  final TextEditingController _controller = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      final next = _controller.text.trim();
      if (next != _query && mounted) setState(() => _query = next);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SizedBox(
      height: 460,
      child: Column(
        children: [
          FTextField(
            control: FTextFieldControl.managed(controller: _controller),
            hint: l10n.executionSearchHint,
          ),
          const SizedBox(height: AppSpacing.s12),
          Expanded(
            child: _query.isEmpty
                ? AppEmptyState(
                    icon: FLucideIcons.search,
                    title: l10n.executionSearchEmptyTitle,
                    message: l10n.executionSearchEmptyBody,
                    compact: true,
                  )
                : FutureBuilder<List<ExecutionSearchHit>>(
                    future: _search(),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) {
                        return const Center(child: FCircularProgress());
                      }
                      final hits = snapshot.data!;
                      if (hits.isEmpty) {
                        return AppEmptyState(
                          icon: FLucideIcons.searchX,
                          title: l10n.executionSearchNoResults,
                          message: l10n.executionSearchTryAgain,
                          compact: true,
                        );
                      }
                      return ListView.separated(
                        itemCount: hits.length,
                        separatorBuilder: (_, _) =>
                            const SizedBox(height: AppSpacing.s6),
                        itemBuilder: (context, index) {
                          final hit = hits[index];
                          return SoftCard(
                            level: SoftCardLevel.raised,
                            onPress: () => _open(hit),
                            padding: const EdgeInsets.all(AppSpacing.s12),
                            child: Row(
                              children: [
                                Icon(_icon(hit.kind), size: AppIconSizes.sm),
                                const SizedBox(width: AppSpacing.s10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        hit.title,
                                        style: context.labelStyle,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      Text(
                                        '${_kindLabel(l10n, hit.kind)} · ${hit.status}',
                                        style: context.captionStyle,
                                      ),
                                    ],
                                  ),
                                ),
                                const Icon(
                                  FLucideIcons.chevronRight,
                                  size: AppIconSizes.xs,
                                ),
                              ],
                            ),
                          );
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Future<List<ExecutionSearchHit>> _search() async {
    final owner = await ref.read(executionOwnerUserIdProvider.future);
    final repository = await ref.read(executionRepositoryProvider.future);
    return repository.search(ownerUserId: owner, query: _query);
  }

  void _open(ExecutionSearchHit hit) {
    Navigator.of(context).pop();
    context.push(switch (hit.kind) {
      ExecutionEntryKind.action => ExecutionRoutes.action(hit.id),
      ExecutionEntryKind.project => ExecutionRoutes.project(hit.id),
      ExecutionEntryKind.commitment => ExecutionRoutes.commitment(hit.id),
      ExecutionEntryKind.progressEntry => ExecutionRoutes.review,
    });
  }
}

IconData _icon(ExecutionEntryKind kind) => switch (kind) {
  ExecutionEntryKind.action => FLucideIcons.listTodo,
  ExecutionEntryKind.project => FLucideIcons.folder,
  ExecutionEntryKind.commitment => FLucideIcons.target,
  ExecutionEntryKind.progressEntry => FLucideIcons.messageSquareText,
};

String _kindLabel(AppLocalizations l10n, ExecutionEntryKind kind) =>
    switch (kind) {
      ExecutionEntryKind.action => l10n.executionSearchKindAction,
      ExecutionEntryKind.project => l10n.executionSearchKindProject,
      ExecutionEntryKind.commitment => l10n.executionSearchKindCommitment,
      ExecutionEntryKind.progressEntry => l10n.executionSearchKindProgress,
    };
