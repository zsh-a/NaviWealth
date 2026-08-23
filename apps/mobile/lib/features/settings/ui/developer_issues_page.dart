import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/ai/composition/ai_context.dart';
import '../../../core/ai/trace/providers.dart';
import '../../../core/auth/current_user.dart';
import '../../../core/config/app_version.dart';
import '../../../core/developer/developer_issue.dart';
import '../../../core/developer/providers.dart';
import '../../../core/shell/settings_ui/settings_page_frame.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';

class DeveloperIssuesPage extends ConsumerStatefulWidget {
  const DeveloperIssuesPage({super.key});

  @override
  ConsumerState<DeveloperIssuesPage> createState() =>
      _DeveloperIssuesPageState();
}

class _DeveloperIssuesPageState extends ConsumerState<DeveloperIssuesPage> {
  final TextEditingController _descriptionController = TextEditingController();
  bool _saving = false;
  String? _fieldError;

  @override
  void initState() {
    super.initState();
    _descriptionController.addListener(_onDescriptionChanged);
  }

  @override
  void dispose() {
    _descriptionController
      ..removeListener(_onDescriptionChanged)
      ..dispose();
    super.dispose();
  }

  void _onDescriptionChanged() {
    if (_fieldError != null || mounted) setState(() => _fieldError = null);
  }

