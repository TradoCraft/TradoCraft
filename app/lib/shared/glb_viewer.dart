import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show setEquals;
import 'package:material_ui/material_ui.dart';

import 'app_icons.dart';

/// Bundled `.glb` asset paths for the 14 standalone tutorial products.
const tutorialGlbAssets = <String, String>{
  'CONV-BELT-1M': 'assets/models/CONV-BELT-1M.glb',
  'MOT-1P-037': 'assets/models/MOT-1P-037.glb',
  'MOT-3P-055': 'assets/models/MOT-3P-055.glb',
  'VFD-3P-055': 'assets/models/VFD-3P-055.glb',
  'PLC-BASE': 'assets/models/PLC-BASE.glb',
  'PLC-EXP-RS485': 'assets/models/PLC-EXP-RS485.glb',
  'PLC-MASTER': 'assets/models/PLC-MASTER.glb',
  'DISP-RS485': 'assets/models/DISP-RS485.glb',
  'MOD-I2C-SWIPE': 'assets/models/MOD-I2C-SWIPE.glb',
  'SENS-I2C-TEMP': 'assets/models/SENS-I2C-TEMP.glb',
  'SENS-IR-24V': 'assets/models/SENS-IR-24V.glb',
  'SENS-420MA': 'assets/models/SENS-420MA.glb',
  'SOL-PUSH': 'assets/models/SOL-PUSH.glb',
  'SOL-LABEL': 'assets/models/SOL-LABEL.glb',
};

/// Returns the bundled `.glb` asset path for [code], or null if none exists.
String? tutorialGlbAssetForCode(String code) => tutorialGlbAssets[code];

/// A single node in a glTF 2.0 `.glb` assembly.
class GlbNode {
  const GlbNode({
    required this.index,
    required this.name,
    required this.depth,
    required this.meshIndex,
    required this.worldMatrix,
    this.parentIndex,
  });

  final int index;
  final String name;
  final int depth;
  final int? meshIndex;
  final Float64List worldMatrix;
  final int? parentIndex;
}

class GlbTriangle {
  const GlbTriangle({
    required this.nodeIndex,
    required this.v0,
    required this.v1,
    required this.v2,
    required this.normal,
    required this.color,
  });

  final int nodeIndex;
  final GlbVec3 v0;
  final GlbVec3 v1;
  final GlbVec3 v2;
  final GlbVec3 normal;
  final Color color;
}

class GlbVec3 {
  const GlbVec3(this.x, this.y, this.z);
  final double x;
  final double y;
  final double z;
}

/// Parsed binary glTF 2.0 (`.glb`) asset with named-node hierarchy and triangle geometry.
class GlbAsset {
  const GlbAsset({
    required this.nodes,
    required this.triangles,
    required this.hasDraco,
  });

  final List<GlbNode> nodes;
  final List<GlbTriangle> triangles;
  final bool hasDraco;

  List<GlbNode> get namedNodes => [
    for (final n in nodes)
      if (n.name.isNotEmpty) n,
  ];

  static List<dynamic> _optList(Map<String, dynamic> map, String key) {
    final v = map[key];
    if (v == null) return const [];
    if (v is! List) {
      throw FormatException('GLB "$key" must be a list');
    }
    return v;
  }

  static Map<String, dynamic> _asMap(Object? v, String name) {
    if (v is! Map<String, dynamic>) {
      throw FormatException('GLB $name must be an object');
    }
    return v;
  }

  static Map<String, dynamic>? _optMap(
    Map<String, dynamic> map,
    String key,
    String name,
  ) {
    final v = map[key];
    if (v == null) return null;
    return _asMap(v, '$name.$key');
  }

  static int? _optInt(Map<String, dynamic> map, String key, String name) {
    final v = map[key];
    if (v == null) return null;
    if (v is! int) {
      throw FormatException('GLB $name.$key must be an integer');
    }
    return v;
  }

  static String? _optString(Map<String, dynamic> map, String key, String name) {
    final v = map[key];
    if (v == null) return null;
    if (v is! String) {
      throw FormatException('GLB $name.$key must be a string');
    }
    return v;
  }

  static List<double> _numList(
    Object? raw,
    int expectedLen,
    String name,
  ) {
    if (raw is! List || raw.length != expectedLen) {
      throw FormatException('GLB $name must be a list of length $expectedLen');
    }
    return [
      for (final item in raw)
        if (item is num)
          item.toDouble()
        else
          throw FormatException('GLB $name entries must be numbers'),
    ];
  }

