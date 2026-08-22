part of '../portfolio_group_sheets.dart';

Future<void> showAddStrategySleeve(
  BuildContext context, {
  required String portfolioId,
}) {
  final l10n = AppLocalizations.of(context);
  return showAppSheet<void>(
    context: context,
    title: l10n.portfolioGroupAddAction,
    builder: (_) => _AddPortfolioGroupForm(portfolioId: portfolioId),
  );
}

class _AddPortfolioGroupForm extends ConsumerStatefulWidget {
  const _AddPortfolioGroupForm({required this.portfolioId});

  final String portfolioId;

  @override
  ConsumerState<_AddPortfolioGroupForm> createState() =>
      _AddPortfolioGroupFormState();
}

class _AddPortfolioGroupFormState
    extends ConsumerState<_AddPortfolioGroupForm> {
  PortfolioStrategyKind? _kind;
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final templates = ref.watch(portfolioStrategyTemplatesProvider);
    return switch (templates) {
      AsyncData(value: final catalog) => Builder(
        builder: (context) {
          final available = catalog
              .where(
                (template) =>
                    template.defaultCapitalRole == StrategyCapitalRole.owner,
              )
              .toList(growable: false);
          if (available.isEmpty) {
            return AppEmptyState(
              icon: FLucideIcons.layers,
              title: l10n.portfolioGroupNoTemplates,
              action: FButton(
                variant: FButtonVariant.outline,
                onPress: () => Navigator.of(context).pop(),
                child: Text(l10n.commonDone),
              ),
            );
          }
          final selectedKind = _kind ?? available.first.kind;
          final selected = strategyTemplateForKind(available, selectedKind)!;
          final locale = Localizations.localeOf(context);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FSelect<PortfolioStrategyKind>.rich(
                enabled: !_busy,
                format: (kind) =>
                    strategyTemplateForKind(
                      available,
                      kind,
                    )?.displayName(locale.languageCode) ??
                    kind.wire,
                control: FSelectControl<PortfolioStrategyKind>.lifted(
                  value: selectedKind,
                  onChange: (value) {
                    if (!_busy) setState(() => _kind = value);
                  },
                ),
                label: Text(l10n.portfolioStrategyLabel),
                children: [
                  for (final template in available)
                    FSelectItem<PortfolioStrategyKind>(
                      value: template.kind,
                      title: Text(template.displayName(locale.languageCode)),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.s16),
              AppBusyButton(
                onPress: () => _add(selected),
                busy: _busy,
                label: l10n.portfolioGroupAddAction,
              ),
            ],
          );
        },
      ),
      AsyncError(:final error, :final stackTrace) => AppEmptyState.error(
        title: userSafeErrorMessage(
          context,
          error,
          stackTrace: stackTrace,
          operation: 'load portfolio strategy templates',
        ),
        action: FButton(
          variant: FButtonVariant.outline,
          onPress: () {
            ref.invalidate(customPortfolioStrategyTemplatesProvider);
          },
          child: Text(l10n.commonRetry),
        ),
      ),
      _ => const Center(child: FCircularProgress()),
    };
  }

  Future<void> _add(PortfolioStrategyTemplate template) async {
    final groupName = template.displayName(
      Localizations.localeOf(context).languageCode,
    );
    setState(() => _busy = true);
    try {
      final repository = await ref.read(
        investmentPortfolioRepositoryProvider.future,
      );
      await repository.addCapitalStrategy(
        portfolioId: widget.portfolioId,
        template: template,
        groupName: groupName,
      );
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      AppMessenger.show(
        context,
        ToastKind.error,
        AppLocalizations.of(context).portfolioSaveFailed,
      );
    }
  }
}

Future<void> showAddStrategyRule(
  BuildContext context, {
  required String portfolioId,
}) {
  final l10n = AppLocalizations.of(context);
  return showAppSheet<void>(
    context: context,
    title: l10n.portfolioOverlayAddAction,
    builder: (_) => _AddPortfolioOverlayForm(portfolioId: portfolioId),
  );
}

class _AddPortfolioOverlayForm extends ConsumerStatefulWidget {
  const _AddPortfolioOverlayForm({required this.portfolioId});

  final String portfolioId;

  @override
  ConsumerState<_AddPortfolioOverlayForm> createState() =>
      _AddPortfolioOverlayFormState();
}

