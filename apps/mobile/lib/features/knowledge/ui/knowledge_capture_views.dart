part of 'knowledge_capture_sheet.dart';

Widget _captureStageTransition(Widget child, Animation<double> animation) {
  final curved = animation.drive(CurveTween(curve: Motion.standardDecelerate));
  final offset = Tween<Offset>(
    begin: const Offset(0, 0.04),
    end: Offset.zero,
  ).animate(curved);
  return FadeTransition(
    opacity: curved,
    child: SizeTransition(
      sizeFactor: curved,
      alignment: Alignment.topCenter,
      child: SlideTransition(position: offset, child: child),
    ),
  );
}

Widget _capturePreviewTransition(Widget child, Animation<double> animation) {
  final curved = animation.drive(CurveTween(curve: Motion.standardDecelerate));
  final offset = Tween<Offset>(
    begin: const Offset(0, -0.06),
    end: Offset.zero,
  ).animate(curved);
  return FadeTransition(
    opacity: curved,
    child: SizeTransition(
      sizeFactor: curved,
      alignment: Alignment.topCenter,
      child: SlideTransition(position: offset, child: child),
    ),
  );
}

class _ClassifyingBody extends StatelessWidget {
  const _ClassifyingBody({super.key, required this.onSkip});

  /// Bail out of the wait — the Note is already saved, the in-flight
  /// classifier becomes an orphan and its eventual result is dropped
  /// by the sheet's `mounted` guard. Useful for slow thinking models
  /// (mimo / Claude extended thinking) where the round-trip can take
  /// 20-30 s.
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.s16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Skeleton shimmer lines to suggest "AI is reading your text"
          // instead of a bare progress bar.
          ...List.generate(3, (i) {
            final widths = <double>[double.infinity, 200, 140];
            return Padding(
              padding: EdgeInsets.only(
                bottom: i < 2 ? AppSpacing.s8 : AppSpacing.s0,
              ),
              child: SkeletonBox(
                height: 14,
                width: widths[i],
                radius: AppRadius.sm,
              ),
            );
          }),
          const SizedBox(height: AppSpacing.s16),
          Text(
            l10n.knowledgeCaptureClassifyingBody,
            textAlign: TextAlign.center,
            style: context.bodyCaptionStyle,
          ),
          const SizedBox(height: AppSpacing.s12),
          Align(
            alignment: Alignment.center,
            child: AppQuietButton(
              label: l10n.knowledgeCaptureSkipClassification,
              onPress: onSkip,
            ),
          ),
        ],
      ),
    );
  }
}

class _SavedCapturePreview extends StatelessWidget {
  const _SavedCapturePreview({
    super.key,
    required this.sectionTitle,
    required this.promoted,
    required this.title,
    required this.body,
  });

  final String sectionTitle;
  final bool promoted;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.theme.colors;
    final typography = context.theme.typography;
    final hasTitle = title.trim().isNotEmpty;
    return KnowledgeWriterSection(
      title: sectionTitle,
      trailing: Icon(
        FLucideIcons.fileCheck,
        size: AppIconSizes.xs,
        color: colors.primary,
      ),
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (hasTitle) ...[
              Text(
                l10n.knowledgeCaptureTitleDiffLabel,
                style: context.captionStyle,
              ),
              const SizedBox(height: AppSpacing.s2),
              _CaptureSharedTextLine(
                text: knowledgeExcerpt(title),
                promoted: promoted,
                style: typography.body.sm,
                maxLines: 2,
              ),
              const SizedBox(height: AppSpacing.s8),
            ],
            Text(
              l10n.knowledgeCaptureBodyDiffLabel,
              style: context.captionStyle,
            ),
            const SizedBox(height: AppSpacing.s2),
            _CaptureSharedTextLine(
              text: knowledgeExcerpt(body),
              promoted: promoted,
              style: context.bodyCaptionStyle,
              maxLines: 3,
            ),
          ],
        ),
      ],
    );
  }
}

class _CaptureSharedTextLine extends StatelessWidget {
  const _CaptureSharedTextLine({
    required this.text,
    required this.promoted,
    required this.style,
    required this.maxLines,
  });

  final String text;
  final bool promoted;
  final TextStyle style;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: promoted ? 1 : 0),
      duration: AppMotionPolicy.duration(context, Motion.medium),
      curve: Motion.standardDecelerate,
      builder: (context, progress, child) {
        final scale = 0.985 + 0.015 * progress;
        final dy = -6 * (1 - progress);
        final color = Color.lerp(
          style.color ?? colors.foreground,
          colors.primary,
          progress * 0.18,
        );
        return Transform.translate(
          offset: Offset(0, dy),
          child: Transform.scale(
            scale: scale,
            alignment: Alignment.centerLeft,
            child: AnimatedDefaultTextStyle(
              duration: AppMotionPolicy.duration(context, Motion.fast),
              curve: Motion.standardDecelerate,
              style: style.copyWith(color: color),
              child: child!,
            ),
          ),
        );
      },
      child: Text(text, maxLines: maxLines, overflow: TextOverflow.ellipsis),
    );
  }
}

