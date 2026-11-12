import 'missions_production.dart' show tutorialZoneCode;
import 'model.dart';
import 'simulated_mail.dart';

/// Chapters 7 to 9: a new customer writes in, the quotation, the change and the order.

Map? _first(Object? list, bool Function(Map) test) {
  final items = list is Map ? list['items'] : list;
  if (items is! List) return null;
  for (final i in items) {
    if (i is Map && test(i)) return i;
  }
  return null;
}

bool _isTutorialTicket(Map t) => t['contact_email'] == tutorialCustomerMail;

bool _isTutorialCustomer(Map c) =>
    '${c['name']}'.toLowerCase().contains('brightwheel');

Map<String, String> _mailCapture(InboundMailResult r, {String? idKey}) => {
  'ticketId': r.ticketId,
  'ticketNumber': r.ticketNumber,
  ?idKey: r.messageId,
};

Map<String, String> _customerCapture(Object? json, MissionContext ctx) {
  final c = _first(json, _isTutorialCustomer);
  return c == null ? const {} : {'customerId': '${c['id']}'};
}

bool _customerExists(Object? json, MissionContext ctx) =>
    _first(json, _isTutorialCustomer) != null;

/// A probe that finds the customer of chapter 7 and captures its id.
const customerProbe = Probe(
  '/api/v1/customers',
  query: {'q': 'Brightwheel', 'limit': 20},
  done: _customerExists,
  capture: _customerCapture,
);

/// Chapter 7: a customer e-mail becomes a ticket; the sender is a new customer.
final customerMission = Mission(
  id: 'customer',
  steps: [
    MissionStep(
      id: 'needs',
      probe: Probe(
        '/api/v1/price-zones',
        done: (json, _) => _first(json, (z) => z['code'] == tutorialZoneCode) != null,
        capture: (json, _) {
          final z = _first(json, (z) => z['code'] == tutorialZoneCode);
          return z == null ? const {} : {'zoneId': '${z['id']}'};
        },
      ),
    ),
    MissionStep(
      id: 'mail1',
      completion: ActionCompletion((host) async {
        final r = await sendTutorialMail(
          host.dio,
          kind: TutorialMailKind.request,
          lang: host.languageCode,
          messageId: host.messageId('request'),
        );
        return _mailCapture(r, idKey: 'mailId1');
      }),
      probe: Probe(
        '/api/v1/tickets',
        query: {'q': 'TUT-CART', 'limit': 50},
        done: (json, _) => _first(json, _isTutorialTicket) != null,
        capture: (json, _) {
          final t = _first(json, _isTutorialTicket);
          return t == null
              ? const {}
              : {'ticketId': '${t['id']}', 'ticketNumber': '${t['number']}'};
        },
      ),
    ),
    const MissionStep(
      id: 'openHelpdesk',
      route: '/helpdesk',
      completion: OnRoute(r'/helpdesk(\?.*)?$'),
    ),
    MissionStep(
      id: 'openTicket',
      route: '/helpdesk/{ticketId}',
      completion: const OnRoute('/helpdesk/{ticketId}'),
    ),
    MissionStep(
      id: 'reply',
      hasHint: true,
      route: '/helpdesk/{ticketId}',
      targets: const ['ticket-send'],
      completion: const OnApi('POST', '/tickets/{ticketId}/replies'),
    ),
    MissionStep(
      id: 'mail2',
      completion: ActionCompletion((host) async {
        final v = host.context.values;
        final r = await sendTutorialMail(
          host.dio,
          kind: TutorialMailKind.details,
          lang: host.languageCode,
          messageId: host.messageId('details'),
          inReplyTo: v['mailId1'],
          ticketNumber: v['ticketNumber'],
        );
        return _mailCapture(r, idKey: 'mailId2');
      }),
    ),
    MissionStep(id: 'readDetails', route: '/helpdesk/{ticketId}'),
    MissionStep(
      id: 'createCustomer',
      hasHint: true,
      route: '/helpdesk/{ticketId}',
      targets: const ['customer-form-save', 'ticket-new-customer'],
      completion: OnApi(
        'POST',
        '/customers',
        predicate: (json, _) => json is Map && _isTutorialCustomer(json),
      ),
      capture: (json) => json is Map ? {'customerId': '${json['id']}'} : const {},
      probe: customerProbe,
    ),
    MissionStep(
      id: 'linked',
      route: '/helpdesk/{ticketId}',
      targets: const ['ticket-new-quotation'],
    ),
    const MissionStep(id: 'done'),
  ],
);

