import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/garmin/garmin_foreground_refresh.dart';

/// TickerMode follows the existing indexed-stack tab visibility. Entering a
/// retained Health tab is a refresh opportunity, not a second navigation hook.
class GarminForegroundRefreshScope extends ConsumerStatefulWidget {
  const GarminForegroundRefreshScope({super.key, required this.child});
  final Widget child;
  @override
  ConsumerState<GarminForegroundRefreshScope> createState() =>
      _GarminForegroundRefreshScopeState();
}

class _GarminForegroundRefreshScopeState
    extends ConsumerState<GarminForegroundRefreshScope> {
  bool _visible = false;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final visible = TickerMode.valuesOf(context).enabled;
    if (visible && !_visible) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && ref.exists(garminForegroundRefreshProvider)) {
          unawaited(ref.read(garminForegroundRefreshProvider)?.check());
        }
      });
    }
    _visible = visible;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
