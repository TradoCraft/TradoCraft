import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../api/generated/export.dart';
import '../l10n/l10n.dart';
import 'portal_csat.dart';
import 'portal_help.dart';
import 'portal_orders.dart';
import 'portal_pages.dart';
import 'portal_repairs.dart';
import 'portal_state.dart';
import '../shared/app_icons.dart';

final portalRouterProvider = Provider<GoRouter>((ref) {
  final signedIn = ValueNotifier(ref.read(portalTokenProvider) != null);
  ref.listen(portalTokenProvider, (_, t) => signedIn.value = t != null);
  ref.onDispose(signedIn.dispose);

  return GoRouter(
    initialLocation: '/',
    refreshListenable: signedIn,
    redirect: (context, state) {
      // The satisfaction survey needs no login: the link is the credential.
      if (state.matchedLocation == '/csat') return null;
      final atLogin = state.matchedLocation == '/login';
      if (!signedIn.value) return atLogin ? null : '/login';
      return atLogin ? '/' : null;
    },
    routes: [
      GoRoute(path: '/login', builder: (_, _) => const PortalLoginPage()),
      GoRoute(
        path: '/csat',
        builder: (_, _) =>
            PortalCsatPage(link: ref.read(initialCsatLinkProvider)),
      ),
      ShellRoute(
        builder: (context, state, child) => PortalShell(child: child),
        routes: [
          GoRoute(path: '/', builder: (_, _) => const PortalTicketsPage()),
          GoRoute(
            path: '/tickets/new',
            builder: (_, _) => const PortalNewTicketPage(),
          ),
          GoRoute(
            path: '/tickets/:id',
            builder: (_, s) => PortalTicketPage(id: s.pathParameters['id']!),
          ),
          GoRoute(
            path: '/repairs',
            builder: (_, _) => const PortalRepairsPage(),
          ),
          GoRoute(
            path: '/repairs/new',
            builder: (_, _) => const PortalAnnounceRepairPage(),
          ),
          GoRoute(
            path: '/repairs/:id',
            builder: (_, s) => PortalRepairPage(id: s.pathParameters['id']!),
          ),
          GoRoute(path: '/help', builder: (_, _) => const PortalHelpPage()),
          GoRoute(
            path: '/help/:id',
            builder: (_, s) => PortalHelpArticlePage(
              key: ValueKey(s.pathParameters['id']),
              id: s.pathParameters['id']!,
            ),
          ),
          GoRoute(path: '/orders', builder: (_, _) => const PortalOrdersPage()),
          GoRoute(
            path: '/orders/:id',
            builder: (_, s) => PortalOrderPage(id: s.pathParameters['id']!),
          ),
          GoRoute(
            path: '/profile',
            builder: (_, _) => const PortalProfilePage(),
          ),
        ],
      ),
    ],
  );
});

/// The customer portal: sign in with an e-mailed link, see and raise tickets, set how we address you.
class PortalApp extends ConsumerWidget {
  const PortalApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'Customer portal',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF2F5D62),
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(),
          isDense: true,
        ),
      ),
      routerConfig: ref.watch(portalRouterProvider),
      locale: ref.watch(portalLocaleProvider),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: [AppLocalizations.delegate, ...GlobalMaterialLocalizations.delegates],
      onGenerateTitle: (context) => context.l10n.portalTitle,
    );
  }
}

/// App bar and navigation around the signed-in pages. Also switches the portal to the language
/// of the person once their profile is known.
class PortalShell extends ConsumerWidget {
  const PortalShell({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    ref.listen<AsyncValue<PortalProfile>>(portalProfileProvider, (_, p) {
      final profile = p.value;
      if (profile != null) {
        ref
            .read(portalLocaleProvider.notifier)
            .set(Locale(profile.effectiveLanguage));
      }
    });
    final profile = ref.watch(portalProfileProvider).value;
    return Scaffold(
      appBar: AppBar(
        title: InkWell(
          onTap: () => context.go('/'),
          child: Text(
            profile == null
                ? l.portalTitle
                : '${l.portalTitle} · ${profile.customerName}',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => context.go('/'),
            child: Text(l.myTickets),
          ),
          TextButton(
            onPressed: () => context.go('/orders'),
            child: Text(l.myOrders),
          ),
          TextButton(
            onPressed: () => context.go('/help'),
            child: Text(l.kbHelp),
          ),
          TextButton(
            onPressed: () => context.go('/repairs'),
            child: Text(l.myRepairs),
          ),
          if (profile != null)
            Center(
              child: Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Text(
                  l.signedInAs(profile.fullName),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ),
          IconButton(
            tooltip: l.myProfile,
            icon: const Icon(AppIcons.person),
            onPressed: () => context.go('/profile'),
          ),
          IconButton(
            tooltip: l.signOut,
            icon: const Icon(AppIcons.logout),
            onPressed: () async {
              try {
                await ref.read(portalApiProvider).endSession();
              } catch (_) {
                // The session may already be gone; signing out locally is what matters.
              }
              await ref.read(portalTokenProvider.notifier).set(null);
              ref.invalidate(portalProfileProvider);
            },
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 860),
          child: child,
        ),
      ),
    );
  }
}