  /// Parses a glTF 2.0 binary (`.glb`) buffer. Throws [FormatException] if invalid.
  static GlbAsset parse(Uint8List bytes) {
    if (bytes.length < 20) {
      throw const FormatException('File is too small to be a GLB model');
    }
    final bd = ByteData.sublistView(bytes);
    final magic = bd.getUint32(0, Endian.little);
    final version = bd.getUint32(4, Endian.little);
    final declaredLength = bd.getUint32(8, Endian.little);
    if (magic != 0x46546C67 || version != 2) {
      throw const FormatException('Not a valid glTF 2.0 binary (.glb) file');
    }
    if (declaredLength < 20 || declaredLength > bytes.length) {
      throw const FormatException(
        'GLB header length is invalid or file is truncated',
      );
    }

    Uint8List? jsonChunk;
    Uint8List? binChunk;
    var offset = 12;
    while (offset < declaredLength) {
      if (offset + 8 > declaredLength) {
        throw const FormatException('GLB chunk header is truncated');
      }
      final chunkLen = bd.getUint32(offset, Endian.little);
      final chunkType = bd.getUint32(offset + 4, Endian.little);
      final dataStart = offset + 8;
      final dataEnd = dataStart + chunkLen;
      if (dataEnd > declaredLength) {
        throw const FormatException(
          'GLB chunk extends past declared file length',
        );
      }
      if (chunkType == 0x4E4F534A && jsonChunk == null) {
        jsonChunk = Uint8List.sublistView(bytes, dataStart, dataEnd);
      } else if (chunkType == 0x004E4942 && binChunk == null) {
        binChunk = Uint8List.sublistView(bytes, dataStart, dataEnd);
      }
      offset = dataEnd;
    }
    if (jsonChunk == null) {
      throw const FormatException('GLB is missing its JSON chunk');
    }

    final decoded = jsonDecode(utf8.decode(jsonChunk));
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('GLB JSON root must be an object');
    }
    final root = decoded;
    final rawNodes = _optList(root, 'nodes');
    final rawMeshes = _optList(root, 'meshes');
    final rawMaterials = _optList(root, 'materials');
    final rawAccessors = _optList(root, 'accessors');
    final rawViews = _optList(root, 'bufferViews');

    // Determine root nodes from the default scene (or nodes without parents).
    final hasParent = List<bool>.filled(rawNodes.length, false);
    for (var i = 0; i < rawNodes.length; i++) {
      final n = _asMap(rawNodes[i], 'nodes[$i]');
      for (final c in _optList(n, 'children')) {
        if (c is! int) {
          throw FormatException('GLB nodes[$i].children must contain integers');
        }
        if (c >= 0 && c < rawNodes.length) {
          hasParent[c] = true;
        }
      }
    }
    final scenes = _optList(root, 'scenes');
    final sceneIdx = _optInt(root, 'scene', 'root') ?? 0;
    final rootIds = <int>[];
    if (sceneIdx >= 0 && sceneIdx < scenes.length) {
      final s = _asMap(scenes[sceneIdx], 'scenes[$sceneIdx]');
      for (final id in _optList(s, 'nodes')) {
        if (id is! int) {
          throw FormatException(
            'GLB scenes[$sceneIdx].nodes must contain integers',
          );
        }
        if (id >= 0 && id < rawNodes.length) rootIds.add(id);
      }
    }
    if (rootIds.isEmpty) {
      for (var i = 0; i < rawNodes.length; i++) {
        if (!hasParent[i]) rootIds.add(i);
      }
    }

    final nodes = <GlbNode>[];
    final visited = <int>{};
    void walk(int idx, int depth, Float64List parentMat, int? parentIdx) {
      if (idx < 0 || idx >= rawNodes.length || !visited.add(idx)) return;
      final m = _asMap(rawNodes[idx], 'nodes[$idx]');
      final local = _nodeLocalMatrix(m);
      final world = _mulMat4(parentMat, local);
      nodes.add(
        GlbNode(
          index: idx,
          name: (_optString(m, 'name', 'nodes[$idx]') ?? '').trim(),
          depth: depth,
          meshIndex: _optInt(m, 'mesh', 'nodes[$idx]'),
          worldMatrix: world,
          parentIndex: parentIdx,
        ),
      );
      for (final c in _optList(m, 'children')) {
        if (c is! int) {
          throw FormatException('GLB nodes[$idx].children must contain integers');
        }
        walk(c, depth + 1, world, idx);
      }
    }

    final identity = _identityMat4();
    for (final r in rootIds) {
      walk(r, 0, identity, null);
    }

