import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../design_system/design_system.dart';

/// Validates a form, then reveals and focuses its first invalid field after
/// inline errors have been laid out. Input values are left untouched.
bool validateAndRevealForm(
  GlobalKey<FormState> key, {
  void Function(Set<FormFieldState<Object?>> fields)? onInvalid,
}) {
  final form = key.currentState;
  if (form == null) return false;
  final invalid = form.validateGranularly();
  if (invalid.isEmpty) return true;
  onInvalid?.call(invalid);
  // Async pickers can register after fields below them. Traverse the rendered
  // tree so the first error follows reading order, not registration timing.
  var field = invalid.first;
  var found = false;
  void visit(Element element) {
    if (found) return;
    final state = element is StatefulElement ? element.state : null;
    if (state is FormFieldState<Object?> && invalid.contains(state)) {
      field = state;
      found = true;
    } else {
      element.visitChildElements(visit);
    }
  }

  (key.currentContext! as Element).visitChildElements(visit);
  var attempts = 0;
  void reveal(Duration _) {
    if (!field.mounted || !field.hasError) return;
    final context = field.context;
    // Use the field's own focusable descendant, never the enclosing form's
    // focus scope (which could return focus to the Save button).
    var focused = false;
    for (final node in FocusScope.of(context).descendants) {
      final nodeContext = node.context;
      if (node is FocusScopeNode || nodeContext == null) continue;
      var belongsToField = nodeContext == context;
      nodeContext.visitAncestorElements((ancestor) {
        if (ancestor == context) belongsToField = true;
        return !belongsToField;
      });
      if (belongsToField && node.canRequestFocus) {
        node.requestFocus();
        focused = true;
        break;
      }
    }
    // A disclosure can still exclude focus during its opening frames. Retry
    // after layout, bounded so a disabled/non-focusable field cannot loop.
    if (!focused && ++attempts < 12) {
      WidgetsBinding.instance.addPostFrameCallback(reveal);
      WidgetsBinding.instance.scheduleFrame();
      return;
    }
    unawaited(
      Scrollable.ensureVisible(
        context,
        alignment: 0.12,
        duration: AppMotionPolicy.duration(context, Motion.componentChange),
        curve: Motion.standardDecelerate,
      ),
    );
  }

  WidgetsBinding.instance.addPostFrameCallback(reveal);
  return false;
}