  Future<void> _capture() async {
    final description = _descriptionController.text.trim();
    if (description.isEmpty) {
      setState(
        () => _fieldError = AppLocalizations.of(
          context,
        ).developerIssuesDescriptionRequired,
      );
      return;
    }
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final store = await ref.read(developerIssueStoreProvider.future);
      final ownerUserId = await ref.read(currentUserIdProvider)();
      final version = await ref.read(appVersionProvider.future);
      final traces = await ref.read(aiTraceStoreProvider).recent(limit: 10);
      final ambient = ref.read(aiContextProvider);
      final capturedContext =
          ref.read(developerIssueContextProvider) ??
          DeveloperIssueContext(
            route: ambient.path,
            domain: ambient.domain?.name,
          );
      await DeveloperIssueCaptureService(store: store).capture(
        ownerUserId: ownerUserId,
        description: description,
        context: capturedContext,
        version: version,
        recentTraces: traces,
      );
      _descriptionController.clear();
      ref.invalidate(developerIssuesProvider);
      if (!mounted) return;
      AppMessenger.show(
        context,
        ToastKind.success,
        AppLocalizations.of(context).developerIssuesSavedToast,
      );
    } on Object {
      if (!mounted) return;
      AppMessenger.show(
        context,
        ToastKind.error,
        AppLocalizations.of(context).developerIssuesSaveFailedToast,
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _export(DeveloperIssue issue) async {
    try {
      await SharePlus.instance.share(
        ShareParams(
          text: issue.toExportText(),
          subject: 'NaviWealth product issue ${issue.id}',
        ),
      );
      final store = await ref.read(developerIssueStoreProvider.future);
      await store.markExported(
        ownerUserId: issue.ownerUserId,
        issueId: issue.id,
        at: DateTime.now(),
      );
      ref.invalidate(developerIssuesProvider);
    } on Object {
      if (!mounted) return;
      AppMessenger.show(
        context,
        ToastKind.error,
        AppLocalizations.of(context).developerIssuesExportFailedToast,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final ambient = ref.watch(aiContextProvider);
    final capturedContext =
        ref.watch(developerIssueContextProvider) ??
        DeveloperIssueContext(
          route: ambient.path,
          domain: ambient.domain?.name,
        );
    final issues = ref.watch(developerIssuesProvider);
    return AppPageScaffold(
      title: l10n.developerIssuesTitle,
      childPad: false,
      child: SettingsPageFrame(
        children: <Widget>[
          SettingsHintText(l10n.developerIssuesSubtitle),
          const SizedBox(height: AppSpacing.s12),
          SoftCard.flat(
            padding: const EdgeInsets.all(AppSpacing.s16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                FTextFormField(
                  control: FTextFieldControl.managed(
                    controller: _descriptionController,
                  ),
                  minLines: 3,
                  maxLines: 6,
                  maxLength: 2000,
                  label: Text(l10n.developerIssuesDescriptionLabel),
                  hint: l10n.developerIssuesDescriptionHint,
                  description: Text(l10n.developerIssuesDescriptionHelp),
                  textInputAction: TextInputAction.newline,
                ),
                if (_fieldError != null) ...<Widget>[
                  const SizedBox(height: AppSpacing.s6),
                  Text(
                    _fieldError!,
                    style: context.captionStyle.copyWith(
                      color: context.theme.colors.destructive,
                    ),
                  ),
                ],
                const SizedBox(height: AppSpacing.s16),
                Text(
                  l10n.developerIssuesContextSection,
                  style: context.captionLabelStyle,
                ),
                const SizedBox(height: AppSpacing.s8),
                AppMetadataStrip(
                  children: <Widget>[
                    AppMetadataItem(
                      label: l10n.developerIssuesRouteLabel,
                      value: capturedContext.route,
                    ),
                    AppMetadataItem(
                      label: l10n.developerIssuesDomainLabel,
                      value:
                          capturedContext.domain ??
                          l10n.developerIssuesShellDomain,
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.s16),
                FButton(
                  onPress: _saving || _descriptionController.text.trim().isEmpty
                      ? null
                      : _capture,
                  child: Text(
                    _saving
                        ? l10n.developerIssuesCapturingAction
                        : l10n.developerIssuesCaptureAction,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.s24),
          Text(
            l10n.developerIssuesHistorySection,
            style: context.titleLabelStyle,
          ),
          const SizedBox(height: AppSpacing.s10),
          issues.whenOrLoading(
            context: context,
            loading: () => const SkeletonCard(
              padding: EdgeInsets.all(AppSpacing.s16),
              child: SkeletonBox(width: double.infinity, height: 96),
            ),
            error: (error, stackTrace) => kDefaultError(
              context,
              error,
              stackTrace,
              onRetry: () => ref.invalidate(developerIssuesProvider),
            ),
            data: (items) => items.isEmpty
                ? SoftCard.flat(
                    padding: const EdgeInsets.all(AppSpacing.s16),
                    child: Text(
                      l10n.developerIssuesEmpty,
                      style: context.bodyCaptionStyle,
                    ),
                  )
                : Column(
                    children: <Widget>[
                      for (var index = 0; index < items.length; index++) ...[
                        _DeveloperIssueTile(
                          issue: items[index],
                          onExport: () => _export(items[index]),
                        ),
                        if (index != items.length - 1)
                          const SizedBox(height: AppSpacing.s8),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _DeveloperIssueTile extends StatelessWidget {
  const _DeveloperIssueTile({required this.issue, required this.onExport});

  final DeveloperIssue issue;
  final VoidCallback onExport;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).toLanguageTag();
    final timestamp = DateFormat.yMd(
      locale,
    ).add_Hm().format(issue.createdAt.toLocal());
    final tags = <String>[
      issue.exportedAt == null
          ? l10n.developerIssuesLocalLabel
          : l10n.developerIssuesExportedLabel,
      if (issue.traceId != null) l10n.developerIssuesTraceAttached,
      if (issue.toolErrors.isNotEmpty)
        l10n.developerIssuesToolErrorsAttached(issue.toolErrors.length),
    ];
    return SoftCard.flat(
      padding: const EdgeInsets.all(AppSpacing.s16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(issue.description, style: context.theme.typography.body.sm),
          const SizedBox(height: AppSpacing.s10),
          AppMetadataStrip(
            spacing: AppSpacing.s12,
            children: <Widget>[
              AppMetadataItem(
                label: l10n.developerIssuesRouteLabel,
                value: issue.route,
                maxWidth: 220,
              ),
              AppMetadataItem(label: timestamp, value: issue.commitSha),
            ],
          ),
          const SizedBox(height: AppSpacing.s10),
          AppMetadataTags(
            label: l10n.developerIssuesContextSection,
            values: tags,
          ),
          const SizedBox(height: AppSpacing.s12),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: FButton(
              variant: FButtonVariant.outline,
              onPress: onExport,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const Icon(FLucideIcons.share2, size: AppIconSizes.xs),
                  const SizedBox(width: AppSpacing.s6),
                  Text(l10n.developerIssuesExportAction),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
