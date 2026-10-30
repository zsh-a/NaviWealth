import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../../core/forms/forms.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../data/bcr_knowledge_providers.dart';
import '../data/bcr_knowledge_sync_service.dart';
import '../domain/bcr_github_target.dart';
import '../domain/bcr_knowledge_connection.dart';
import '../domain/bcr_knowledge_source.dart';
import 'bcr_knowledge_sync_feedback.dart';

Future<void> showBcrKnowledgeSyncSheet(
  BuildContext context, {
  BcrKnowledgeConnection? connection,
  BcrKnowledgeSource? source,
}) => showGuardedFormSheet<void>(
  context: context,
  builder: (_, dirty) =>
      _SyncSheet(dirty: dirty, connection: connection, source: source),
);

class _SyncSheet extends ConsumerStatefulWidget {
  const _SyncSheet({required this.dirty, this.connection, this.source});
  final FormDirtyController dirty;
  final BcrKnowledgeConnection? connection;
  final BcrKnowledgeSource? source;
  @override
  ConsumerState<_SyncSheet> createState() => _SyncSheetState();
}

class _SyncSheetState extends ConsumerState<_SyncSheet>
    with FormSubmission<_SyncSheet> {
  late final _label = TextEditingController(
    text: widget.connection?.label ?? widget.source?.label,
  );
  late final _repository = TextEditingController(
    text: widget.connection == null
        ? ''
        : '${widget.connection!.target.owner}/${widget.connection!.target.repository}',
  );
  late final _branch = TextEditingController(
    text: widget.connection?.target.branch,
  );
  final _token = TextEditingController();
  CancelToken? _cancel;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Credentials never enter form recovery, preferences, sync or exports.
    widget.dirty.bindTextControllers([_label, _repository, _branch, _token]);
  }

  @override
  void dispose() {
    _cancel?.cancel();
    for (final controller in [_label, _repository, _branch, _token]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _connect() async {
    if (_busy) return;
    try {
      final parsed = BcrGithubTarget.parseRepository(_repository.text);
      if (_branch.text.trim().isNotEmpty) {
        BcrGithubTarget(
          owner: parsed.owner,
          repository: parsed.repository,
          branch: _branch.text.trim(),
        );
      }
      if (_label.text.trim().isEmpty ||
          _label.text.length > 200 ||
          (widget.connection == null && _token.text.trim().isEmpty)) {
        throw const FormatException();
      }
    } on FormatException {
      setState(
        () => _error = AppLocalizations.of(context).knowledgeBcrRequired,
      );
      return;
    }
    _error = null;
    _cancel = CancelToken();
    await submitForm<void>(
      dirty: widget.dirty,
      onBusyChanged: (busy) => setState(() => _busy = busy),
      commit: () async {
        final service = await ref.read(bcrKnowledgeSyncServiceProvider.future);
        var token = _token.text.trim();
        if (token.isEmpty && widget.connection != null) {
          token =
              await ref
                  .read(bcrGithubCredentialsProvider)
                  .read(service.owner, widget.connection!.credentialId) ??
              '';
        }
        if (token.isEmpty) throw BcrSyncLocalFailure.credentials;
        await service.connect(
          label: _label.text,
          repositoryAddress: _repository.text,
          branch: _branch.text.trim(),
          libraryUrl: widget.source?.libraryUrl,
          token: token,
          cancelToken: _cancel,
        );
        _token.clear();
      },
      leave: () => Navigator.of(context).pop(),
      failureMessage: (error) => bcrKnowledgeFailureMessage(context, error),
      successMessage: AppLocalizations.of(context).knowledgeBcrConnected,
      showFailureToast: false,
      tag: 'knowledge-bcr-connect',
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AppSheet(
      title: l10n.knowledgeBcrSyncTitle,
      actions: [
        if (_busy)
          AppIconButton(
            icon: FLucideIcons.square,
            tooltip: l10n.knowledgeBcrStop,
            onPress: () => _cancel?.cancel(),
          ),
      ],
      footer: AppSheetFooter(
        submitKey: const Key('bcr-connect-submit'),
        submitLabel: l10n.knowledgeBcrConnect,
        cancelLabel: l10n.commonCancel,
        busy: _busy,
        onSubmit: _connect,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l10n.knowledgeBcrHint, style: context.bodyCaptionStyle),
          const SizedBox(height: AppSpacing.s16),
          FTextField(
            key: const Key('bcr-source-name'),
            control: FTextFieldControl.managed(controller: _label),
            label: Text(l10n.knowledgeBcrName),
            enabled: !_busy,
          ),
          const SizedBox(height: AppSpacing.s12),
          FTextField(
            key: const Key('bcr-source-repository'),
            control: FTextFieldControl.managed(controller: _repository),
            label: Text(l10n.knowledgeBcrRepository),
            hint: l10n.knowledgeBcrRepositoryHint,
            enabled: !_busy && widget.connection == null,
          ),
          const SizedBox(height: AppSpacing.s12),
          FTextField(
            key: const Key('bcr-source-branch'),
            control: FTextFieldControl.managed(controller: _branch),
            label: Text(l10n.knowledgeBcrBranch),
            hint: l10n.knowledgeBcrBranchHint,
            enabled: !_busy && widget.connection == null,
          ),
          const SizedBox(height: AppSpacing.s12),
          FTextField(
            key: const Key('bcr-source-token'),
            control: FTextFieldControl.managed(controller: _token),
            label: Text(l10n.knowledgeBcrToken),
            hint: widget.connection == null ? null : l10n.knowledgeBcrTokenKeep,
            enabled: !_busy,
            obscureText: true,
          ),
          const SizedBox(height: AppSpacing.s6),
          Text(l10n.knowledgeBcrTokenHint, style: context.captionStyle),
          Text(
            kIsWeb ? l10n.knowledgeBcrTokenWeb : l10n.knowledgeBcrTokenNative,
            style: context.captionStyle,
          ),
          if (_error ?? submissionFailureMessage case final message?) ...[
            const SizedBox(height: AppSpacing.s12),
            AppStatusBanner(message: message, kind: AppStatusKind.error),
          ],
        ],
      ),
    );
  }
}
