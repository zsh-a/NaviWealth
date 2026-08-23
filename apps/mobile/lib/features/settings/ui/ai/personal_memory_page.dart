import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/ai/contracts/context_evidence.dart';
import '../../../../core/auth/current_user.dart';
import '../../../../core/lifeos/personal_profile/personal_profile_fact.dart';
import '../../../../core/lifeos/personal_profile/providers.dart';
import '../../../../core/shell/settings_ui/inline_setting_row.dart';
import '../../../../core/shell/settings_ui/settings_page_frame.dart';
import '../../../../design_system/design_system.dart';
import '../../../../l10n/gen/app_localizations.dart';

const Uuid _profileUuid = Uuid();

class PersonalMemoryPage extends ConsumerStatefulWidget {
  const PersonalMemoryPage({super.key});

  @override
  ConsumerState<PersonalMemoryPage> createState() => _PersonalMemoryPageState();
}

class _PersonalMemoryPageState extends ConsumerState<PersonalMemoryPage> {
  late Future<List<PersonalProfileFact>> _facts = _load();

  Future<List<PersonalProfileFact>> _load() async {
    final ownerUserId = await ref.read(currentUserIdProvider)();
    final store = await ref.read(personalProfileStoreProvider.future);
    return store.listCurrent(
      ownerUserId: ownerUserId,
      at: DateTime.now().toUtc(),
    );
  }

  void _reload() {
    setState(() => _facts = _load());
  }

  Future<void> _openEditor([PersonalProfileFact? fact]) async {
    final changed = await showAppFormSheet<bool>(
      context: context,
      builder: (_) => _PersonalProfileFactSheet(initial: fact),
    );
    if (changed == true && mounted) _reload();
  }

