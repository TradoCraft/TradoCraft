import 'package:flutter_test/flutter_test.dart';
import 'package:tradocraft_app/features/admin/modules_tree.dart';

/// Diamond: a <- b, a <- c, b & c <- d. Plus an independent root e.
final _diamond = <String, List<String>>{
  'a': [],
  'b': ['a'],
  'c': ['a'],
  'd': ['b', 'c'],
  'e': [],
};

List<String> _flat(List<ModuleTreeNode> nodes) => [
  for (final n in nodes) ...[
    '${n.depth}:${n.repeat ? '*' : ''}${n.code}',
    ..._flat(n.children),
  ],
];

void main() {
  group('buildModuleTree', () {
    test('roots, children and the repeated multi-parent module', () {
      final tree = buildModuleTree(_diamond);
      expect(_flat(tree), ['0:a', '1:b', '2:d', '1:c', '2:*d', '0:e']);
      final repeat = tree.first.children[1].children.single;
      expect(repeat.parent, 'c');
      expect(repeat.otherRequires, ['b']);
      expect(repeat.id, 'd-under-c');
      expect(tree.first.children[0].children.single.id, 'd');
    });

    test('a cycle does not loop and its modules are still listed', () {
      final tree = buildModuleTree({
        'x': ['y'],
        'y': ['x'],
        'z': [],
      });
      final all = _flat(tree).map((s) => s.split(':').last.replaceAll('*', ''));
      expect(all, containsAll(['x', 'y', 'z']));
      expect(all.length, lessThan(10));
    });
  });

  group('toggleModule', () {
    test('off takes every transitive dependent along', () {
      final r = toggleModule(_diamond, {}, 'a', false);
      expect(r.disabled, {'a', 'b', 'c', 'd'});
      expect(r.alsoChanged, ['b', 'c', 'd']);
    });

    test('off on a leaf changes only that module', () {
      final r = toggleModule(_diamond, {}, 'd', false);
      expect(r.disabled, {'d'});
      expect(r.alsoChanged, isEmpty);
    });

    test('on enables transitive requirements, not dependents', () {
      final r = toggleModule(_diamond, {'a', 'b', 'c', 'd'}, 'd', true);
      expect(r.disabled, isEmpty);
      expect(r.alsoChanged, ['a', 'b', 'c']);
      final r2 = toggleModule(_diamond, {'a', 'b', 'c', 'd'}, 'b', true);
      expect(r2.disabled, {'c', 'd'});
      expect(r2.alsoChanged, ['a']);
    });

    test(
      'does not modify its input and already-off modules are not reported',
      () {
        final input = {'b'};
        final r = toggleModule(_diamond, input, 'a', false);
        expect(input, {'b'});
        expect(r.alsoChanged, ['c', 'd']);
      },
    );

    test('the result always satisfies the server rule', () {
      for (final code in _diamond.keys) {
        for (final on in [true, false]) {
          final r = toggleModule(_diamond, {'c', 'd'}, code, on);
          for (final e in _diamond.entries) {
            if (!r.disabled.contains(e.key)) {
              expect(
                e.value.any(r.disabled.contains),
                isFalse,
                reason: '$code $on ${e.key}',
              );
            }
          }
        }
      }
    });

    test('a cycle terminates', () {
      final cyc = {
        'x': ['y'],
        'y': ['x'],
      };
      expect(toggleModule(cyc, {}, 'x', false).disabled, {'x', 'y'});
      expect(toggleModule(cyc, {'x', 'y'}, 'x', true).disabled, isEmpty);
    });
  });
}
