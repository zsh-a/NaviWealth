import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/domain/account.dart';
import '../../data/domain/enums.dart';
import '../../data/repositories/providers.dart';
import '../../design_system/design_system.dart';
import '../settings/data/base_currency_preference.dart';
import '../shared/forms/forms.dart';
import 'accounts_page.dart' show accountTypeLabel;

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

class _AccountFormPageState extends ConsumerState<AccountFormPage> {
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

  AccountType _type = AccountType.bank;
  String? _currency;
  bool _archived = false;
  bool _busy = false;
  Account? _initial;

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
      _currency = existing.currency;
      _archived = existing.archived;
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      final repo = await ref.read(accountRepositoryProvider.future);
      if (_initial == null) {
        await repo.create(
          type: _type,
          name: _nameController.text.trim(),
          currency: _currency!,
          institution: _emptyToNull(_institutionController.text),
          accountNumber: _emptyToNull(_accountNumberController.text),
          note: _emptyToNull(_noteController.text),
        );
      } else {
        await repo.update(
          _initial!.id,
          name: _nameController.text.trim(),
          currency: _currency,
          institution: _institutionController.text.trim(),
          clearInstitution: _institutionController.text.trim().isEmpty,
          accountNumber: _accountNumberController.text.trim(),
          clearAccountNumber: _accountNumberController.text.trim().isEmpty,
          note: _noteController.text.trim(),
          clearNote: _noteController.text.trim().isEmpty,
          archived: _archived,
        );
      }
      if (!mounted) return;
      context.go('/accounts');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    if (_initial == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除账户'),
        content: Text('确认删除“${_initial!.name}”？该操作可同步给其他设备。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      final repo = await ref.read(accountRepositoryProvider.future);
      await repo.softDelete(_initial!.id);
      if (!mounted) return;
      context.go('/accounts');
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
    final loadingExisting = widget.isEdit && _initial == null;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isEdit ? '编辑账户' : '新建账户'),
        actions: [
          if (widget.isEdit)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: '删除',
              onPressed: _busy ? null : _delete,
            ),
        ],
      ),
      body: loadingExisting
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              autovalidateMode: AutovalidateMode.onUserInteraction,
              child: ListView(
                padding: Spacing.pageMobile,
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                children: [
                  DropdownButtonFormField<AccountType>(
                    // ignore: deprecated_member_use
                    value: _type,
                    decoration: const InputDecoration(
                      labelText: '账户类型',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      for (final t in AccountType.values)
                        DropdownMenuItem(
                          value: t,
                          child: Text(accountTypeLabel(t)),
                        ),
                    ],
                    onChanged: (v) {
                      if (v == null) return;
                      setState(() => _type = v);
                    },
                  ),
                  const SizedBox(height: Spacing.s12),
                  TextFormField(
                    controller: _nameController,
                    focusNode: _nameFocus,
                    textInputAction: TextInputAction.next,
                    onFieldSubmitted: (_) => _institutionFocus.requestFocus(),
                    decoration: const InputDecoration(
                      labelText: '账户名称',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? '请输入账户名称' : null,
                  ),
                  const SizedBox(height: Spacing.s12),
                  CurrencyPicker(
                    value: _currency,
                    onChanged: (v) => setState(() => _currency = v),
                  ),
                  const SizedBox(height: Spacing.s12),
                  TextFormField(
                    controller: _institutionController,
                    focusNode: _institutionFocus,
                    textInputAction: TextInputAction.next,
                    onFieldSubmitted: (_) =>
                        _accountNumberFocus.requestFocus(),
                    decoration: const InputDecoration(
                      labelText: '机构',
                      helperText: '银行 / 券商 / 平台名称（可选）',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: Spacing.s12),
                  TextFormField(
                    controller: _accountNumberController,
                    focusNode: _accountNumberFocus,
                    textInputAction: TextInputAction.next,
                    onFieldSubmitted: (_) => _noteFocus.requestFocus(),
                    decoration: const InputDecoration(
                      labelText: '账号 / 末位号（可选）',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: Spacing.s12),
                  NoteField(
                    controller: _noteController,
                    focusNode: _noteFocus,
                  ),
                  if (widget.isEdit) ...[
                    const SizedBox(height: Spacing.s12),
                    SwitchListTile(
                      title: const Text('归档'),
                      subtitle: const Text('归档后不会出现在主列表中。'),
                      value: _archived,
                      onChanged: (v) => setState(() => _archived = v),
                    ),
                  ],
                  const SizedBox(height: Spacing.s24),
                  FilledButton(
                    onPressed: _busy ? null : _save,
                    child: Text(_busy ? '保存中…' : '保存'),
                  ),
                ],
              ),
            ),
    );
  }
}
