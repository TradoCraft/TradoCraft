import 'package:flutter_test/flutter_test.dart';
import 'package:tradocraft_app/framework/search/favourite.dart';
import 'package:tradocraft_app/framework/search/filter_model.dart';

const _status = FilterDef(
  key: 'status',
  label: 'Status',
  options: [('draft', 'Draft'), ('sent', 'Sent'), ('won', 'Won')],
);
const _country = FilterDef(
  key: 'country',
  label: 'Country',
  options: [('de', 'Germany'), ('nl', 'Netherlands')],
);
const _defs = [_status, _country];

void main() {
  group('FilterSelection', () {
    test('toggle adds, removes and drops an empty filter', () {
      var s = FilterSelection.empty.toggle('status', 'draft');
      expect(s.of('status'), {'draft'});
      s = s.toggle('status', 'sent');
      expect(s.of('status'), {'draft', 'sent'});
      expect(s.count, 2);
      s = s.toggle('status', 'draft').toggle('status', 'sent');
      expect(s.isEmpty, isTrue);
      expect(s.keys, isEmpty);
    });

    test('is immutable', () {
      final a = FilterSelection.empty.toggle('status', 'draft');
      a.toggle('status', 'sent');
      expect(a.of('status'), {'draft'});
      expect(() => a.of('status').add('x'), throwsUnsupportedError);
    });

    test('equality ignores order and empty sets', () {
      final a = FilterSelection({
        'status': {'draft', 'sent'},
        'country': {'de'},
      });
      final b = FilterSelection({
        'country': {'de'},
        'status': {'sent', 'draft'},
        'x': <String>{},
      });
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a == a.toggle('country', 'nl'), isFalse);
      expect(FilterSelection.empty, FilterSelection({}));
    });

    test('chips follow the definition order and option order', () {
      final s = FilterSelection({
        'country': {'nl'},
        'status': {'sent', 'draft'},
        'unknown': {'a'},
      });
      expect(s.chips(_defs, 'or').map((c) => c.text), [
        'Status: Draft or Sent',
        'Country: Netherlands',
      ]);
      expect(s.chips(_defs, 'or').map((c) => c.key), ['status', 'country']);
      expect(s.lastKey(_defs), 'country');
      expect(FilterSelection.empty.lastKey(_defs), isNull);
    });

    test('without and cleared', () {
      final s = FilterSelection({
        'status': {'draft'},
        'country': {'de'},
      });
      expect(s.without('status').keys, ['country']);
      expect(s.cleared().isEmpty, isTrue);
    });

    test('sanitized drops unknown filters and options', () {
      final s = FilterSelection({
        'status': {'draft', 'gone'},
        'nope': {'x'},
        'country': {'zz'},
      }).sanitized(_defs);
      expect(
        s,
        FilterSelection({
          'status': {'draft'},
        }),
      );
    });

    test('toQuery gives sets and stableKey is order independent', () {
      final s = FilterSelection({
        'status': {'sent', 'draft'},
      });
      expect(s.toQuery(), {
        'status': {'draft', 'sent'},
      });
      expect(s.toQuery()['status'], isA<Set<String>>());
      expect(
        s.stableKey,
        FilterSelection({
          'status': {'draft', 'sent'},
        }).stableKey,
      );
    });
  });

  group('Favourite', () {
    test('round trips', () {
      final f = Favourite(
        name: 'My drafts',
        search: 'acme',
        filters: FilterSelection({
          'status': {'draft', 'sent'},
        }),
      );
      final back = Favourite.decodeList(Favourite.encodeList([f]));
      expect(back, [f]);
    });

    test('ignores unknown keys and tolerates missing parts', () {
      final list = Favourite.decodeList(
        '{"favourites":[{"name":"A","extra":1,"filters":{"s":["x",3,""],"t":"bad"}},'
        '{"name":"B"}],"version":9}',
      );
      expect(list.map((f) => f.name), ['A', 'B']);
      expect(
        list[0].filters,
        FilterSelection({
          's': {'x'},
        }),
      );
      expect(list[1].search, '');
      expect(list[1].filters.isEmpty, isTrue);
    });

    test('damaged data gives an empty list, bad entries are skipped', () {
      expect(Favourite.decodeList(null), isEmpty);
      expect(Favourite.decodeList(''), isEmpty);
      expect(Favourite.decodeList('{not json'), isEmpty);
      expect(Favourite.decodeList('42'), isEmpty);
      expect(Favourite.decodeList('{"favourites":"x"}'), isEmpty);
      final list = Favourite.decodeList(
        '{"favourites":[1,null,{"name":5},{"name":"  "},{"name":"ok"},{"name":"ok"}]}',
      );
      expect(list.map((f) => f.name), ['ok']);
    });

    test('sanitized drops what the definitions do not know', () {
      final f = Favourite(
        name: 'x',
        search: 's',
        filters: FilterSelection({
          'status': {'draft', 'gone'},
          'nope': {'a'},
        }),
      ).sanitized(_defs);
      expect(
        f.filters,
        FilterSelection({
          'status': {'draft'},
        }),
      );
      expect(f.search, 's');
    });

    test('upsert replaces by name', () {
      final a = const Favourite(name: 'a', search: '1');
      final b = const Favourite(name: 'b');
      final list = Favourite.upsert(
        Favourite.upsert([a], b),
        const Favourite(name: 'a', search: '2'),
      );
      expect(list.map((f) => f.name), ['a', 'b']);
      expect(list.first.search, '2');
    });
  });
}
