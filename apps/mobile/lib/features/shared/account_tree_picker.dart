import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

import '../../data/domain/account.dart';
import '../../data/domain/enums.dart';
import '../accounts/account_icon_catalog.dart';

/// FIR-128 §1.2 — drop-in replacement for the legacy flat
/// [AccountPicker] / [CategoryGridPicker] that surfaces the
/// [Account.parentId] tree as Beancount-style breadcrumb labels
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
/// them inside [DropdownMenuItem] is a deliberate next-step (it requires
/// a Material icon name → [IconData] resolver that is itself a small
/// project) — the leading affordance is a single bullet glyph today so
/// the picker's text content stays the source of truth.
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
    this.validator,
  });

  /// Full account list (typically `repo.watchActive()` or a derived
  /// provider). The picker filters / projects internally.
  final List<Account> accounts;

  final String? value;
  final ValueChanged<String?> onChanged;

  /// When non-null, only accounts whose [Account.category] equals this
  /// are shown.
  final AccountCategory? category;

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

  final FormFieldValidator<String>? validator;

  @override
  Widget build(BuildContext context) {
    final entries = _buildEntries();
    final effectiveValue = entries.any((e) => e.account.id == value)
        ? value
        : null;
    return DropdownButtonFormField<String>(
      isExpanded: true,
      initialValue: effectiveValue,
      decoration: InputDecoration(
        labelText: label ?? 'Account',
        helperText: helperText,
      ),
      items: entries.map((e) {
        final iconData = resolveAccountIcon(e.account.icon);
        final iconColor = _parseHexColor(e.account.color);
        final prefix = e.account.parentId == null ? '• ' : '› ';
        return DropdownMenuItem<String>(
          value: e.account.id,
          child: Padding(
            padding: EdgeInsets.only(left: e.depth * 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (iconData != null) ...[
                  Icon(
                    iconData,
                    size: 16,
                    color: iconColor ?? context.theme.colors.mutedForeground,
                  ),
                  const SizedBox(width: 4),
                  Text(e.path, overflow: TextOverflow.ellipsis),
                ] else
                  Text('$prefix${e.path}', overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        );
      }).toList(),
      onChanged: entries.isEmpty ? null : onChanged,
      validator: validator,
    );
  }

  List<_PickerEntry> _buildEntries() {
    final byId = <String, Account>{for (final a in accounts) a.id: a};
    final filtered = accounts.where((a) {
      if (a.sync.deletedAt != null) return false;
      if (!includeArchived && a.archived) return false;
      if (category != null && a.category != category) return false;
      if (!allowSystemAccounts && a.id.startsWith('system-account:')) {
        return false;
      }
      return true;
    });

    final entries = <_PickerEntry>[];
    for (final a in filtered) {
      final pathParts = <String>[];
      var depth = 0;
      var cursor = a;
      while (true) {
        pathParts.add(cursor.name);
        final parentId = cursor.parentId;
        if (parentId == null) break;
        final parent = byId[parentId];
        if (parent == null) break;
        // Defensive: stop after 64 hops if the parent chain is
        // pathological so render doesn't hang.
        if (depth > 64) break;
        cursor = parent;
        depth += 1;
      }
      entries.add(
        _PickerEntry(
          account: a,
          depth: depth,
          path: pathParts.reversed.join(' › '),
        ),
      );
    }
    entries.sort((a, b) => a.path.compareTo(b.path));
    return entries;
  }
}

class _PickerEntry {
  const _PickerEntry({
    required this.account,
    required this.depth,
    required this.path,
  });

  final Account account;
  final int depth;
  final String path;
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
