import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

import '../../app/route_paths.dart';
import '../../core/ai/write/write.dart';
import '../../core/haptics/haptics.dart';
import '../../data/domain/account.dart';
import '../../data/domain/enums.dart';
import '../../data/repositories/providers.dart';
import '../../design_system/design_system.dart';
import '../../l10n/gen/app_localizations.dart';
import '../settings/data/base_currency_preference.dart';
import '../shared/account_tree_picker.dart';
import '../shared/forms/forms.dart';
import 'account_icon_catalog.dart';
import 'ui/account_category_picker.dart';

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
    with OptimisticFormSubmit<AccountFormPage> {
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
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    final l10n = AppLocalizations.of(context);
    final repo = await ref.read(accountRepositoryProvider.future);
    if (!mounted) return;

    final type = _type;
    final category = _category;
    final name = _nameController.text.trim();
    final currency = _currency!;
    final institution = _emptyToNull(_institutionController.text);
    final accountNumber = _emptyToNull(_accountNumberController.text);
    final note = _emptyToNull(_noteController.text);
    final archived = _archived;
    final initial = _initial;
    final parentId = _parentId;
    final icon = _icon;
    final color = _color;

    await submitOptimistic(
      pop: () {
        Haptics.success();
        context.go(AppRoutes.accountsList);
      },
      tag: 'account',
      failureMessage: (_) => l10n.commonSaveFailed,
      retryLabel: l10n.commonRetry,
      write: () async {
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
      },
    );
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
      context.go(AppRoutes.accountsList);
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
    return FScaffold(
      header: FHeader.nested(
        title: title,
        prefixes: [backHeaderAction(context)],
        suffixes: [
          if (widget.isEdit)
            FHeaderAction(
              icon: const Icon(Icons.delete_outline),
              onPress: _busy ? null : _delete,
            ),
        ],
      ),
      childPad: false,
      child: Material(
        color: Colors.transparent,
        child: loadingExisting
            ? const Center(child: FCircularProgress())
            : Form(
                key: _formKey,
                autovalidateMode: AutovalidateMode.onUserInteraction,
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  children: [
                    // Wave 40 — surface AI provenance when this
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
                      const SizedBox(height: 8),
                    ],
                    // Wealth-container category picker — semantic
                    // icon-grid, not a dropdown. The accounting side
                    // (`_category`) auto-derives via
                    // [accountSideForCategory] on every selection and
                    // is never user-editable.
                    Padding(
                      padding: const EdgeInsets.only(left: 4, bottom: 8),
                      child: Text(
                        l10n.accountFormTypeLabel,
                        style: context.theme.typography.sm.copyWith(
                          fontWeight: FontWeight.w600,
                          color: context.theme.colors.mutedForeground,
                        ),
                      ),
                    ),
                    AccountCategoryPicker(
                      value: _type,
                      onChanged: (v) {
                        setState(() {
                          _type = v;
                          _category = accountSideForCategory(v);
                        });
                      },
                    ),
                    const SizedBox(height: 16),
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
                    const SizedBox(height: 12),
                    _ParentAccountPickerSection(
                      currentAccountId: _initial?.id,
                      category: _category,
                      parentId: _parentId,
                      onChanged: (v) => setState(() => _parentId = v),
                    ),
                    const SizedBox(height: 12),
                    _IconPickerSection(
                      selected: _icon,
                      color: _color,
                      onChanged: (v) => setState(() => _icon = v),
                    ),
                    const SizedBox(height: 12),
                    _ColorPickerSection(
                      selected: _color,
                      onChanged: (v) => setState(() => _color = v),
                    ),
                    const SizedBox(height: 12),
                    CurrencyPicker(
                      value: _currency,
                      onChanged: (v) => setState(() => _currency = v),
                    ),
                    const SizedBox(height: 12),
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
                    const SizedBox(height: 12),
                    FTextFormField(
                      control: FTextFieldControl.managed(
                        controller: _accountNumberController,
                      ),
                      label: Text(l10n.accountFormAccountNumberLabel),
                      focusNode: _accountNumberFocus,
                      textInputAction: TextInputAction.next,
                      onSubmit: (_) => _noteFocus.requestFocus(),
                    ),
                    const SizedBox(height: 12),
                    NoteField(
                      controller: _noteController,
                      focusNode: _noteFocus,
                    ),
                    if (widget.isEdit) ...[
                      const SizedBox(height: 12),
                      FSwitch(
                        label: Text(l10n.accountFormArchivedTitle),
                        description: Text(l10n.accountFormArchivedSubtitle),
                        value: _archived,
                        onChange: (v) => setState(() => _archived = v),
                      ),
                    ],
                    const SizedBox(height: 24),
                    FButton(
                      variant: FButtonVariant.primary,
                      onPress: _busy ? null : _save,
                      child: Text(
                        _busy ? l10n.accountFormSaving : l10n.accountFormSave,
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}

/// Parent picker + clear button. Filters the candidate list to
/// same-category accounts and excludes the current account plus its
/// descendants so the tree can never form a cycle.
class _ParentAccountPickerSection extends ConsumerWidget {
  const _ParentAccountPickerSection({
    required this.currentAccountId,
    required this.category,
    required this.parentId,
    required this.onChanged,
  });

  /// `null` in the create flow.
  final String? currentAccountId;
  final AccountSide category;
  final String? parentId;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final accountsAsync = ref.watch(accountsStreamProvider);
    final accounts = accountsAsync.value ?? const <Account>[];
    final filtered = _candidates(accounts);

    return Row(
      children: [
        Expanded(
          child: AccountTreePicker(
            accounts: filtered,
            value: parentId,
            onChanged: onChanged,
            category: category,
            label: l10n.accountFormParentLabel,
            helperText: l10n.accountFormParentHelper,
            allowSystemAccounts: false,
          ),
        ),
        if (parentId != null)
          FTooltip(
            tipBuilder: (_, _) => Text(l10n.accountFormMakeTopLevelTooltip),
            child: FButton.icon(
              variant: FButtonVariant.ghost,
              onPress: () => onChanged(null),
              child: const Icon(Icons.clear, size: 18),
            ),
          ),
      ],
    );
  }

  /// Same-category accounts minus self minus self's descendants.
  List<Account> _candidates(List<Account> all) {
    final selfId = currentAccountId;
    if (selfId == null) {
      return all.where((a) => a.category == category).toList();
    }
    final descendants = _descendantIds(selfId, all);
    return all
        .where(
          (a) =>
              a.id != selfId &&
              !descendants.contains(a.id) &&
              a.category == category,
        )
        .toList();
  }

  Set<String> _descendantIds(String rootId, List<Account> all) {
    final byParent = <String, List<Account>>{};
    for (final a in all) {
      final pid = a.parentId;
      if (pid == null) continue;
      byParent.putIfAbsent(pid, () => []).add(a);
    }
    final out = <String>{};
    final stack = <String>[rootId];
    while (stack.isNotEmpty) {
      final cur = stack.removeLast();
      for (final child in byParent[cur] ?? const <Account>[]) {
        if (out.add(child.id)) stack.add(child.id);
      }
    }
    return out;
  }
}

/// Horizontal grid of icon options keyed off [kAccountIconCatalogue].
/// Selecting an icon snaps the form's `_icon`; the leading "None"
/// tile clears it.
class _IconPickerSection extends StatelessWidget {
  const _IconPickerSection({
    required this.selected,
    required this.color,
    required this.onChanged,
  });

  final String? selected;
  final String? color;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final tint = _parseHexColor(color) ?? context.theme.colors.primary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.accountFormIconHeading, style: context.theme.typography.xs),
        const SizedBox(height: 4),
        SizedBox(
          height: 56,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: kAccountIconCatalogue.length + 1,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              if (index == 0) {
                final isSelected = selected == null;
                return _IconChip(
                  isSelected: isSelected,
                  selectionTint: tint,
                  onTap: () => onChanged(null),
                  tooltip: l10n.accountFormNoIconTooltip,
                  child: Icon(
                    Icons.do_not_disturb_on_outlined,
                    color: context.theme.colors.mutedForeground,
                  ),
                );
              }
              final entry = kAccountIconCatalogue[index - 1];
              final isSelected = selected == entry.name;
              return _IconChip(
                isSelected: isSelected,
                selectionTint: tint,
                onTap: () => onChanged(entry.name),
                tooltip: entry.name,
                child: Icon(
                  entry.icon,
                  color: isSelected ? tint : context.theme.colors.foreground,
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _IconChip extends StatelessWidget {
  const _IconChip({
    required this.isSelected,
    required this.selectionTint,
    required this.onTap,
    required this.child,
    required this.tooltip,
  });

  final bool isSelected;
  final Color selectionTint;
  final VoidCallback onTap;
  final Widget child;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    return FTooltip(
      tipBuilder: (_, _) => Text(tooltip),
      child: FTappable(
        onPress: onTap,
        child: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            color: isSelected
                ? selectionTint.withValues(alpha: 0.1)
                : colors.muted,
            border: Border.all(
              color: isSelected ? selectionTint : colors.border,
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Center(child: child),
        ),
      ),
    );
  }
}

/// Horizontal palette of preset hex colours from
/// [kAccountColorPalette]. Tapping a swatch snaps `_color`; the
/// leading "None" tile clears it.
class _ColorPickerSection extends StatelessWidget {
  const _ColorPickerSection({required this.selected, required this.onChanged});

  final String? selected;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.accountFormColorHeading, style: context.theme.typography.xs),
        const SizedBox(height: 4),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _ColorSwatch(
              isSelected: selected == null,
              onTap: () => onChanged(null),
              tooltip: l10n.accountFormNoColorTooltip,
              fill: context.theme.colors.muted,
              border: context.theme.colors.border,
              child: Icon(
                Icons.do_not_disturb_on_outlined,
                size: 16,
                color: context.theme.colors.mutedForeground,
              ),
            ),
            for (final hex in kAccountColorPalette)
              _ColorSwatch(
                isSelected: selected == hex,
                onTap: () => onChanged(hex),
                fill: _parseHexColor(hex) ?? context.theme.colors.secondary,
                tooltip: hex,
                border: selected == hex
                    ? context.theme.colors.primary
                    : context.theme.colors.border,
              ),
          ],
        ),
      ],
    );
  }
}

class _ColorSwatch extends StatelessWidget {
  const _ColorSwatch({
    required this.isSelected,
    required this.onTap,
    required this.fill,
    required this.border,
    required this.tooltip,
    this.child,
  });

  final bool isSelected;
  final VoidCallback onTap;
  final Color fill;
  final Color border;
  final String tooltip;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return FTooltip(
      tipBuilder: (_, _) => Text(tooltip),
      child: FTappable(
        onPress: onTap,
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: fill,
            border: Border.all(color: border, width: isSelected ? 3 : 1),
          ),
          child: child == null ? null : Center(child: child),
        ),
      ),
    );
  }
}

/// `#RRGGBB` (with or without leading `#`) → [Color]; returns `null`
/// for any malformed input. Mirrors the helper in `account_tree_picker.dart`
/// — duplicated here on purpose so the form file stays self-contained
/// for the picker sub-widgets above.
Color? _parseHexColor(String? value) {
  if (value == null || value.isEmpty) return null;
  var hex = value.replaceFirst('#', '');
  if (hex.length == 6) hex = 'FF$hex';
  if (hex.length != 8) return null;
  final parsed = int.tryParse(hex, radix: 16);
  if (parsed == null) return null;
  return Color(parsed);
}
