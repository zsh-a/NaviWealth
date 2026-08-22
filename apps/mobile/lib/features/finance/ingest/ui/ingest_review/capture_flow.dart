part of '../ingest_review_page.dart';

// Extension methods on a State subclass legitimately call setState, which
// the analyzer flags as protected outside the class body.
// ignore_for_file: invalid_use_of_protected_member

extension _IngestCaptureFlow on _IngestReviewPageState {
  Future<void> _captureCamera() async {
    if (!_beginCapture()) return;
    late final IngestCaptureOutcome outcome;
    try {
      outcome = await ref.read(cameraIngestCaptureProvider).capture();
    } catch (_) {
      outcome = const IngestCaptureFailure(IngestCaptureFailureCode.unreadable);
    }
    _endCapture();
    if (!mounted) return;
    await _handleCaptureOutcome(
      outcome,
      retry: _captureCamera,
      actionLabel: AppLocalizations.of(context).ingestRetakePhoto,
    );
  }

  Future<void> _onDrop(DropDoneDetails detail) async {
    if (detail.files.isEmpty || !_beginCapture()) return;
    final failures = <IngestCaptureFailure>[];
    try {
      for (final file in detail.files) {
        try {
          final outcome = await xFileToIngestSource(file);
          if (!mounted) return;
          switch (outcome) {
            case IngestCaptureSuccess(:final source):
              await _runIngest(source);
            case IngestCaptureFailure():
              failures.add(outcome);
            case IngestCaptureCancelled():
              break;
          }
        } catch (_) {
          if (!mounted) return;
          failures.add(
            IngestCaptureFailure(
              IngestCaptureFailureCode.unreadable,
              fileName: file.name,
            ),
          );
        }
      }
    } finally {
      _endCapture();
    }
    if (!mounted || failures.isEmpty) return;
    final l10n = AppLocalizations.of(context);
    AppMessenger.show(
      context,
      ToastKind.error,
      failures.length == 1
          ? localizedIngestCaptureFailure(l10n, failures.single)
          : l10n.ingestDroppedSourcesRejected(failures.length),
    );
  }

  Future<void> _openPasteDialog() async {
    final text = await showGuardedFormSheet<String>(
      context: context,
      builder: (_, dirty) => _PasteSheet(
        dirty: dirty,
        maxTextCodeUnits: ref.read(ingestCaptureTextLimitProvider),
      ),
    );
    if (text == null) return;
    final outcome = ingestSourceFromTextCapture(
      text: text,
      // Stable non-display breadcrumb (persisted + traced).
      originLabel: 'paste',
    );
    if (!mounted) return;
    await _handleCaptureOutcome(
      outcome,
      retry: _openPasteDialog,
      actionLabel: AppLocalizations.of(context).commonRetry,
    );
  }

  Future<void> _pickFile() async {
    // The system picker provides its own modal UI; _runIngest owns the
    // busy state for the parse that follows.
    if (!_beginCapture()) return;
    late final IngestCaptureOutcome outcome;
    try {
      outcome = await ref.read(ingestCaptureSourceProvider).pickFile();
    } catch (_) {
      outcome = const IngestCaptureFailure(IngestCaptureFailureCode.unreadable);
    }
    _endCapture();
    if (!mounted) return;
    await _handleCaptureOutcome(
      outcome,
      retry: _pickFile,
      actionLabel: AppLocalizations.of(context).ingestChooseAnotherFile,
    );
  }

  bool _beginCapture() {
    if (_busy != null || !_captureLease.tryAcquire()) return false;
    setState(() {});
    return true;
  }

  void _endCapture() {
    if (mounted) setState(_captureLease.release);
  }

  Future<void> _handleCaptureOutcome(
    IngestCaptureOutcome outcome, {
    Future<void> Function()? retry,
    String? actionLabel,
  }) async {
    switch (outcome) {
      case IngestCaptureSuccess(:final source):
        await _runIngest(source, retry: retry, retryLabel: actionLabel);
      case IngestCaptureFailure():
        _showCaptureFailure(outcome, retry: retry, actionLabel: actionLabel);
      case IngestCaptureCancelled():
        break;
    }
  }

  void _showCaptureFailure(
    IngestCaptureFailure failure, {
    Future<void> Function()? retry,
    String? actionLabel,
  }) {
    final l10n = AppLocalizations.of(context);
    AppMessenger.show(
      context,
      ToastKind.error,
      localizedIngestCaptureFailure(l10n, failure),
      actionLabel: retry == null ? null : actionLabel,
      onAction: retry == null ? null : () => unawaited(retry()),
    );
  }