  Future<void> _forget(PersonalProfileFact fact) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showConfirmDialog(
      context: context,
      title: Text(l10n.personalMemoryDeleteTitle),
      body: Text(l10n.personalMemoryDeleteBody),
      confirmLabel: l10n.commonDelete,
      cancelLabel: l10n.commonCancel,
      destructive: true,
      icon: FLucideIcons.trash2,
    );
    if (confirmed != true || !mounted) return;
    final store = await ref.read(personalProfileStoreProvider.future);
    await store.forget(ownerUserId: fact.ownerUserId, id: fact.id);
    if (mounted) _reload();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final activeDomainScopes = ref.watch(
      activePersonalProfileDomainScopesProvider,
    );
    return AppPageScaffold(
      title: l10n.personalMemoryTitle,
      childPad: false,
      child: FutureBuilder<List<PersonalProfileFact>>(
        future: _facts,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: FCircularProgress());
          }
          if (snapshot.hasError) {
            return SettingsPageFrame(
              children: <Widget>[
                AppStatusBanner(
                  kind: AppStatusKind.error,
                  message: l10n.personalMemoryLoadFailed('${snapshot.error}'),
                ),
              ],
            );
          }
          final facts = snapshot.data ?? const <PersonalProfileFact>[];
          return SettingsPageFrame(
            children: <Widget>[
              AppSection.group(
                title: l10n.personalMemorySection,
                children: facts.isEmpty
                    ? <Widget>[
                        Padding(
                          padding: const EdgeInsets.all(AppSpacing.s16),
                          child: Text(
                            l10n.personalMemoryEmpty,
                            style: context.bodyCaptionStyle,
                          ),
                        ),
                      ]
                    : <Widget>[
                        for (var index = 0; index < facts.length; index++) ...[
                          _ProfileFactRow(
                            fact: facts[index],
                            domainActive:
                                facts[index].domainScope == null ||
                                activeDomainScopes.contains(
                                  facts[index].domainScope,
                                ),
                            onEdit: () => _openEditor(facts[index]),
                            onForget: () => _forget(facts[index]),
                          ),
                          if (index != facts.length - 1)
                            const AppGradientDivider(),
                        ],
                      ],
              ),
              const SizedBox(height: AppSpacing.s16),
              FButton(
                onPress: _openEditor,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    const Icon(FLucideIcons.plus, size: AppIconSizes.sm),
                    const SizedBox(width: AppSpacing.s8),
                    Text(l10n.personalMemoryAdd),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ProfileFactRow extends StatelessWidget {
  const _ProfileFactRow({
    required this.fact,
    required this.domainActive,
    required this.onEdit,
    required this.onForget,
  });

  final PersonalProfileFact fact;
  final bool domainActive;
  final VoidCallback onEdit;
  final VoidCallback onForget;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return InlineLinkRow(
      icon: _kindIcon(fact.kind),
      label: fact.summary,
      subtitle: <String>[
        '${_kindLabel(l10n, fact.kind)} · ${fact.key}',
        if (fact.domainScope != null) fact.domainScope!,
        if (!domainActive) l10n.personalMemoryInactiveDomain,
      ].join(' · '),
      trailing: Icon(
        FLucideIcons.trash2,
        size: AppIconSizes.sm,
        color: context.theme.colors.destructive,
      ),
      onTrailingTap: onForget,
      onTap: onEdit,
    );
  }
}

class _PersonalProfileFactSheet extends ConsumerStatefulWidget {
  const _PersonalProfileFactSheet({required this.initial});

  final PersonalProfileFact? initial;

  @override
  ConsumerState<_PersonalProfileFactSheet> createState() =>
      _PersonalProfileFactSheetState();
}

class _PersonalProfileFactSheetState
    extends ConsumerState<_PersonalProfileFactSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _key;
  late final TextEditingController _value;
  late final TextEditingController _summary;
  late final TextEditingController _domain;
  late PersonalProfileFactKind _kind;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _key = TextEditingController(text: initial?.key ?? '');
    _value = TextEditingController(text: _displayValue(initial?.value));
    _summary = TextEditingController(text: initial?.summary ?? '');
    _domain = TextEditingController(text: initial?.domainScope ?? '');
    _kind = initial?.kind ?? PersonalProfileFactKind.goal;
  }

  @override
  void dispose() {
    _key.dispose();
    _value.dispose();
    _summary.dispose();
    _domain.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || !(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final now = DateTime.now().toUtc();
      final ownerUserId = await ref.read(currentUserIdProvider)();
      final store = await ref.read(personalProfileStoreProvider.future);
      final initial = widget.initial;
      final domain = _domain.text.trim();
      final fact = PersonalProfileFact(
        id: 'profile_fact:${_profileUuid.v4()}',
        ownerUserId: ownerUserId,
        kind: _kind,
        key: _key.text.trim(),
        value: _parseValue(_value.text),
        summary: _summary.text.trim(),
        domainScope: domain.isEmpty ? null : domain,
        authority: EvidenceAuthority.userConfirmed,
        provenance: EvidenceProvenance(
          source: 'settings_profile',
          sourceId: initial?.id,
          observedAt: now,
        ),
        confidence: 1,
        confirmedAt: now,
        validFrom: now,
        supersedesFactId: initial?.id,
        createdAt: now,
        updatedAt: now,
      );
      if (initial == null) {
        await store.create(fact);
      } else {
        await store.supersede(
          ownerUserId: ownerUserId,
          priorId: initial.id,
          replacement: fact,
          at: now,
        );
      }
      if (mounted) Navigator.of(context).pop(true);
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = '$error';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AppSheet(
      title: widget.initial == null
          ? l10n.personalMemoryCreateTitle
          : l10n.personalMemoryEditTitle,
      footer: _ProfileSheetFooter(saving: _saving, onSave: _save),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (_error != null) ...<Widget>[
              AppStatusBanner(kind: AppStatusKind.error, message: _error!),
              const SizedBox(height: AppSpacing.s12),
            ],
            Text(l10n.personalMemoryKind, style: context.captionLabelStyle),
            const SizedBox(height: AppSpacing.s6),
            AppAdaptiveChoice<PersonalProfileFactKind>(
              title: l10n.personalMemoryKind,
              options: PersonalProfileFactKind.values,
              value: _kind,
              labelOf: (kind) => _kindLabel(l10n, kind),
              iconOf: _kindIcon,
              onChanged: _saving
                  ? (_) {}
                  : (kind) => setState(() => _kind = kind),
            ),
            const SizedBox(height: AppSpacing.s12),
            FTextFormField(
              control: FTextFieldControl.managed(controller: _key),
              label: Text(l10n.personalMemoryKey),
              hint: l10n.personalMemoryKeyHint,
              validator: (value) => value == null || value.trim().isEmpty
                  ? l10n.personalMemoryRequired
                  : null,
            ),
            const SizedBox(height: AppSpacing.s12),
            FTextFormField(
              control: FTextFieldControl.managed(controller: _value),
              label: Text(l10n.personalMemoryValue),
              hint: l10n.personalMemoryValueHint,
              minLines: 2,
              maxLines: 5,
            ),
            const SizedBox(height: AppSpacing.s12),
            FTextFormField(
              control: FTextFieldControl.managed(controller: _summary),
              label: Text(l10n.personalMemorySummary),
              hint: l10n.personalMemorySummaryHint,
              minLines: 2,
              maxLines: 5,
              validator: (value) => value == null || value.trim().isEmpty
                  ? l10n.personalMemoryRequired
                  : null,
            ),
            const SizedBox(height: AppSpacing.s12),
            FTextFormField(
              control: FTextFieldControl.managed(controller: _domain),
              label: Text(l10n.personalMemoryDomain),
              hint: l10n.personalMemoryDomainHint,
              maxLines: 1,
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileSheetFooter extends StatelessWidget {
  const _ProfileSheetFooter({required this.saving, required this.onSave});

  final bool saving;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Row(
      children: <Widget>[
        Expanded(
          child: FButton(
            variant: FButtonVariant.outline,
            onPress: saving ? null : () => Navigator.of(context).maybePop(),
            child: Text(l10n.commonCancel),
          ),
        ),
        const SizedBox(width: AppSpacing.s8),
        Expanded(
          child: FButton(
            onPress: saving ? null : onSave,
            child: Text(l10n.commonSave),
          ),
        ),
      ],
    );
  }
}

String _kindLabel(AppLocalizations l10n, PersonalProfileFactKind kind) =>
    switch (kind) {
      PersonalProfileFactKind.goal => l10n.personalMemoryKindGoal,
      PersonalProfileFactKind.preference => l10n.personalMemoryKindPreference,
      PersonalProfileFactKind.constraint => l10n.personalMemoryKindConstraint,
      PersonalProfileFactKind.rule => l10n.personalMemoryKindRule,
    };

IconData _kindIcon(PersonalProfileFactKind kind) => switch (kind) {
  PersonalProfileFactKind.goal => FLucideIcons.target,
  PersonalProfileFactKind.preference => FLucideIcons.heart,
  PersonalProfileFactKind.constraint => FLucideIcons.shieldAlert,
  PersonalProfileFactKind.rule => FLucideIcons.listChecks,
};

String _displayValue(Object? value) {
  if (value == null) return '';
  if (value is String) return value;
  return const JsonEncoder.withIndent('  ').convert(value);
}

Object? _parseValue(String input) {
  final trimmed = input.trim();
  if (trimmed.isEmpty) return null;
  try {
    return jsonDecode(trimmed);
  } on FormatException {
    return trimmed;
  }
}
