import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../domain/execution_models.dart';

const String kExecutionPickerNone = '';

typedef ExecutionRelationSelection = ({
  String? projectId,
  String? commitmentId,
});

String executionRelationPickerLabel(
  AppLocalizations l10n,
  List<ExecutionProject> projects,
  List<ExecutionCommitment> commitments,
  ExecutionRelationSelection selection,
) {
  final commitment = executionCommitmentById(
    commitments,
    selection.commitmentId,
  );
  if (commitment != null) return commitment.title;
  final projectId = selection.projectId;
  if (projectId != null && projectId.isNotEmpty) {
    for (final project in projects) {
      if (project.id == projectId) return project.title;
    }
    return l10n.executionUnknownProject;
  }
  return l10n.executionNoRelation;
}

String executionProjectPickerLabel(
  AppLocalizations l10n,
  List<ExecutionProject> projects,
  String? projectId,
) {
  if (projectId == null || projectId.isEmpty) {
    return l10n.executionNoProject;
  }
  for (final project in projects) {
    if (project.id == projectId) return project.title;
  }
  return l10n.executionUnknownProject;
}

String executionActionPickerLabel(
  AppLocalizations l10n,
  List<ExecutionAction> actions,
  String? actionId,
) {
  if (actionId == null || actionId.isEmpty) {
    return l10n.executionNoAction;
  }
  for (final action in actions) {
    if (action.id == actionId) return action.title;
  }
  return l10n.executionUnknownAction;
}

String executionCommitmentPickerLabel(
  AppLocalizations l10n,
  List<ExecutionCommitment> commitments,
  String? commitmentId,
) {
  if (commitmentId == null || commitmentId.isEmpty) {
    return l10n.executionNoCommitment;
  }
  for (final commitment in commitments) {
    if (commitment.id == commitmentId) return commitment.title;
  }
  return l10n.executionUnknownCommitment;
}

ExecutionCommitment? executionCommitmentById(
  List<ExecutionCommitment> commitments,
  String? commitmentId,
) {
  if (commitmentId == null || commitmentId.isEmpty) return null;
  for (final commitment in commitments) {
    if (commitment.id == commitmentId) return commitment;
  }
  return null;
}

({String? projectId, String? commitmentId}) executionRelationAfterProjectPick({
  required List<ExecutionCommitment> commitments,
  required String? currentCommitmentId,
  required String pickedProjectId,
}) {
  final nextProjectId = pickedProjectId == kExecutionPickerNone
      ? null
      : pickedProjectId;
  final commitment = executionCommitmentById(commitments, currentCommitmentId);
  final commitmentProjectId = commitment?.projectId;
  final clearsCommitment =
      commitmentProjectId != null &&
      commitmentProjectId.isNotEmpty &&
      commitmentProjectId != nextProjectId;
  return (
    projectId: nextProjectId,
    commitmentId: clearsCommitment ? null : currentCommitmentId,
  );
}

({String? projectId, String? commitmentId})
executionRelationAfterCommitmentPick({
  required List<ExecutionCommitment> commitments,
  required String? currentProjectId,
  required String pickedCommitmentId,
}) {
  if (pickedCommitmentId == kExecutionPickerNone) {
    return (projectId: currentProjectId, commitmentId: null);
  }
  final commitment = executionCommitmentById(commitments, pickedCommitmentId);
  final commitmentProjectId = commitment?.projectId;
  return (
    projectId: commitmentProjectId == null || commitmentProjectId.isEmpty
        ? currentProjectId
        : commitmentProjectId,
    commitmentId: pickedCommitmentId,
  );
}

Future<ExecutionRelationSelection?> showExecutionRelationPicker({
  required BuildContext context,
  required List<ExecutionProject> projects,
  required List<ExecutionCommitment> commitments,
  required ExecutionRelationSelection selected,
}) {
  final l10n = AppLocalizations.of(context);
  return showAppSheet<ExecutionRelationSelection>(
    context: context,
    title: l10n.executionRelationField,
    scrollable: false,
    maxHeightFactor: 0.82,
    builder: (sheetContext) => _RelationPickerList(
      projects: projects,
      commitments: commitments,
      selected: selected,
    ),
  );
}