  /// Shared tail for every capture entry (paste / file): run the
  /// pipeline and surface the outcome with one consistent toast set.
  Future<void> _runIngest(
    IngestSource source, {
    Future<void> Function()? retry,
    String? retryLabel,
  }) async {
    final l10n = AppLocalizations.of(context);
    final sourceLabel = _sourceLabel(l10n, source);
    setState(() {
      _busy = _IngestBusyState(
        action: _IngestAction.parsing,
        title: l10n.ingestProcessingTitle,
        message: l10n.ingestProcessingBody(sourceLabel),
        icon: _sourceIcon(source.kind),
      );
    });
    try {
      final result = await ref.read(ingestControllerProvider).ingest(source);
      if (!mounted) return;
      final qualityReport = IngestQualityReport.fromResult(source.kind, result);
      setState(() => _latestQualityReport = qualityReport);
      await _recordIngestQualityMetrics(result);
      if (!mounted) return;
      if (result.isRejected) {
        final rejection = result.rejectedReason!;
        _showCaptureParseFailure(
          rejection == ingestDatabaseUnavailableReason
              ? l10n.ingestParseFailed
              : rejection,
          retry: retry,
          retryLabel: retryLabel,
        );
      } else if (result.total == 0) {
        AppMessenger.show(context, ToastKind.info, l10n.ingestNoTransactions);
      } else {
        final hasAuditedSkips =
            result.parseDiagnosticsComplete && result.skippedCount > 0;
        AppMessenger.show(
          context,
          hasAuditedSkips ? ToastKind.warning : ToastKind.success,
          hasAuditedSkips
              ? l10n.ingestParseSummaryWithSkipped(
                  result.total,
                  result.newCount,
                  result.duplicateCount,
                  result.skippedCount,
                )
              : l10n.ingestParseSummary(
                  result.total,
                  result.newCount,
                  result.duplicateCount,
                ),
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _latestQualityReport = IngestQualityReport.failed(source.kind),
        );
        _showCaptureParseFailure(
          l10n.ingestParseFailed,
          retry: retry,
          retryLabel: retryLabel,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _recordIngestQualityMetrics(IngestResult result) async {
    final metrics = ref.read(productMetricsProvider.notifier);
    await metrics.record(
      ProductFunnelEvent.importCycleCompleted,
      success: !result.isRejected,
    );
    await metrics.record(
      ProductFunnelEvent.importRowsAccepted,
      success: true,
      quantity: result.newCount,
    );
    await metrics.record(
      ProductFunnelEvent.importRowsDeduplicated,
      success: true,
      quantity: result.duplicateCount,
    );
    await metrics.record(
      ProductFunnelEvent.importRowsRejected,
      success: false,
      quantity: result.skippedCount + (result.isRejected ? 1 : 0),
    );
  }

  void _copyLatestQualityReport() {
    final report = _latestQualityReport;
    if (report == null) return;
    Clipboard.setData(ClipboardData(text: report.encode()));
    AppMessenger.show(
      context,
      ToastKind.success,
      AppLocalizations.of(context).ingestDiagnosticsCopied,
    );
  }

  void _showCaptureParseFailure(
    String message, {
    Future<void> Function()? retry,
    String? retryLabel,
  }) {
    AppMessenger.show(
      context,
      ToastKind.error,
      message,
      actionLabel: retry == null ? null : retryLabel,
      onAction: retry == null ? null : () => unawaited(retry()),
    );
  }

  void _showRetry(String message, Future<void> Function() retry) {
    final l10n = AppLocalizations.of(context);
    AppMessenger.show(
      context,
      ToastKind.error,
      message,
      actionLabel: l10n.commonRetry,
      onAction: () => unawaited(retry()),
    );
  }
}

IconData _sourceIcon(IngestSourceKind kind) {
  return switch (kind) {
    IngestSourceKind.csv => FLucideIcons.fileSpreadsheet,
    IngestSourceKind.pasteText => FLucideIcons.clipboard,
    IngestSourceKind.receiptImage => FLucideIcons.image,
    IngestSourceKind.statementPdf => FLucideIcons.fileText,
    IngestSourceKind.email => FLucideIcons.mail,
  };
}

String _sourceLabel(AppLocalizations l10n, IngestSource source) {
  final label = source.originLabel?.trim();
  if (label != null && label.isNotEmpty && label != 'paste') return label;
  return switch (source.kind) {
    IngestSourceKind.csv => l10n.ingestSourceCsv,
    IngestSourceKind.pasteText => l10n.ingestSourcePaste,
    IngestSourceKind.receiptImage => l10n.ingestSourceImage,
    IngestSourceKind.statementPdf => l10n.ingestSourcePdf,
    IngestSourceKind.email => l10n.ingestSourceEmail,
  };
}
