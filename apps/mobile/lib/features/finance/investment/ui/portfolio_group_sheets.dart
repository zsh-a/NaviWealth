import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/finance/home/domain/dashboard_models.dart';
import 'package:naviwealth/features/finance/home/ui/asset_category_visuals.dart';
import 'package:naviwealth/features/finance/rebalance/domain/portfolio_rebalance_group.dart';
import 'package:naviwealth/features/finance/rebalance/domain/rebalance_models.dart';
import 'package:naviwealth/features/finance/rebalance/ui/target_allocation_editor_sheet.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

import '../data/investment_portfolio_providers.dart';
import '../domain/strategy/portfolio_strategy.dart';
import '../domain/strategy/portfolio_strategy_template.dart';
import 'capital_allocation_plan_editor.dart';
import 'portfolio_strategy_visuals.dart';

class PortfolioGroupsSection extends ConsumerWidget {
  const PortfolioGroupsSection({super.key, required this.portfolioId});

  final String portfolioId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final groups = ref.watch(portfolioRebalanceGroupsProvider);
    return groups.whenOrLoading(
      context: context,
      onRetry: () => ref.invalidate(portfolioRebalanceGroupsProvider),
      data: (allGroups) {
        final items = allGroups
            .where((group) => group.portfolioId == portfolioId)
            .toList(growable: false);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.portfolioGroupsSectionTitle,
                    style: context.theme.typography.body.sm,
                  ),
                ),
                if (items.isNotEmpty)
                  FButton(
                    variant: FButtonVariant.ghost,
                    onPress: () =>
                        _showStrategyAllocationEditor(context, ref, items),
                    child: Text(l10n.capitalAllocationEditAction),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.s8),
            if (items.isNotEmpty)
              AppGroupedSurface(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    for (var index = 0; index < items.length; index++) ...[
                      FTile(
                        prefix: const Icon(FLucideIcons.layers3),
                        title: Text(items[index].name),
                        subtitle: Text(
                          l10n.portfolioGroupWeightSummary(
                            _percentFromBps(items[index].targetWeightBps),
                            _transferPolicyLabel(
                              l10n,
                              items[index].transferPolicy,
                            ),
                          ),
                        ),
                        suffix: const Icon(
                          FLucideIcons.chevronRight,
                          size: AppIconSizes.sm,
                        ),
                        onPress: () =>
                            _showEditGroupSheet(context, group: items[index]),
                      ),
                      if (index != items.length - 1)
                        const AppGroupedDivider(
                          indent: AppSpacing.s12,
                          endIndent: AppSpacing.s12,
                        ),
                    ],
                  ],
                ),
              ),
            const SizedBox(height: AppSpacing.s8),
            FButton(
              variant: FButtonVariant.outline,
              prefix: const Icon(FLucideIcons.plus),
              onPress: () =>
                  _showAddGroupSheet(context, portfolioId: portfolioId),
              child: Text(l10n.portfolioGroupAddAction),
            ),
            const SizedBox(height: AppSpacing.s8),
            FButton(
              variant: FButtonVariant.outline,
              prefix: const Icon(FLucideIcons.combine),
              onPress: () =>
                  _showAddOverlaySheet(context, portfolioId: portfolioId),
              child: Text(l10n.portfolioOverlayAddAction),
            ),
          ],
        );
      },
    );
  }
}

Future<void> _showStrategyAllocationEditor(
  BuildContext context,
  WidgetRef ref,
  List<PortfolioRebalanceGroup> groups,
) {
  final l10n = AppLocalizations.of(context);
  final groupById = {for (final group in groups) group.id: group};
  return showCapitalAllocationPlanEditor(
    context: context,
    title: l10n.portfolioStrategyAllocationEditTitle,
    subtitle: l10n.portfolioStrategyAllocationPlanSubtitle,
    weightLabel: l10n.portfolioGroupTargetWeightLabel,
    singleItemHint: l10n.portfolioGroupSingleTargetHint,
    drafts: [
      for (final group in groups)
        CapitalAllocationDraft(
          id: group.id,
          name: group.name,
          targetWeightBps: group.targetWeightBps,
          driftBandBps: group.driftBandBps,
          transferPolicy: group.transferPolicy,
        ),
    ],
    onSave: (drafts) async {
      final repository = await ref.read(
        investmentPortfolioRepositoryProvider.future,
      );
      await repository.updateStrategyPlan(
        portfolioId: groups.first.portfolioId,
        groups: [
          for (final draft in drafts)
            groupById[draft.id]!.copyWith(
              targetWeightBps: draft.targetWeightBps,
              driftBandBps: draft.driftBandBps,
              transferPolicy: draft.transferPolicy,
            ),
        ],
      );
    },
  );
}

