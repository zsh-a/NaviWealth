part of '../ingest_review_page.dart';

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
          AppActionButton(
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
          AppActionButton(
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
          AppActionButton(
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
  const _PasteSheet({required this.dirty, required this.maxTextCodeUnits});

  final FormDirtyController dirty;
  final int maxTextCodeUnits;

  @override
  State<_PasteSheet> createState() => _PasteSheetState();
}

class _PasteSheetState extends State<_PasteSheet> {
  final _controller = TextEditingController();
  _PasteValidationError? _validationError;

  @override
  void initState() {
    super.initState();
    widget.dirty.bindTextControllers([_controller]);
    _controller.addListener(_clearValidationError);
  }

  @override
  void dispose() {
    _controller.removeListener(_clearValidationError);
    _controller.dispose();
    super.dispose();
  }

  void _clearValidationError() {
    final clearsError = switch (_validationError) {
      _PasteValidationError.required => _controller.text.trim().isNotEmpty,
      _PasteValidationError.tooLong =>
        _controller.text.length <= widget.maxTextCodeUnits,
      null => false,
    };
    if (clearsError) {
      setState(() => _validationError = null);
    }
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
          final text = _controller.text;
          if (text.length > widget.maxTextCodeUnits) {
            setState(() => _validationError = _PasteValidationError.tooLong);
            return;
          }
          if (text.trim().isEmpty) {
            setState(() => _validationError = _PasteValidationError.required);
            return;
          }
          widget.dirty.markPristine();
          Navigator.of(context).pop(text);
        },
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FTextField(
            control: FTextFieldControl.managed(controller: _controller),
            autofocus: true,
            maxLines: 10,
            minLines: 6,
            hint: l10n.ingestPasteHint,
          ),
          if (_validationError != null) ...[
            const SizedBox(height: AppSpacing.s6),
            Text(
              switch (_validationError!) {
                _PasteValidationError.required => l10n.ingestPasteRequired,
                _PasteValidationError.tooLong => l10n.ingestCaptureTextTooLong(
                  widget.maxTextCodeUnits,
                ),
              },
              style: context.bodyCaptionStyle.copyWith(
                color: context.theme.colors.destructive,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

enum _PasteValidationError { required, tooLong }
