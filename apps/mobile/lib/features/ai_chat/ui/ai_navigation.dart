/// Navigation helpers for AI surfaces.
///
/// AI sheets, chat cards, and inline result chips are usually temporary
/// context. Opening details/settings from them should push a new route so
/// Back returns to the conversation instead of replacing it.
library;

import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../../app/route_paths.dart';
import '../../../core/shell/selection_query.dart';

String aiHistoryLocation(String sessionId) {
  return Uri(
    path: AppRoutes.settingsAiHistory,
    queryParameters: <String, String>{kSelectedQueryKey: sessionId},
  ).toString();
}

void pushFromAiSurface(BuildContext context, String location) {
  context.push(location);
}

void popThenPushFromAiSurface(BuildContext context, String location) {
  final router = GoRouter.of(context);
  Navigator.of(context).pop();
  router.push(location);
}
