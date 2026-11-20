import 'package:flutter_test/flutter_test.dart';
import 'package:tradocraft_app/features/tutorial/missions_production.dart';
import 'package:tradocraft_app/features/tutorial/missions_sales.dart';
import 'package:tradocraft_app/features/tutorial/model.dart';

import 'fake_http.dart';

Future<void> _assist(
  Mission mission,
  String id,
  FakeHttp http, [
  Map<String, String> values = const {},
]) => mission.steps.singleWhere((step) => step.id == id).assist!(
  ActionHost(dio: fakeDio(http), context: MissionContext(values)),
);

void main() {
  test('zone assistance creates the tutorial export zone', () async {
    const path = 'POST /api/v1/price-zones';
    final http = FakeHttp({path: (_) => {}});

    await _assist(pricesMission, 'zone', http);

    expect(http.bodies[path], {'code': 'TUT-EXPORT', 'name': 'Export zone'});
  });

  test('division creation uses the signed-in user as its member', () async {
    const path = 'POST /api/v1/production/divisions';
    final http = FakeHttp({
      'GET /api/v1/me': (_) => {'user_id': 'current-user'},
      path: (_) => {},
    });

    await _assist(manufacturingMission, 'division', http);

    expect(http.bodies[path], {
      'code': 'TUT-ASM',
      'name': 'Tutorial assembly',
      'member_user_ids': ['current-user'],
    });
  });

  test(
    'cart prices use the tutorial export zone and the demo home zone',
    () async {
      const path = 'POST /api/v1/products/cart/prices';
      final http = FakeHttp({
        'GET /api/v1/price-zones': (_) => [
          {'id': 'other', 'code': 'Z2'},
          {'id': 'home', 'code': 'Z1'},
        ],
        path: (_) => {},
      });
      const values = {'cartId': 'cart', 'zoneId': 'export'};

      await _assist(pricesMission, 'priceExport', http, values);
      expect(http.bodies[path], {
        'zone_id': 'export',
        'unit_price': '1450',
        'valid_from': matches(RegExp(r'^\d{4}-\d{2}-\d{2}$')),
      });

      await _assist(pricesMission, 'priceHome', http, values);
      expect(http.bodies[path], {
        'zone_id': 'home',
        'unit_price': '1200',
        'valid_from': matches(RegExp(r'^\d{4}-\d{2}-\d{2}$')),
      });
    },
  );

  test('Brightwheel is created with the export zone from the story', () async {
    const path = 'POST /api/v1/customers';
    final http = FakeHttp({path: (_) => {}});

    await _assist(customerMission, 'createCustomer', http, {'zoneId': 'z'});

    expect(http.bodies[path], {
      'code': 'TUT-CUST',
      'name': 'Brightwheel Logistics BV',
      'vat_number': 'BE0123456749',
      'street': 'Voorbeeldlaan 12',
      'postal_code': '9000',
      'city': 'Gent',
      'price_zone_id': 'z',
    });
  });

  test('quotation draft lets the server resolve the cart price', () async {
    const path = 'POST /api/v1/quotations';
    final http = FakeHttp({path: (_) => {}});

    await _assist(quotationMission, 'create', http, {
      'customerId': 'customer',
      'cartId': 'cart',
    });

    expect(http.bodies[path], {
      'customer_id': 'customer',
      'lines': [
        {'product_id': 'cart', 'quantity': '8'},
      ],
    });
  });

  test(
    'customer link preserves the latest ticket fields and version',
    () async {
      const path = '/api/v1/tickets/ticket';
      const properties = {
        'subject': 'Quote for a cart',
        'status': 'open',
        'priority': 'normal',
        'category': 'sales',
        'language': 'en',
        'owner_user_id': 'owner',
        'contact_id': null,
        'contact_name': 'Maya Okafor',
        'contact_email': 'maya.okafor@example.test',
        'quotation_id': null,
        'opportunity_id': null,
      };
      final http = FakeHttp({
        'GET $path': (_) => {
          'ticket': {...properties, 'version': 12},
        },
        'PUT $path': (_) => {},
      });

      await _assist(customerMission, 'linked', http, {
        'ticketId': 'ticket',
        'customerId': 'brightwheel',
      });

      expect(http.bodies['PUT $path'], {
        ...properties,
        'customer_id': 'brightwheel',
        'expected_version': 12,
      });
    },
  );

  test(
    'quotation assistance needs the customer and cart before writing',
    () async {
      final http = FakeHttp({});

      await expectLater(
        _assist(quotationMission, 'create', http, {'cartId': 'cart'}),
        throwsStateError,
      );

      expect(http.requests, isEmpty);
    },
  );
}
