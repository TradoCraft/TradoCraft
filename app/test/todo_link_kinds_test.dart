import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tradocraft_app/app/api.dart' show TodoLinkKind;
import 'package:tradocraft_app/app/detail_routes.dart';
import 'package:tradocraft_app/app/workspace.dart' show sectionOfDetail;
import 'package:tradocraft_app/features/todo/link_kinds.dart';

void main() {
  test('the registry covers every kind of the API, once', () {
    final codes = [for (final k in linkKinds) k.code];
    expect(codes.toSet().length, codes.length);
    expect(
      codes.toSet(),
      TodoLinkKind.$valuesDefined.map((k) => k.json).toSet(),
    );
    expect(codes.length, 16);
  });

  test('every kind builds a location that opens as a workspace tab', () {
    for (final k in linkKinds) {
      final loc = buildLinkLocation(k.kind, 'abc-123')!;
      expect(isDetailLocation(loc), isTrue, reason: '${k.code}: $loc');
      expect(detailScreen(Uri.parse(loc)), isNotNull, reason: k.code);
      // The section list of the tab exists, for the shell's highlight.
      expect(sectionOfDetail(loc), startsWith('/'));
    }
  });

  test('parse(build(kind, id)) round-trips', () {
    for (final k in linkKinds) {
      final r = parseLinkLocation(buildLinkLocation(k.kind, 'abc-123')!);
      expect(r, isNotNull, reason: k.code);
      expect(r!.kind, k.kind);
      expect(r.id, 'abc-123');
      expect(r.location, buildLinkLocation(k.kind, 'abc-123'));
    }
  });

  test('a query string does not change the record', () {
    expect(parseLinkLocation('/orders/o1?tab=lines')!.id, 'o1');
  });

  test('pages of a section that are not records have no object', () {
    for (final loc in const [
      '/orders',
      '/quotations',
      '/quotations/new',
      '/helpdesk/answers',
      '/helpdesk/settings',
      '/helpdesk/calendar',
      '/helpdesk/automation',
      '/helpdesk/reports',
      '/jobs/contracts',
      '/jobs/contracts/c1',
      '/jobs/equipment/c1',
      '/production/release',
      '/production/divisions',
      '/production/work-centres',
      '/production/capacity',
      '/delivery/settings',
      '/kb/categories',
      '/repairs/departments',
      '/stock/warehouses',
      '/stock/counts',
      '/stock/products/p1',
      '/reports/r1',
      '/reports/new',
      '/configurator/builder',
      '/configurator/configurations/x',
      '/todo',
      '/customers',
      '',
      '/',
    ]) {
      expect(parseLinkLocation(loc), isNull, reason: loc);
    }
  });

  test('a location with a kind but no route falls back to the stored one', () {
    // A kind the app does not know (a newer server): nothing is built.
    expect(linkKindInfo(TodoLinkKind.$unknown), isNull);
    expect(
      resolveLinkLocation(TodoLinkKind.$unknown, 'x', stored: '/future/x'),
      '/future/x',
    );
    // The built location wins over the stored one.
    expect(
      resolveLinkLocation(TodoLinkKind.order, 'o1', stored: '/old/o1'),
      '/orders/o1',
    );
    // Only paths inside the app are followed.
    expect(
      resolveLinkLocation(null, null, stored: 'https://evil.example/'),
      isNull,
    );
    expect(resolveLinkLocation(null, null, stored: '//evil.example'), isNull);
    expect(resolveLinkLocation(null, null), isNull);
  });

  test(
    'the permissions match the server mapping in crates/todo/src/link.rs',
    () {
      final f = File('../crates/todo/src/link.rs');
      if (!f.existsSync()) return; // not run from the repository
      final src = f.readAsStringSync();
      final body = src.substring(src.indexOf('fn read_permission'));
      String snake(String s) => s
          .replaceAllMapped(
            RegExp('(?<=[a-z])[A-Z]'),
            (m) => '_${m[0]!.toLowerCase()}',
          )
          .toLowerCase();
      final expected = <String, String>{};
      for (final m in RegExp(
        r'((?:TodoLinkKind::\w+\s*\|?\s*)+)=>\s*\{?\s*Permission::(\w+)',
      ).allMatches(body)) {
        final perm = RegExp(r'^([A-Z][a-z]+)([A-Z][a-z]+)$').firstMatch(m[2]!)!;
        final code = '${perm[1]!.toLowerCase()}.${perm[2]!.toLowerCase()}';
        for (final k in RegExp(r'TodoLinkKind::(\w+)').allMatches(m[1]!)) {
          expected[snake(k[1]!)] = code;
        }
      }
      expect(expected.length, 16);
      for (final k in linkKinds) {
        expect(k.permission, expected[k.code], reason: k.code);
      }
    },
  );
}
