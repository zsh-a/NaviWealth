part of 'ingest_review_page.dart';

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.onPaste,
    required this.onImport,
    required this.onCamera,
  });

  final VoidCallback? onPaste;
  final VoidCallback? onImport;
  final VoidCallback? onCamera;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AppEmptyState(
      icon: FLucideIcons.inbox,
      title: l10n.ingestEmptyTitle,
      message: l10n.ingestEmptyBody,
      iconSize: AppIconSizes.xxl,
      action: Wrap(
        alignment: WrapAlignment.center,
        spacing: AppSpacing.s8,
        runSpacing: AppSpacing.s8,
        children: [
          FButton(
            variant: FButtonVariant.outline,
            onPress: onCamera,
            prefix: const Icon(FLucideIcons.camera),
            child: Flexible(
              child: Text(
                l10n.ingestCameraAction,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          FButton(
            variant: FButtonVariant.outline,
            onPress: onImport,
            prefix: const Icon(FLucideIcons.paperclip),
            child: Flexible(
              child: Text(
                l10n.ingestImportFileAction,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          FButton(
            variant: FButtonVariant.outline,
            onPress: onPaste,
            prefix: const Icon(FLucideIcons.clipboard),
            child: Flexible(
              child: Text(
                l10n.ingestPasteAction,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PasteSheet extends StatefulWidget {
  const _PasteSheet({required this.dirty});

  final FormDirtyController dirty;

  @override
  State<_PasteSheet> createState() => _PasteSheetState();
}

class _PasteSheetState extends State<_PasteSheet> {
  final _controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    widget.dirty.bindTextControllers([_controller]);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AppSheet(
      title: l10n.ingestPasteTitle,
      footer: AppSheetFooter(
        submitLabel: l10n.ingestParseAction,
        cancelLabel: l10n.commonCancel,
        onSubmit: () {
          widget.dirty.markPristine();
          Navigator.of(context).pop(_controller.text);
        },
      ),
      child: FTextField(
        control: FTextFieldControl.managed(controller: _controller),
        autofocus: true,
        maxLines: 10,
        minLines: 6,
        hint: l10n.ingestPasteHint,
      ),
    );
  }
}
