import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/features/finance/composition/finance_route_paths.dart';
import 'package:naviwealth/features/finance/data/preferences/base_currency_preference.dart';
import 'package:naviwealth/features/finance/data/repositories/providers.dart';
import 'package:naviwealth/features/finance/domain/models/account.dart';
import 'package:naviwealth/features/finance/domain/models/enums.dart';

import '../../../core/ai/write/write.dart';
import '../../../core/haptics/haptics.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../shared/account_color.dart';
import '../shared/account_icon_catalog.dart';
import '../shared/account_tree_picker.dart';
import '../shared/forms/forms.dart';
import 'ui/account_category_picker.dart';

part 'account_form_page_pickers.dart';

/// Create / edit page for a single [Account].
///
/// Both flows share the same form because the persisted fields are the
/// same; we just call `create` vs. `update` on the repo. We keep the page
/// stateful so a transient edit doesn't reload from the stream and stomp
/// the user's in-flight changes.
class AccountFormPage extends ConsumerStatefulWidget {
  const AccountFormPage({super.key, this.accountId});

  /// `null` for the create flow.
  final String? accountId;

  bool get isEdit => accountId != null;

  @override
  ConsumerState<AccountFormPage> createState() => _AccountFormPageState();
}

class _AccountFormPageState extends ConsumerState<AccountFormPage>
    with FormDirtyGuard<AccountFormPage> {
  @override
  String get leaveFallback => FinanceRoutes.wealthAccounts;

  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _institutionController = TextEditingController();
  final _accountNumberController = TextEditingController();
  final _noteController = TextEditingController();

  // Focus chain: name → institution → accountNumber → note.
  final _nameFocus = FocusNode();
  final _institutionFocus = FocusNode();
  final _accountNumberFocus = FocusNode();
  final _noteFocus = FocusNode();

  AccountCategory _type = AccountCategory.bank;
  AccountSide _category = accountSideForCategory(AccountCategory.bank);

  /// Tracks whether the user has explicitly picked a [_category] yet. Until
  // _categoryUserPicked is gone — accounting side is auto-derived from
  // the wealth-container category and never user-pickable.
  String? _currency;
  bool _archived = false;
  bool _busy = false;
  Account? _initial;

  /// Selected parent in the Beancount tree. `null` means top-level.
  /// Constrained on save to a same-category account (asset under
  /// asset, etc.) so the tree never crosses categories.
  String? _parentId;

  /// Icon name; `null` falls back to the bullet glyph in the picker /
  /// list rows. See [account_icon_catalog.dart] for the canonical set.
  String? _icon;

  /// Hex colour (`#RRGGBB`) from [kAccountColorPalette], or `null`.
  String? _color;

  @override
  void initState() {
    super.initState();
    dirty.bindTextControllers([
      _nameController,
      _institutionController,
      _accountNumberController,
      _noteController,
    ]);
    if (widget.isEdit) {
      _loadInitial();
    } else {
      // Default the new-account currency to the dashboard's base
      // currency — the legacy hard-coded "CNY" forced overseas users to
      // pick the right currency manually for every account.
      _currency = ref.read(baseCurrencyProvider);
    }
  }

  Future<void> _loadInitial() async {
    final repo = await ref.read(accountRepositoryProvider.future);
    final existing = await repo.findById(widget.accountId!);
    if (existing == null || !mounted) return;
    setState(() {
      _initial = existing;
      _nameController.text = existing.name;
      _institutionController.text = existing.institution ?? '';
      _accountNumberController.text = existing.accountNumber ?? '';
      _noteController.text = existing.note ?? '';
      _type = existing.type;
      _category = existing.category;
      _currency = existing.currency;
      _archived = existing.archived;
      _parentId = existing.parentId;
      _icon = existing.icon;
      _color = existing.color;
    });
    // Hydrating an existing record is not a user edit.
    dirty.snapshotBaseline();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final l10n = AppLocalizations.of(context);
    final type = _type;
    final category = _category;
    final name = _nameController.text.trim();
    final currency = _currency;
    if (currency == null) {
      AppMessenger.show(
        context,
        ToastKind.error,
        l10n.formCurrencyPickerRequired,
      );
      return;
    }
    setState(() => _busy = true);
    dirty.busy = true;
    try {
      final repo = await ref.read(accountRepositoryProvider.future);
      if (!mounted) return;

      final institution = _emptyToNull(_institutionController.text);
      final accountNumber = _emptyToNull(_accountNumberController.text);
      final note = _emptyToNull(_noteController.text);
      final archived = _archived;
      final initial = _initial;
      final parentId = _parentId;
      final icon = _icon;
      final color = _color;

      if (initial == null) {
        await repo.create(
          type: type,
          name: name,
          currency: currency,
          category: category,
          institution: institution,
          accountNumber: accountNumber,
          note: note,
          parentId: parentId,
          icon: icon,
          color: color,
        );
      } else {
        await repo.update(
          initial.id,
          name: name,
          currency: currency,
          category: category != initial.category ? category : null,
          institution: institution ?? '',
          clearInstitution: institution == null,
          accountNumber: accountNumber ?? '',
          clearAccountNumber: accountNumber == null,
          note: note ?? '',
          clearNote: note == null,
          archived: archived,
          parentId: parentId ?? '',
          clearParentId: parentId == null,
          icon: icon ?? '',
          clearIcon: icon == null,
          color: color ?? '',
          clearColor: color == null,
        );
      }
      if (!mounted) return;
      dirty.markPristine();
      Haptics.success();
      popOrGo(context, fallback: FinanceRoutes.wealthAccounts);
    } on Object {
      if (!mounted) return;
      Haptics.error();
      AppMessenger.show(context, ToastKind.error, l10n.commonSaveFailed);
    } finally {
      if (mounted) {
        dirty.busy = false;
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _delete() async {
    if (_initial == null) return;
    final l10n = AppLocalizations.of(context);
    final ok = await showConfirmDialog(
      context: context,
      title: Text(l10n.accountFormDeleteTitle),
      body: Text(l10n.accountFormDeleteContent(_initial!.name)),
      cancelLabel: l10n.accountFormCancelAction,
      confirmLabel: l10n.accountFormDeleteAction,
      destructive: true,
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      final repo = await ref.read(accountRepositoryProvider.future);
      await repo.softDelete(_initial!.id);
      if (!mounted) return;
      dirty.markPristine();
      popOrGo(context, fallback: FinanceRoutes.wealthAccounts);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String? _emptyToNull(String raw) {
    final trimmed = raw.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _institutionController.dispose();
    _accountNumberController.dispose();
    _noteController.dispose();
    _nameFocus.dispose();
    _institutionFocus.dispose();
    _accountNumberFocus.dispose();
    _noteFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final loadingExisting = widget.isEdit && _initial == null;
    final initial = _initial;
    final title = widget.isEdit
        ? (initial != null
              ? OptionalHero(
                  tag: 'account-${initial.id}-name',
                  child: Text(initial.name),
                )
              : Text(l10n.accountFormEditTitle))
        : Text(l10n.accountFormCreateTitle);
    return guardedScope(
      child: AppFormPageScaffold(
        title: title,
        confirmLeave: handleBackIntent,
        actions: [
          if (widget.isEdit)
            FHeaderAction(
              icon: const Icon(FLucideIcons.trash2),
              onPress: _busy ? null : _delete,
            ),
        ],
        child: loadingExisting
            ? const Center(child: FCircularProgress())
            : Form(
                key: _formKey,
                autovalidateMode: AutovalidateMode.onUserInteraction,
                child: AppFormScaffoldBody(
                  action: SizedBox(
                    width: double.infinity,
                    child: FButton(
                      variant: FButtonVariant.primary,
                      onPress: _busy ? null : _save,
                      child: Text(
                        _busy ? l10n.accountFormSaving : l10n.accountFormSave,
                      ),
                    ),
                  ),
                  children: [
                    // Surface AI provenance when this
                    // account was last touched by an AI proposal
                    // (`propose_account_create`). The widget is
                    // self-gating: renders nothing when the entity
                    // has no recent touch.
                    if (widget.isEdit && widget.accountId != null) ...[
                      Align(
                        alignment: Alignment.centerLeft,
                        child: AiTouchMark(
                          entityType: 'accounts',
                          entityId: widget.accountId!,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.s8),
                    ],
                    // Wealth-container category picker — semantic
                    // icon-grid, not a dropdown. The accounting side
                    // (`_category`) auto-derives via
                    // [accountSideForCategory] on every selection and
                    // is never user-editable.
                    Padding(
                      padding: const EdgeInsets.only(
                        left: AppSpacing.s4,
                        bottom: AppSpacing.s8,
                      ),
                      child: Text(
                        l10n.accountFormTypeLabel,
                        style: context.mutedLabelStyle,
                      ),
                    ),
                    AccountCategoryPicker(
                      value: _type,
                      onChanged: (v) {
                        setState(() {
                          _type = v;
                          _category = accountSideForCategory(v);
                          dirty.markDirty();
                        });
                      },
                    ),
                    const SizedBox(height: AppSpacing.s16),
                    FTextFormField(
                      control: FTextFieldControl.managed(
                        controller: _nameController,
                      ),
                      label: Text(l10n.accountFormNameLabel),
                      focusNode: _nameFocus,
                      textInputAction: TextInputAction.next,
                      validator: (v) => (v == null || v.trim().isEmpty)
                          ? l10n.accountFormNameRequired
                          : null,
                      onSubmit: (_) => _institutionFocus.requestFocus(),
                    ),
                    const SizedBox(height: AppSpacing.s12),
                    _ParentAccountPickerSection(
                      currentAccountId: _initial?.id,
                      category: _category,
                      parentId: _parentId,
                      onChanged: (v) => setState(() {
                        _parentId = v;
                        dirty.markDirty();
                      }),
                    ),
                    const SizedBox(height: AppSpacing.s12),
                    _IconPickerSection(
                      selected: _icon,
                      color: _color,
                      onChanged: (v) => setState(() {
                        _icon = v;
                        dirty.markDirty();
                      }),
                    ),
                    const SizedBox(height: AppSpacing.s12),
                    _ColorPickerSection(
                      selected: _color,
                      onChanged: (v) => setState(() {
                        _color = v;
                        dirty.markDirty();
                      }),
                    ),
                    const SizedBox(height: AppSpacing.s12),
                    CurrencyPicker(
                      value: _currency,
                      onChanged: (v) => setState(() {
                        _currency = v;
                        dirty.markDirty();
                      }),
                    ),
                    const SizedBox(height: AppSpacing.s12),
                    FTextFormField(
                      control: FTextFieldControl.managed(
                        controller: _institutionController,
                      ),
                      label: Text(l10n.accountFormInstitutionLabel),
                      description: Text(l10n.accountFormInstitutionHelper),
                      focusNode: _institutionFocus,
                      textInputAction: TextInputAction.next,
                      onSubmit: (_) => _accountNumberFocus.requestFocus(),
                    ),
                    const SizedBox(height: AppSpacing.s12),
                    FTextFormField(
                      control: FTextFieldControl.managed(
                        controller: _accountNumberController,
                      ),
                      label: Text(l10n.accountFormAccountNumberLabel),
                      focusNode: _accountNumberFocus,
                      textInputAction: TextInputAction.next,
                      onSubmit: (_) => _noteFocus.requestFocus(),
                    ),
                    const SizedBox(height: AppSpacing.s12),
                    NoteField(
                      controller: _noteController,
                      focusNode: _noteFocus,
                    ),
                    if (widget.isEdit) ...[
                      const SizedBox(height: AppSpacing.s12),
                      FSwitch(
                        label: Text(l10n.accountFormArchivedTitle),
                        description: Text(l10n.accountFormArchivedSubtitle),
                        value: _archived,
                        onChange: (v) => setState(() {
                          _archived = v;
                          dirty.markDirty();
                        }),
                      ),
                    ],
                  ],
                ),
              ),
      ),
    );
  }
}