class _AddPortfolioOverlayFormState
    extends ConsumerState<_AddPortfolioOverlayForm> {
  PortfolioStrategyKind? _kind;
  String? _groupId;
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final templates = ref.watch(portfolioStrategyTemplatesProvider);
    final groups = ref.watch(portfolioRebalanceGroupsProvider);
    return switch ((templates, groups)) {
      (AsyncData(value: final catalog), AsyncData(value: final allGroups)) =>
        Builder(
          builder: (context) {
            final available = catalog
                .where(
                  (template) =>
                      template.defaultCapitalRole ==
                      StrategyCapitalRole.overlay,
                )
                .toList(growable: false);
            final portfolioGroups = allGroups
                .where((group) => group.portfolioId == widget.portfolioId)
                .toList(growable: false);
            if (available.isEmpty || portfolioGroups.isEmpty) {
              return AppEmptyState(
                icon: FLucideIcons.combine,
                title: l10n.portfolioOverlayNoTemplates,
                action: FButton(
                  variant: FButtonVariant.outline,
                  onPress: () => showCustomPortfolioStrategyTemplateSheet(
                    context,
                    initialRole: StrategyCapitalRole.overlay,
                  ),
                  child: Text(l10n.portfolioStrategyCustomCreateAction),
                ),
              );
            }
            final locale = Localizations.localeOf(context);
            final selectedKind = _kind ?? available.first.kind;
            final selectedTemplate = strategyTemplateForKind(
              available,
              selectedKind,
            )!;
            final selectedGroupId = _groupId ?? portfolioGroups.first.id;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                FSelect<PortfolioStrategyKind>.rich(
                  enabled: !_busy,
                  format: (kind) =>
                      strategyTemplateForKind(
                        available,
                        kind,
                      )?.displayName(locale.languageCode) ??
                      kind.wire,
                  control: FSelectControl<PortfolioStrategyKind>.lifted(
                    value: selectedKind,
                    onChange: (value) {
                      if (value != null) setState(() => _kind = value);
                    },
                  ),
                  label: Text(l10n.portfolioStrategyLabel),
                  children: [
                    for (final template in available)
                      FSelectItem<PortfolioStrategyKind>(
                        value: template.kind,
                        title: Text(template.displayName(locale.languageCode)),
                      ),
                  ],
                ),
                const SizedBox(height: AppSpacing.s12),
                FSelect<String>.rich(
                  enabled: !_busy,
                  format: (id) => portfolioGroups
                      .where((group) => group.id == id)
                      .first
                      .name,
                  control: FSelectControl<String>.lifted(
                    value: selectedGroupId,
                    onChange: (value) {
                      if (value != null) setState(() => _groupId = value);
                    },
                  ),
                  label: Text(l10n.portfolioOverlayHostGroupLabel),
                  children: [
                    for (final group in portfolioGroups)
                      FSelectItem<String>(
                        value: group.id,
                        title: Text(group.name),
                      ),
                  ],
                ),
                const SizedBox(height: AppSpacing.s16),
                AppBusyButton(
                  onPress: () => _add(
                    template: selectedTemplate,
                    groupId: selectedGroupId,
                  ),
                  busy: _busy,
                  label: l10n.portfolioOverlayAddAction,
                ),
              ],
            );
          },
        ),
      (AsyncError(:final error, :final stackTrace), _) ||
      (_, AsyncError(:final error, :final stackTrace)) => AppEmptyState.error(
        title: userSafeErrorMessage(
          context,
          error,
          stackTrace: stackTrace,
          operation: 'load portfolio overlays',
        ),
      ),
      _ => const Center(child: FCircularProgress()),
    };
  }

  Future<void> _add({
    required PortfolioStrategyTemplate template,
    required String groupId,
  }) async {
    setState(() => _busy = true);
    try {
      final repository = await ref.read(
        investmentPortfolioRepositoryProvider.future,
      );
      await repository.addStrategyOverlay(
        portfolioId: widget.portfolioId,
        rebalanceGroupId: groupId,
        template: template,
      );
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      AppMessenger.show(
        context,
        ToastKind.error,
        AppLocalizations.of(context).portfolioSaveFailed,
      );
    }
  }
}

