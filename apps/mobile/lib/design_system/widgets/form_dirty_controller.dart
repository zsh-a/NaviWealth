import 'package:flutter/widgets.dart';

/// Tracks whether a form holds unsaved input.
///
/// Pure design-system primitive (no l10n / router / Riverpod deps) so it
/// can be consumed by [showAppFormSheet] as well as the features-layer
/// `FormDirtyGuard` mixin. Bind it to the form's
/// [TextEditingController]s with [bindTextControllers] — typed edits flip
/// dirty automatically against a captured baseline, so an async hydrate
/// of an existing record does not count — and call [markDirty] from
/// non-text pickers (currency, date, account, switches…). [busy] gates
/// dismissal while a submit is in flight.
class FormDirtyController extends ChangeNotifier {
  bool _dirty = false;
  bool _busy = false;
  bool _disposed = false;

  final List<TextEditingController> _bound = <TextEditingController>[];
  final Map<TextEditingController, String> _baseline =
      <TextEditingController, String>{};

  bool get isDirty => _dirty;

  /// Whether a submit is currently in flight. While true the guard
  /// swallows every dismissal vector so a half-written record can't be
  /// abandoned mid-write.
  bool get busy => _busy;

  set busy(bool value) {
    if (_busy == value || _disposed) return;
    _busy = value;
    notifyListeners();
  }

  void markDirty() {
    if (_dirty || _disposed) return;
    _dirty = true;
    notifyListeners();
  }

  /// Treat the current field values as the saved/clean baseline. Call
  /// after a successful save so the post-save pop is not flagged.
  void markPristine() {
    for (final c in _bound) {
      _baseline[c] = c.text;
    }
    final wasDirty = _dirty;
    _dirty = false;
    if (wasDirty && !_disposed) notifyListeners();
  }

  /// Re-capture the baseline without touching the dirty flag — call
  /// once async hydrate has populated the controllers.
  void snapshotBaseline() {
    for (final c in _bound) {
      _baseline[c] = c.text;
    }
  }

  /// Attach listeners so the form flips dirty on the first edit that
  /// diverges from the captured baseline. Call once (e.g. in initState);
  /// pair with [snapshotBaseline] after an async hydrate.
  void bindTextControllers(List<TextEditingController> controllers) {
    for (final c in controllers) {
      if (_bound.contains(c)) continue;
      _bound.add(c);
      _baseline[c] = c.text;
      c.addListener(_onBoundChanged);
    }
  }

  void _onBoundChanged() {
    if (_dirty || _disposed) return;
    for (final c in _bound) {
      if (c.text != (_baseline[c] ?? '')) {
        markDirty();
        return;
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    for (final c in _bound) {
      // Controllers are owned (and disposed) by the host form; detaching
      // our listener is best-effort — if the form disposed the
      // controller first the listener is already gone.
      try {
        c.removeListener(_onBoundChanged);
      } catch (_) {
        // Controller already disposed — nothing to detach.
      }
    }
    _bound.clear();
    _baseline.clear();
    super.dispose();
  }
}
