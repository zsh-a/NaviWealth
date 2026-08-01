part of '../ingest_review_page.dart';

class _CapturePopoverAction extends StatefulWidget {
  const _CapturePopoverAction({
    required this.enabled,
    required this.onCamera,
    required this.onFile,
    required this.onPaste,
  });

  final bool enabled;
  final VoidCallback onCamera;
  final VoidCallback onFile;
  final VoidCallback onPaste;

  @override
  State<_CapturePopoverAction> createState() => _CapturePopoverActionState();
}

class _CapturePopoverActionState extends State<_CapturePopoverAction>
    with SingleTickerProviderStateMixin {
  late final FPopoverController _controller;
  final FocusNode _triggerFocus = FocusNode(debugLabel: 'ingest capture menu');

  @override
  void initState() {
    super.initState();
    _controller = FPopoverController(vsync: this);
  }

  @override
  void dispose() {
    _controller.dispose();
    _triggerFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return FPopover(
      control: FPopoverControl.managed(controller: _controller),
      popoverAnchor: AlignmentDirectional.topEnd,
      childAnchor: AlignmentDirectional.bottomEnd,
      constraints: const FPortalConstraints(
        minWidth: 200,
        maxWidth: 280,
        maxHeight: 360,
      ),
      popoverBuilder: (context, _) => SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.s4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _CaptureOption(
              icon: FLucideIcons.camera,
              label: l10n.ingestCameraAction,
              onPress: () => _select(widget.onCamera),
            ),
            _CaptureOption(
              icon: FLucideIcons.paperclip,
              label: l10n.ingestImportFileAction,
              onPress: () => _select(widget.onFile),
            ),
            _CaptureOption(
              icon: FLucideIcons.clipboard,
              label: l10n.ingestPasteAction,
              onPress: () => _select(widget.onPaste),
            ),
          ],
        ),
      ),
      child: AppHeaderAction(
        semanticsLabel: l10n.ingestCaptureMenuAction,
        icon: const Icon(FLucideIcons.plus),
        focusNode: _triggerFocus,
        onPress: widget.enabled ? _controller.toggle : null,
      ),
    );
  }

  Future<void> _select(VoidCallback action) async {
    await _controller.hide();
    if (!mounted) return;
    _triggerFocus.requestFocus();
    action();
  }
}

class _CaptureOption extends StatelessWidget {
  const _CaptureOption({
    required this.icon,
    required this.label,
    required this.onPress,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPress;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      button: true,
      label: label,
      onTap: onPress,
      excludeSemantics: true,
      child: AppTappable(
        onPress: onPress,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.s12,
            vertical: AppSpacing.s10,
          ),
          child: Row(
            children: [
              Icon(icon, size: AppIconSizes.sm),
              const SizedBox(width: AppSpacing.s10),
              Expanded(child: Text(label)),
            ],
          ),
        ),
      ),
    );
  }
}
