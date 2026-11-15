import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

/// Cancels the browser's own action for a key the app handled.
///
/// The web engine calls `preventDefault` only when the framework's key-data path answers "handled",
/// and that path always answers no (the answer comes back separately), so a key the app took still
/// reaches the browser: Ctrl+S would also open "Save page", Ctrl+F the find bar, Alt+F a menu.
///
/// The engine handles a key event in a capture-phase listener on the window, and the framework runs
/// inside it, so once that listener has returned the host has said whether it took the key
/// ([markHandled]). A capture-phase listener on the window registered after the engine's runs next,
/// and cancels the default for exactly that event. It must be a capture listener on the window: the
/// engine stops the propagation of some events, which the bubble phase never sees, but listeners on
/// the same node and phase still run. A mark expires when the event is through, so it can never
/// leak to a key the app did not take.
class BrowserDefaults {
  const BrowserDefaults._();

  static bool _installed = false;
  static bool _handled = false;

  /// Starts listening (once). Called when the app starts, after the engine has registered its own.
  static void install() {
    if (_installed) return;
    _installed = true;
    globalContext.callMethod(
      'addEventListener'.toJS,
      'keydown'.toJS,
      ((JSObject event) {
        if (!_handled) return;
        _handled = false;
        event.callMethod('preventDefault'.toJS);
      }).toJS,
      true.toJS,
    );
  }

  /// Says the key event being handled was taken by the app.
  static void markHandled() {
    _handled = true;
    // The event's dispatch is one task: the mark is gone before the next task, taken or not.
    Timer.run(() => _handled = false);
  }
}
