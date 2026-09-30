import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../shell/settings_route_paths.dart';
import '../action_dispatcher.dart';

/// Shared source lifecycle: load, reuse/open, or explicitly replace a dropped action.
class SourceActionControl extends ConsumerStatefulWidget {
  const SourceActionControl({
    super.key,
    required this.source,
    required this.buildDraft,
    required this.createLabel,
    required this.openLabel,
    required this.confirmTitle,
    required this.confirmBody,
    required this.successMessage,
    this.createKey,
    this.openKey,
    this.onCreated,
    this.onBusyChanged,
    this.beforeOpen,
    this.openAfterCreate = true,
    this.checkAvailability = false,
  });

  final LifeActionSource source;
  final LifeActionDraft Function(String? replacesActionId) buildDraft;
  final String createLabel;
  final String openLabel;
  final String confirmTitle;
  final String confirmBody;
  final String successMessage;
  final Key? createKey;
  final Key? openKey;
  final Future<void> Function(String id)? onCreated;
  final ValueChanged<bool>? onBusyChanged;
  final VoidCallback? beforeOpen;
  final bool openAfterCreate;
  final bool checkAvailability;

  @override
  ConsumerState<SourceActionControl> createState() =>
      _SourceActionControlState();
}

class _SourceActionControlState extends ConsumerState<SourceActionControl> {
  bool _busy = false;
  bool _confirming = false;
  String? _failure;
  LifeActionDraft? _pendingDraft;
  String? _createdId;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (widget.checkAvailability) {
      final availability = ref.watch(lifeOpenActionCountProvider);
      if (availability.isLoading) return kDefaultLoading;
      if (availability.hasError) {
        return AppEmptyState.error(
          title: l10n.commonLoadFailed,
          retryLabel: l10n.commonRetry,
          onRetry: () => ref.invalidate(lifeOpenActionCountProvider),
        );
      }
      if (availability.asData?.value == null) {
        return AppQuietButton(
          label: l10n.lifeSignalEnableExecution,
          onPress: () =>
              context.push('${SettingsRoutes.domains}?resume=execution'),
        );
      }
    }
    final linked = ref.watch(lifeLinkedActionProvider(widget.source));
    final content = linked.when(
      loading: () => kDefaultLoading,
      error: (_, _) => AppEmptyState.error(
        title: l10n.commonLoadFailed,
        retryLabel: l10n.commonRetry,
        onRetry: () => ref.invalidate(lifeLinkedActionProvider(widget.source)),
      ),
      data: (action) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (action != null) ...[
            AppBadge(label: sourceActionStateLabel(l10n, action.state)),
            const SizedBox(height: AppSpacing.s8),
            Text(l10n.sourceActionLinked, style: context.bodyCaptionStyle),
            const SizedBox(height: AppSpacing.s10),
            AppQuietButton(
              key: widget.openKey,
              label: widget.openLabel,
              onPress:
                  _busy ||
                      _confirming ||
                      ref.watch(lifeActionRouteBuilderProvider) == null
                  ? null
                  : () => _open(action.id),
            ),
          ],
          if (action == null || action.state == LifeActionState.dropped) ...[
            const SizedBox(height: AppSpacing.s10),
            AppBusyButton(
              key: widget.createKey,
              label: action == null
                  ? widget.createLabel
                  : l10n.sourceActionReplace,
              busyLabel: l10n.commonSaving,
              busy: _busy,
              onPress: _confirming ? null : () => _create(action),
            ),
          ],
        ],
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        content,
        if (_failure != null) ...[
          const SizedBox(height: AppSpacing.s10),
          AppStatusBanner(kind: AppStatusKind.error, message: _failure!),
          const SizedBox(height: AppSpacing.s8),
          AppBusyButton(
            label: l10n.commonRetry,
            busy: _busy,
            busyLabel: l10n.commonSaving,
            onPress: _confirming || _pendingDraft == null
                ? null
                : () => _create(null, retry: true),
          ),
        ],
      ],
    );
  }

  Future<void> _create(LifeLinkedAction? existing, {bool retry = false}) async {
    if (_busy || _confirming) return;
    setState(() {
      _confirming = true;
      _failure = null;
    });
    widget.onBusyChanged?.call(true);
    final l10n = AppLocalizations.of(context);
    final replacing = existing?.state == LifeActionState.dropped;
    try {
      if (!retry) {
        final confirmed = await showConfirmDialog(
          context: context,
          title: Text(
            replacing
                ? l10n.sourceActionReplaceConfirmTitle
                : widget.confirmTitle,
          ),
          body: Text(
            replacing
                ? l10n.sourceActionReplaceConfirmBody
                : widget.confirmBody,
          ),
          confirmLabel: replacing
              ? l10n.sourceActionReplace
              : widget.createLabel,
          cancelLabel: l10n.commonCancel,
        );
        if (!mounted || confirmed != true) return;
        _pendingDraft = widget.buildDraft(replacing ? existing!.id : null);
        _createdId = null;
      }
      setState(() {
        _confirming = false;
        _busy = true;
      });
      final id =
          _createdId ??
          await ref.read(lifeActionDispatcherProvider)(_pendingDraft!);
      if (id == null) {
        throw StateError('Execution action dispatch is unavailable.');
      }
      _createdId = id;
      // Source bookkeeping may fail independently. Retrying reuses the durable action.
      await widget.onCreated?.call(id);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _pendingDraft = null;
        _createdId = null;
      });
      widget.onBusyChanged?.call(false);
      // Publish the unlocked PopScope before closing a guarded source sheet.
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
      AppMessenger.show(context, ToastKind.success, widget.successMessage);
      if (widget.openAfterCreate) _open(id);
      ref.invalidate(lifeLinkedActionProvider(widget.source));
    } catch (error) {
      if (!mounted) return;
      setState(
        () => _failure = userSafeErrorMessage(
          context,
          error,
          operation: 'create source action',
        ),
      );
      AppMessenger.show(context, ToastKind.error, _failure!);
    } finally {
      widget.onBusyChanged?.call(false);
      if (mounted) {
        setState(() {
          _busy = false;
          _confirming = false;
        });
      }
    }
  }

  void _open(String id) {
    final path = ref.read(lifeActionRouteBuilderProvider)?.call(id);
    if (path == null) return;
    final router = GoRouter.of(context);
    widget.beforeOpen?.call();
    router.push<void>(path);
  }
}

String sourceActionStateLabel(AppLocalizations l10n, LifeActionState state) =>
    switch (state) {
      LifeActionState.todo => l10n.executionStatusTodo,
      LifeActionState.doing => l10n.executionStatusDoing,
      LifeActionState.blocked => l10n.executionStatusBlocked,
      LifeActionState.done => l10n.executionStatusDone,
      LifeActionState.dropped => l10n.executionStatusDropped,
    };
