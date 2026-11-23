import 'dart:convert';
import 'dart:ui' show PointerDeviceKind;
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tradocraft_app/app/api.dart';
import 'package:tradocraft_app/app/environments.dart';
import 'package:tradocraft_app/features/field/offline/kv_store.dart';
import 'package:tradocraft_app/features/products/product_form.dart';
import 'package:tradocraft_app/features/products/product_thumb.dart';
import 'package:tradocraft_app/l10n/app_localizations.dart';
import 'package:tradocraft_app/shared/glb_viewer.dart';
import 'package:tradocraft_app/shared/photos.dart';

import 'fake_http.dart';

/// Builds a minimal valid glTF 2.0 binary (`.glb`) assembly with named nodes and a triangle mesh.
Uint8List _buildTestGlb() {
  // 3 vertices (9 float32 = 36 bytes) + 3 uint16 indices (6 bytes, padded to 8 bytes) = 44 bytes.
  final bin = ByteData(44);
  final coords = [
    0.0, 0.0, 0.0, // v0
    1.0, 0.0, 0.0, // v1
    0.5, 1.0, 0.0, // v2
  ];
  for (var i = 0; i < coords.length; i++) {
    bin.setFloat32(i * 4, coords[i], Endian.little);
  }
  bin.setUint16(36, 0, Endian.little);
  bin.setUint16(38, 1, Endian.little);
  bin.setUint16(40, 2, Endian.little);

  final jsonMap = {
    'asset': {'version': '2.0'},
    'scene': 0,
    'scenes': [
      {
        'nodes': [0],
      },
    ],
    'nodes': [
      {
        'name': 'ConveyorFrame',
        'mesh': 0,
        'children': [1, 2],
      },
      {
        'name': 'DriveMotor',
        'mesh': 0,
        'translation': [1.0, 0.0, 0.0],
      },
      {
        'name': 'OpticalSensor',
        'mesh': 0,
        'translation': [0.5, 0.5, 0.2],
      },
    ],
    'meshes': [
      {
        'primitives': [
          {
            'attributes': {'POSITION': 0},
            'indices': 1,
          },
        ],
      },
    ],
    'bufferViews': [
      {'buffer': 0, 'byteOffset': 0, 'byteLength': 36},
      {'buffer': 0, 'byteOffset': 36, 'byteLength': 6},
    ],
    'accessors': [
      {
        'bufferView': 0,
        'componentType': 5126,
        'count': 3,
        'type': 'VEC3',
        'min': [0.0, 0.0, 0.0],
        'max': [1.0, 1.0, 0.0],
      },
      {
        'bufferView': 1,
        'componentType': 5123,
        'count': 3,
        'type': 'SCALAR',
      },
    ],
    'buffers': [
      {'byteLength': 44},
    ],
  };

  var jsonBytes = utf8.encode(jsonEncode(jsonMap));
  final pad = (4 - (jsonBytes.length % 4)) % 4;
  if (pad > 0) {
    jsonBytes = Uint8List.fromList([...jsonBytes, ...List.filled(pad, 0x20)]);
  }

  final totalLen = 12 + 8 + jsonBytes.length + 8 + 44;
  final out = ByteData(totalLen);
  // Header
  out.setUint32(0, 0x46546C67, Endian.little);
  out.setUint32(4, 2, Endian.little);
  out.setUint32(8, totalLen, Endian.little);
  // JSON chunk
  out.setUint32(12, jsonBytes.length, Endian.little);
  out.setUint32(16, 0x4E4F534A, Endian.little);
  final outBytes = out.buffer.asUint8List();
  outBytes.setRange(20, 20 + jsonBytes.length, jsonBytes);
  // BIN chunk
  final binHeader = 20 + jsonBytes.length;
  out.setUint32(binHeader, 44, Endian.little);
  out.setUint32(binHeader + 4, 0x004E4942, Endian.little);
  outBytes.setRange(binHeader + 8, totalLen, bin.buffer.asUint8List());
  return outBytes;
}

