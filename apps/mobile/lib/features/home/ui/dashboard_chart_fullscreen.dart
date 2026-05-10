import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';

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
      child: Scaffold(
        backgroundColor: Theme.of(context).colorScheme.surface,
        appBar: AppBar(
          backgroundColor: Theme.of(context).colorScheme.surface,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          title: Text(widget.title),
          leading: IconButton(
            tooltip: AppLocalizations.of(context).commonClose,
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
        body: SafeArea(
          child: Padding(padding: Spacing.pageMobile, child: widget.child),
        ),
      ),
    );
  }
}
