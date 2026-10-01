import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import 'form_dirty_controller.dart';

/// Guards in-page navigation that does not pop a route, such as selecting
/// another row or closing a master-detail pane. Registrations are owned by
/// the forms, and scoped to a router and one route rather than app-global.
class FormLeaveController {
  final _forms = <FormDirtyController, Future<bool> Function()>{};
  Future<bool>? _pending;

  bool get isBusy => _forms.keys.any((form) => form.busy);

  bool get hasPendingChanges =>
      _forms.keys.any((form) => form.isDirty || form.busy);

  void register(FormDirtyController form, Future<bool> Function() confirm) {
    _forms[form] = confirm;
  }

  void unregister(FormDirtyController form) => _forms.remove(form);

  Future<bool> confirmLeave() {
    if (isBusy) return Future.value(false);
    if (!hasPendingChanges) return Future.value(true);
    return _pending ??= _confirm().whenComplete(() => _pending = null);
  }

  Future<bool> _confirm() async {
    for (final entry in _forms.entries.toList(growable: false)) {
      if (!await entry.value()) return false;
    }
    return !_forms.keys.any((form) => form.busy);
  }
}

class FormLeaveScope extends StatefulWidget {
  const FormLeaveScope({
    super.key,
    required this.routePath,
    required this.child,
  });

  final String routePath;
  final Widget child;

  static final _routers = Expando<Map<String, FormLeaveController>>();

  static FormLeaveController? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<_FormLeaveInherited>()
      ?.controller;

  static FormLeaveController? forRouter(GoRouter router, {String? path}) =>
      _routers[router]?[path ?? router.routeInformationProvider.value.uri.path];

  static Future<bool> confirmRouteLeave(BuildContext context, {String? path}) {
    final router = GoRouter.maybeOf(context);
    return router == null
        ? Future.value(true)
        : forRouter(router, path: path)?.confirmLeave() ?? Future.value(true);
  }

  @override
  State<FormLeaveScope> createState() => _FormLeaveScopeState();
}

class _FormLeaveScopeState extends State<FormLeaveScope> {
  final _controller = FormLeaveController();
  GoRouter? _router;
  String? _registeredPath;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final router = GoRouter.maybeOf(context);
    if (router == _router && widget.routePath == _registeredPath) return;
    _unregister();
    _router = router;
    _registeredPath = widget.routePath;
    if (router != null) {
      final scopes = FormLeaveScope._routers[router] ??= {};
      scopes[widget.routePath] = _controller;
    }
  }

  @override
  void didUpdateWidget(FormLeaveScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.routePath != widget.routePath) {
      _unregister();
      _registeredPath = widget.routePath;
      final router = _router;
      if (router != null) {
        FormLeaveScope._routers[router]![widget.routePath] = _controller;
      }
    }
  }

  void _unregister() {
    final router = _router;
    if (router == null) return;
    final scopes = FormLeaveScope._routers[router];
    if (scopes?[_registeredPath] == _controller) {
      scopes?.remove(_registeredPath);
    }
  }

  @override
  void dispose() {
    _unregister();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      _FormLeaveInherited(controller: _controller, child: widget.child);
}

class _FormLeaveInherited extends InheritedWidget {
  const _FormLeaveInherited({required this.controller, required super.child});

  final FormLeaveController controller;

  @override
  bool updateShouldNotify(_FormLeaveInherited oldWidget) =>
      controller != oldWidget.controller;
}
