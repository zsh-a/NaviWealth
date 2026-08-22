part of '../portfolio_group_sheets.dart';

Future<void> showCustomPortfolioStrategyTemplateSheet(
  BuildContext context, {
  PortfolioStrategyTemplate? existing,
  StrategyCapitalRole initialRole = StrategyCapitalRole.owner,
}) {
  final l10n = AppLocalizations.of(context);
  return showAppSheet<void>(
    context: context,
    title: existing == null
        ? l10n.portfolioStrategyCustomCreateAction
        : l10n.portfolioStrategyEditAction,
    builder: (_) => _CustomStrategyTemplateForm(
      existing: existing,
      initialRole: initialRole,
    ),
  );
}

class _CustomStrategyTemplateForm extends ConsumerStatefulWidget {
  const _CustomStrategyTemplateForm({this.existing, required this.initialRole});

  final PortfolioStrategyTemplate? existing;
  final StrategyCapitalRole initialRole;

  @override
  ConsumerState<_CustomStrategyTemplateForm> createState() =>
      _CustomStrategyTemplateFormState();
}

class _CustomStrategyTemplateFormState
    extends ConsumerState<_CustomStrategyTemplateForm> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _band = TextEditingController(text: '5');
  late StrategyCapitalRole _role;
  AssetCategory _category = AssetCategory.etf;
  GroupTransferPolicy _policy = GroupTransferPolicy.bidirectional;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _role = widget.initialRole;
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
              inputFormatters: const [percentInputFormatter],
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
