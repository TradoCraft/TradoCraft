import '../../app/shell.dart';
import '../../l10n/l10n.dart';
import 'model.dart';

/// Includes the in-module tab when the module alone does not locate the task.
String? tutorialMenuPath(
  AppLocalizations l,
  Mission mission,
  MissionStep step,
) {
  final route = step.route;
  if (route == null) return null;
  final module = moduleMenuPath(l, route);
  if (module.isEmpty) return null;
  final tab = switch ((mission.id, step.id)) {
    ('product', 'bomTab' || 'revision' || 'lines' || 'activate') =>
      l.billOfMaterials,
    ('suppliers', _)
        when route == '/purchasing' || route.startsWith('/suppliers/') =>
      l.purchSuppliers,
    (_, _)
        when route.startsWith('/purchase-orders/') ||
            (route == '/purchasing' && mission.id == 'buying') =>
      l.purchOrders,
    (_, _) when route.startsWith('/supplier-invoices/') =>
      l.finSupplierInvoices,
    (_, _) when route == '/stock/warehouses' => l.stockWarehouses,
    (_, _) when route == '/production/divisions' => l.productionDivisions,
    (_, _) when route == '/production/release' => l.productionToRelease,
    (_, _) when route == '/helpdesk/answers' => l.preparedAnswers,
    ('invoices', 'tolerances') => l.finSettings,
    ('invoices', 'second') => l.finSupplierInvoices,
    ('prices', 'openAdmin' || 'zone') => l.adminPriceZones,
    ('prices', 'priceExport' || 'priceHome') => l.prices,
    _ => null,
  };
  return [...module, ?tab].join(' › ');
}

/// The actual controls and fields used in the manual flow. The chapter text
/// supplies the exercise values and explains the expected result.
List<String> tutorialManualActions(
  AppLocalizations l,
  Mission mission,
  MissionStep step,
) => switch ((mission.id, step.id)) {
  (_, 'warehouse') => [
    l.stockNewWarehouse,
    [l.code, l.name].join(', '),
    l.save,
  ],
  ('product', 'motor' || 'frame' || 'controller' || 'cart') => [
    l.newProduct,
    [l.code, l.name, l.type].join(', '),
    l.save,
  ],
  ('product', 'revision') => [l.newRevision],
  ('product', 'lines') => [l.addComponent, l.saveDraft],
  ('product', 'activate') => [l.activate],
  ('suppliers', 'supplierA' || 'supplierB') => [
    l.purchNewSupplier,
    [l.code, l.name].join(', '),
    l.save,
  ],
  ('suppliers', _) => [
    l.purchPriceList,
    l.purchAddProduct,
    [l.unitPrice, l.purchLeadTimeDays, l.purchMoq].join(', '),
    l.save,
  ],
  ('buying', 'order') => [
    l.purchNewOrder,
    l.purchSupplier,
    [l.products, l.quantity].join(', '),
    l.save,
  ],
  ('buying', 'approve') => [l.purchApprove],
  ('buying', 'send') => [l.send],
  ('buying', 'receiveRest') => [
    l.purchReceiveGoods,
    [l.purchReceiveDestination, l.purchReceiveQty].join(', '),
    l.purchReceiveGoods,
  ],
  ('manufacturing', 'division') => [
    l.productionDivisionAdd,
    [l.code, l.name, l.productionDivisionMembers].join(', '),
    l.save,
  ],
  ('prices', 'zone') => [
    l.newPriceZone,
    [l.code, l.name].join(', '),
    l.save,
  ],
  ('prices', 'priceExport' || 'priceHome') => [
    l.newPrice,
    [l.priceZone, l.unitPrice].join(', '),
    l.save,
  ],
  ('customer', 'createCustomer') => [
    l.newCustomer,
    [l.code, l.name, l.vatNumber, l.priceZone].join(', '),
    l.save,
  ],
  ('customer', 'linked') => [l.customer, l.saveChanges],
  ('quotation', 'create') => [
    l.newQuotation,
    l.customer,
    [l.products, l.quantity].join(', '),
    l.save,
  ],
  _ => const [],
};
