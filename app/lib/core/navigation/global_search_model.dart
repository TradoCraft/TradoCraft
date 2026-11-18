import 'package:material_ui/material_ui.dart';

import '../../app/api.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/app_icons.dart';

/// One record found by the global search.
class SearchHit {
  const SearchHit({required this.title, required this.path, this.subtitle});

  final String title;
  final String? subtitle;

  /// The location that opens the record (a detail location becomes a workspace tab).
  final String path;
}

/// One entity the global search can ask: which permission it needs, how it is labelled, and how
/// to fetch the first matches from the server.
class SearchEntity {
  const SearchEntity({
    required this.id,
    required this.permission,
    required this.label,
    required this.icon,
    required this.fetch,
  });

  final String id;
  final String permission;
  final String Function(AppLocalizations l) label;
  final IconData icon;
  final Future<List<SearchHit>> Function(TradocraftApi api, String q, int limit)
  fetch;
}

/// The hits of one entity, or [failed] when that entity could not be searched.
class SearchGroup {
  const SearchGroup(this.entity, this.hits, {this.failed = false});

  final SearchEntity entity;
  final List<SearchHit> hits;
  final bool failed;
}

String _join(Iterable<String?> parts) =>
    parts.where((p) => p != null && p.trim().isNotEmpty).join(' · ');

/// The entities of the global search. Each uses the `q` parameter of its list endpoint, which
/// matches without regard to case and accents (ADR 0057).
final List<SearchEntity> globalSearchEntities = [
  SearchEntity(
    id: 'customers',
    permission: 'customers.read',
    label: (l) => l.customers,
    icon: AppIcons.business,
    fetch: (api, q, n) async => [
      for (final c in (await api.crm.listCustomers(q: q, limit: n)).items)
        SearchHit(
          title: c.name,
          subtitle: _join([c.code, c.city]),
          path: '/customers/${c.id}',
        ),
    ],
  ),
  SearchEntity(
    id: 'opportunities',
    permission: 'opportunities.read',
    label: (l) => l.opportunities,
    icon: AppIcons.trendingUp,
    fetch: (api, q, n) async => [
      for (final o in (await api.crm.listOpportunities(q: q, limit: n)).items)
        SearchHit(
          title: _join([o.number, o.title]),
          subtitle: o.customerName,
          path: '/opportunities/${o.id}',
        ),
    ],
  ),
  SearchEntity(
    id: 'quotations',
    permission: 'quotations.read',
    label: (l) => l.quotations,
    icon: AppIcons.requestQuote,
    fetch: (api, q, n) async => [
      for (final x in (await api.sales.listQuotations(q: q, limit: n)).items)
        SearchHit(
          title: x.number,
          subtitle: x.customerName,
          path: '/quotations/${x.id}',
        ),
    ],
  ),
  SearchEntity(
    id: 'orders',
    permission: 'orders.read',
    label: (l) => l.orders,
    icon: AppIcons.inventory,
    fetch: (api, q, n) async => [
      for (final o in (await api.sales.listOrders(q: q, limit: n)).items)
        SearchHit(
          title: o.number,
          subtitle: o.customerName,
          path: '/orders/${o.id}',
        ),
    ],
  ),
  SearchEntity(
    id: 'deliveries',
    permission: 'delivery.read',
    label: (l) => l.deliveries,
    icon: AppIcons.outbox,
    fetch: (api, q, n) async => [
      for (final d in (await api.delivery.listNotes(q: q, limit: n)).items)
        SearchHit(
          title: d.number,
          subtitle: _join([d.customerName, d.orderNumber]),
          path: '/delivery/${d.id}',
        ),
    ],
  ),
  SearchEntity(
    id: 'products',
    permission: 'products.read',
    label: (l) => l.products,
    icon: AppIcons.inventory2,
    fetch: (api, q, n) async => [
      for (final p in (await api.products.listProducts(q: q, limit: n)).items)
        SearchHit(title: p.name, subtitle: p.code, path: '/products/${p.id}'),
    ],
  ),
  SearchEntity(
    id: 'stock',
    permission: 'inventory.read',
    label: (l) => l.stockTitle,
    icon: AppIcons.warehouse,
    fetch: (api, q, n) async {
      // One hit per product: a product on several locations is one record to open.
      final seen = <String>{};
      return [
        for (final r in (await api.inventory.listStock(q: q, limit: n)).items)
          if (seen.add(r.productId))
            SearchHit(
              title: r.productName,
              subtitle: r.productCode,
              path: '/stock/products/${r.productId}',
            ),
      ];
    },
  ),
  SearchEntity(
    id: 'production',
    permission: 'production.read',
    label: (l) => l.production,
    icon: AppIcons.precisionManufacturing,
    fetch: (api, q, n) async => [
      for (final p in (await api.production.listOrders(q: q, limit: n)).items)
        SearchHit(
          title: p.number,
          subtitle: _join([p.productCode, p.productName]),
          path: '/production/${p.id}',
        ),
    ],
  ),
  SearchEntity(
    id: 'repairs',
    permission: 'repairs.read',
    label: (l) => l.repairs,
    icon: AppIcons.buildCircle,
    fetch: (api, q, n) async => [
      for (final r in (await api.repairs.listRepairs(q: q, limit: n)).items)
        SearchHit(
          title: r.number,
          subtitle: _join([r.productDescription, r.customerName]),
          path: '/repairs/${r.id}',
        ),
    ],
  ),
  SearchEntity(
    id: 'tickets',
    permission: 'helpdesk.read',
    label: (l) => l.helpdesk,
    icon: AppIcons.supportAgent,
    fetch: (api, q, n) async => [
      for (final t in (await api.helpdesk.listTickets(q: q, limit: n)).items)
        SearchHit(
          title: _join([t.number, t.subject]),
          subtitle: t.customerName,
          path: '/helpdesk/${t.id}',
        ),
    ],
  ),
  SearchEntity(
    id: 'kb',
    permission: 'kb.read',
    label: (l) => l.kbTitle,
    icon: AppIcons.menuBook,
    fetch: (api, q, n) async => [
      for (final e in await api.kb.listKbEntries(q: q, limit: n))
        SearchHit(title: e.title, subtitle: e.number, path: '/kb/${e.id}'),
    ],
  ),
  SearchEntity(
    id: 'suppliers',
    permission: 'purchasing.read',
    label: (l) => l.globalSearchSuppliers,
    icon: AppIcons.shoppingCart,
    // This endpoint has no `limit`: the list is cut here.
    fetch: (api, q, n) async => [
      for (final s in (await api.purchasing.listSuppliers(q: q)).take(n))
        SearchHit(title: s.name, subtitle: s.code, path: '/suppliers/${s.id}'),
    ],
  ),
  SearchEntity(
    id: 'supplier-invoices',
    permission: 'finance.read',
    label: (l) => l.globalSearchSupplierInvoices,
    icon: AppIcons.accountBalance,
    fetch: (api, q, n) async => [
      for (final i in (await api.finance.listInvoices(q: q, limit: n)).items)
        SearchHit(
          title: _join([i.number, i.invoiceNumber]),
          subtitle: i.supplierName,
          path: '/supplier-invoices/${i.id}',
        ),
    ],
  ),
];

