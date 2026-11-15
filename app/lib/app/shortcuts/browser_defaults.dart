// The browser's own action for a key (Ctrl+S saves the page, Ctrl+F finds, Alt+letter opens a menu)
// must not run when the app took the key. Only the web has such an action; elsewhere this does
// nothing.
export 'browser_defaults_stub.dart'
    if (dart.library.js_interop) 'browser_defaults_web.dart';