class _RelationPickerList extends StatefulWidget {
  const _RelationPickerList({
    required this.projects,
    required this.commitments,
    required this.selected,
  });

  final List<ExecutionProject> projects;
  final List<ExecutionCommitment> commitments;
  final ExecutionRelationSelection selected;

  @override
  State<_RelationPickerList> createState() => _RelationPickerListState();
}

class _RelationPickerListState extends State<_RelationPickerList> {
  final TextEditingController _query = TextEditingController();

  @override
  void initState() {
    super.initState();
    _query.addListener(_refresh);
  }

  @override
  void dispose() {
    _query.removeListener(_refresh);
    _query.dispose();
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final query = _query.text.trim().toLowerCase();
    final showSearch = widget.projects.length + widget.commitments.length > 6;
    final independent = widget.commitments
        .where((commitment) => commitment.projectId == null)
        .toList(growable: false);
    final visibleProjects = widget.projects
        .where((project) {
          if (query.isEmpty || _matchesProject(project, query)) return true;
          return widget.commitments.any(
            (commitment) =>
                commitment.projectId == project.id &&
                _matchesCommitment(commitment, query),
          );
        })
        .toList(growable: false);
    final visibleIndependent = independent
        .where(
          (commitment) =>
              query.isEmpty || _matchesCommitment(commitment, query),
        )
        .toList(growable: false);
    final hasMatches =
        visibleProjects.isNotEmpty || visibleIndependent.isNotEmpty;
    final maxListHeight = MediaQuery.sizeOf(context).height * 0.5;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ExecutionPickerTile(
          icon: FLucideIcons.inbox,
          title: l10n.executionNoRelation,
          selected:
              widget.selected.projectId == null &&
              widget.selected.commitmentId == null,
          onPress: () =>
              Navigator.of(context).pop((projectId: null, commitmentId: null)),
        ),
        if (showSearch) ...[
          const AppDivider(),
          const SizedBox(height: AppSpacing.s8),
          FTextField(
            control: FTextFieldControl.managed(controller: _query),
            hint: l10n.executionPickerSearchHint,
            prefixBuilder: (ctx, style, variants) => const Padding(
              padding: EdgeInsetsDirectional.only(
                start: AppSpacing.s12,
                end: AppSpacing.s8,
              ),
              child: Icon(FLucideIcons.search, size: AppIconSizes.h18),
            ),
          ),
          const SizedBox(height: AppSpacing.s8),
        ] else
          const AppDivider(),
        ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxListHeight),
          child: !hasMatches
              ? AppEmptyState(
                  icon: FLucideIcons.searchX,
                  title: l10n.executionPickerSearchEmpty,
                  action: query.isEmpty
                      ? null
                      : FButton(
                          variant: FButtonVariant.outline,
                          onPress: _query.clear,
                          child: Text(l10n.aiChatSessionsSearchClear),
                        ),
                )
              : ListView(
                  shrinkWrap: true,
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  children: [
                    for (var index = 0; index < visibleProjects.length; index++)
                      ..._projectGroup(
                        context,
                        visibleProjects[index],
                        query,
                        showDivider: index > 0,
                      ),
                    if (visibleIndependent.isNotEmpty) ...[
                      if (visibleProjects.isNotEmpty) const AppDivider(),
                      _RelationGroupLabel(
                        label: l10n.executionCommitmentsSection,
                      ),
                      for (final commitment in visibleIndependent)
                        _commitmentTile(context, commitment),
                    ],
                  ],
                ),
        ),
      ],
    );
  }

  List<Widget> _projectGroup(
    BuildContext context,
    ExecutionProject project,
    String query, {
    required bool showDivider,
  }) {
    final commitments = widget.commitments
        .where(
          (commitment) =>
              commitment.projectId == project.id &&
              (query.isEmpty || _matchesCommitment(commitment, query)),
        )
        .toList(growable: false);
    return [
      if (showDivider) const AppDivider(),
      ExecutionPickerTile(
        icon: FLucideIcons.folder,
        title: project.title,
        subtitle: AppLocalizations.of(context).executionProjectField,
        selected:
            widget.selected.projectId == project.id &&
            widget.selected.commitmentId == null,
        onPress: () => Navigator.of(
          context,
        ).pop((projectId: project.id, commitmentId: null)),
      ),
      for (final commitment in commitments)
        Padding(
          padding: const EdgeInsetsDirectional.only(start: AppSpacing.s20),
          child: _commitmentTile(context, commitment),
        ),
    ];
  }

  Widget _commitmentTile(BuildContext context, ExecutionCommitment commitment) {
    return ExecutionPickerTile(
      icon: FLucideIcons.target,
      title: commitment.title,
      subtitle: AppLocalizations.of(context).executionCommitmentField,
      selected: widget.selected.commitmentId == commitment.id,
      onPress: () => Navigator.of(
        context,
      ).pop((projectId: commitment.projectId, commitmentId: commitment.id)),
    );
  }

  bool _matchesProject(ExecutionProject project, String query) =>
      project.title.toLowerCase().contains(query) ||
      project.description.toLowerCase().contains(query);

  bool _matchesCommitment(ExecutionCommitment commitment, String query) =>
      commitment.title.toLowerCase().contains(query) ||
      commitment.description.toLowerCase().contains(query);
}