/// The search itself, apart from any widget: asks every entity the user may read, in parallel,
/// and keeps going when one of them fails.
class GlobalSearch {
  GlobalSearch(
    this.api,
    this.permissions, {
    List<SearchEntity>? entities,
    this.limit = 5,
  }) : entities = entities ?? globalSearchEntities;

  final TradocraftApi api;

  /// The permissions of the signed-in user; null while unknown (nothing is asked then).
  final Set<String>? permissions;
  final List<SearchEntity> entities;
  final int limit;

  /// The entities this user may search.
  List<SearchEntity> get permitted => [
    for (final e in entities)
      if (permissions?.contains(e.permission) ?? false) e,
  ];

  /// The groups with hits, and the failed ones (so the UI can say so); entities without a match
  /// are left out. The order of [entities] is kept.
  Future<List<SearchGroup>> search(String query) async {
    final q = query.trim();
    if (q.isEmpty) return const [];
    final groups = await Future.wait([for (final e in permitted) _one(e, q)]);
    return [
      for (final g in groups)
        if (g.failed || g.hits.isNotEmpty) g,
    ];
  }

  Future<SearchGroup> _one(SearchEntity e, String q) async {
    try {
      return SearchGroup(e, await e.fetch(api, q, limit));
    } catch (_) {
      return SearchGroup(e, const [], failed: true);
    }
  }
}

/// Folds accents and case, for matching navigation destinations by label.
String foldForSearch(String s) {
  const from = 'àáâãäåçèéêëìíîïñòóôõöùúûüýÿ';
  const to = 'aaaaaaceeeeiiiinooooouuuuyy';
  final b = StringBuffer();
  for (final r in s.toLowerCase().runes) {
    final c = String.fromCharCode(r);
    final i = from.indexOf(c);
    b.write(i < 0 ? c : to[i]);
  }
  return b.toString();
}
