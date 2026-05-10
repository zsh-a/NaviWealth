import 'package:flutter/material.dart' show Icons, MaterialPageRoute, Navigator;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

Future<void> showDashboardChartFullscreen({
  required BuildContext context,
  required String title,
  required Widget child,
}) {
  return Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => _DashboardChartFullscreenPage(title: title, child: child),
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
            icon: const Icon(Icons.close),
            onPress: () => Navigator.of(context).pop(),
          ),
        ],
      ),
      childPad: false,
      child: SafeArea(
        child: Padding(padding: const EdgeInsets.all(16), child: widget.child),
      ),
    );
  }
}
