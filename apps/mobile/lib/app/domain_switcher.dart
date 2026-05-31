/// On-demand OS switcher for the multi-domain shell
/// (`docs/lifeos-shell.md` §3, dogfood Option B follow-up).
///
/// Switcher entry on mobile is a **long-press on the bottom navigation
/// bar** — no per-page chrome, no always-visible chip. This file owns
/// the sheet that renders when long-press fires. The sheet is also the
/// fallback for any other entry that wants to surface the picker.
///
/// Desktop (≥ 600 px) keeps its always-visible left dock in
/// `app_dock_shell.dart` — vertical space isn't at a premium there.
library;

import 'package:flutter/material.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

import '../core/shell/domain_shell.dart';
import '../design_system/design_system.dart';
import '../l10n/gen/app_localizations.dart';

/// Show the domain-picker sheet. No-op if fewer than 2 domains are
/// registered (single-domain installs never need the picker).
Future<void> showDomainSwitcherSheet(
  BuildContext context,
  List<DomainShellSpec> specs,
) async {
  if (specs.length < 2) return;
  final activePath = GoRouter.of(
    context,
  ).routeInformationProvider.value.uri.path;
  final active = activeSpecForPath(specs, activePath);
  await showAppSheet<void>(
    context: context,
    title: AppLocalizations.of(context).shellSwitchDomainTitle,
    scrollable: false,
    builder: (sheetContext) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final spec in specs)
            _DomainRow(
              spec: spec,
              selected: spec.scope == active.scope,
              onTap: () {
                Navigator.of(sheetContext).pop();
                if (spec.scope != active.scope) {
                  final target = spec.tabs.isNotEmpty
                      ? spec.tabs.first.routePath
                      : '/';
                  GoRouter.of(context).go(target);
                }
              },
            ),
        ],
      );
    },
  );
}

class _DomainRow extends StatelessWidget {
  const _DomainRow({
    required this.spec,
    required this.selected,
    required this.onTap,
  });

  final DomainShellSpec spec;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final iconColor = selected ? colors.primary : colors.foreground;
    return FTappable(
      onPress: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s8,
          vertical: AppSpacing.s12,
        ),
        child: Row(
          children: [
            Icon(
              selected ? spec.selectedIcon : spec.icon,
              color: iconColor,
              size: 22,
            ),
            const SizedBox(width: AppSpacing.s12),
            Expanded(
              child: Text(
                spec.label,
                style: context.theme.typography.sm.copyWith(
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  color: iconColor,
                ),
              ),
            ),
            if (selected) Icon(Icons.check, size: 18, color: colors.primary),
          ],
        ),
      ),
    );
  }
}
