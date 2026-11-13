import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/admin/admin_page.dart';
import '../features/configurator/builder/builder_pages.dart';
import '../features/configurator/builder/revision_editor.dart';
import '../features/configurator/configurator_page.dart';
import '../features/configurator/runner_screen.dart';
import '../features/customers/customers_page.dart';
import '../features/delivery/deliveries_page.dart';
import '../features/production/divisions_page.dart';
import '../features/production/production_page.dart';
import '../features/production/release_page.dart';
import '../features/delivery/delivery_settings_page.dart';
import '../features/helpdesk/answers_page.dart';
import '../features/helpdesk/automation_page.dart';
import '../features/helpdesk/calendar_page.dart';
import '../features/helpdesk/helpdesk_settings_page.dart';
import '../features/helpdesk/reports_page.dart';
import '../features/reports/report_builder_page.dart';
import '../features/reports/report_screen.dart';
import '../features/reports/reports_page.dart';
import '../features/todo/todo_page.dart';
import '../features/helpdesk/tickets_page.dart';
import '../features/kb/kb_categories_page.dart';
import '../features/kb/kb_page.dart';
import '../features/field/contracts_page.dart';
import '../features/field/customer_equipment_page.dart';
import '../features/field/jobs_page.dart';
import '../features/inventory/counts_page.dart' show CountsPage;
import '../features/inventory/stock_page.dart';
import '../features/inventory/warehouses_page.dart';
import '../features/planning/planning_page.dart';
import '../features/planning/planning_settings_page.dart';
import '../features/orders/orders_page.dart';
import '../features/shipping/shipping_page.dart';
import '../features/login/login_page.dart';
import '../features/setup/setup_page.dart';
import '../features/opportunities/opportunities_page.dart';
import '../features/products/products_page.dart';
import '../features/finance/finance_page.dart';
import '../features/purchasing/purchasing_page.dart';
import '../features/packages/intake_page.dart';
import '../features/packages/receiving_page.dart';
import '../features/repairs/departments_page.dart';
import '../features/repairs/repairs_page.dart';
import '../features/quotations/quotations_page.dart';
import '../features/tutorial/chapter_map_page.dart';
import 'session.dart';
import '../features/field/offline/offline_ui.dart' show OfflineSyncHost;
import 'shell.dart';
import 'shortcuts/registry.dart' show ModalShortcutObserver, shortcutRegistryProvider;
import 'workspace.dart' show DetailPortal;

