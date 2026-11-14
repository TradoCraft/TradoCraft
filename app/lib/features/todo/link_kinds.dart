import 'package:flutter/widgets.dart';

import '../../app/api.dart' show TodoLinkKind;
import '../../l10n/l10n.dart';
import '../../shared/app_icons.dart';

/// What the app knows about one kind of record a to-do can be linked to (ADR 0061).
///
/// The kinds, their wire codes and the read permission that decides who may see a link of the
/// kind are fixed by the server (`crates/todo/src/link.rs`, `read_permission`): keep the
/// permission column in step with it. The route template is the app's own: the location of a link
/// is built from kind and id here, so it follows route changes of the app; the `link_location`
/// stored with the item is only a fallback (see [resolveLinkLocation]).
class LinkKindInfo {
  const LinkKindInfo(
    this.kind,
    this.template,
    this.label,
    this.icon,
    this.permission, {
    this.reserved = const {},
  });

  /// The kind on the wire (`TodoLinkKind.json`).
  final TodoLinkKind kind;

  /// The detail route with `{id}` where the record id goes, e.g. `/quotations/{id}`.
  final String template;

  /// The singular name of the kind, in the language of the user (the workspace tab labels).
  final String Function(AppLocalizations l) label;

  /// The icon of the kind.
  final IconData icon;

  /// The permission that lets a user read records of the kind (the server's mapping).
  final String permission;

  /// Names in the `{id}` position that are pages of the section, not records.
  final Set<String> reserved;

  /// The wire code, e.g. `purchase_order`.
  String get code => kind.json!;

  /// The location of record [id].
  String locationFor(String id) =>
      template.replaceFirst('{id}', Uri.encodeComponent(id));

  /// The record id of [segments] when they are a record location of this kind, else null.
  String? idIn(List<String> segments) {
    final t = template.substring(1).split('/');
    if (segments.length != t.length) return null;
    String? id;
    for (var i = 0; i < t.length; i++) {
      if (t[i] == '{id}') {
        id = segments[i];
      } else if (t[i] != segments[i]) {
        return null;
      }
    }
    if (id == null || id.isEmpty || id == 'new' || reserved.contains(id)) {
      return null;
    }
    return id;
  }
}

/// The 16 kinds, in the order of the server's list.
const linkKinds = <LinkKindInfo>[
  LinkKindInfo(
    TodoLinkKind.customer,
    '/customers/{id}',
    _customer,
    AppIcons.business,
    'customers.read',
  ),
  LinkKindInfo(
    TodoLinkKind.quotation,
    '/quotations/{id}',
    _quotation,
    AppIcons.requestQuote,
    'quotations.read',
  ),
  LinkKindInfo(
    TodoLinkKind.order,
    '/orders/{id}',
    _order,
    AppIcons.inventory,
    'orders.read',
  ),
  LinkKindInfo(
    TodoLinkKind.ticket,
    '/helpdesk/{id}',
    _ticket,
    AppIcons.supportAgent,
    'helpdesk.read',
    reserved: {'answers', 'settings', 'calendar', 'automation', 'reports'},
  ),
  LinkKindInfo(
    TodoLinkKind.repair,
    '/repairs/{id}',
    _repair,
    AppIcons.buildCircle,
    'repairs.read',
    reserved: {'departments'},
  ),
  LinkKindInfo(
    TodoLinkKind.job,
    '/jobs/{id}',
    _job,
    AppIcons.engineering,
    'field.read',
    reserved: {'contracts'},
  ),
  LinkKindInfo(
    TodoLinkKind.productionOrder,
    '/production/{id}',
    _production,
    AppIcons.precisionManufacturing,
    'production.read',
    reserved: {'release', 'divisions', 'work-centres', 'capacity'},
  ),
  LinkKindInfo(
    TodoLinkKind.delivery,
    '/delivery/{id}',
    _delivery,
    AppIcons.outbox,
    'delivery.read',
    reserved: {'settings'},
  ),
  LinkKindInfo(
    TodoLinkKind.product,
    '/products/{id}',
    _product,
    AppIcons.inventory2,
    'products.read',
  ),
  LinkKindInfo(
    TodoLinkKind.opportunity,
    '/opportunities/{id}',
    _opportunity,
    AppIcons.trendingUp,
    'opportunities.read',
  ),
  LinkKindInfo(
    TodoLinkKind.purchaseOrder,
    '/purchase-orders/{id}',
    _purchaseOrder,
    AppIcons.shoppingCart,
    'purchasing.read',
  ),
  LinkKindInfo(
    TodoLinkKind.goodsReceipt,
    '/goods-receipts/{id}',
    _goodsReceipt,
    AppIcons.moveToInbox,
    'purchasing.read',
  ),
  LinkKindInfo(
    TodoLinkKind.supplier,
    '/suppliers/{id}',
    _supplier,
    AppIcons.localShipping,
    'purchasing.read',
  ),
  LinkKindInfo(
    TodoLinkKind.supplierInvoice,
    '/supplier-invoices/{id}',
    _supplierInvoice,
    AppIcons.accountBalance,
    'finance.read',
  ),
  LinkKindInfo(
    TodoLinkKind.kbEntry,
    '/kb/{id}',
    _kbEntry,
    AppIcons.menuBook,
    'kb.read',
    reserved: {'categories'},
  ),
  LinkKindInfo(
    TodoLinkKind.stockCount,
    '/stock/counts/{id}',
    _stockCount,
    AppIcons.factCheck,
    'inventory.read',
  ),
];