Future<void> _showAddGroupSheet(
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
    final strategies = ref.watch(portfolioStrategyConfigsProvider);
    final templates = ref.watch(portfolioStrategyTemplatesProvider);
    return switch ((strategies, templates)) {
      (
        AsyncData(value: final allStrategies),
        AsyncData(value: final catalog),
      ) =>
        Builder(
          builder: (context) {
            final configured = allStrategies
                .where((strategy) => strategy.portfolioId == widget.portfolioId)
                .map((strategy) => strategy.kind)
                .toSet();
            final available = catalog
                .where(
                  (template) =>
                      template.defaultCapitalRole ==
                          StrategyCapitalRole.owner &&
                      !configured.contains(template.kind),
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
      (AsyncError(:final error, :final stackTrace), _) ||
      (_, AsyncError(:final error, :final stackTrace)) => AppEmptyState.error(
        title: userSafeErrorMessage(
          context,
          error,
          stackTrace: stackTrace,
          operation: 'load portfolio strategy templates',
        ),
        action: FButton(
          variant: FButtonVariant.outline,
          onPress: () {
            ref.invalidate(portfolioStrategyConfigsProvider);
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

Future<void> showPortfolioStrategyLibrarySheet(BuildContext context) {
  final l10n = AppLocalizations.of(context);
  return showAppSheet<void>(
    context: context,
    title: l10n.portfolioStrategyLibraryTitle,
    subtitle: l10n.portfolioStrategyLibrarySubtitle,
    builder: (_) => const _PortfolioStrategyLibrary(),
  );
}

class _PortfolioStrategyLibrary extends ConsumerWidget {
  const _PortfolioStrategyLibrary();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final languageCode = Localizations.localeOf(context).languageCode;
    final templates = ref.watch(portfolioStrategyTemplatesProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FButton(
          onPress: () => showCustomPortfolioStrategyTemplateSheet(context),
          prefix: const Icon(FLucideIcons.plus),
          child: Text(l10n.portfolioStrategyCustomCreateAction),
        ),
        const SizedBox(height: AppSpacing.s12),
        switch (templates) {
          AsyncData(value: final items) => Column(
            children: [
              for (final template in items)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.s8),
                  child: SoftCard.flat(
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.s12),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  template.displayName(languageCode),
                                  style: context.theme.typography.body.sm,
                                ),
                                Text(
                                  template.isBuiltIn
                                      ? l10n.portfolioStrategyBuiltInBadge
                                      : l10n.portfolioStrategyCustomBadge,
                                  style: context.captionStyle,
                                ),
                              ],
                            ),
                          ),
                          if (!template.isBuiltIn) ...[
                            FButton(
                              variant: FButtonVariant.ghost,
                              onPress: () =>
                                  showCustomPortfolioStrategyTemplateSheet(
                                    context,
                                    existing: template,
                                  ),
                              child: Text(l10n.portfolioStrategyEditAction),
                            ),
                            FButton(
                              variant: FButtonVariant.ghost,
                              onPress: () => _archiveStrategyTemplate(
                                context,
                                ref,
                                template,
                              ),
                              child: Text(l10n.portfolioStrategyArchiveAction),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
          AsyncError(:final error, :final stackTrace) => AppEmptyState.error(
            title: l10n.portfolioStrategyLibraryTitle,
            message: userSafeErrorMessage(
              context,
              error,
              stackTrace: stackTrace,
              operation: 'load strategy library',
            ),
          ),
          _ => const Center(child: FCircularProgress()),
        },
      ],
    );
  }

  Future<void> _archiveStrategyTemplate(
    BuildContext context,
    WidgetRef ref,
    PortfolioStrategyTemplate template,
  ) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showConfirmDialog(
      context: context,
      title: Text(l10n.portfolioStrategyArchiveTitle),
      body: Text(l10n.portfolioStrategyArchiveBody),
      cancelLabel: l10n.commonCancel,
      confirmLabel: l10n.portfolioStrategyArchiveAction,
      icon: FLucideIcons.archive,
    );
    if (confirmed != true || !context.mounted) return;
    try {
      final repository = await ref.read(
        investmentPortfolioRepositoryProvider.future,
      );
      await repository.archiveCustomStrategyTemplate(template);
    } catch (_) {
      if (context.mounted) {
        AppMessenger.show(
          context,
          ToastKind.error,
          l10n.portfolioStrategyArchiveFailed,
        );
      }
    }
  }
}

Future<void> showCustomPortfolioStrategyTemplateSheet(
  BuildContext context, {
  PortfolioStrategyTemplate? existing,
}) {
  final l10n = AppLocalizations.of(context);
  return showAppSheet<void>(
    context: context,
    title: existing == null
        ? l10n.portfolioStrategyCustomCreateAction
        : l10n.portfolioStrategyEditAction,
    builder: (_) => _CustomStrategyTemplateForm(existing: existing),
  );
}

class _CustomStrategyTemplateForm extends ConsumerStatefulWidget {
  const _CustomStrategyTemplateForm({this.existing});

  final PortfolioStrategyTemplate? existing;

  @override
  ConsumerState<_CustomStrategyTemplateForm> createState() =>
      _CustomStrategyTemplateFormState();
}

class _CustomStrategyTemplateFormState
    extends ConsumerState<_CustomStrategyTemplateForm> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _band = TextEditingController(text: '5');
  StrategyCapitalRole _role = StrategyCapitalRole.owner;
  AssetCategory _category = AssetCategory.etf;
  GroupTransferPolicy _policy = GroupTransferPolicy.bidirectional;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    if (existing == null) return;
    final languageCode =
        WidgetsBinding.instance.platformDispatcher.locale.languageCode;
    _name.text = existing.displayName(languageCode);
    _band.text = (existing.defaultDriftBandBps / 100).toStringAsFixed(
      existing.defaultDriftBandBps % 100 == 0 ? 0 : 2,
    );
    _role = existing.defaultCapitalRole;
    _policy = existing.defaultTransferPolicy;
    _category = existing.defaultInternalTarget.weights.entries
        .reduce((a, b) => a.value >= b.value ? a : b)
        .key;
  }

  @override
  void dispose() {
    _name.dispose();
    _band.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FTextFormField(
            control: FTextFieldControl.managed(controller: _name),
            label: Text(l10n.portfolioStrategyCustomNameLabel),
            validator: (value) => value?.trim().isEmpty ?? true
                ? l10n.portfolioNameRequired
                : null,
          ),
          const SizedBox(height: AppSpacing.s12),
          FSelect<StrategyCapitalRole>.rich(
            enabled: !_busy && widget.existing == null,
            format: (role) => role == StrategyCapitalRole.owner
                ? l10n.portfolioStrategyCapitalOwner
                : l10n.portfolioStrategyCapitalOverlay,
            control: FSelectControl<StrategyCapitalRole>.lifted(
              value: _role,
              onChange: (value) {
                if (value != null) setState(() => _role = value);
              },
            ),
            label: Text(l10n.portfolioStrategyCapitalRoleLabel),
            children: [
              for (final role in StrategyCapitalRole.values)
                FSelectItem<StrategyCapitalRole>(
                  value: role,
                  title: Text(
                    role == StrategyCapitalRole.owner
                        ? l10n.portfolioStrategyCapitalOwner
                        : l10n.portfolioStrategyCapitalOverlay,
                  ),
                ),
            ],
          ),
          if (_role == StrategyCapitalRole.owner) ...[
            const SizedBox(height: AppSpacing.s12),
            FSelect<AssetCategory>.rich(
              enabled: !_busy,
              format: (category) => _assetCategoryLabel(l10n, category),
              control: FSelectControl<AssetCategory>.lifted(
                value: _category,
                onChange: (value) {
                  if (value != null) setState(() => _category = value);
                },
              ),
              label: Text(l10n.portfolioStrategyDefaultAssetLabel),
              children: [
                for (final category in AssetCategory.values)
                  FSelectItem<AssetCategory>(
                    value: category,
                    title: Text(_assetCategoryLabel(l10n, category)),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.s12),
            FTextFormField(
              control: FTextFieldControl.managed(controller: _band),
              label: Text(l10n.portfolioGroupDriftBandLabel),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [_percentFormatter],
              validator: (value) => _validatePercent(value, l10n),
            ),
            const SizedBox(height: AppSpacing.s12),
            FSelect<GroupTransferPolicy>.rich(
              enabled: !_busy,
              format: (policy) => _transferPolicyLabel(l10n, policy),
              control: FSelectControl<GroupTransferPolicy>.lifted(
                value: _policy,
                onChange: (value) {
                  if (value != null) setState(() => _policy = value);
                },
              ),
              label: Text(l10n.portfolioGroupTransferPolicyLabel),
              children: [
                for (final policy in GroupTransferPolicy.values)
                  FSelectItem<GroupTransferPolicy>(
                    value: policy,
                    title: Text(_transferPolicyLabel(l10n, policy)),
                  ),
              ],
            ),
          ],
          const SizedBox(height: AppSpacing.s16),
          AppBusyButton(onPress: _save, busy: _busy, label: l10n.commonSave),
        ],
      ),
    );
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final languageCode = Localizations.localeOf(context).languageCode;
    setState(() => _busy = true);
    try {
      final repository = await ref.read(
        investmentPortfolioRepositoryProvider.future,
      );
      final existing = widget.existing;
      if (existing == null) {
        await repository.createCustomStrategyTemplate(
          name: _name.text,
          languageCode: languageCode,
          iconToken: 'layers',
          capitalRole: _role,
          defaultInternalTarget: TargetAllocation(weights: {_category: 1}),
          defaultDriftBandBps: _bpsFromPercent(_band.text),
          defaultTransferPolicy: _policy,
        );
      } else {
        await repository.updateCustomStrategyTemplate(
          template: existing,
          name: _name.text,
          languageCode: languageCode,
          defaultInternalTarget: TargetAllocation(weights: {_category: 1}),
          defaultDriftBandBps: _bpsFromPercent(_band.text),
          defaultTransferPolicy: _policy,
        );
      }
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

Future<void> _showAddOverlaySheet(
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
    final strategies = ref.watch(portfolioStrategyConfigsProvider);
    final templates = ref.watch(portfolioStrategyTemplatesProvider);
    final groups = ref.watch(portfolioRebalanceGroupsProvider);
    return switch ((strategies, templates, groups)) {
      (
        AsyncData(value: final allStrategies),
        AsyncData(value: final catalog),
        AsyncData(value: final allGroups),
      ) =>
        Builder(
          builder: (context) {
            final configured = allStrategies
                .where((strategy) => strategy.portfolioId == widget.portfolioId)
                .map((strategy) => strategy.kind)
                .toSet();
            final available = catalog
                .where(
                  (template) =>
                      template.defaultCapitalRole ==
                          StrategyCapitalRole.overlay &&
                      !configured.contains(template.kind),
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
                  onPress: () => Navigator.of(context).pop(),
                  child: Text(l10n.commonDone),
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
      (AsyncError(:final error, :final stackTrace), _, _) ||
      (_, AsyncError(:final error, :final stackTrace), _) ||
      (
        _,
        _,
        AsyncError(:final error, :final stackTrace),
      ) => AppEmptyState.error(
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

Future<void> _showEditGroupSheet(
  BuildContext context, {
  required PortfolioRebalanceGroup group,
}) {
  final l10n = AppLocalizations.of(context);
  return showAppSheet<void>(
    context: context,
    title: l10n.portfolioGroupEditTitle,
    builder: (_) => _EditPortfolioGroupForm(group: group),
  );
}

class _EditPortfolioGroupForm extends ConsumerStatefulWidget {
  const _EditPortfolioGroupForm({required this.group});

  final PortfolioRebalanceGroup group;

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
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
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
          const SizedBox(height: AppSpacing.s16),
          AppBusyButton(onPress: _save, busy: _busy, label: l10n.commonSave),
        ],
      ),
    );
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _busy = true);
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

  Future<void> _editAssetAllocation(BuildContext context) async {
    await showTargetAllocationEditorSheet(
      context: context,
      initialAllocation: _internalTarget,
      onSave: (allocation) async {
        final repository = await ref.read(
          investmentPortfolioRepositoryProvider.future,
        );
        final updated = await repository.updateGroup(
          widget.group.copyWith(internalTarget: allocation),
        );
        if (mounted) {
          setState(() => _internalTarget = updated.internalTarget);
        }
      },
    );
  }
}

final _percentFormatter = FilteringTextInputFormatter.allow(
  RegExp(r'^\d{0,3}(\.\d{0,2})?'),
);

String? _validatePercent(String? value, AppLocalizations l10n) {
  final parsed = double.tryParse(value?.trim() ?? '');
  return parsed == null || parsed < 0 || parsed > 100
      ? l10n.targetAllocationEditorRangeError
      : null;
}

int _bpsFromPercent(String value) => (double.parse(value.trim()) * 100).round();

String _percentFromBps(int value) {
  final percent = value / 100;
  return percent == percent.roundToDouble()
      ? percent.toStringAsFixed(0)
      : percent.toStringAsFixed(2);
}

String _transferPolicyLabel(AppLocalizations l10n, GroupTransferPolicy policy) {
  return switch (policy) {
    GroupTransferPolicy.bidirectional =>
      l10n.portfolioGroupTransferBidirectional,
    GroupTransferPolicy.inflowsOnly => l10n.portfolioGroupTransferInflowsOnly,
    GroupTransferPolicy.isolated => l10n.portfolioGroupTransferIsolated,
  };
}

String _assetCategoryLabel(AppLocalizations l10n, AssetCategory category) =>
    AssetCategoryVisuals.label(l10n, category);
