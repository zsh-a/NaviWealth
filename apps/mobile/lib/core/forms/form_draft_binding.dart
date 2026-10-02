import 'package:flutter/widgets.dart';

import '../../design_system/widgets/form_dirty_controller.dart';
import 'local_form_draft.dart';

/// Connects an owner-scoped draft to input, explicit discard and app lifecycle.
/// Domain hosts own payloads and keep their revision checks when restoring.
class FormDraftBinding with WidgetsBindingObserver {
  FormDraftBinding({
    required this.store,
    required this.form,
    required this.dirty,
    required this.payload,
    required this.inputs,
  }) : session = store == null ? null : LocalFormDraftSession(store, form) {
    WidgetsBinding.instance.addObserver(this);
    for (final input in inputs) {
      input.addListener(capture);
    }
    dirty.addListener(capture);
    dirty.onDiscard = complete;
  }

  LocalFormDraftSession? session;
  final LocalFormDraftStore? store;
  final String form;
  final FormDirtyController dirty;
  final Map<String, Object?> Function() payload;
  final List<Listenable> inputs;
  bool _applying = false;
  bool _completed = false;

  bool get hasPending => session?.pending != null;

  void capture() {
    if (!_applying && dirty.isDirty && !dirty.busy) {
      if (_completed && store != null) {
        session = LocalFormDraftSession(store!, form)..accept();
        _completed = false;
      }
      session?.capture(payload());
    }
  }

  void restore(void Function(Map<String, Object?>) apply) {
    final value = session?.pending;
    if (value == null) return;
    _applying = true;
    try {
      apply(value);
      session!.accept();
      dirty.markDirty();
    } finally {
      _applying = false;
    }
    capture();
  }

  void discardPending() => session?.discardPending();
  void complete() {
    session?.complete();
    _completed = true;
    dirty.markPristine();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      capture();
      session?.flush();
    }
  }

  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    capture();
    session?.dispose();
    for (final input in inputs) {
      input.removeListener(capture);
    }
    dirty.removeListener(capture);
    dirty.onDiscard = null;
  }
}
