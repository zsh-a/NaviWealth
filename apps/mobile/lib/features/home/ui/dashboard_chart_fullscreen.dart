import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../../../design_system/design_system.dart';

Future<void> showDashboardChartFullscreen({
  required BuildContext context,
  required String title,
  required Widget child,
}) {
  return Navigator.of(context).push<void>(
    PageRouteBuilder<void>(
      fullscreenDialog: true,
      pageBuilder: (_, _, _) =>
          _DashboardChartFullscreenPage(title: title, child: child),
      transitionsBuilder: (_, animation, _, child) =>
          FadeTransition(opacity: animation, child: child),
    ),
  );
}

class _DashboardChartFullscreenPage extends StatefulWidget {
  const _DashboardChartFullscreenPage({
    required this.title,
    required this.child,
  });

  final String title;
  final Widget child;

  @override
  State<_DashboardChartFullscreenPage> createState() =>
      _DashboardChartFullscreenPageState();
}

class _DashboardChartFullscreenPageState
    extends State<_DashboardChartFullscreenPage> {
  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  @override
  void dispose() {
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FScaffold(
      header: FHeader.nested(
        title: Text(widget.title),
        prefixes: [
          FHeaderAction(
            icon: const Icon(FLucideIcons.x),
            onPress: () => Navigator.of(context).pop(),
          ),
        ],
      ),
      childPad: false,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.s16),
          child: widget.child,
        ),
      ),
    );
  }
}