String _customer(AppLocalizations l) => l.tabCustomer;
String _quotation(AppLocalizations l) => l.tabQuotation;
String _order(AppLocalizations l) => l.tabOrder;
String _ticket(AppLocalizations l) => l.tabTicket;
String _repair(AppLocalizations l) => l.tabRepair;
String _job(AppLocalizations l) => l.tabJob;
String _production(AppLocalizations l) => l.tabProductionOrder;
String _delivery(AppLocalizations l) => l.tabDeliveryNote;
String _product(AppLocalizations l) => l.tabProduct;
String _opportunity(AppLocalizations l) => l.tabOpportunity;
String _purchaseOrder(AppLocalizations l) => l.tabPurchaseOrder;
String _goodsReceipt(AppLocalizations l) => l.tabGoodsReceipt;
String _supplier(AppLocalizations l) => l.tabSupplier;
String _supplierInvoice(AppLocalizations l) => l.tabSupplierInvoice;
String _kbEntry(AppLocalizations l) => l.tabArticle;
String _stockCount(AppLocalizations l) => l.tabCount;

/// The registry entry of [kind], or null for an unknown kind (a newer server).
LinkKindInfo? linkKindInfo(TodoLinkKind? kind) {
  if (kind == null) return null;
  for (final k in linkKinds) {
    if (k.kind == kind) return k;
  }
  return null;
}

/// The location of record [id] of [kind]; null when the app has no route for the kind.
String? buildLinkLocation(TodoLinkKind kind, String id) =>
    linkKindInfo(kind)?.locationFor(id);

/// A record the app can link a to-do to.
class LinkRef {
  const LinkRef(this.info, this.id);

  final LinkKindInfo info;
  final String id;

  TodoLinkKind get kind => info.kind;

  /// The location of the record.
  String get location => info.locationFor(id);
}

/// The record that [location] shows, or null when it is not the detail page of a linkable record:
/// a list, a settings page or another non-record sub-route (`/helpdesk/answers`,
/// `/jobs/contracts`, `/quotations/new`, `/reports/...`, ...) has no object.
LinkRef? parseLinkLocation(String location) {
  final Uri uri;
  try {
    uri = Uri.parse(location);
  } on FormatException {
    return null;
  }
  final segments = uri.pathSegments;
  for (final k in linkKinds) {
    final id = k.idIn(segments);
    if (id != null) return LinkRef(k, id);
  }
  return null;
}

/// Where to jump for a stored link: the location built from kind and id, or [stored] (the
/// `link_location` saved with the item) when the kind has no route here. A stored location is only
/// used when it is a path inside the app (one leading slash). Null: nowhere to go.
String? resolveLinkLocation(TodoLinkKind? kind, String? id, {String? stored}) {
  if (kind != null && id != null) {
    final built = buildLinkLocation(kind, id);
    if (built != null) return built;
  }
  if (stored != null && stored.startsWith('/') && !stored.startsWith('//')) {
    return stored;
  }
  return null;
}