Future<void> showEditStrategySleeve(
  BuildContext context, {
  required PortfolioRebalanceGroup group,
}) async {
  final l10n = AppLocalizations.of(context);
  final dirty = FormDirtyController();
  try {
    await showAppSheet<void>(
      context: context,
      title: l10n.portfolioGroupEditTitle,
      dirtyGuard: dirty,
      confirmDismiss: () => confirmDiscardIfDirty(context, dirty),
      builder: (_) => _EditPortfolioGroupForm(group: group, dirty: dirty),
    );
  } finally {
    dirty.dispose();
  }
}

class _EditPortfolioGroupForm extends ConsumerStatefulWidget {
  const _EditPortfolioGroupForm({required this.group, required this.dirty});

  final PortfolioRebalanceGroup group;
  final FormDirtyController dirty;

  @override
  ConsumerState<_EditPortfolioGroupForm> createState() =>
      _EditPortfolioGroupFormState();
}

class _EditPortfolioGroupFormState
    extends ConsumerState<_EditPortfolioGroupForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late TargetAllocation _internalTarget;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.group.name);
    _internalTarget = widget.group.internalTarget;
    widget.dirty.bindTextControllers([_name]);
    widget.dirty.snapshotBaseline();
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final strategies =
        ref.watch(portfolioStrategyConfigsProvider).value ??
        const <PortfolioStrategyConfig>[];
    final templates =
        ref.watch(portfolioStrategyTemplatesProvider).value ??
        kBuiltInPortfolioStrategyTemplates;
    final portfolioGroupCount =
        ref
            .watch(portfolioRebalanceGroupsProvider)
            .value
            ?.where(
              (candidate) => candidate.portfolioId == widget.group.portfolioId,
            )
            .length ??
        0;
    final overlays = strategies
        .where(
          (strategy) =>
              strategy.portfolioId == widget.group.portfolioId &&
              strategy.rebalanceGroupId == widget.group.id &&
              strategy.capitalRole == StrategyCapitalRole.overlay,
        )
        .toList(growable: false);
    final languageCode = Localizations.localeOf(context).languageCode;
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FTextFormField(
            control: FTextFieldControl.managed(controller: _name),
            label: Text(l10n.portfolioGroupNameLabel),
            validator: (value) => value?.trim().isEmpty ?? true
                ? l10n.portfolioNameRequired
                : null,
          ),
          const SizedBox(height: AppSpacing.s12),
          AppGroupedSurface(
            padding: EdgeInsets.zero,
            child: FTile(
              prefix: const Icon(FLucideIcons.chartPie),
              title: Text(l10n.targetAllocationEditorTitle),
              subtitle: Text(l10n.targetAllocationEditorSubtitle),
              suffix: const Icon(
                FLucideIcons.chevronRight,
                size: AppIconSizes.sm,
              ),
              onPress: _busy ? null : () => _editAssetAllocation(context),
            ),
          ),
          if (overlays.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.s16),
            Text(
              l10n.portfolioOverlaySectionTitle,
              style: context.theme.typography.body.sm,
            ),
            const SizedBox(height: AppSpacing.s8),
            AppGroupedSurface(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  for (var index = 0; index < overlays.length; index++) ...[
                    FTile(
                      prefix: const Icon(FLucideIcons.combine),
                      title: Text(
                        strategyTemplateForKind(
                              templates,
                              overlays[index].kind,
                            )?.displayName(languageCode) ??
                            overlays[index].kind.wire,
                      ),
                      suffix: FButton(
                        variant: FButtonVariant.ghost,
                        onPress: _busy
                            ? null
                            : () => _deleteOverlay(overlays[index]),
                        child: Text(l10n.commonDelete),
                      ),
                    ),
                    if (index != overlays.length - 1)
                      const AppGroupedDivider(
                        indent: AppSpacing.s12,
                        endIndent: AppSpacing.s12,
                      ),
                  ],
                ],
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.s16),
          AppBusyButton(onPress: _save, busy: _busy, label: l10n.commonSave),
          const SizedBox(height: AppSpacing.s12),
          if (portfolioGroupCount == 1) ...[
            Text(
              l10n.portfolioStrategyDeleteLastBlocked,
              style: context.captionStyle,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.s8),
          ],
          FButton(
            variant: FButtonVariant.destructive,
            onPress: _busy || portfolioGroupCount <= 1 ? null : _delete,
            child: Text(l10n.portfolioStrategyDeleteAction),
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _busy = true);
    widget.dirty.busy = true;
    try {
      final repository = await ref.read(
        investmentPortfolioRepositoryProvider.future,
      );
      await repository.updateGroup(
        widget.group.copyWith(
          name: _name.text.trim(),
          internalTarget: _internalTarget,
        ),
      );
      widget.dirty.markPristine();
      widget.dirty.busy = false;
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      widget.dirty.busy = false;
      AppMessenger.show(
        context,
        ToastKind.error,
        AppLocalizations.of(context).portfolioSaveFailed,
      );
    }
  }

  Future<void> _editAssetAllocation(BuildContext context) async {
    TargetAllocation? selected;
    await showTargetAllocationEditorSheet(
      context: context,
      initialAllocation: _internalTarget,
      onSave: (allocation) async {
        selected = allocation;
      },
    );
    if (mounted && selected != null) {
      setState(() => _internalTarget = selected!);
      widget.dirty.markDirty();
    }
  }

  Future<void> _delete() async {
    final l10n = AppLocalizations.of(context);
    final groups =
        ref.read(portfolioRebalanceGroupsProvider).value ??
        const <PortfolioRebalanceGroup>[];
    final destinations = groups
        .where(
          (candidate) =>
              candidate.portfolioId == widget.group.portfolioId &&
              candidate.id != widget.group.id,
        )
        .toList(growable: false);
    if (destinations.isEmpty) {
      AppMessenger.show(
        context,
        ToastKind.warning,
        l10n.portfolioStrategyDeleteLastBlocked,
      );
      return;
    }
    final assignments =
        ref.read(portfolioCapitalAssignmentsProvider).value ??
        const <PortfolioCapitalAssignment>[];
    final strategies =
        ref.read(portfolioStrategyConfigsProvider).value ??
        const <PortfolioStrategyConfig>[];
    final destinationId = await showRemovalTransferSheet(
      context: context,
      title: l10n.portfolioStrategyDeleteAction,
      description: l10n.portfolioStrategyDeleteTransferDescription(
        _percentFromBps(widget.group.targetWeightBps),
        assignments
            .where(
              (assignment) => assignment.rebalanceGroupId == widget.group.id,
            )
            .length,
        strategies
            .where(
              (strategy) =>
                  strategy.rebalanceGroupId == widget.group.id &&
                  strategy.capitalRole == StrategyCapitalRole.overlay,
            )
            .length,
      ),
      options: [
        for (final destination in destinations)
          RemovalTransferOption(
            id: destination.id,
            title: destination.name,
            subtitle: l10n.portfolioGroupWeightSummary(
              _percentFromBps(destination.targetWeightBps),
              _transferPolicyLabel(l10n, destination.transferPolicy),
            ),
          ),
      ],
    );
    if (destinationId == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final repository = await ref.read(
        investmentPortfolioRepositoryProvider.future,
      );
      await repository.removeCapitalStrategy(
        widget.group,
        destinationGroupId: destinationId,
      );
      widget.dirty.markPristine();
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      setState(() => _busy = false);
      AppMessenger.show(
        context,
        ToastKind.error,
        portfolioRemovalErrorMessage(
          l10n,
          error,
          fallback: l10n.portfolioStrategyDeleteFailed,
        ),
      );
    }
  }

  Future<void> _deleteOverlay(PortfolioStrategyConfig overlay) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showConfirmDialog(
      context: context,
      title: Text(l10n.portfolioOverlayDeleteAction),
      body: Text(l10n.portfolioOverlayDeleteConfirmation),
      confirmLabel: l10n.commonDelete,
      cancelLabel: l10n.commonCancel,
      destructive: true,
      icon: FLucideIcons.trash2,
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      final repository = await ref.read(
        investmentPortfolioRepositoryProvider.future,
      );
      await repository.removeStrategyOverlay(overlay);
      if (mounted) setState(() => _busy = false);
    } catch (error) {
      if (!mounted) return;
      setState(() => _busy = false);
      AppMessenger.show(
        context,
        ToastKind.error,
        portfolioRemovalErrorMessage(
          l10n,
          error,
          fallback: l10n.portfolioStrategyDeleteFailed,
        ),
      );
    }
  }
}