final routerProvider = Provider<GoRouter>((ref) {
  final signedIn = ValueNotifier(ref.read(sessionProvider).isSignedIn);
  ref.listen(sessionProvider, (_, s) => signedIn.value = s.isSignedIn);
  ref.onDispose(signedIn.dispose);

  return GoRouter(
    // Dialogs and popups are modal for keyboard shortcuts (see ModalShortcutObserver).
    observers: [ModalShortcutObserver(ref.read(shortcutRegistryProvider))],
    initialLocation: '/quotations',
    refreshListenable: signedIn,
    redirect: (context, state) {
      final atLogin =
          state.matchedLocation == '/login' ||
          state.matchedLocation == '/setup';
      if (!signedIn.value) return atLogin ? null : '/login';
      return atLogin ? '/quotations' : null;
    },
    routes: [
      GoRoute(path: '/login', builder: (_, _) => const LoginPage()),
      // Company setup wizard (ADR 0047); `?server=` names the server to set up.
      GoRoute(
        path: '/setup',
        builder: (_, state) =>
            SetupPage(server: state.uri.queryParameters['server']),
      ),
      GoRoute(path: '/tutorial', builder: (_, _) => const TutorialMapPage()),
      ShellRoute(
        // Bottom sheets and menus opened from a shell page use this navigator, not the root.
        observers: [ModalShortcutObserver(ref.read(shortcutRegistryProvider))],
        builder: (context, state, child) => OfflineSyncHost(
          child: AppShell(location: state.matchedLocation, child: child),
        ),
        routes: [
          GoRoute(
            path: '/quotations',
            builder: (_, _) => const QuotationsPage(),
          ),
          GoRoute(
            path: '/quotations/new',
            builder: (_, s) => DetailPortal(location: s.uri.toString()),
          ),
          GoRoute(
            path: '/quotations/:id',
            builder: (_, s) => DetailPortal(location: s.uri.toString()),
          ),
          GoRoute(
            path: '/configurator',
            builder: (_, s) =>
                ConfiguratorPage(customerId: s.uri.queryParameters['customer']),
          ),
          GoRoute(
            path: '/configurator/builder',
            builder: (_, _) => const BuilderModelsPage(),
          ),
          GoRoute(
            path: '/configurator/builder/models/:id',
            builder: (_, s) => ModelPage(
              key: ValueKey(s.pathParameters['id']),
              id: s.pathParameters['id']!,
            ),
          ),
          GoRoute(
            path: '/configurator/builder/revisions/:id',
            builder: (_, s) => RevisionEditorScreen(
              key: ValueKey(s.pathParameters['id']),
              id: s.pathParameters['id']!,
            ),
          ),
          GoRoute(
            path: '/configurator/configurations/:id',
            builder: (_, s) => RunnerScreen(
              key: ValueKey(s.pathParameters['id']),
              id: s.pathParameters['id']!,
            ),
          ),
          GoRoute(path: '/helpdesk', builder: (_, _) => const TicketsPage()),
          GoRoute(
            path: '/helpdesk/answers',
            builder: (_, _) => const AnswersPage(),
          ),
          GoRoute(
            path: '/helpdesk/settings',
            builder: (_, _) => const HelpdeskSettingsPage(),
          ),
          GoRoute(
            path: '/helpdesk/calendar',
            builder: (_, _) => const CalendarPage(),
          ),
          GoRoute(
            path: '/helpdesk/automation',
            builder: (_, _) => const AutomationPage(),
          ),
          GoRoute(
            path: '/helpdesk/reports',
            builder: (_, _) => const ReportsPage(),
          ),
          GoRoute(
            path: '/helpdesk/:id',
            builder: (_, s) => DetailPortal(location: s.uri.toString()),
          ),
          GoRoute(path: '/todo', builder: (_, _) => const TodoPage()),
          GoRoute(
            path: '/reports',
            builder: (_, _) => const SavedReportsPage(),
          ),
          GoRoute(
            path: '/reports/new',
            builder: (_, _) => const ReportBuilderPage(),
          ),
          GoRoute(
            path: '/reports/:id',
            builder: (_, s) => SavedReportScreen(
              key: ValueKey(s.pathParameters['id']),
              id: s.pathParameters['id']!,
            ),
          ),
          GoRoute(
            path: '/reports/:id/edit',
            builder: (_, s) => ReportBuilderPage(
              key: ValueKey(s.pathParameters['id']),
              id: s.pathParameters['id'],
            ),
          ),
          GoRoute(path: '/kb', builder: (_, _) => const KbPage()),
          GoRoute(
            path: '/kb/categories',
            builder: (_, _) => const KbCategoriesPage(),
          ),
          GoRoute(
            path: '/kb/:id',
            builder: (_, s) => DetailPortal(location: s.uri.toString()),
          ),
          GoRoute(path: '/repairs', builder: (_, _) => const RepairsPage()),
          GoRoute(
            path: '/repairs/departments',
            builder: (_, _) => const DepartmentsPage(),
          ),
          GoRoute(
            path: '/repairs/:id',
            builder: (_, s) => DetailPortal(location: s.uri.toString()),
          ),
          GoRoute(path: '/packages', builder: (_, _) => const ReceivingPage()),
          GoRoute(path: '/intake', builder: (_, _) => const IntakePage()),
          GoRoute(path: '/jobs', builder: (_, _) => const JobsPage()),
          GoRoute(
            path: '/jobs/contracts',
            builder: (_, _) => const ContractsPage(),
          ),
          GoRoute(
            path: '/jobs/contracts/:id',
            builder: (_, s) => DetailPortal(location: s.uri.toString()),
          ),
          GoRoute(
            path: '/jobs/equipment/:customerId',
            builder: (_, s) => CustomerEquipmentPage(
              customerId: s.pathParameters['customerId']!,
            ),
          ),
          GoRoute(
            path: '/jobs/:id',
            builder: (_, s) => DetailPortal(location: s.uri.toString()),
          ),
          GoRoute(path: '/planning', builder: (_, _) => const PlanningPage()),
          GoRoute(
            path: '/planning/settings',
            builder: (_, _) => const PlanningSettingsPage(),
          ),
          GoRoute(path: '/orders', builder: (_, _) => const OrdersPage()),
          GoRoute(
            path: '/orders/:id',
            builder: (_, s) => DetailPortal(location: s.uri.toString()),
          ),
          GoRoute(
            path: '/production',
            builder: (_, _) => const ProductionQueuePage(),
          ),
          GoRoute(
            path: '/production/release',
            builder: (_, _) => const ReleasePage(),
          ),
          GoRoute(
            path: '/production/divisions',
            builder: (_, _) => const DivisionsPage(),
          ),
          GoRoute(
            path: '/production/:id',
            builder: (_, s) => DetailPortal(location: s.uri.toString()),
          ),
          GoRoute(path: '/delivery', builder: (_, _) => const DeliveriesPage()),
          GoRoute(
            path: '/delivery/settings',
            builder: (_, _) => const DeliverySettingsPage(),
          ),
          GoRoute(
            path: '/delivery/:id',
            builder: (_, s) => DetailPortal(location: s.uri.toString()),
          ),
          GoRoute(path: '/shipping', builder: (_, _) => const ShippingPage()),
          GoRoute(path: '/stock', builder: (_, _) => const StockPage()),
          GoRoute(
            path: '/stock/warehouses',
            builder: (_, _) => const WarehousesPage(),
          ),
          GoRoute(path: '/stock/counts', builder: (_, _) => const CountsPage()),
          GoRoute(
            path: '/stock/counts/:id',
            builder: (_, s) => DetailPortal(location: s.uri.toString()),
          ),
          GoRoute(
            path: '/stock/products/:id',
            builder: (_, s) => DetailPortal(location: s.uri.toString()),
          ),
          GoRoute(path: '/customers', builder: (_, _) => const CustomersPage()),
          GoRoute(
            path: '/customers/:id',
            builder: (_, s) => DetailPortal(location: s.uri.toString()),
          ),
          GoRoute(path: '/products', builder: (_, _) => const ProductsPage()),
          GoRoute(
            path: '/products/:id',
            builder: (_, s) => DetailPortal(location: s.uri.toString()),
          ),
          GoRoute(
            path: '/purchasing',
            builder: (_, _) => const PurchasingPage(),
          ),
          GoRoute(path: '/finance', builder: (_, _) => const FinancePage()),
          GoRoute(
            path: '/supplier-invoices/:id',
            builder: (_, s) => DetailPortal(location: s.uri.toString()),
          ),
          GoRoute(
            path: '/purchase-orders/:id',
            builder: (_, s) => DetailPortal(location: s.uri.toString()),
          ),
          GoRoute(
            path: '/goods-receipts/:id',
            builder: (_, s) => DetailPortal(location: s.uri.toString()),
          ),
          GoRoute(
            path: '/suppliers/:id',
            builder: (_, s) => DetailPortal(location: s.uri.toString()),
          ),
          GoRoute(path: '/admin', builder: (_, _) => const AdminPage()),
          GoRoute(
            path: '/opportunities',
            builder: (_, _) => const OpportunitiesPage(),
          ),
          GoRoute(
            path: '/opportunities/:id',
            builder: (_, s) => DetailPortal(location: s.uri.toString()),
          ),
        ],
      ),
    ],
  );
});