class _ComposeBody extends StatelessWidget {
  const _ComposeBody({
    super.key,
    required this.titleController,
    required this.bodyController,
    required this.selectedKind,
    required this.onKindChanged,
  });
  final TextEditingController titleController;
  final TextEditingController bodyController;
  final CaptureKind? selectedKind;
  final ValueChanged<CaptureKind?> onKindChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return KnowledgeWriterSection(
      title: l10n.knowledgeCaptureTitle,
      children: [
        _CaptureKindPicker(
          selectedKind: selectedKind,
          onChanged: onKindChanged,
        ),
        FTextField(
          control: FTextFieldControl.managed(controller: titleController),
          label: Text(l10n.knowledgeCaptureTitleField),
          hint: l10n.knowledgeCaptureTitleHint,
        ),
        FTextField(
          control: FTextFieldControl.managed(controller: bodyController),
          label: Text(l10n.knowledgeCaptureBodyField),
          hint: l10n.knowledgeCaptureBodyHint,
          minLines: 4,
          maxLines: 8,
        ),
        Align(
          alignment: Alignment.centerRight,
          child: SpeechInputButton(controller: bodyController),
        ),
      ],
    );
  }
}

class _CaptureKindPicker extends StatelessWidget {
  const _CaptureKindPicker({
    required this.selectedKind,
    required this.onChanged,
  });

  final CaptureKind? selectedKind;
  final ValueChanged<CaptureKind?> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final options = <_CaptureKindOption>[
      _CaptureKindOption(null, l10n.knowledgeCaptureKindAuto),
      for (final kind in CaptureKind.values)
        _CaptureKindOption(kind, _captureKindShortLabel(l10n, kind)),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.knowledgeCaptureTypeLabel, style: context.captionStyle),
        const SizedBox(height: AppSpacing.s6),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (var i = 0; i < options.length; i++) ...[
                _CaptureKindChip(
                  label: options[i].label,
                  selected: options[i].kind == selectedKind,
                  onTap: () => onChanged(options[i].kind),
                ),
                if (i != options.length - 1)
                  const SizedBox(width: AppSpacing.s6),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _CaptureKindChip extends StatelessWidget {
  const _CaptureKindChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AppFilterChip(label: label, active: selected, onPress: onTap);
  }
}

class _CaptureKindOption {
  const _CaptureKindOption(this.kind, this.label);

  final CaptureKind? kind;
  final String label;
}

String _captureKindShortLabel(AppLocalizations l10n, CaptureKind kind) {
  return switch (kind) {
    CaptureKind.note => l10n.knowledgeCaptureKindNote,
    CaptureKind.routine => l10n.knowledgeCaptureKindRoutine,
    CaptureKind.decision => l10n.knowledgeCaptureKindDecision,
    CaptureKind.principle => l10n.knowledgeCaptureKindPrinciple,
    CaptureKind.assumption => l10n.knowledgeCaptureKindAssumption,
    CaptureKind.concept => l10n.knowledgeCaptureKindConcept,
    CaptureKind.experiment => l10n.knowledgeCaptureKindExperiment,
  };
}

class _SuggestionBody extends StatelessWidget {
  const _SuggestionBody({
    super.key,
    required this.suggestion,
    required this.originalTitle,
    required this.originalBody,
    required this.applying,
    required this.onAccept,
    required this.onDismiss,
  });
  final CaptureClassification suggestion;
  final String originalTitle;
  final String originalBody;
  final bool applying;
  final VoidCallback onAccept;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (suggestion.hasPolish)
          _PolishPanel(
            suggestion: suggestion,
            originalTitle: originalTitle,
            originalBody: originalBody,
          ),
        if (suggestion.hasPolish && suggestion.isUpgrade)
          const SizedBox(height: AppSpacing.s8),
        if (suggestion.isUpgrade) _UpgradePanel(suggestion: suggestion),
        if (!suggestion.isUpgrade && suggestion.hasPolish)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.s8),
            child: Text(
              l10n.knowledgeCaptureNotePolishOnly(suggestion.reasonZh),
              style: context.captionStyle,
            ),
          ),
      ],
    );
  }
}

