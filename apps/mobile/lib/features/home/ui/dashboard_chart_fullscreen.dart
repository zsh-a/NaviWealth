import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:forui/forui.dart';


Future<void> showDashboardChartFullscreen({
  required BuildContext context,
  required String title,
  required Widget child,
}) {
  return showDialog<void>(
    context: context,
    useSafeArea: false,
    builder: (context) =>
        _DashboardChartFullscreenDialog(title: title, child: child),
  );
}

class _DashboardChartFullscreenDialog extends StatefulWidget {
  const _DashboardChartFullscreenDialog({
    required this.title,
    required this.child,
  });

  final String title;
  final Widget child;

  @override
  State<_DashboardChartFullscreenDialog> createState() =>
      _DashboardChartFullscreenDialogState();
}

class _DashboardChartFullscreenDialogState
    extends State<_DashboardChartFullscreenDialog> {
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
    return Dialog.fullscreen(
      child: FScaffold(
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
        child: Material(
          color: Colors.transparent,
          child: SafeArea(
            child: Padding(padding: const EdgeInsets.all(16), child: widget.child),
          ),
        ),
      ),
    );
  }
}
