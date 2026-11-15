import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tradocraft_app/l10n/app_localizations.dart';
import 'package:tradocraft_app/shared/csv_transfer.dart';
import 'package:tradocraft_app/shared/file_export.dart';
import 'package:tradocraft_app/shared/file_export_io.dart' as io;
import 'package:tradocraft_app/shared/file_export_path.dart';

Uint8List _b(String s) => Uint8List.fromList(s.codeUnits);

/// Creates a link; false only when the host lacks the privilege for symbolic links.
bool _tryLink(String path, String target) {
  try {
    Link(path).createSync(target);
    return true;
  } on FileSystemException {
    if (Platform.isWindows) return false;
    rethrow;
  }
}

void main() {
  late Directory tmp;

  setUp(() => tmp = Directory.systemTemp.createTempSync('file_export_test'));
  tearDown(() => tmp.deleteSync(recursive: true));

  group('safeSegments', () {
    test('accepts nested relative paths with either separator', () {
      expect(safeSegments('a/b/c.pdf'), ['a', 'b', 'c.pdf']);
      expect(safeSegments(r'a\b\c.pdf'), ['a', 'b', 'c.pdf']);
      expect(safeSegments('./a//b.pdf'), ['a', 'b.pdf']);
    });

    test('rejects absolute paths, drive letters, parent segments and empties', () {
      for (final bad in [
        '',
        '/etc/passwd',
        r'\windows\x',
        'C:/x.pdf',
        r'c:\x.pdf',
        '../x.pdf',
        'a/../../x.pdf',
        r'a\..\x.pdf',
        '..',
        '.',
        '/',
        '~/x.pdf',
        'a\u0000b',
      ]) {
        expect(() => safeSegments(bad), throwsA(isA<UnsafePathException>()), reason: bad);
      }
    });
  });

  group('writeUnique', () {
    test('creates nested folders and returns the written path', () async {
      final path = await io.writeUnique(tmp.path, 'list/Z1/nl/file.pdf', _b('x'));
      expect(path, p.join(tmp.resolveSymbolicLinksSync(), 'list', 'Z1', 'nl', 'file.pdf'));
      expect(File(path).readAsStringSync(), 'x');
    });

    test('creates the base folder when it does not exist yet', () async {
      final base = p.join(tmp.path, 'new', 'dir');
      final path = await io.writeUnique(base, 'a.csv', _b('1'));
      expect(File(path).existsSync(), isTrue);
    });

    test('never overwrites: appends (2), (3) before the extension', () async {
      final a = await io.writeUnique(tmp.path, 'd/report.pdf', _b('one'));
      final b = await io.writeUnique(tmp.path, 'd/report.pdf', _b('two'));
      final c = await io.writeUnique(tmp.path, 'd/report.pdf', _b('three'));
      expect(p.basename(a), 'report.pdf');
      expect(p.basename(b), 'report (2).pdf');
      expect(p.basename(c), 'report (3).pdf');
      expect(File(a).readAsStringSync(), 'one');
      expect(File(b).readAsStringSync(), 'two');
      expect(File(c).readAsStringSync(), 'three');
    });

    test('a name without extension gets the suffix at the end', () async {
      await io.writeUnique(tmp.path, 'README', _b('1'));
      final second = await io.writeUnique(tmp.path, 'README', _b('2'));
      expect(p.basename(second), 'README (2)');
    });

    test('rejects traversal and absolute paths without writing anything', () async {
      final outside = Directory('${tmp.path}/outside')..createSync();
      final base = Directory('${tmp.path}/base')..createSync();
      for (final bad in ['../outside/x.pdf', 'a/../../outside/x.pdf', '/tmp/x.pdf', outside.path]) {
        await expectLater(
          io.writeUnique(base.path, bad, _b('x')),
          throwsA(isA<UnsafePathException>()),
          reason: bad,
        );
      }
      expect(outside.listSync(), isEmpty);
      expect(base.listSync(), isEmpty);
    });

    test('does not follow a symbolic link that leaves the base folder', () async {
      final outside = Directory('${tmp.path}/outside')..createSync();
      final base = Directory('${tmp.path}/base')..createSync();
      if (!_tryLink('${base.path}/escape', outside.path)) {
        markTestSkipped('The host does not allow symbolic links.');
        return;
      }
      await expectLater(
        io.writeUnique(base.path, 'escape/x.pdf', _b('x')),
        throwsA(isA<UnsafePathException>()),
      );
      expect(outside.listSync(), isEmpty);
    });

    test('does not create folders through a symbolic link in the middle of the path', () async {
      final outside = Directory('${tmp.path}/outside')..createSync();
      final base = Directory('${tmp.path}/base')..createSync();
      if (!_tryLink('${base.path}/mid', outside.path)) {
        markTestSkipped('The host does not allow symbolic links.');
        return;
      }
      await expectLater(
        io.writeUnique(base.path, 'mid/new/deeper/x.pdf', _b('x')),
        throwsA(isA<UnsafePathException>()),
      );
      expect(outside.listSync(), isEmpty);
    });
  });

  group('FileExport', () {
    FileExport make({String? downloads, List<String>? shared}) => FileExport(
      downloads: () async => downloads,
      fallback: (name, _) async {
        shared?.add(name);
        return true;
      },
    );

    test('writes under the Downloads folder by default', () async {
      final r = await make(downloads: tmp.path).save('x/a.pdf', _b('1'));
      expect(r.saved, isTrue);
      expect(r.baseFolder, tmp.path);
      expect(File(r.path!).readAsStringSync(), '1');
    });

    test('a base folder overrides Downloads', () async {
      final other = Directory('${tmp.path}/other')..createSync();
      final r = await make(downloads: '${tmp.path}/dl').save('a.pdf', _b('1'), baseFolder: other.path);
      expect(r.path!.startsWith(other.resolveSymbolicLinksSync()), isTrue);
      expect(Directory('${tmp.path}/dl').existsSync(), isFalse);
    });

    test('without a folder (browser, mobile) the platform mechanism gets the file name only', () async {
      final shared = <String>[];
      final r = await make(shared: shared).save('list/Z1/a.pdf', _b('1'));
      expect(r.saved, isTrue);
      expect(r.path, isNull);
      expect(shared, ['a.pdf']);
    });

    test('rejects an unsafe path before anything happens, also without a folder', () async {
      final shared = <String>[];
      await expectLater(
        make(shared: shared).save('../a.pdf', _b('1')),
        throwsA(isA<UnsafePathException>()),
      );
      await expectLater(
        make(downloads: tmp.path).save('/abs.pdf', _b('1')),
        throwsA(isA<UnsafePathException>()),
      );
      expect(shared, isEmpty);
    });
  });

  testWidgets('saveExport shows "Saved to <path>" with an Open action', (tester) async {
    final opened = <String>[];
    Future<Object?>? saving;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          downloadsFolderProvider.overrideWithValue(() async => tmp.path),
          pathOpenerProvider.overrideWithValue((p) async => opened.add(p)),
          csvSaverProvider.overrideWithValue((_, _) async => true),
        ],
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: [
            AppLocalizations.delegate,
            ...GlobalMaterialLocalizations.delegates,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) => TextButton(
                onPressed: () => saving = saveExport(context, ref, 'q/offer.pdf', _b('pdf')),
                child: const Text('go'),
              ),
            ),
          ),
        ),
      ),
    );
    // Real file I/O: the tap and the wait run outside the fake clock.
    await tester.runAsync(() async {
      await tester.tap(find.text('go'));
      await saving;
    });
    await tester.pump(); // the snack bar slides in
    await tester.pump(const Duration(milliseconds: 500));
    final real = p.join(tmp.resolveSymbolicLinksSync(), 'q', 'offer.pdf');
    expect(find.text('Saved to $real'), findsOneWidget);
    await tester.tap(find.text('Open'));
    expect(opened, [real]);
  });
}