class _RelationGroupLabel extends StatelessWidget {
  const _RelationGroupLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(
        AppSpacing.s16,
        AppSpacing.s12,
        AppSpacing.s16,
        AppSpacing.s4,
      ),
      child: Text(label, style: context.captionLabelStyle),
    );
  }
}

Future<String?> showExecutionActionPicker({
  required BuildContext context,
  required List<ExecutionAction> actions,
  required String? selectedId,
}) {
  final l10n = AppLocalizations.of(context);
  return showAppSheet<String>(
    context: context,
    title: l10n.executionActionField,
    scrollable: false,
    maxHeightFactor: 0.82,
    builder: (sheetContext) => _PickerList(
      emptyIcon: FLucideIcons.listTodo,
      emptyTitle: l10n.executionNoActionsAvailable,
      clearLabel: l10n.executionNoAction,
      clearIcon: FLucideIcons.x,
      selectedId: selectedId,
      items: [
        for (final a in actions)
          _PickerItem(
            id: a.id,
            label: a.title,
            detail: a.note,
            icon: FLucideIcons.listTodo,
          ),
      ],
    ),
  );
}

Future<String?> showExecutionProjectPicker({
  required BuildContext context,
  required List<ExecutionProject> projects,
  required String? selectedId,
}) {
  final l10n = AppLocalizations.of(context);
  return showAppSheet<String>(
    context: context,
    title: l10n.executionProjectField,
    scrollable: false,
    maxHeightFactor: 0.82,
    builder: (sheetContext) => _PickerList(
      emptyIcon: FLucideIcons.folderOpen,
      emptyTitle: l10n.executionNoProjectsAvailable,
      clearLabel: l10n.executionNoProject,
      clearIcon: FLucideIcons.x,
      selectedId: selectedId,
      items: [
        for (final p in projects)
          _PickerItem(
            id: p.id,
            label: p.title,
            detail: p.description,
            icon: FLucideIcons.folder,
          ),
      ],
    ),
  );
}

Future<String?> showExecutionCommitmentPicker({
  required BuildContext context,
  required List<ExecutionCommitment> commitments,
  required String? selectedId,
}) {
  final l10n = AppLocalizations.of(context);
  return showAppSheet<String>(
    context: context,
    title: l10n.executionCommitmentField,
    scrollable: false,
    maxHeightFactor: 0.82,
    builder: (sheetContext) => _PickerList(
      emptyIcon: FLucideIcons.target,
      emptyTitle: l10n.executionNoCommitmentsAvailable,
      clearLabel: l10n.executionNoCommitment,
      clearIcon: FLucideIcons.x,
      selectedId: selectedId,
      items: [
        for (final c in commitments)
          _PickerItem(
            id: c.id,
            label: c.title,
            detail: c.description,
            icon: FLucideIcons.target,
          ),
      ],
    ),
  );
}