    var hasDraco = false;
    final triangles = <GlbTriangle>[];
    if (binChunk != null) {
      final binBd = ByteData.sublistView(binChunk);
      for (final node in nodes) {
        final meshIdx = node.meshIndex;
        if (meshIdx == null || meshIdx < 0 || meshIdx >= rawMeshes.length) {
          continue;
        }
        final mesh = _asMap(rawMeshes[meshIdx], 'meshes[$meshIdx]');
        final primitives = _optList(mesh, 'primitives');
        for (var pIdx = 0; pIdx < primitives.length; pIdx++) {
          final prim = _asMap(
            primitives[pIdx],
            'meshes[$meshIdx].primitives[$pIdx]',
          );
          final exts = prim['extensions'];
          if (exts is Map && exts.containsKey('KHR_draco_mesh_compression')) {
            hasDraco = true;
            continue;
          }
          final mode = _optInt(prim, 'mode', 'primitive') ?? 4;
          if (mode != 4 && mode != 5 && mode != 6) continue;
          final attrs = _optMap(prim, 'attributes', 'primitive');
          final posIdx = attrs == null
              ? null
              : _optInt(attrs, 'POSITION', 'primitive.attributes');
          if (posIdx == null) continue;
          final positions = _readVec3(
            rawAccessors,
            rawViews,
            binChunk,
            binBd,
            posIdx,
          );
          if (positions.isEmpty) continue;
          final idxAcc = _optInt(prim, 'indices', 'primitive');
          final indices = idxAcc != null
              ? _readIndices(
                  rawAccessors,
                  rawViews,
                  binChunk,
                  binBd,
                  idxAcc,
                )
              : List<int>.generate(positions.length, (i) => i);
          final color = _materialColor(
            rawMaterials,
            _optInt(prim, 'material', 'primitive'),
          );

          final worldPositions = [
            for (final p in positions) _transformPoint(node.worldMatrix, p),
          ];

          void addTri(int i0, int i1, int i2) {
            if (i0 < 0 ||
                i1 < 0 ||
                i2 < 0 ||
                i0 >= worldPositions.length ||
                i1 >= worldPositions.length ||
                i2 >= worldPositions.length) {
              return;
            }
            final v0 = worldPositions[i0];
            final v1 = worldPositions[i1];
            final v2 = worldPositions[i2];
            triangles.add(
              GlbTriangle(
                nodeIndex: node.index,
                v0: v0,
                v1: v1,
                v2: v2,
                normal: _faceNormal(v0, v1, v2),
                color: color,
              ),
            );
          }

          if (mode == 4) {
            for (var i = 0; i + 2 < indices.length; i += 3) {
              addTri(indices[i], indices[i + 1], indices[i + 2]);
            }
          } else if (mode == 5) {
            for (var i = 0; i + 2 < indices.length; i++) {
              if (i.isEven) {
                addTri(indices[i], indices[i + 1], indices[i + 2]);
              } else {
                addTri(indices[i + 1], indices[i], indices[i + 2]);
              }
            }
          } else {
            // mode == 6: TRIANGLE_FAN anchored at indices[0].
            for (var i = 1; i + 1 < indices.length; i++) {
              addTri(indices[0], indices[i], indices[i + 1]);
            }
          }
        }
      }
    }

