import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/shell/entity_route_resolver.dart';
import '../domain/execution_models.dart';

String? executionSourceRoute(WidgetRef ref, ExecutionSourceRef source) {
  final family = source.rowFamily;
  final rowId = source.rowId;
  if (family == null || family.isEmpty || rowId == null || rowId.isEmpty) {
    return null;
  }
  final separator = family.indexOf(':');
  final table = separator < 0 ? family : family.substring(separator + 1);
  return ref.read(entityRouteResolverProvider)(
    EntityRouteRef(entityTable: table, entityId: rowId),
  );
}

VoidCallback? executionSourceOpen(
  BuildContext context,
  WidgetRef ref,
  ExecutionSourceRef source,
) {
  final route = executionSourceRoute(ref, source);
  return route == null ? null : () => context.push(route);
}