class _PickerList extends StatefulWidget {
  const _PickerList({
    required this.items,
    required this.selectedId,
    required this.clearLabel,
    required this.clearIcon,
    required this.emptyIcon,
    required this.emptyTitle,
  });

  final List<_PickerItem> items;
  final String? selectedId;
  final String clearLabel;
  final IconData clearIcon;
  final IconData emptyIcon;
  final String emptyTitle;

  @override
  State<_PickerList> createState() => _PickerListState();
}

class _PickerListState extends State<_PickerList> {
  final TextEditingController _query = TextEditingController();

  @override
  void initState() {
    super.initState();
    _query.addListener(_onQueryChanged);
  }

  @override
  void dispose() {
    _query.removeListener(_onQueryChanged);
    _query.dispose();
    super.dispose();
  }

  void _onQueryChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final showSearch = widget.items.length > 6;
    final query = _query.text.trim().toLowerCase();
    final filtered = query.isEmpty
        ? widget.items
        : widget.items
              .where(
                (item) =>
                    item.label.toLowerCase().contains(query) ||
                    item.detail.toLowerCase().contains(query),
              )
              .toList(growable: false);

    if (widget.items.isEmpty) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ExecutionPickerTile(
            icon: widget.clearIcon,
            title: widget.clearLabel,
            selected: widget.selectedId == null || widget.selectedId!.isEmpty,
            onPress: () => Navigator.of(context).pop(kExecutionPickerNone),
          ),
          const SizedBox(height: AppSpacing.s8),
          AppEmptyState(icon: widget.emptyIcon, title: widget.emptyTitle),
        ],
      );
    }

    final maxListHeight = MediaQuery.sizeOf(context).height * 0.44;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ExecutionPickerTile(
          icon: widget.clearIcon,
          title: widget.clearLabel,
          selected: widget.selectedId == null || widget.selectedId!.isEmpty,
          onPress: () => Navigator.of(context).pop(kExecutionPickerNone),
        ),
        const AppDivider(),
        if (showSearch) ...[
          const SizedBox(height: AppSpacing.s8),
          FTextField(
            control: FTextFieldControl.managed(controller: _query),
            hint: l10n.executionPickerSearchHint,
            prefixBuilder: (ctx, style, variants) => const Padding(
              padding: EdgeInsetsDirectional.only(
                start: AppSpacing.s12,
                end: AppSpacing.s8,
              ),
              child: Icon(FLucideIcons.search, size: AppIconSizes.h18),
            ),
          ),
          const SizedBox(height: AppSpacing.s8),
        ],
        ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxListHeight),
          child: filtered.isEmpty
              ? AppEmptyState(
                  icon: FLucideIcons.searchX,
                  title: l10n.executionPickerSearchEmpty,
                  action: FButton(
                    variant: FButtonVariant.outline,
                    onPress: _query.clear,
                    child: Text(l10n.aiChatSessionsSearchClear),
                  ),
                )
              : ListView.builder(
                  shrinkWrap: true,
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    final item = filtered[index];
                    return ExecutionPickerTile(
                      icon: item.icon,
                      title: item.label,
                      subtitle: item.detail.trim().isEmpty
                          ? null
                          : item.detail.trim(),
                      selected: item.id == widget.selectedId,
                      onPress: () => Navigator.of(context).pop(item.id),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class ExecutionPickerTile extends StatelessWidget {
  const ExecutionPickerTile({
    super.key,
    required this.icon,
    required this.title,
    required this.selected,
    required this.onPress,
    this.subtitle,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final bool selected;
  final VoidCallback onPress;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    return FTile(
      prefix: Icon(icon, color: selected ? colors.primary : null),
      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: subtitle == null
          ? null
          : Text(subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis),
      suffix: selected
          ? Icon(FLucideIcons.check, color: colors.primary)
          : const Icon(FLucideIcons.chevronRight),
      onPress: onPress,
    );
  }
}

class _PickerItem {
  const _PickerItem({
    required this.id,
    required this.label,
    required this.detail,
    required this.icon,
  });

  final String id;
  final String label;
  final String detail;
  final IconData icon;
}
