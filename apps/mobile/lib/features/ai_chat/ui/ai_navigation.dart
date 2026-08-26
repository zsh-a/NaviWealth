/// Navigation helpers for AI surfaces.
///
/// AI sheets, chat cards, and inline result chips are usually temporary
/// context. Opening details/settings from them should push a new route so
/// Back returns to the conversation instead of replacing it.
library;

import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../../core/shell/selection_query.dart';
import '../../../core/shell/settings_route_paths.dart';

String aiHistoryLocation(String sessionId) {
  return Uri(
    path: SettingsRoutes.aiHistory,
    queryParameters: <String, String>{kSelectedQueryKey: sessionId},
  ).toString();
}

/// Pushes a route from an AI surface through the shared router seam.
///
/// Keep AI-originated links here instead of calling `context.push` at each
/// card/indicator. The router owns the lightweight AI destination transition;
/// this seam keeps future AI navigation changes from reintroducing one-off
/// pushes that bypass it.
void pushFromAiSurface(BuildContext context, String location) {
  context.push(location);
}

void popThenPushFromAiSurface(BuildContext context, String location) {
  final router = GoRouter.of(context);
  Navigator.of(context).pop();
  router.push(location);
}
