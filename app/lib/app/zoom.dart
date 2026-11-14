import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/field/offline/kv_store.dart';

/// The zoom of the whole app, like a web page: Ctrl + / Ctrl - / Ctrl 0 and Ctrl + mouse wheel.
/// It is remembered per profile (or per device without a profile).
class ZoomNotifier extends Notifier<double> {
  static const key = 'ui_zoom';
  static const min = 0.5, max = 3.0, step = 0.1;

  /// Set once the zoom was changed, so a slower read of the stored value cannot overwrite it.
  bool _changed = false;

  @override
  double build() {
    _changed = false;
    ref.read(kvStoreProvider).get(key).then((v) {
      final z = double.tryParse(v ?? '');
      if (!_changed && ref.mounted && z != null && z >= min && z <= max) {
        state = z;
      }
    }, onError: (Object _) {});
    return 1.0;
  }

  /// Zooms in (positive) or out (negative) by [delta], within [min] and [max].
  void zoomBy(double delta) => set(state + delta);

  /// Back to 100 %.
  void reset() => set(1.0);

  /// Sets the zoom (clamped to [min]..[max], in whole percent) and stores it.
  void set(double z) {
    _changed = true;
    final clamped = (z.clamp(min, max) * 100).roundToDouble() / 100;
    if (clamped == state) return;
    state = clamped;
    ref.read(kvStoreProvider).set(key, clamped.toString());
  }
}

/// The current zoom factor (1.0 = 100 %).
final zoomProvider = NotifierProvider<ZoomNotifier, double>(ZoomNotifier.new);

/// Scales everything below it (text, controls, spacing) by [zoomProvider] and handles the zoom
/// keys. Hit testing follows the scaling, so clicks land where things are drawn.
class ZoomShell extends ConsumerStatefulWidget {
  const ZoomShell({super.key, required this.child});
  final Widget child;

  @override
  ConsumerState<ZoomShell> createState() => _ZoomShellState();
}

/// State of [ZoomShell]: listens to the zoom keys while it is mounted.
class _ZoomShellState extends ConsumerState<ZoomShell> {
  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    super.dispose();
  }

  /// Ctrl or Cmd with plus, minus or 0; returns whether the key was a zoom key.
  bool _onKey(KeyEvent e) {
    if (e is KeyUpEvent) return false;
    final kb = HardwareKeyboard.instance;
    if (!(kb.isControlPressed || kb.isMetaPressed)) return false;
    final k = e.logicalKey;
    final zoom = ref.read(zoomProvider.notifier);
    if (k == LogicalKeyboardKey.equal ||
        k == LogicalKeyboardKey.add ||
        k == LogicalKeyboardKey.numpadAdd) {
      zoom.zoomBy(ZoomNotifier.step);
    } else if (k == LogicalKeyboardKey.minus ||
        k == LogicalKeyboardKey.numpadSubtract) {
      zoom.zoomBy(-ZoomNotifier.step);
    } else if (k == LogicalKeyboardKey.digit0 ||
        k == LogicalKeyboardKey.numpad0) {
      zoom.reset();
    } else {
      return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final zoom = ref.watch(zoomProvider);
    final child = Listener(
      onPointerSignal: (e) {
        if (e is PointerScrollEvent &&
            (HardwareKeyboard.instance.isControlPressed ||
                HardwareKeyboard.instance.isMetaPressed)) {
          ref
              .read(zoomProvider.notifier)
              .zoomBy(
                e.scrollDelta.dy < 0 ? ZoomNotifier.step : -ZoomNotifier.step,
              );
        }
      },
      child: widget.child,
    );
    if (zoom == 1.0) return child;
    return LayoutBuilder(
      builder: (context, box) {
        final w = box.maxWidth / zoom, h = box.maxHeight / zoom;
        final mq = MediaQuery.of(context);
        return ClipRect(
          child: OverflowBox(
            alignment: Alignment.topLeft,
            minWidth: w,
            maxWidth: w,
            minHeight: h,
            maxHeight: h,
            child: Transform.scale(
              scale: zoom,
              alignment: Alignment.topLeft,
              child: MediaQuery(
                data: mq.copyWith(size: Size(w, h)),
                child: child,
              ),
            ),
          ),
        );
      },
    );
  }
}
