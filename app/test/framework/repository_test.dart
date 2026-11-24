import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tradocraft_app/app/api.dart';
import 'package:tradocraft_app/features/customers/customer_repository.dart';
import 'package:tradocraft_app/features/quotations/quotation_repository.dart';
import 'package:tradocraft_app/framework/data/repository.dart';
import 'package:tradocraft_app/shared/live_record_watcher.dart';

import '../fake_http.dart';

TradocraftApi _api(FakeHttp http) => TradocraftApi(fakeDio(http));

Map<String, Object?> _summary() => {
  'id': 'q1',
  'number': 'Q2026-0001',
  'revision': 1,
  'status': 'draft',
  'customer_id': 'c2',
  'customer_name': 'Bêta Industrie SA',
  'quote_date': '2026-11-05',
  'currency': 'EUR',
  'subtotal': '100.00',
  'purpose': 'sale',
  'shipping_status': 'none',
  'total': '121.00',
  'valid_until': '2026-12-05',
};

void main() {
  group('base types', () {
    test('ListQuery defaults and blank search', () {
      const q = ListQuery();
      expect(q.offset, 0);
      expect(q.limit, 50);
      expect(q.q, isNull);
      expect(const ListQuery(search: '').q, isNull);
      expect(const ListQuery(search: 'be').q, 'be');
      expect(q.copyWith(offset: 10).offset, 10);
    });

    test('Page total falls back to the item count', () {
      expect(const Page<int>([1, 2]).totalOrCount, 2);
      final (items, total) = const Page<int>([1, 2], total: 9).asLoaderResult;
      expect(items, [1, 2]);
      expect(total, 9);
    });
  });

  group('CustomerRepository', () {
    test('list sends search, offset and limit', () async {
      final http = FakeHttp({
        'GET /api/v1/customers': (_) => {
          'items': [customerJson()],
          'total': 7,
        },
      });
      final page = await CustomerRepository(_api(http).crm)
          .list(const ListQuery(search: 'be', offset: 20, limit: 10));
      expect(page.items.single.code, 'C0002');
      expect(page.total, 7);
      expect(http.queries.single, {'q': 'be', 'offset': 20, 'limit': 10});
    });

    test(
      'list sends the active filter only when one option is selected',
      () async {
        final http = FakeHttp({
          'GET /api/v1/customers': (_) => {'items': [], 'total': 0},
        });
        final repo = CustomerRepository(_api(http).crm);
        await repo.list(
          const ListQuery(
            filters: {
              'active': {'false'},
            },
          ),
        );
        await repo.list(
          const ListQuery(
            filters: {
              'active': {'true', 'false'},
            },
          ),
        );
        expect(http.queries[0]['active'], false);
        expect(http.queries[1].containsKey('active'), isFalse);
      },
    );

    test('groups sends group_by with the search and filters', () async {
      final http = FakeHttp({
        'GET /api/v1/customers/groups': (_) => {
          'group_by': 'active',
          'groups': [
            {'value': 'true', 'count': 4},
            {'value': 'false', 'count': 1},
          ],
        },
      });
      final groups = await CustomerRepository(_api(http).crm).groups(
        const ListQuery(
          search: 'be',
          filters: {
            'country_code': {'NL', 'BE'},
          },
        ),
        'active',
      );
      expect(
        [for (final g in groups) (g.value, g.count)],
        [('true', 4), ('false', 1)],
      );
      expect(http.queries.single, {
        'group_by': 'active',
        'q': 'be',
        'country_code': 'BE,NL',
      });
    });

    test('get reads by id', () async {
      final http = FakeHttp({
        'GET /api/v1/customers/c2': (_) => customerJson(),
      });
      final c = await CustomerRepository(_api(http).crm).get('c2');
      expect(c.name, 'Bêta Industrie SA');
    });

    test('a 409 record_changed passes through as before', () async {
      final http = FakeHttp({
        'GET /api/v1/customers/c2': (_) => const FakeStatus(409, {
          'error': 'conflict',
          'code': 'record_changed',
          'message': 'changed',
        }),
      });
      try {
        await CustomerRepository(_api(http).crm).get('c2');
        fail('should throw');
      } on DioException catch (e) {
        expect(errorCode(e), 'record_changed');
        expect(isRecordChangedError(e), isTrue);
        expect(errorStatus(e), 409);
      }
    });

    test('a missing customer is a 404', () async {
      final http = FakeHttp({});
      try {
        await CustomerRepository(_api(http).crm).get('nope');
        fail('should throw');
      } catch (e) {
        expect(errorStatus(e), 404);
      }
    });
  });

  group('QuotationRepository', () {
    test('list sends the status filter', () async {
      final http = FakeHttp({
        'GET /api/v1/quotations': (_) => {
          'items': [_summary()],
          'total': 1,
        },
      });
      final page = await QuotationRepository(_api(http).sales).list(
        const ListQuery(
          search: 'x',
          limit: 5,
          filters: {
            'status': {'sent', 'draft'},
          },
        ),
      );
      expect(page.items.single.number, 'Q2026-0001');
      expect(page.total, 1);
      expect(http.queries.single, {
        'q': 'x',
        'status': 'draft,sent',
        'offset': 0,
        'limit': 5,
      });
    });

    test(
      'get hits the quotation route and 409 on update passes through',
      () async {
        final http = FakeHttp({
          'PUT /api/v1/quotations/q1': (_) => const FakeStatus(409, {
            'error': 'conflict',
            'code': 'record_changed',
            'message': 'changed',
          }),
        });
        final repo = QuotationRepository(_api(http).sales);
        await expectLater(
          repo.update(
            'q1',
            QuotationInput.fromJson({
              'customer_id': 'c2',
              'quote_date': '2026-11-05',
              'expected_version': 1,
              'lines': <Object?>[],
            }),
          ),
          throwsA(predicate(isRecordChangedError)),
        );
        expect(http.requests, ['PUT /api/v1/quotations/q1']);
        expect(
          http.bodies['PUT /api/v1/quotations/q1'],
          containsPair('expected_version', 1),
        );
      },
    );
  });
}
