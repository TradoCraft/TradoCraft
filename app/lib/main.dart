import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/router.dart';
import 'l10n/l10n.dart';
import 'app/brand.dart';
import 'app/environments.dart';
import 'app/profile.dart';
import 'app/session.dart';
import 'app/shortcuts/host.dart';
import 'app/zoom.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_mode.dart';
import 'features/field/offline/kv_store.dart';
import 'features/tutorial/overlay.dart';

/// The storage of [profile]; when its file cannot be opened the session runs on in memory
/// (like [PrefsKvStore] does) so the app still starts, only without remembering anything.
Future<KvStore> _openStore(String? profile) async {
  if (profile == null) return PrefsKvStore();
  try {
    return await JsonFileKvStore.openProfile(profile);
  } catch (_) {
    return MemoryKvStore();
  }
}

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  final demoUrl = _demoServer(args);
  final profile = demoUrl == null ? parseProfile(args) : 'portable-demo';
  // A profile keeps everything in a file of its own; without one the platform preferences are used.
  final KvStore store = demoUrl == null
      ? await _openStore(profile)
      : JsonFileKvStore(File(Platform.environment['TRADOCRAFT_DEMO_PROFILE']!));
  final session = demoUrl == null
      ? await SessionStore.load(store)
      : Session(serverUrl: demoUrl, devUser: 'admin@example.com');
  // The stored list of environments; an installation from before them gets its one session as
  // the first environment.
  final environments = demoUrl == null
      ? await EnvironmentStore.load(store, session)
      : EnvironmentStore.fromSession(session);
  // The active environment's sign-in is the session that is used.
  final active = environments.active.session;
  runApp(
    ProviderScope(
      overrides: [
        initialEnvironmentsProvider.overrideWithValue(environments),
        profileProvider.overrideWithValue(profile),
        kvStoreProvider.overrideWithValue(store),
        initialSessionProvider.overrideWithValue(active),
      ],
      child: const TradocraftApp(),
    ),
  );
}

String? _demoServer(List<String> args) {
  if (kIsWeb ||
      !Platform.isWindows ||
      !args.contains('--portable-demo') ||
      Platform.environment['TRADOCRAFT_DEMO_PROFILE']?.isNotEmpty != true) {
    return null;
  }
  final url = Platform.environment['TRADOCRAFT_DEMO_URL'];
  return url != null && RegExp(r'^http://127\.0\.0\.1:[0-9]+$').hasMatch(url)
      ? url
      : null;
}

class TradocraftApp extends ConsumerWidget {
  const TradocraftApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Keeps the list of environments following the session for as long as the app runs.
    ref.read(environmentsProvider);
    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: brandName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ref.watch(themeModeProvider),
      // The tutorial's spotlight and narrator sit inside the zoom, above every page and dialog.
      builder: (context, child) => ZoomShell(
        child: ShortcutsHost(
          child: TutorialHost(router: router, child: child ?? const SizedBox()),
        ),
      ),
      routerConfig: router,
      locale: ref.watch(localeProvider),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: [
        AppLocalizations.delegate,
        ...GlobalMaterialLocalizations.delegates,
      ],
      onGenerateTitle: (context) {
        final profile = ref.read(profileProvider);
        return appWindowTitle(profile);
      },
    );
  }
}
