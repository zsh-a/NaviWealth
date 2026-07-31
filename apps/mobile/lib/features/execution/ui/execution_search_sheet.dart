import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../composition/execution_route_paths.dart';
import '../data/execution_repository.dart';
import '../data/providers.dart';
import '../domain/execution_models.dart';
import 'execution_widgets.dart';

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
  Timer? _debounce;
  List<ExecutionSearchHit> _hits = const <ExecutionSearchHit>[];
  _ExecutionSearchScope _scope = _ExecutionSearchScope.all;
  bool _loading = false;
  int _requestId = 0;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      final next = _controller.text.trim();
      if (next == _query || !mounted) return;
      setState(() => _query = next);
      _debounce?.cancel();
      if (next.isEmpty) {
        setState(() {
          _hits = const <ExecutionSearchHit>[];
          _loading = false;
        });
        return;
      }
      _debounce = Timer(const Duration(milliseconds: 250), _runSearch);
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
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
          const SizedBox(height: AppSpacing.s8),
          AppAdaptiveChoice<_ExecutionSearchScope>(
            title: l10n.executionSearchFilterTitle,
            options: _ExecutionSearchScope.values,
            value: _scope,
            labelOf: (scope) => switch (scope) {
              _ExecutionSearchScope.all => l10n.executionSearchFilterAll,
              _ExecutionSearchScope.action => l10n.executionSearchKindAction,
              _ExecutionSearchScope.project => l10n.executionSearchKindProject,
              _ExecutionSearchScope.commitment =>
                l10n.executionSearchKindCommitment,
            },
            iconOf: (scope) => switch (scope) {
              _ExecutionSearchScope.all => FLucideIcons.search,
              _ExecutionSearchScope.action => FLucideIcons.listTodo,
              _ExecutionSearchScope.project => FLucideIcons.folder,
              _ExecutionSearchScope.commitment => FLucideIcons.target,
            },
            onChanged: (scope) => setState(() => _scope = scope),
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
                : _loading
                ? const Center(child: FCircularProgress())
                : _visibleHits.isEmpty
                ? AppEmptyState(
                    icon: FLucideIcons.searchX,
                    title: l10n.executionSearchNoResults,
                    message: l10n.executionSearchTryAgain,
                    compact: true,
                  )
                : ListView.separated(
                    itemCount: _visibleHits.length,
                    separatorBuilder: (_, _) =>
                        const SizedBox(height: AppSpacing.s6),
                    itemBuilder: (context, index) {
                      final hit = _visibleHits[index];
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
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    hit.title,
                                    style: context.labelStyle,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  Text(
                                    '${_kindLabel(l10n, hit.kind)} · ${_statusLabel(l10n, hit)}',
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
                  ),
          ),
        ],
      ),
    );
  }

  List<ExecutionSearchHit> get _visibleHits {
    final kind = switch (_scope) {
      _ExecutionSearchScope.all => null,
      _ExecutionSearchScope.action => ExecutionEntryKind.action,
      _ExecutionSearchScope.project => ExecutionEntryKind.project,
      _ExecutionSearchScope.commitment => ExecutionEntryKind.commitment,
    };
    return kind == null
        ? _hits
        : _hits.where((hit) => hit.kind == kind).toList(growable: false);
  }

  Future<void> _runSearch() async {
    final requestId = ++_requestId;
    setState(() => _loading = true);
    final owner = await ref.read(executionOwnerUserIdProvider.future);
    final repository = await ref.read(executionRepositoryProvider.future);
    final hits = await repository.search(ownerUserId: owner, query: _query);
    if (!mounted || requestId != _requestId) return;
    setState(() {
      _hits = hits;
      _loading = false;
    });
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

enum _ExecutionSearchScope { all, action, project, commitment }

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

String _statusLabel(AppLocalizations l10n, ExecutionSearchHit hit) {
  return switch (hit.kind) {
    ExecutionEntryKind.action => executionStatusLabel(
      l10n,
      ExecutionActionStatus.parse(hit.status),
    ),
    ExecutionEntryKind.project => executionProjectStatusLabel(
      l10n,
      ExecutionProjectStatus.parse(hit.status),
    ),
    ExecutionEntryKind.commitment => executionCommitmentStatusLabel(
      l10n,
      ExecutionCommitmentStatus.parse(hit.status),
    ),
    ExecutionEntryKind.progressEntry => executionProgressKindLabel(
      l10n,
      ExecutionProgressKind.parse(hit.status),
    ),
  };
}
