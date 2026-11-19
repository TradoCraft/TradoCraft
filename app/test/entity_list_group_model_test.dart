import 'package:flutter_test/flutter_test.dart';
import 'package:tradocraft_app/framework/search/favourite.dart';
import 'package:tradocraft_app/framework/search/filter_model.dart';
import 'package:tradocraft_app/framework/search/group_model.dart';

const _status = FilterDef(
  key: 'status',
  label: 'Status',
  options: [('draft', 'Draft'), ('sent', 'Sent')],
);

void main() {
  group('groupHeaders', () {
    test('uses option labels, raw value without option or def', () {
      final b = [const GroupBucket('draft', 3), const GroupBucket('weird', 1)];
      final h = groupHeaders(b, _status);
      expect([for (final x in h) x.label], ['Draft', 'weird']);
      expect([for (final x in h) x.count], [3, 1]);
      expect([for (final x in h) x.value], ['draft', 'weird']);
      expect(groupHeaders(b, null).first.label, 'draft');
      expect(groupHeaders(const [], _status), isEmpty);
    });
  });

  group('Favourite.groupBy', () {
    test('round trips and is omitted when null', () {
      const f = Favourite(name: 'A', groupBy: 'status');
      expect(f.toJson()['groupBy'], 'status');
      expect(Favourite.fromJson(f.toJson()), f);
      expect(const Favourite(name: 'A').toJson().containsKey('groupBy'), false);
      expect(f == const Favourite(name: 'A'), false);
    });

    test('older stored data decodes without groupBy', () {
      final f = Favourite.fromJson({'name': 'Old', 'search': 'x'})!;
      expect(f.groupBy, isNull);
      expect(Favourite.fromJson({'name': 'B', 'groupBy': 5})!.groupBy, isNull);
      expect(Favourite.fromJson({'name': 'B', 'groupBy': ''})!.groupBy, isNull);
    });

    test('sanitized drops an unknown key', () {
      const f = Favourite(name: 'A', groupBy: 'status');
      expect(
        f
            .sanitized(const [_status], groups: const [GroupDef('status', 'S')])
            .groupBy,
        'status',
      );
      expect(
        f
            .sanitized(const [_status], groups: const [GroupDef('x', 'X')])
            .groupBy,
        isNull,
      );
      expect(f.sanitized(const [_status]).groupBy, isNull);
    });
  });
}
