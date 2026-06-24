import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';

/// Defers a provider subscription until after the first frame.
///
/// Use this for UI surfaces that need values from providers with broad
/// async/stream dependency graphs. The first build receives [initialValue];
/// the real provider is attached post-frame, so any synchronous Riverpod
/// refresh caused by dependency flushing happens outside Flutter's build pass.
class DeferredProviderSnapshot<T> extends ConsumerStatefulWidget {
  const DeferredProviderSnapshot({
    required this.provider,
    required this.initialValue,
    required this.builder,
    super.key,
  });

  final ProviderListenable<T> provider;
  final T initialValue;
  final Widget Function(BuildContext context, T value) builder;

  @override
  ConsumerState<DeferredProviderSnapshot<T>> createState() =>
      _DeferredProviderSnapshotState<T>();
}

class _DeferredProviderSnapshotState<T>
    extends ConsumerState<DeferredProviderSnapshot<T>> {
  ProviderSubscription<T>? _subscription;
  late T _value = widget.initialValue;

  @override
  void initState() {
    super.initState();
    _scheduleSubscription();
  }

  @override
  void didUpdateWidget(covariant DeferredProviderSnapshot<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.provider == widget.provider) return;
    _subscription?.close();
    _subscription = null;
    _value = widget.initialValue;
    _scheduleSubscription();
  }

  void _scheduleSubscription() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _subscription != null) return;
      _subscription = ref.listenManual<T>(widget.provider, (_, next) {
        if (!mounted || _value == next) return;
        setState(() {
          _value = next;
        });
      }, fireImmediately: true);
    });
  }

  @override
  void dispose() {
    _subscription?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _value);
}