    return GlbAsset(nodes: nodes, triangles: triangles, hasDraco: hasDraco);
  }

  static Color _materialColor(List<dynamic> materials, int? matIdx) {
    if (matIdx == null || matIdx < 0 || matIdx >= materials.length) {
      return const Color(0xFF90A4AE);
    }
    final mat = _asMap(materials[matIdx], 'materials[$matIdx]');
    final pbr = _optMap(mat, 'pbrMetallicRoughness', 'materials[$matIdx]');
    if (pbr != null && pbr['baseColorFactor'] != null) {
      final rawFactor = pbr['baseColorFactor'];
      if (rawFactor is! List) {
        throw FormatException(
          'GLB materials[$matIdx].pbrMetallicRoughness.baseColorFactor must be a list',
        );
      }
      if (rawFactor.length >= 3) {
        for (var i = 0; i < 3; i++) {
          if (rawFactor[i] is! num) {
            throw FormatException(
              'GLB materials[$matIdx] baseColorFactor[$i] must be a number',
            );
          }
        }
        final r = ((rawFactor[0] as num).toDouble().clamp(0.0, 1.0) * 255)
            .round();
        final g = ((rawFactor[1] as num).toDouble().clamp(0.0, 1.0) * 255)
            .round();
        final b = ((rawFactor[2] as num).toDouble().clamp(0.0, 1.0) * 255)
            .round();
        return Color.fromARGB(255, r, g, b);
      }
    }
    return const Color(0xFF90A4AE);
  }

  static ({int viewOffset, int viewEnd, int? stride}) _viewBounds(
    List<dynamic> views,
    int viewIdx,
    int binLength,
  ) {
    final view = _asMap(views[viewIdx], 'bufferViews[$viewIdx]');
    final viewOffset = _optInt(view, 'byteOffset', 'bufferViews[$viewIdx]') ?? 0;
    final viewLength = _optInt(view, 'byteLength', 'bufferViews[$viewIdx]');
    if (viewOffset < 0 || viewLength == null || viewLength < 0) {
      throw FormatException(
        'GLB bufferViews[$viewIdx] has invalid byteOffset/byteLength',
      );
    }
    final stride = _optInt(view, 'byteStride', 'bufferViews[$viewIdx]');
    final viewEnd = math.min(binLength, viewOffset + viewLength);
    return (viewOffset: viewOffset, viewEnd: viewEnd, stride: stride);
  }

  static List<int> _readScalarIndicesFromView(
    List<dynamic> views,
    Uint8List bin,
    ByteData bd,
    int viewIdx,
    int accOffset,
    int count,
    int? comp,
  ) {
    if (viewIdx < 0 || viewIdx >= views.length || accOffset < 0 || count <= 0) {
      return const [];
    }
    final bounds = _viewBounds(views, viewIdx, bin.length);
    final base = bounds.viewOffset + accOffset;
    if (base < bounds.viewOffset) return const [];
    final out = <int>[];
    if (comp == 5121) {
      for (var i = 0; i < count && base + i < bounds.viewEnd; i++) {
        out.add(bin[base + i]);
      }
    } else if (comp == 5123) {
      for (var i = 0; i < count && base + i * 2 + 2 <= bounds.viewEnd; i++) {
        out.add(bd.getUint16(base + i * 2, Endian.little));
      }
    } else if (comp == 5125) {
      for (var i = 0; i < count && base + i * 4 + 4 <= bounds.viewEnd; i++) {
        out.add(bd.getUint32(base + i * 4, Endian.little));
      }
    }
    return out;
  }

  static List<GlbVec3> _readVec3FromView(
    List<dynamic> views,
    Uint8List bin,
    ByteData bd,
    int viewIdx,
    int accOffset,
    int count,
  ) {
    if (viewIdx < 0 || viewIdx >= views.length || accOffset < 0 || count <= 0) {
      return const [];
    }
    final bounds = _viewBounds(views, viewIdx, bin.length);
    final stride = bounds.stride ?? 12;
    if (stride < 12) return const [];
    final out = <GlbVec3>[];
    for (var i = 0; i < count; i++) {
      final base = bounds.viewOffset + accOffset + i * stride;
      if (base < bounds.viewOffset || base + 12 > bounds.viewEnd) break;
      out.add(
        GlbVec3(
          bd.getFloat32(base, Endian.little),
          bd.getFloat32(base + 4, Endian.little),
          bd.getFloat32(base + 8, Endian.little),
        ),
      );
    }
    return out;
  }

  static List<GlbVec3> _readVec3(
    List<dynamic> accessors,
    List<dynamic> views,
    Uint8List bin,
    ByteData bd,
    int accIdx,
  ) {
    if (accIdx < 0 || accIdx >= accessors.length) return const [];
    final acc = _asMap(accessors[accIdx], 'accessors[$accIdx]');
    if (_optInt(acc, 'componentType', 'accessors[$accIdx]') != 5126 ||
        _optString(acc, 'type', 'accessors[$accIdx]') != 'VEC3') {
      return const [];
    }
    final count = _optInt(acc, 'count', 'accessors[$accIdx]') ?? 0;
    if (count <= 0) return const [];
    final viewIdx = _optInt(acc, 'bufferView', 'accessors[$accIdx]');
    final accOffset = _optInt(acc, 'byteOffset', 'accessors[$accIdx]') ?? 0;
    final sparse = _optMap(acc, 'sparse', 'accessors[$accIdx]');

    List<GlbVec3> out;
    if (viewIdx == null) {
      if (sparse == null) return const [];
      out = List<GlbVec3>.filled(
        count,
        const GlbVec3(0, 0, 0),
        growable: true,
      );
    } else {
      if (viewIdx < 0 || viewIdx >= views.length) return const [];
      out = _readVec3FromView(views, bin, bd, viewIdx, accOffset, count);
    }

    if (sparse != null) {
      final sparseCount = _optInt(sparse, 'count', 'sparse') ?? 0;
      if (sparseCount > 0) {
        final sIndices = _optMap(sparse, 'indices', 'sparse');
        final sValues = _optMap(sparse, 'values', 'sparse');
        if (sIndices == null || sValues == null) {
          throw const FormatException(
            'GLB sparse accessor must define indices and values',
          );
        }
        final idxView = _optInt(sIndices, 'bufferView', 'sparse.indices');
        final valView = _optInt(sValues, 'bufferView', 'sparse.values');
        if (idxView == null || valView == null) {
          throw const FormatException(
            'GLB sparse indices and values must specify bufferView',
          );
        }
        final idxOffset =
            _optInt(sIndices, 'byteOffset', 'sparse.indices') ?? 0;
        final idxComp = _optInt(sIndices, 'componentType', 'sparse.indices');
        final valOffset = _optInt(sValues, 'byteOffset', 'sparse.values') ?? 0;
        final patchIdx = _readScalarIndicesFromView(
          views,
          bin,
          bd,
          idxView,
          idxOffset,
          sparseCount,
          idxComp,
        );
        final patchVals = _readVec3FromView(
          views,
          bin,
          bd,
          valView,
          valOffset,
          sparseCount,
        );
        final n = math.min(patchIdx.length, patchVals.length);
        for (var k = 0; k < n; k++) {
          final target = patchIdx[k];
          if (target >= 0 && target < out.length) {
            out[target] = patchVals[k];
          }
        }
      }
    }
    return out;
  }

  static List<int> _readIndices(
    List<dynamic> accessors,
    List<dynamic> views,
    Uint8List bin,
    ByteData bd,
    int accIdx,
  ) {
    if (accIdx < 0 || accIdx >= accessors.length) return const [];
    final acc = _asMap(accessors[accIdx], 'accessors[$accIdx]');
    final viewIdx = _optInt(acc, 'bufferView', 'accessors[$accIdx]');
    if (viewIdx == null || viewIdx < 0 || viewIdx >= views.length) {
      return const [];
    }
    final count = _optInt(acc, 'count', 'accessors[$accIdx]') ?? 0;
    final comp = _optInt(acc, 'componentType', 'accessors[$accIdx]');
    final accOffset = _optInt(acc, 'byteOffset', 'accessors[$accIdx]') ?? 0;
    return _readScalarIndicesFromView(
      views,
      bin,
      bd,
      viewIdx,
      accOffset,
      count,
      comp,
    );
  }

  static Float64List _identityMat4() => Float64List.fromList([
    1, 0, 0, 0,
    0, 1, 0, 0,
    0, 0, 1, 0,
    0, 0, 0, 1,
  ]);

  static Float64List _nodeLocalMatrix(Map<String, dynamic> node) {
    if (node['matrix'] != null) {
      return Float64List.fromList(_numList(node['matrix'], 16, 'node.matrix'));
    }
    final t = node['translation'] != null
        ? _numList(node['translation'], 3, 'node.translation')
        : const [0.0, 0.0, 0.0];
    final r = node['rotation'] != null
        ? _numList(node['rotation'], 4, 'node.rotation')
        : const [0.0, 0.0, 0.0, 1.0];
    final s = node['scale'] != null
        ? _numList(node['scale'], 3, 'node.scale')
        : const [1.0, 1.0, 1.0];
    final tx = t[0];
    final ty = t[1];
    final tz = t[2];
    final x = r[0];
    final y = r[1];
    final z = r[2];
    final w = r[3];
    final sx = s[0];
    final sy = s[1];
    final sz = s[2];

    final x2 = x + x;
    final y2 = y + y;
    final z2 = z + z;
    final xx = x * x2;
    final xy = x * y2;
    final xz = x * z2;
    final yy = y * y2;
    final yz = y * z2;
    final zz = z * z2;
    final wx = w * x2;
    final wy = w * y2;
    final wz = w * z2;

    return Float64List.fromList([
      (1 - (yy + zz)) * sx,
      (xy + wz) * sx,
      (xz - wy) * sx,
      0,
      (xy - wz) * sy,
      (1 - (xx + zz)) * sy,
      (yz + wx) * sy,
      0,
      (xz + wy) * sz,
      (yz - wx) * sz,
      (1 - (xx + yy)) * sz,
      0,
      tx,
      ty,
      tz,
      1,
    ]);
  }

  static Float64List _mulMat4(Float64List a, Float64List b) {
    final out = Float64List(16);
    for (var col = 0; col < 4; col++) {
      for (var row = 0; row < 4; row++) {
        out[col * 4 + row] =
            a[row] * b[col * 4] +
            a[4 + row] * b[col * 4 + 1] +
            a[8 + row] * b[col * 4 + 2] +
            a[12 + row] * b[col * 4 + 3];
      }
    }
    return out;
  }

  static GlbVec3 _transformPoint(Float64List m, GlbVec3 v) => GlbVec3(
    m[0] * v.x + m[4] * v.y + m[8] * v.z + m[12],
    m[1] * v.x + m[5] * v.y + m[9] * v.z + m[13],
    m[2] * v.x + m[6] * v.y + m[10] * v.z + m[14],
  );

  static GlbVec3 _faceNormal(GlbVec3 a, GlbVec3 b, GlbVec3 c) {
    final ux = b.x - a.x;
    final uy = b.y - a.y;
    final uz = b.z - a.z;
    final vx = c.x - a.x;
    final vy = c.y - a.y;
    final vz = c.z - a.z;
    final nx = uy * vz - uz * vy;
    final ny = uz * vx - ux * vz;
    final nz = ux * vy - uy * vx;
    final len = math.sqrt(nx * nx + ny * ny + nz * nz);
    if (len < 1e-8) return const GlbVec3(0, 1, 0);
    return GlbVec3(nx / len, ny / len, nz / len);
  }
}