class _PolishPanel extends StatelessWidget {
  const _PolishPanel({
    required this.suggestion,
    required this.originalTitle,
    required this.originalBody,
  });
  final CaptureClassification suggestion;
  final String originalTitle;
  final String originalBody;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final l10n = AppLocalizations.of(context);
    final titleChanged =
        suggestion.polishedTitle != null &&
        suggestion.polishedTitle != originalTitle;
    final bodyChanged =
        suggestion.polishedBody != null &&
        suggestion.polishedBody != originalBody;
    return KnowledgeWriterSection(
      title: l10n.knowledgeCapturePolishedVersionTitle,
      trailing: Icon(
        FLucideIcons.wand,
        size: AppIconSizes.xs,
        color: colors.primary,
      ),
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (titleChanged) ...[
              _DiffRow(
                label: l10n.knowledgeCaptureTitleDiffLabel,
                before: originalTitle.isEmpty
                    ? l10n.knowledgeCaptureEmptyValue
                    : originalTitle,
                after: suggestion.polishedTitle!,
              ),
              if (bodyChanged) const SizedBox(height: AppSpacing.s8),
            ],
            if (bodyChanged)
              _DiffRow(
                label: l10n.knowledgeCaptureBodyDiffLabel,
                before: originalBody.isEmpty
                    ? l10n.knowledgeCaptureEmptyValue
                    : originalBody,
                after: suggestion.polishedBody!,
              ),
          ],
        ),
      ],
    );
  }
}

class _DiffRow extends StatelessWidget {
  const _DiffRow({
    required this.label,
    required this.before,
    required this.after,
  });
  final String label;
  final String before;
  final String after;

  @override
  Widget build(BuildContext context) {
    final typography = context.theme.typography;
    final colors = context.theme.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(label, style: context.captionStyle),
        const SizedBox(height: AppSpacing.s4),
        // Original — muted, stricken
        SoftCard.flat(
          borderless: true,
          padding: const EdgeInsets.all(AppSpacing.s8),
          child: Text(
            knowledgeExcerpt(before),
            style: context.bodyCaptionStyle.copyWith(
              decoration: TextDecoration.lineThrough,
              decorationColor: colors.mutedForeground,
            ),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(height: AppSpacing.s4),
        // Arrow indicator
        Icon(
          FLucideIcons.arrowDown,
          size: AppIconSizes.xs,
          color: colors.primary,
        ),
        const SizedBox(height: AppSpacing.s4),
        // Improved — primary tint via SoftCard (hero wash kept off for density)
        SoftCard.raised(
          borderless: false,
          padding: const EdgeInsets.all(AppSpacing.s8),
          child: Text(
            knowledgeExcerpt(after),
            style: typography.body.sm.copyWith(color: colors.foreground),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class _UpgradePanel extends StatelessWidget {
  const _UpgradePanel({required this.suggestion});
  final CaptureClassification suggestion;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final l10n = AppLocalizations.of(context);
    final headline = switch (suggestion.kind) {
      CaptureKind.routine => l10n.knowledgeCaptureKindRoutineDescription,
      CaptureKind.decision => l10n.knowledgeCaptureKindDecisionDescription,
      CaptureKind.assumption => l10n.knowledgeCaptureKindAssumptionDescription,
      CaptureKind.principle => l10n.knowledgeCaptureKindPrincipleDescription,
      CaptureKind.concept => l10n.knowledgeCaptureKindConceptDescription,
      CaptureKind.experiment => l10n.knowledgeCaptureKindExperimentDescription,
      CaptureKind.note => l10n.knowledgeCaptureKindNoteDescription,
    };
    final detail = switch (suggestion.kind) {
      CaptureKind.routine =>
        '${l10n.knowledgeCaptureRoutineUpgradeDetail(suggestion.statement ?? '', suggestion.intervalDays ?? 180)}${suggestion.scope != null && suggestion.scope != '*' ? ' ${l10n.knowledgeCaptureRoutineScopeDetail(suggestion.scope!)}' : ''} ${l10n.knowledgeCaptureRoutineReminderDetail}',
      _ => suggestion.reasonZh,
    };
    return KnowledgeWriterSection(
      title: headline,
      trailing: Icon(
        FLucideIcons.sparkles,
        size: AppIconSizes.xs,
        color: colors.primary,
      ),
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(detail, style: context.bodyCaptionStyle),
            const SizedBox(height: AppSpacing.s4),
            Text(
              l10n.knowledgeCaptureSuggestionReasonConfidence(
                suggestion.reasonZh,
                suggestion.confidence.toStringAsFixed(2),
              ),
              style: context.captionStyle,
            ),
          ],
        ),
      ],
    );
  }
}
