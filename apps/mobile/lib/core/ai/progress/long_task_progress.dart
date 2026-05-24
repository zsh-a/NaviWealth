import 'package:flutter/foundation.dart';

/// `roadmap-next.md` §4 M-2 — descriptor for a long-running AI task
/// the UI should keep the user oriented inside of.
///
/// Producers (device agent loop, batch applier, tool dispatcher) push
/// a [LongTaskProgress] each time something observable changes; the
/// UI subscribes and renders. The model intentionally stays narrow —
/// label + indeterminate/ratio + optional cancel — so the same widget
/// covers "calling tool X (3/5)", "applying 12 of 30 edits", and
/// "Anthropic is thinking…".
@immutable
class LongTaskProgress {
  const LongTaskProgress({
    required this.id,
    required this.label,
    required this.startedAt,
    this.ratio,
    this.detail,
    this.cancelable = false,
  });

  /// Stable id for the task instance — lets the UI keep position
  /// stability across rebuilds and produces idempotent updates.
  final String id;

  /// Human-readable label (e.g. "Applying 12 of 30 edits").
  final String label;

  /// Optional secondary line (e.g. tool name, percent text — anything
  /// extra the label couldn't summarize).
  final String? detail;

  /// Wall clock at which the task entered the running state. Used by
  /// the UI to start showing elapsed time after a brief grace window
  /// so very short tasks don't visibly tick.
  final DateTime startedAt;

  /// `null` for indeterminate; otherwise in `[0, 1]`. Out-of-range
  /// values are clamped at read time via [normalisedRatio].
  final double? ratio;

  /// `true` when the task surfaces a cancel affordance. The cancel
  /// itself is dispatched out-of-band via the producer's own channel
  /// (this widget never mutates state).
  final bool cancelable;

  /// `[0, 1]`-clamped ratio if one is set, otherwise `null`. Producers
  /// occasionally over- or under-report; clamping spares every UI
  /// consumer the same guard.
  double? get normalisedRatio {
    final r = ratio;
    if (r == null) return null;
    if (r.isNaN) return null;
    if (r <= 0) return 0;
    if (r >= 1) return 1;
    return r;
  }

  /// `true` when the task has no determinate ratio — UIs should show a
  /// looping indicator instead of a filled progress bar.
  bool get isIndeterminate => normalisedRatio == null;

  /// Elapsed wall time at [now], floored to zero.
  Duration elapsedFrom(DateTime now) {
    final diff = now.difference(startedAt);
    return diff.isNegative ? Duration.zero : diff;
  }

  LongTaskProgress copyWith({
    String? label,
    String? detail,
    double? ratio,
    bool? cancelable,
  }) {
    return LongTaskProgress(
      id: id,
      label: label ?? this.label,
      startedAt: startedAt,
      detail: detail ?? this.detail,
      ratio: ratio ?? this.ratio,
      cancelable: cancelable ?? this.cancelable,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is LongTaskProgress &&
      other.id == id &&
      other.label == label &&
      other.detail == detail &&
      other.startedAt == startedAt &&
      other.ratio == ratio &&
      other.cancelable == cancelable;

  @override
  int get hashCode =>
      Object.hash(id, label, detail, startedAt, ratio, cancelable);
}