/// Compact non-interactive 3D preview of a `.glb` model for list thumbnails and hover cards.
class GlbMiniPreview extends StatefulWidget {
  const GlbMiniPreview({super.key, required this.bytes});

  final Uint8List bytes;

  @override
  State<GlbMiniPreview> createState() => _GlbMiniPreviewState();
}

class _GlbMiniPreviewState extends State<GlbMiniPreview> {
  GlbAsset? _asset;

  @override
  void initState() {
    super.initState();
    _parse();
  }

  @override
  void didUpdateWidget(GlbMiniPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.bytes, widget.bytes)) _parse();
  }

  void _parse() {
    try {
      _asset = GlbAsset.parse(widget.bytes);
    } catch (_) {
      _asset = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final asset = _asset;
    if (asset == null || asset.triangles.isEmpty) {
      return const Center(child: Icon(Icons.view_in_ar_outlined));
    }
    return CustomPaint(
      size: Size.infinite,
      painter: _GlbPainter(
        triangles: asset.triangles.length <= 4000
            ? asset.triangles
            : List<GlbTriangle>.generate(
                4000,
                (i) => asset.triangles[(i * asset.triangles.length) ~/ 4000],
                growable: false,
              ),
        hiddenNodes: const {},
        selectedNodes: const {},
        highlightColor: Theme.of(context).colorScheme.primary,
        yaw: 0.6,
        pitch: 0.4,
        zoom: 1.0,
      ),
    );
  }
}

