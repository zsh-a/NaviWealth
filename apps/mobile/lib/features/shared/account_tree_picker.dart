import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import 'package:naviwealth/features/finance/data/domain/account.dart';
import 'package:naviwealth/features/finance/data/domain/enums.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';
import '../accounts/account_icon_catalog.dart';
import 'account_l10n.dart';

/// FIR-128 §1.2 — drop-in replacement for the legacy flat
/// [AccountPicker] that surfaces the [Account.parentId] tree as
/// Beancount-style breadcrumb labels
/// ("Expenses › Trading › Fee"). One picker covers every category
/// (asset / liability / income / expense / equity); the [category]
/// prop narrows the list to a single bucket when forms only want to
/// pick from one.
///
/// The widget is intentionally stateless and takes the *full* account
/// list — the caller resolves it via [AccountRepository.watchActive]
/// (or a Riverpod provider built on top) and pipes the snapshot in. We
/// recompute paths on every build because the inputs are bounded
/// (typically tens, sometimes hundreds, of rows on the largest user
/// trees we anticipate); the cost is dwarfed by the dropdown render
/// itself.
///
/// FIR-133 children carry [Account.icon] / [Account.color]; rendering
/// them inside the picker uses [FSelectItem]'s prefix slot so the leading
/// glyph + breadcrumb path stay legible.
class AccountTreePicker extends StatelessWidget {
  const AccountTreePicker({
    super.key,
    required this.accounts,
    required this.value,
    required this.onChanged,
    this.category,
    this.label,
    this.helperText,
    this.allowSystemAccounts = true,
    this.includeArchived = false,
    this.leafOnly = false,
    this.validator,
  });

  /// Full account list (typically `repo.watchActive()` or a derived
  /// provider). The picker filters / projects internally.
  final List<Account> accounts;

  final String? value;
  final ValueChanged<String?> onChanged;

  /// When non-null, only accounts whose [Account.category] equals this
  /// are shown.
  final AccountSide? category;

  /// Form-field label override. When null, the picker renders a
  /// generic "Account" placeholder.
  final String? label;

  /// Optional helper text rendered below the picker (e.g. "Pick the
  /// expense category for this transaction").
  final String? helperText;

  /// FIR-126 carries a few `system-account:*` rows that are always
  /// useful for the [JournalEntryBuilders] layer (Capital Gains,
  /// Opening Balance, etc.). Set to `false` on user-facing forms that
  /// shouldn't surface the abstract counter-accounts.
  final bool allowSystemAccounts;

  /// Archived rows (`Account.archived == true`) are hidden by default
  /// because the user can't write to them; toggle on for "edit any
  /// account" flows.
  final bool includeArchived;

  /// When true, rows that have children are treated as grouping nodes and are
  /// not selectable.
  final bool leafOnly;

  final FormFieldValidator<String>? validator;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final entries = _buildEntries(l10n);
    final effectiveValue = entries.any((e) => e.account.id == value)
        ? value
        : null;
    final pathById = <String, String>{
      for (final e in entries) e.account.id: e.path,
    };
    return FSelect<String>.rich(
      format: (id) => pathById[id] ?? '',
      control: FSelectControl<String>.lifted(
        value: effectiveValue,
        onChange: onChanged,
      ),
      label: Text(label ?? 'Account'),
      description: helperText == null ? null : Text(helperText!),
      enabled: entries.isNotEmpty,
      validator: validator ?? FFormFieldProperties.defaultValidator,
      children: [
        for (final e in entries)
          FSelectItem<String>(
            value: e.account.id,
            title: Text(e.path, maxLines: 2, overflow: TextOverflow.fade),
            prefix: _LeadingGlyph(account: e.account),
          ),
      ],
    );
  }

  List<_PickerEntry> _buildEntries(AppLocalizations l10n) {
    final byId = <String, Account>{for (final a in accounts) a.id: a};
    final filtered = accounts
        .where((a) {
          if (a.sync.deletedAt != null) return false;
          if (!includeArchived && a.archived) return false;
          if (category != null && a.category != category) return false;
          if (!allowSystemAccounts && a.id.startsWith('system-account:')) {
            return false;
          }
          return true;
        })
        .toList(growable: false);
    final parentIds = {
      for (final account in filtered)
        if (account.parentId != null) account.parentId!,
    };

    final entriesByPath = <String, _PickerEntry>{};
    for (final a in filtered) {
      if (leafOnly && parentIds.contains(a.id)) continue;
      final entry = _PickerEntry(
        account: a,
        path: localizedAccountPath(l10n, a, byId),
      );
      final key = entry.path.trim().toLowerCase();
      final existing = entriesByPath[key];
      if (existing == null || _prefer(entry, existing)) {
        entriesByPath[key] = entry;
      }
    }
    final entries = entriesByPath.values.toList();
    entries.sort((a, b) => a.path.compareTo(b.path));
    return entries;
  }

  bool _prefer(_PickerEntry next, _PickerEntry existing) {
    if (next.account.id == value) return true;
    if (existing.account.id == value) return false;
    final nextSystem = _isSystemAccount(next.account);
    final existingSystem = _isSystemAccount(existing.account);
    if (nextSystem != existingSystem) return !nextSystem;
    return next.account.id.compareTo(existing.account.id) < 0;
  }

  bool _isSystemAccount(Account account) {
    return systemAccountPath(account) != null;
  }
}

class _PickerEntry {
  const _PickerEntry({required this.account, required this.path});

  final Account account;
  final String path;
}

class _LeadingGlyph extends StatelessWidget {
  const _LeadingGlyph({required this.account});

  final Account account;

  @override
  Widget build(BuildContext context) {
    final iconData = resolveAccountIcon(account.icon);
    final iconColor = _parseHexColor(account.color);
    if (iconData != null) {
      return Icon(
        iconData,
        size: 16,
        color: iconColor ?? context.theme.colors.mutedForeground,
      );
    }
    return Text(
      account.parentId == null ? '•' : '›',
      style: TextStyle(color: context.theme.colors.mutedForeground),
    );
  }
}

/// `#RRGGBB` (with or without leading `#`) → [Color]; returns `null`
/// for any malformed input so callers can fall back to the theme's
/// default tint without a try / catch.
Color? _parseHexColor(String? value) {
  if (value == null || value.isEmpty) return null;
  var hex = value.replaceFirst('#', '');
  if (hex.length == 6) hex = 'FF$hex';
  if (hex.length != 8) return null;
  final parsed = int.tryParse(hex, radix: 16);
  if (parsed == null) return null;
  return Color(parsed);
}
