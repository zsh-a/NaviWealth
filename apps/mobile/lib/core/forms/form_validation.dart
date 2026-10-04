import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../design_system/design_system.dart';

/// Validates a form, then reveals and focuses its first invalid field after
/// inline errors have been laid out. Input values are left untouched.
bool validateAndRevealForm(GlobalKey<FormState> key) {
  final form = key.currentState;
  if (form == null) return false;
  final invalid = form.validateGranularly();
  if (invalid.isEmpty) return true;
  final field = invalid.first;
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!field.mounted || !field.hasError) return;
    final context = field.context;
    // Use the field's own focusable descendant, never the enclosing form's
    // focus scope (which could return focus to the Save button).
    for (final node in FocusScope.of(context).traversalDescendants) {
      final nodeContext = node.context;
      if (node is FocusScopeNode || nodeContext == null) continue;
      var belongsToField = nodeContext == context;
      nodeContext.visitAncestorElements((ancestor) {
        if (ancestor == context) belongsToField = true;
        return !belongsToField;
      });
      if (belongsToField) {
        node.requestFocus();
        break;
      }
    }
    unawaited(
      Scrollable.ensureVisible(
        context,
        alignment: 0.12,
        duration: AppMotionPolicy.duration(context, Motion.componentChange),
        curve: Motion.standardDecelerate,
      ),
    );
  });
  return false;
}
