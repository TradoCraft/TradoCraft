import 'dart:convert';
import 'dart:ui' show PointerDeviceKind;
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tradocraft_app/features/products/product_thumb.dart';
import 'package:tradocraft_app/shared/glb_viewer.dart';
import 'package:tradocraft_app/shared/photos.dart';

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
}