/// Interactive 3D viewer for glTF 2.0 `.glb` assemblies with named-node highlighting and visibility.
class GlbViewer extends StatefulWidget {
  const GlbViewer({super.key, required this.bytes, this.filename});

  final Uint8List bytes;
  final String? filename;

  @override
  State<GlbViewer> createState() => _GlbViewerState();
}

class _GlbViewerState extends State<GlbViewer> {
  static const int _maxPreviewTriangles = 12000;

  GlbAsset? _asset;
  List<GlbTriangle> _previewTriangles = const [];
  String? _error;
  int? _selectedNode;
  final Set<int> _hiddenNodes = {};
  double _yaw = 0.6;
  double _pitch = 0.4;
  double _zoom = 1.0;

  @override
  void initState() {
    super.initState();
    _parse();
  }

  @override
  void didUpdateWidget(GlbViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.bytes, widget.bytes)) {
      _selectedNode = null;
      _hiddenNodes.clear();
      _parse();
    }
  }

  void _parse() {
    try {
      final asset = GlbAsset.parse(widget.bytes);
      final tris = asset.triangles;
      _asset = asset;
      _previewTriangles = tris.length <= _maxPreviewTriangles
          ? tris
          : List<GlbTriangle>.generate(
              _maxPreviewTriangles,
              (i) => tris[(i * tris.length) ~/ _maxPreviewTriangles],
              growable: false,
            );
      _error = null;
    } catch (e) {
      _asset = null;
      _previewTriangles = const [];
      _error = e.toString();
    }
  }

  static Set<int> _expandSubtree(List<GlbNode> nodes, Set<int> roots) {
    if (roots.isEmpty) return const {};
    final out = <int>{...roots};
    for (final n in nodes) {
      if (n.parentIndex != null && out.contains(n.parentIndex)) {
        out.add(n.index);
      }
    }
    return out;
  }

  void _resetView() {
    setState(() {
      _yaw = 0.6;
      _pitch = 0.4;
      _zoom = 1.0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (_error != null || _asset == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(_error ?? 'Unable to read 3D model'),
        ),
      );
    }
    final asset = _asset!;
    final named = asset.namedNodes;

    final viewport = GestureDetector(
      onPanUpdate: (d) => setState(() {
        _yaw += d.delta.dx * 0.01;
        _pitch = (_pitch + d.delta.dy * 0.01).clamp(-1.4, 1.4);
      }),
      child: Stack(
        children: [
          Container(
            color: theme.colorScheme.surfaceContainerLow,
            child: asset.triangles.isEmpty
                ? Center(
                    child: Text(
                      asset.hasDraco
                          ? 'Draco-compressed mesh (named parts listed)'
                          : 'No triangle geometry in model',
                    ),
                  )
                : CustomPaint(
                    key: const ValueKey('glb-canvas'),
                    size: Size.infinite,
                    painter: _GlbPainter(
                      triangles: _previewTriangles,
                      hiddenNodes: Set<int>.unmodifiable(
                        _expandSubtree(asset.nodes, _hiddenNodes),
                      ),
                      selectedNodes: Set<int>.unmodifiable(
                        _expandSubtree(
                          asset.nodes,
                          _selectedNode == null ? const {} : {_selectedNode!},
                        ),
                      ),
                      highlightColor: theme.colorScheme.primary,
                      yaw: _yaw,
                      pitch: _pitch,
                      zoom: _zoom,
                    ),
                  ),
          ),
          Positioned(
            right: 8,
            bottom: 8,
            child: Card(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: Overlay.maybeOf(context) != null
                        ? 'Zoom in'
                        : null,
                    icon: const Icon(AppIcons.add),
                    onPressed: () =>
                        setState(() => _zoom = (_zoom * 1.25).clamp(0.3, 5.0)),
                  ),
                  IconButton(
                    tooltip: Overlay.maybeOf(context) != null
                        ? 'Zoom out'
                        : null,
                    icon: const Icon(Icons.remove),
                    onPressed: () =>
                        setState(() => _zoom = (_zoom / 1.25).clamp(0.3, 5.0)),
                  ),
                  IconButton(
                    tooltip: Overlay.maybeOf(context) != null
                        ? 'Reset view'
                        : null,
                    icon: const Icon(AppIcons.refresh),
                    onPressed: _resetView,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );

    final nodePanel = Container(
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 8, 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Assembly parts (${named.length})',
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                if (_hiddenNodes.isNotEmpty || _selectedNode != null)
                  TextButton(
                    key: const ValueKey('glb-show-all'),
                    onPressed: () => setState(() {
                      _hiddenNodes.clear();
                      _selectedNode = null;
                    }),
                    child: const Text('Show all'),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: named.isEmpty
                ? const Center(child: Text('No named parts'))
                : ListView.builder(
                    itemCount: named.length,
                    itemBuilder: (_, i) {
                      final n = named[i];
                      final hidden = _hiddenNodes.contains(n.index);
                      final selected = _selectedNode == n.index;
                      return ListTile(
                        key: ValueKey('glb-node-${n.index}'),
                        dense: true,
                        selected: selected,
                        contentPadding: EdgeInsets.only(
                          left: 12.0 + n.depth * 12.0,
                          right: 4,
                        ),
                        title: Text(
                          n.name,
                          overflow: TextOverflow.ellipsis,
                          style: hidden
                              ? TextStyle(color: theme.disabledColor)
                              : null,
                        ),
                        trailing: IconButton(
                          key: ValueKey('glb-node-toggle-${n.index}'),
                          icon: Icon(
                            hidden
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                            size: 18,
                          ),
                          onPressed: () => setState(() {
                            if (hidden) {
                              _hiddenNodes.remove(n.index);
                            } else {
                              _hiddenNodes.add(n.index);
                            }
                          }),
                        ),
                        onTap: () => setState(() {
                          _selectedNode = selected ? null : n.index;
                        }),
                      );
                    },
                  ),
          ),
        ],
      ),
    );

    return LayoutBuilder(
      builder: (_, box) {
        if (box.maxWidth >= 600) {
          return Row(
            children: [
              Expanded(child: viewport),
              SizedBox(width: 240, child: nodePanel),
            ],
          );
        }
        return Column(
          children: [
            Expanded(flex: 3, child: viewport),
            Expanded(flex: 2, child: nodePanel),
          ],
        );
      },
    );
  }
}

class _GlbPainter extends CustomPainter {
  _GlbPainter({
    required this.triangles,
    required this.hiddenNodes,
    required this.selectedNodes,
    required this.highlightColor,
    required this.yaw,
    required this.pitch,
    required this.zoom,
  });

  final List<GlbTriangle> triangles;
  final Set<int> hiddenNodes;
  final Set<int> selectedNodes;
  final Color highlightColor;
  final double yaw;
  final double pitch;
  final double zoom;

  @override
  void paint(Canvas canvas, Size size) {
    if (triangles.isEmpty || size.isEmpty) return;

    var minX = double.infinity;
    var minY = double.infinity;
    var minZ = double.infinity;
    var maxX = -double.infinity;
    var maxY = -double.infinity;
    var maxZ = -double.infinity;
    for (final t in triangles) {
      for (final v in [t.v0, t.v1, t.v2]) {
        if (v.x < minX) minX = v.x;
        if (v.y < minY) minY = v.y;
        if (v.z < minZ) minZ = v.z;
        if (v.x > maxX) maxX = v.x;
        if (v.y > maxY) maxY = v.y;
        if (v.z > maxZ) maxZ = v.z;
      }
    }
    final cx = (minX + maxX) / 2;
    final cy = (minY + maxY) / 2;
    final cz = (minZ + maxZ) / 2;
    final extent = math.max(
      1e-4,
      math.max(maxX - minX, math.max(maxY - minY, maxZ - minZ)),
    );
    final scale = (math.min(size.width, size.height) * 0.65 / extent) * zoom;

    final cosY = math.cos(yaw);
    final sinY = math.sin(yaw);
    final cosP = math.cos(pitch);
    final sinP = math.sin(pitch);

    GlbVec3 rot(GlbVec3 v) {
      final dx = v.x - cx;
      final dy = v.y - cy;
      final dz = v.z - cz;
      final rx = dx * cosY - dz * sinY;
      final rz = dx * sinY + dz * cosY;
      final ry = dy * cosP - rz * sinP;
      final rz2 = dy * sinP + rz * cosP;
      return GlbVec3(rx, ry, rz2);
    }

    final projected = <({Path path, double depth, Color color})>[];
    for (final t in triangles) {
      if (hiddenNodes.contains(t.nodeIndex)) continue;
      final p0 = rot(t.v0);
      final p1 = rot(t.v1);
      final p2 = rot(t.v2);
      final depth = (p0.z + p1.z + p2.z) / 3;

      final nr = rot(
        GlbVec3(cx + t.normal.x, cy + t.normal.y, cz + t.normal.z),
      );
      final light = (0.35 + 0.65 * nr.z.abs()).clamp(0.25, 1.0);
      var base = t.color;
      if (selectedNodes.isNotEmpty) {
        base = selectedNodes.contains(t.nodeIndex)
            ? highlightColor
            : base.withValues(alpha: 0.35);
      }
      final shaded = Color.fromARGB(
        (base.a * 255).round(),
        (base.r * 255 * light).round().clamp(0, 255),
        (base.g * 255 * light).round().clamp(0, 255),
        (base.b * 255 * light).round().clamp(0, 255),
      );

      final ox = size.width / 2;
      final oy = size.height / 2;
      final path = Path()
        ..moveTo(ox + p0.x * scale, oy - p0.y * scale)
        ..lineTo(ox + p1.x * scale, oy - p1.y * scale)
        ..lineTo(ox + p2.x * scale, oy - p2.y * scale)
        ..close();
      projected.add((path: path, depth: depth, color: shaded));
    }

    projected.sort((a, b) => a.depth.compareTo(b.depth));
    final fill = Paint()..style = PaintingStyle.fill;
    final edge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5
      ..color = Colors.black.withValues(alpha: 0.12);
    for (final item in projected) {
      fill.color = item.color;
      canvas.drawPath(item.path, fill);
      canvas.drawPath(item.path, edge);
    }
  }

  @override
  bool shouldRepaint(_GlbPainter old) =>
      old.yaw != yaw ||
      old.pitch != pitch ||
      old.zoom != zoom ||
      old.highlightColor != highlightColor ||
      !setEquals(old.selectedNodes, selectedNodes) ||
      !setEquals(old.hiddenNodes, hiddenNodes) ||
      old.triangles != triangles;
}
