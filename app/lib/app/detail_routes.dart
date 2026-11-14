import 'package:flutter/widgets.dart';

import '../features/customers/customer_screen.dart';
import '../features/delivery/delivery_screen.dart';
import '../features/field/contract_screen.dart';
import '../features/field/job_screen.dart';
import '../features/helpdesk/ticket_screen.dart';
import '../features/inventory/counts_page.dart' show CountScreen;
import '../features/inventory/product_stock_screen.dart';
import '../features/kb/kb_entry_screen.dart';
import '../features/opportunities/opportunity_screen.dart';
import '../features/orders/order_screen.dart';
import '../features/production/production_screen.dart';
import '../features/products/product_screen.dart';
import '../features/finance/invoice_screen.dart';
import '../features/purchasing/order_screen.dart';
import '../features/purchasing/receipt_screen.dart';
import '../features/purchasing/supplier_screen.dart';
import '../features/quotations/quotation_screen.dart';
import '../features/repairs/repair_screen.dart';

/// The detail screens that open in a workspace tab (a ticket, a quotation, an order, ...), as
/// opposed to the section lists and their settings pages, which stay in the main area.
///
/// Returns null when [uri] is not a detail location. Every screen gets a key made of the location,
/// so a screen is never reused for another record.
Widget? detailScreen(Uri uri) {
  final s = uri.pathSegments;
  if (s.length < 2) return null;
  final key = ValueKey(uri.toString());
  final id = s[1];
  switch (s[0]) {
    case 'quotations' when s.length == 2:
      return id == 'new'
          ? QuotationScreen(
              key: key,
              customerId: uri.queryParameters['customer'],
              opportunityId: uri.queryParameters['opportunity'],
            )
          : QuotationScreen(key: key, id: id);
    case 'helpdesk'
        when s.length == 2 &&
            !const {
              'answers',
              'settings',
              'calendar',
              'automation',
              'reports',
            }.contains(id):
      return TicketScreen(key: key, id: id);
    case 'kb' when s.length == 2 && id != 'categories':
      return KbEntryScreen(key: key, id: id);
    case 'repairs' when s.length == 2 && id != 'departments':
      return RepairScreen(key: key, id: id);
    case 'jobs' when s.length == 2 && id != 'contracts':
      return JobScreen(key: key, id: id);
    case 'jobs' when s.length == 3 && id == 'contracts':
      return ContractScreen(key: key, id: s[2] == 'new' ? null : s[2]);
    case 'orders' when s.length == 2:
      return OrderScreen(key: key, id: id);
    case 'production'
        when s.length == 2 && !const {'release', 'divisions'}.contains(id):
      return ProductionScreen(key: key, id: id);
    case 'delivery' when s.length == 2 && id != 'settings':
      return DeliveryScreen(key: key, id: id);
    case 'suppliers' when s.length == 2:
      return SupplierScreen(key: key, id: id);
    case 'supplier-invoices' when s.length == 2:
      return SupplierInvoiceScreen(key: key, id: id);
    case 'purchase-orders' when s.length == 2:
      return PurchaseOrderScreen(key: key, id: id);
    case 'goods-receipts' when s.length == 2:
      return GoodsReceiptScreen(key: key, id: id);
    case 'customers' when s.length == 2:
      return CustomerScreen(key: key, id: id);
    case 'products' when s.length == 2:
      return ProductScreen(key: key, id: id);
    case 'opportunities' when s.length == 2:
      return OpportunityScreen(key: key, id: id);
    case 'stock' when s.length == 3 && id == 'products':
      return ProductStockScreen(key: key, id: s[2]);
    case 'stock' when s.length == 3 && id == 'counts':
      return CountScreen(key: key, id: s[2]);
  }
  return null;
}

/// Whether [location] is a detail location, i.e. whether [detailScreen] accepts it. The screen is
/// only created, never built, so this stays cheap.
bool isDetailLocation(String location) =>
    detailScreen(Uri.parse(location)) != null;