bool _qStatus(Object? json, Set<String> statuses) =>
    json is Map && statuses.contains(json['status']);

/// Whether the quotation [json] has a line for the cart with exactly [quantity] pieces.
bool _hasCartQuantity(Object? json, MissionContext ctx, num quantity) {
  final lines = json is Map ? json['lines'] : null;
  if (lines is! List) return false;
  for (final l in lines) {
    if (l is Map && l['product_id'] == ctx.values['cartId']) {
      final q = num.tryParse('${l['quantity']}');
      if (q != null && q == quantity) return true;
    }
  }
  return false;
}

/// The paths of the full records of the quotations in a list answer.
List<String> _quotationPaths(Object? page, MissionContext ctx) {
  final items = page is Map ? page['items'] : page;
  return [
    if (items is List)
      for (final i in items)
        if (i is Map && i['id'] != null) '/api/v1/quotations/${i['id']}',
  ];
}

/// The first quotation of the tutorial customer for 8 carts (a full record from [details]).
Map? _firstQuotation(Object? details, MissionContext ctx) {
  if (details is! List) return null;
  for (final q in details) {
    if (q is Map &&
        q['customer_id'] == ctx.values['customerId'] &&
        q['supersedes_id'] == null &&
        _hasCartQuantity(q, ctx, 8)) {
      return q;
    }
  }
  return null;
}

/// The revision of the quotation `quotationId`: it points back at it and has a later revision
/// number than 1 (a full record from [details]). The creation and discovery paths pick the same one.
Map? _revisionOf(Object? details, MissionContext ctx) {
  if (details is! List) return null;
  for (final q in details) {
    if (q is Map &&
        q['supersedes_id'] == ctx.values['quotationId'] &&
        ((q['revision'] as num?) ?? 0) > 1) {
      return q;
    }
  }
  return null;
}

/// Chapter 8: a quotation for the new customer, a note from production, sent.
final quotationMission = Mission(
  id: 'quotation',
  steps: [
    const MissionStep(id: 'needs', probe: customerProbe),
    const MissionStep(
      id: 'openQuotations',
      route: '/quotations',
      targets: ['quotations-create'],
      completion: OnRoute(r'/quotations(\?.*)?$'),
    ),
    MissionStep(
      id: 'create',
      hasHint: true,
      route: '/quotations/new?customer={customerId}',
      targets: const ['quotation-save', 'quotations-create'],
      completion: OnApi(
        'POST',
        '/quotations',
        predicate: (json, ctx) =>
            json is Map &&
            json['customer_id'] == ctx.values['customerId'] &&
            _hasCartQuantity(json, ctx, 8),
      ),
      capture: (json) => json is Map ? {'quotationId': '${json['id']}'} : const {},
      probe: Probe(
        '/api/v1/quotations',
        query: {'customer_id': '{customerId}', 'limit': 20},
        expand: _quotationPaths,
        done: (details, ctx) => _firstQuotation(details, ctx) != null,
        capture: (details, ctx) {
          final q = _firstQuotation(details, ctx);
          return q == null ? const {} : {'quotationId': '${q['id']}'};
        },
      ),
    ),
    MissionStep(
      id: 'lead',
      hasHint: true,
      route: '/quotations/{quotationId}',
      targets: const ['quotation-save'],
      completion: OnApi(
        'PUT',
        '/quotations/{quotationId}',
        predicate: (json, _) =>
            json is Map && '${json['notes'] ?? ''}'.trim().isNotEmpty,
      ),
      probe: Probe(
        '/api/v1/quotations/{quotationId}',
        done: (json, _) =>
            json is Map && '${json['notes'] ?? ''}'.trim().isNotEmpty,
      ),
    ),
    MissionStep(
      id: 'send',
      route: '/quotations/{quotationId}',
      targets: const ['quotation-send'],
      completion: const OnApi('POST', '/quotations/{quotationId}/send'),
      probe: Probe(
        '/api/v1/quotations/{quotationId}',
        done: (json, _) => _qStatus(json, {'sent', 'accepted', 'superseded'}),
      ),
    ),
    MissionStep(
      id: 'pdf',
      hasHint: true,
      route: '/quotations/{quotationId}',
      targets: const ['quotation-pdf'],
    ),
    const MissionStep(id: 'done'),
  ],
);

