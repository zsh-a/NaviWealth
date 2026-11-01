import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Uses the app's Flutter Material pages explicitly.
///
/// go_router 18 detects MaterialApp from the standalone material_ui package.
/// Our Flutter MaterialApp otherwise falls back to NoTransitionPage, bypassing
/// the app's transitions and native iOS navigation. Route ownership, matching,
/// guards, restoration and explicit page builders remain GoRouter's contract.
class AppGoRoute extends GoRoute {
  AppGoRoute({
    required super.path,
    super.name,
    super.builder,
    GoRouterPageBuilder? pageBuilder,
    super.parentNavigatorKey,
    super.redirect,
    super.onExit,
    super.routes,
    super.caseSensitive,
    super.metadata,
  }) : super(
         pageBuilder:
             pageBuilder ??
             (builder == null
                 ? null
                 : (context, state) => MaterialPage<void>(
                     key: state.pageKey,
                     name: state.name ?? state.path,
                     arguments: <String, String>{
                       ...state.pathParameters,
                       ...state.uri.queryParameters,
                     },
                     restorationId: state.pageKey.value,
                     child: Builder(
                       builder: (context) => builder(context, state),
                     ),
                   )),
       );
}