void main() {
  test('isGlbBytes detects glTF 2.0 binary magic header', () {
    final glb = _buildTestGlb();
    expect(isGlbBytes(glb), isTrue);
    expect(isGlbBytes(Uint8List.fromList([1, 2, 3, 4])), isFalse);
  });

  test('GlbAsset.parse extracts named node hierarchy and triangles', () {
    final asset = GlbAsset.parse(_buildTestGlb());
    expect(asset.namedNodes.map((n) => n.name), [
      'ConveyorFrame',
      'DriveMotor',
      'OpticalSensor',
    ]);
    expect(asset.namedNodes.map((n) => n.depth), [0, 1, 1]);
    expect(asset.triangles.length, 3);
  });

  testWidgets('GlbViewer renders 3D canvas and named node controls', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GlbViewer(bytes: _buildTestGlb(), filename: 'assembly.glb'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('glb-canvas')), findsOneWidget);
    expect(find.text('Assembly parts (3)'), findsOneWidget);
    expect(find.text('ConveyorFrame'), findsOneWidget);
    expect(find.text('DriveMotor'), findsOneWidget);
    expect(find.text('OpticalSensor'), findsOneWidget);

    // Select a named node and toggle visibility of another.
    await tester.tap(find.byKey(const ValueKey('glb-node-1')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('glb-node-toggle-2')));
    await tester.pump();
    expect(find.byKey(const ValueKey('glb-show-all')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('glb-show-all')));
    await tester.pump();
    expect(find.byKey(const ValueKey('glb-show-all')), findsNothing);
  });

  testWidgets(
    'ProductThumb shows bundled tutorial GLB small and enlarges on mouse hover',
    (tester) async {
      expect(tutorialGlbAssets.length, 14);
      expect(
        tutorialGlbAssetForCode('CONV-BELT-1M'),
        'assets/models/CONV-BELT-1M.glb',
      );

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: Center(
                child: ProductThumb(
                  productId: 'p-conv',
                  productCode: 'CONV-BELT-1M',
                  mediaId: null,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(GlbMiniPreview), findsOneWidget);
      expect(find.byKey(const ValueKey('thumb-hover-p-conv')), findsNothing);

      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset.zero);
      addTearDown(gesture.removePointer);
      await tester.pump();
      await gesture.moveTo(
        tester.getCenter(find.byKey(const ValueKey('thumb-p-conv'))),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('thumb-hover-p-conv')), findsOneWidget);
      expect(find.byType(GlbMiniPreview), findsNWidgets(2));

      await gesture.moveTo(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('thumb-hover-p-conv')), findsNothing);
    },
  );

  testWidgets(
    'ProductForm auto-stages matching tutorial GLB in tutorial environment',
    (tester) async {
      final http = FakeHttp({
        'GET /api/v1/me': (_) => meJson(['products.read', 'products.write']),
        'GET /api/v1/product-families': (_) => <Object?>[],
        'GET /api/v1/packaging-categories': (_) => <Object?>[],
      });
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            dioProvider.overrideWithValue(fakeDio(http)),
            kvStoreProvider.overrideWithValue(MemoryKvStore()),
            initialEnvironmentsProvider.overrideWithValue(
              EnvironmentsState(
                items: const [
                  AppEnvironment(
                    id: 'tut',
                    name: 'Tutorial',
                    kind: EnvironmentKind.tutorial,
                    serverUrl: 'http://test',
                  ),
                ],
                activeId: 'tut',
              ),
            ),
          ],
          child: MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: [
              AppLocalizations.delegate,
              ...GlobalMaterialLocalizations.delegates,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            home: const Scaffold(body: ProductForm(asTab: true)),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextField, 'Code'),
        'MOT-1P-037',
      );
      await tester.pumpAndSettle();

      expect(find.text('MOT-1P-037.glb'), findsOneWidget);
    },
  );

  Uint8List packGlb(Map<String, Object?> jsonMap, Uint8List binBytes) {
    var jsonBytes = utf8.encode(jsonEncode(jsonMap));
    final jPad = (4 - (jsonBytes.length % 4)) % 4;
    if (jPad > 0) {
      jsonBytes = Uint8List.fromList([...jsonBytes, ...List.filled(jPad, 0x20)]);
    }
    final bPad = (4 - (binBytes.length % 4)) % 4;
    final paddedBin = bPad > 0
        ? Uint8List.fromList([...binBytes, ...List.filled(bPad, 0)])
        : binBytes;
    final totalLen = 12 + 8 + jsonBytes.length + 8 + paddedBin.length;
    final out = ByteData(totalLen);
    out.setUint32(0, 0x46546C67, Endian.little);
    out.setUint32(4, 2, Endian.little);
    out.setUint32(8, totalLen, Endian.little);
    out.setUint32(12, jsonBytes.length, Endian.little);
    out.setUint32(16, 0x4E4F534A, Endian.little);
    final outBytes = out.buffer.asUint8List();
    outBytes.setRange(20, 20 + jsonBytes.length, jsonBytes);
    final binHdr = 20 + jsonBytes.length;
    out.setUint32(binHdr, paddedBin.length, Endian.little);
    out.setUint32(binHdr + 4, 0x004E4942, Endian.little);
    outBytes.setRange(binHdr + 8, totalLen, paddedBin);
    return outBytes;
  }

  testWidgets(
    'GlbViewer visibility-only toggle updates painter snapshot and shouldRepaint',
    (tester) async {
      tester.view.physicalSize = const Size(1000, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GlbViewer(bytes: _buildTestGlb(), filename: 'assembly.glb'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final before = tester
          .widget<CustomPaint>(find.byKey(const ValueKey('glb-canvas')))
          .painter!;

      // Visibility-only toggle on node 2 (OpticalSensor).
      await tester.tap(find.byKey(const ValueKey('glb-node-toggle-2')));
      await tester.pump();

      final after = tester
          .widget<CustomPaint>(find.byKey(const ValueKey('glb-canvas')))
          .painter!;
      expect(after.shouldRepaint(before), isTrue);

      // Toggling parent node 0 (ConveyorFrame) hides its entire subtree (0, 1, 2).
      await tester.tap(find.byKey(const ValueKey('glb-node-toggle-0')));
      await tester.pump();
      final afterParentHide = tester
          .widget<CustomPaint>(find.byKey(const ValueKey('glb-canvas')))
          .painter!;
      expect(afterParentHide.shouldRepaint(after), isTrue);
    },
  );

  test('GlbAsset.parse expands triangle strips and fans', () {
    // 4 vertices for a quad.
    final bin = ByteData(4 * 12);
    final coords = [
      0.0, 0.0, 0.0, //
      1.0, 0.0, 0.0, //
      0.0, 1.0, 0.0, //
      1.0, 1.0, 0.0, //
    ];
    for (var i = 0; i < coords.length; i++) {
      bin.setFloat32(i * 4, coords[i], Endian.little);
    }

    for (final mode in [5, 6]) {
      final glb = packGlb({
        'asset': {'version': '2.0'},
        'nodes': [
          {'name': 'Quad', 'mesh': 0},
        ],
        'meshes': [
          {
            'primitives': [
              {
                'mode': mode,
                'attributes': {'POSITION': 0},
              },
            ],
          },
        ],
        'bufferViews': [
          {'buffer': 0, 'byteOffset': 0, 'byteLength': 48},
        ],
        'accessors': [
          {
            'bufferView': 0,
            'componentType': 5126,
            'count': 4,
            'type': 'VEC3',
          },
        ],
      }, bin.buffer.asUint8List());
      final asset = GlbAsset.parse(glb);
      expect(asset.triangles.length, 2, reason: 'mode $mode produces 2 tris');
    }
  });

  test('GlbAsset.parse supports sparse POSITION without base bufferView', () {
    // Sparse indices: [1, 2] (uint16 = 4 bytes) + values: 2x VEC3 (24 bytes) = 28 bytes.
    final bin = ByteData(28);
    bin.setUint16(0, 1, Endian.little);
    bin.setUint16(2, 2, Endian.little);
    bin.setFloat32(4, 1.0, Endian.little);
    bin.setFloat32(16, 0.0, Endian.little);
    bin.setFloat32(20, 1.0, Endian.little);

    final glb = packGlb({
      'asset': {'version': '2.0'},
      'nodes': [
        {'name': 'SparseTri', 'mesh': 0},
      ],
      'meshes': [
        {
          'primitives': [
            {
              'attributes': {'POSITION': 0},
            },
          ],
        },
      ],
      'bufferViews': [
        {'buffer': 0, 'byteOffset': 0, 'byteLength': 4},
        {'buffer': 0, 'byteOffset': 4, 'byteLength': 24},
      ],
      'accessors': [
        {
          'componentType': 5126,
          'count': 3,
          'type': 'VEC3',
          'sparse': {
            'count': 2,
            'indices': {'bufferView': 0, 'componentType': 5123},
            'values': {'bufferView': 1},
          },
        },
      ],
    }, bin.buffer.asUint8List());

    final asset = GlbAsset.parse(glb);
    expect(asset.triangles.length, 1);
    expect(asset.triangles.first.v0.x, 0.0);
    expect(asset.triangles.first.v1.x, 1.0);
    expect(asset.triangles.first.v2.y, 1.0);
  });

  test('GlbAsset.parse rejects truncated chunks and malformed JSON with FormatException', () {
    final valid = _buildTestGlb();
    final truncated = Uint8List.sublistView(valid, 0, valid.length - 4);
    expect(() => GlbAsset.parse(truncated), throwsFormatException);

    final badJsonGlb = Uint8List.fromList([
      0x67, 0x6C, 0x54, 0x46, // glTF
      2, 0, 0, 0, // v2
      24, 0, 0, 0, // total len 24
      4, 0, 0, 0, // json len 4
      0x4A, 0x53, 0x4F, 0x4E, // JSON
      0x5B, 0x5D, 0x20, 0x20, // "[]  " (array instead of object)
    ]);
    expect(() => GlbAsset.parse(badJsonGlb), throwsFormatException);
  });
}