bool _orderStatusNot(Object? json, Set<String> statuses) {
  final o = json is Map ? json['order'] : null;
  return o is Map && !statuses.contains(o['status']);
}

bool _productionStatus(Object? json, Set<String> statuses) =>
    json is Map && statuses.contains(json['status']);

/// Chapter 9: the customer wants a change; revision, order, production, and some units for stock.
final changeMission = Mission(
  id: 'change',
  steps: [
    MissionStep(
      id: 'needs',
      probe: Probe(
        '/api/v1/quotations/{quotationId}',
        done: (json, _) => _qStatus(json, {'sent', 'accepted', 'superseded'}),
      ),
    ),
    MissionStep(
      id: 'mail3',
      completion: ActionCompletion((host) async {
        final v = host.context.values;
        final r = await sendTutorialMail(
          host.dio,
          kind: TutorialMailKind.change,
          lang: host.languageCode,
          messageId: host.messageId('change'),
          inReplyTo: v['mailId1'],
          ticketNumber: v['ticketNumber'],
        );
        return _mailCapture(r);
      }),
    ),
    MissionStep(
      id: 'openQuote',
      route: '/quotations/{quotationId}',
      completion: const OnRoute('/quotations/{quotationId}'),
    ),
    MissionStep(
      id: 'revise',
      hasHint: true,
      route: '/quotations/{quotationId}',
      targets: const ['quotation-revise-keep', 'quotation-revise'],
      completion: OnApi(
        'POST',
        '/quotations/{quotationId}/revise',
        predicate: (json, ctx) =>
            json is Map && json['supersedes_id'] == ctx.values['quotationId'],
      ),
      capture: (json) => json is Map ? {'quotation2Id': '${json['id']}'} : const {},
      probe: Probe(
        '/api/v1/quotations',
        query: {'customer_id': '{customerId}', 'limit': 20},
        expand: _quotationPaths,
        done: (details, ctx) => _revisionOf(details, ctx) != null,
        capture: (details, ctx) {
          final q = _revisionOf(details, ctx);
          return q == null ? const {} : {'quotation2Id': '${q['id']}'};
        },
      ),
    ),
    MissionStep(
      id: 'edit',
      hasHint: true,
      route: '/quotations/{quotation2Id}',
      targets: const ['quotation-save'],
      completion: OnApi(
        'PUT',
        '/quotations/{quotation2Id}',
        predicate: (json, ctx) => _hasCartQuantity(json, ctx, 10),
      ),
      probe: Probe(
        '/api/v1/quotations/{quotation2Id}',
        done: (json, ctx) => _hasCartQuantity(json, ctx, 10),
      ),
    ),
    MissionStep(
      id: 'send',
      route: '/quotations/{quotation2Id}',
      targets: const ['quotation-send'],
      completion: const OnApi('POST', '/quotations/{quotation2Id}/send'),
      probe: Probe(
        '/api/v1/quotations/{quotation2Id}',
        done: (json, _) => _qStatus(json, {'sent', 'accepted'}),
      ),
    ),
    MissionStep(
      id: 'accept',
      route: '/quotations/{quotation2Id}',
      targets: const ['quotation-accept'],
      completion: const OnApi('POST', '/quotations/{quotation2Id}/accept'),
      probe: Probe(
        '/api/v1/quotations/{quotation2Id}',
        done: (json, _) => _qStatus(json, {'accepted'}),
      ),
    ),
    MissionStep(
      id: 'convert',
      hasHint: true,
      route: '/quotations/{quotation2Id}',
      targets: const ['quotation-convert'],
      completion: const OnApi('POST', '/quotations/{quotation2Id}/convert'),
      capture: (json) {
        final o = json is Map ? json['order'] : null;
        return o is Map ? {'orderId': '${o['id']}'} : const {};
      },
    ),
    MissionStep(
      id: 'openOrder',
      route: '/orders/{orderId}',
      completion: const OnRoute('/orders/{orderId}'),
    ),
    MissionStep(
      id: 'sendOrder',
      hasHint: true,
      route: '/orders/{orderId}',
      targets: const ['order-send'],
      completion: const OnApi('POST', '/orders/{orderId}/send'),
      probe: Probe(
        '/api/v1/orders/{orderId}',
        done: (json, _) => _orderStatusNot(json, {'draft'}),
      ),
    ),
    MissionStep(
      id: 'confirm',
      route: '/orders/{orderId}',
      targets: const ['order-confirm'],
      completion: const OnApi('POST', '/orders/{orderId}/confirm'),
      probe: Probe(
        '/api/v1/orders/{orderId}',
        done: (json, _) => _orderStatusNot(json, {'draft', 'sent'}),
      ),
    ),
    MissionStep(
      id: 'release',
      route: '/production/release',
      targets: const ['production-release-line'],
      completion: OnApi(
        'POST',
        '/production-orders',
        predicate: (json, ctx) =>
            json is Map && json['order_id'] == ctx.values['orderId'],
      ),
      capture: (json) =>
          json is Map ? {'orderProductionId': '${json['id']}'} : const {},
      probe: Probe(
        '/api/v1/production-orders',
        query: {'order_id': '{orderId}'},
        done: (json, _) => _first(json, (o) => o['status'] != 'cancelled') != null,
        capture: (json, _) {
          final o = _first(json, (o) => o['status'] != 'cancelled');
          return o == null ? const {} : {'orderProductionId': '${o['id']}'};
        },
      ),
    ),
    MissionStep(
      id: 'start',
      route: '/production/{orderProductionId}',
      targets: const ['production-start'],
      completion: const OnApi(
        'POST',
        '/production-orders/{orderProductionId}/start',
      ),
      probe: Probe(
        '/api/v1/production-orders/{orderProductionId}',
        done: (json, _) => _productionStatus(json, {'in_progress', 'completed'}),
      ),
    ),
    MissionStep(
      id: 'complete',
      route: '/production/{orderProductionId}',
      targets: const ['production-complete-save', 'production-complete'],
      completion: const OnApi(
        'POST',
        '/production-orders/{orderProductionId}/complete',
      ),
      probe: Probe(
        '/api/v1/production-orders/{orderProductionId}',
        done: (json, _) => _productionStatus(json, {'completed'}),
      ),
    ),
    const MissionStep(id: 'ready', route: '/orders/{orderId}'),
    MissionStep(
      id: 'stock',
      hasHint: true,
      route: '/production',
      targets: const ['production-build-save', 'production-build'],
      completion: OnApi(
        'POST',
        '/production-orders',
        predicate: (json, ctx) =>
            json is Map &&
            json['product_id'] == ctx.values['cartId'] &&
            json['order_id'] == null &&
            json['id'] != ctx.values['productionId'],
      ),
    ),
    const MissionStep(id: 'done'),
  ],
);
