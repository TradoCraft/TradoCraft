/// Cancels the browser's own action for a key the app handled. Nothing to do outside the web.
class BrowserDefaults {
  const BrowserDefaults._();

  /// Starts listening (once).
  static void install() {}

  /// Says the key event being handled was taken by the app.
  static void markHandled() {}
}
