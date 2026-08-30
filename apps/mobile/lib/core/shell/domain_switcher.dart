/// On-demand OS switcher for the multi-domain shell
/// (`docs/architecture/lifeos-shell.md` §3, dogfood Option B follow-up).
///
/// Mobile exposes a compact current-domain chip above the bottom navigation;
/// long-press on the bottom navigation remains a fallback. This file owns
/// the sheet shared by both entries and any other surface that wants to
/// expose the picker.
///
/// Full desktop (≥ [Breakpoints.shellDesktop]) keeps its always-visible left
/// dock in `app_dock_shell.dart`. Tablet widths keep the switcher in the page
/// header so the domain dock and tab rail never stack side by side.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

import '../../design_system/design_system.dart';
import '../../l10n/gen/app_localizations.dart';
import 'domain_shell.dart';

/// App-composed route for the cross-domain home surface.
///
/// Core does not own a LifeOS route. The app composition root overrides this
/// with its registered home path; isolated domain-shell tests can leave it
/// null and still switch directly between domain roots.
final domainSwitcherHomePathProvider = Provider<String?>((ref) => null);

/// Show the workspace picker. It remains useful with one registered domain
/// when [homePath] contributes the cross-domain Life surface.
///
/// Offers the app-composed home surface first when [homePath] is present.
Future<void> showDomainSwitcherSheet(
  BuildContext context,
  List<DomainShellSpec> specs,
  String? homePath,
) async {
  if (specs.length < 2 && homePath == null) return;
  final activePath = GoRouter.of(context)
      .routeInformationProvider
      .value
      .uri
      .path;
  final active = activeSpecForPath(specs, activePath);
  final onHome =
      homePath != null &&
      (activePath == homePath || activePath.startsWith('$homePath/'));
  final l10n = AppLocalizations.of(context);
  final router = GoRouter.of(context);
  await showAppSheet<void>(
    context: context,
    title: l10n.shellSwitchDomainTitle,
    scrollable: false,
    builder: (sheetContext) {
      void selectTarget(String target, {required bool selected}) {
        if (selected) {
          Navigator.of(sheetContext).pop();
          return;
        }
        AppInteraction.signal(AppInteractionIntent.navigate);
        unawaited(closeSheetThen(sheetContext, () => router.go(target)));
      }

      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (homePath != null)
            _LifeRow(
              selected: onHome,
              onTap: () => selectTarget(homePath, selected: onHome),
            ),
          for (final spec in specs)
            _DomainRow(
              spec: spec,
              selected: !onHome && spec.scope == active.scope,
              onTap: () {
                final selected = !onHome && spec.scope == active.scope;
                if (spec.tabs.isEmpty && homePath == null) return;
                final target = spec.tabs.isNotEmpty
                    ? spec.tabs.first.routePath
                    : homePath!;
                selectTarget(target, selected: selected);
              },
            ),
        ],
      );
    },
  );
}

class _LifeRow extends StatelessWidget {
  const _LifeRow({required this.selected, required this.onTap});

  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final iconColor = selected ? colors.primary : colors.foreground;
    return AppTappable(
      onPress: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s8,
          vertical: AppSpacing.s12,
        ),
        child: Row(
          children: [
            Icon(FLucideIcons.house, color: iconColor, size: AppIconSizes.mlg),
            const SizedBox(width: AppSpacing.s12),
            Expanded(
              child: Text(
                AppLocalizations.of(context).lifeNavLabel,
                style:
                    (selected
                            ? context.labelStyle
                            : context.theme.typography.body.sm.copyWith(
                                fontWeight: FontWeight.w400,
                              ))
                        .copyWith(color: iconColor),
              ),
            ),
            if (selected)
              Icon(
                FLucideIcons.check,
                color: colors.primary,
                size: AppIconSizes.md,
              ),
          ],
        ),
      ),
    );
  }
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
    return AppTappable(
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
              size: AppIconSizes.mlg,
            ),
            const SizedBox(width: AppSpacing.s12),
            Expanded(
              child: Text(
                spec.label,
                style:
                    (selected
                            ? context.labelStyle
                            : context.theme.typography.body.sm.copyWith(
                                fontWeight: FontWeight.w400,
                              ))
                        .copyWith(color: iconColor),
              ),
            ),
            if (selected)
              Icon(
                FLucideIcons.check,
                size: AppIconSizes.h18,
                color: colors.primary,
              ),
          ],
        ),
      ),
    );
  }
}
