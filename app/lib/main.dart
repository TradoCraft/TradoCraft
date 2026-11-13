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
  final profile = parseProfile(args);
  // A profile keeps everything in a file of its own; without one the platform preferences are used.
  final KvStore store = await _openStore(profile);
  final session = await SessionStore.load(store);
  // The stored list of environments; an installation from before them gets its one session as
  // the first environment.
  final environments = await EnvironmentStore.load(store, session);
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
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF2F5D62),
        visualDensity: VisualDensity.compact,
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(),
          isDense: true,
        ),
      ),
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
