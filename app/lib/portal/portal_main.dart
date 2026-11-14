import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_web_plugins/url_strategy.dart';

import 'portal_app.dart';
import 'portal_state.dart';

/// Entry point of the customer portal (a separate build from the staff app):
///
///     flutter run -d chrome -t lib/portal/portal_main.dart
///     flutter build web -t lib/portal/portal_main.dart --dart-define=PORTAL_API_URL=https://api.example.com
///
/// The login e-mail links to `<portal_url>/login#token=...` and the satisfaction survey to
/// `<portal_url>/csat#token=...&rating=good|bad`, so the app uses path URLs and the
/// web server must serve index.html for unknown paths.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  usePathUrlStrategy();
  // Read the link before the router starts and rewrites the address. A fresh link wins over an
  // old session: whoever clicked it wants to be signed in as the person it was sent to.
  final linkToken = linkTokenFromUri(Uri.base);
  final csatLink = csatLinkFromUri(Uri.base);
  final token = linkToken == null ? await PortalTokenStore.load() : null;
  runApp(
    ProviderScope(
      overrides: [
        initialPortalTokenProvider.overrideWithValue(token),
        initialPortalLinkTokenProvider.overrideWithValue(linkToken),
        initialCsatLinkProvider.overrideWithValue(csatLink),
      ],
      child: const PortalApp(),
    ),
  );
}
