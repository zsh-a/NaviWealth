import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../core/lifeos/domain_pack.dart';
import '../../core/shell/settings_route_paths.dart';

DomainSettingsSpec domainSettingsSpec({
  required IconData icon,
  required String label,
  required DomainSettingsSubtitleBuilder subtitle,
  required String routePath,
  required String routeName,
  required Widget page,
}) {
  return DomainSettingsSpec(
    icon: icon,
    label: label,
    subtitle: subtitle,
    routeBuilder: (wrap) => GoRoute(
      path: _settingsChildPath(routePath),
      name: routeName,
      builder: (context, state) => wrap(page),
    ),
  );
}

String _settingsChildPath(String absolutePath) {
  const prefix = '${SettingsRoutes.root}/';
  if (!absolutePath.startsWith(prefix)) {
    throw ArgumentError.value(
      absolutePath,
      'absolutePath',
      'must be under ${SettingsRoutes.root}',
    );
  }
  return absolutePath.substring(prefix.length);
}
