import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';

import 'app_icons.dart';

/// A single node in a glTF 2.0 `.glb` assembly.
class GlbNode {
  const GlbNode({
    required this.index,
    required this.name,
    required this.depth,
    required this.meshIndex,
    required this.worldMatrix,
  });

  final int index;
  final String name;
  final int depth;
  final int? meshIndex;
  final Float64List worldMatrix;
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

  /// Parses a glTF 2.0 binary (`.glb`) buffer. Throws [FormatException] if invalid.
  static GlbAsset parse(Uint8List bytes) {
    if (bytes.length < 20) {
      throw const FormatException('File is too small to be a GLB model');
    }
    final bd = ByteData.sublistView(bytes);
    final magic = bd.getUint32(0, Endian.little);
    final version = bd.getUint32(4, Endian.little);
    if (magic != 0x46546C67 || version != 2) {
      throw const FormatException('Not a valid glTF 2.0 binary (.glb) file');
    }

    Uint8List? jsonChunk;
    Uint8List? binChunk;
    var offset = 12;
    while (offset + 8 <= bytes.length) {
      final chunkLen = bd.getUint32(offset, Endian.little);
      final chunkType = bd.getUint32(offset + 4, Endian.little);
      final dataStart = offset + 8;
      final dataEnd = math.min(dataStart + chunkLen, bytes.length);
      if (chunkType == 0x4E4F534A && jsonChunk == null) {
        jsonChunk = Uint8List.sublistView(bytes, dataStart, dataEnd);
      } else if (chunkType == 0x004E4942 && binChunk == null) {
        binChunk = Uint8List.sublistView(bytes, dataStart, dataEnd);
      }
      offset = dataStart + chunkLen;
    }
    if (jsonChunk == null) {
      throw const FormatException('GLB is missing its JSON chunk');
    }

    final root = jsonDecode(utf8.decode(jsonChunk)) as Map<String, dynamic>;
    final rawNodes = (root['nodes'] as List?) ?? const [];
    final rawMeshes = (root['meshes'] as List?) ?? const [];
    final rawMaterials = (root['materials'] as List?) ?? const [];
    final rawAccessors = (root['accessors'] as List?) ?? const [];
    final rawViews = (root['bufferViews'] as List?) ?? const [];

    // Determine root nodes from the default scene (or nodes without parents).
    final hasParent = List<bool>.filled(rawNodes.length, false);
    for (final n in rawNodes) {
      if (n is Map) {
        for (final c in (n['children'] as List?) ?? const []) {
          if (c is int && c >= 0 && c < rawNodes.length) {
            hasParent[c] = true;
          }
        }
      }
    }
    final scenes = (root['scenes'] as List?) ?? const [];
    final sceneIdx = (root['scene'] as int?) ?? 0;
    final rootIds = <int>[];
    if (sceneIdx >= 0 && sceneIdx < scenes.length) {
      final s = scenes[sceneIdx];
      if (s is Map && s['nodes'] is List) {
        for (final id in s['nodes'] as List) {
          if (id is int && id >= 0 && id < rawNodes.length) rootIds.add(id);
        }
      }
    }
    if (rootIds.isEmpty) {
      for (var i = 0; i < rawNodes.length; i++) {
        if (!hasParent[i]) rootIds.add(i);
      }
    }

    final nodes = <GlbNode>[];
    final visited = <int>{};
    void walk(int idx, int depth, Float64List parentMat) {
      if (idx < 0 || idx >= rawNodes.length || !visited.add(idx)) return;
      final m = rawNodes[idx] as Map<String, dynamic>;
      final local = _nodeLocalMatrix(m);
      final world = _mulMat4(parentMat, local);
      nodes.add(
        GlbNode(
          index: idx,
          name: (m['name'] as String?)?.trim() ?? '',
          depth: depth,
          meshIndex: m['mesh'] as int?,
          worldMatrix: world,
        ),
      );
      for (final c in (m['children'] as List?) ?? const []) {
        if (c is int) walk(c, depth + 1, world);
      }
    }

    final identity = _identityMat4();
    for (final r in rootIds) {
      walk(r, 0, identity);
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
        final mesh = rawMeshes[meshIdx] as Map<String, dynamic>;
        final primitives = (mesh['primitives'] as List?) ?? const [];
        for (final prim in primitives) {
          if (prim is! Map<String, dynamic>) continue;
          final exts = prim['extensions'];
          if (exts is Map && exts.containsKey('KHR_draco_mesh_compression')) {
            hasDraco = true;
            continue;
          }
          final mode = (prim['mode'] as int?) ?? 4;
          if (mode != 4) continue;
          final attrs = prim['attributes'] as Map<String, dynamic>?;
          final posIdx = attrs?['POSITION'] as int?;
          if (posIdx == null) continue;
          final positions = _readVec3(
            rawAccessors,
            rawViews,
            binChunk,
            binBd,
            posIdx,
          );
          if (positions.isEmpty) continue;
          final indices = prim['indices'] is int
              ? _readIndices(
                  rawAccessors,
                  rawViews,
                  binChunk,
                  binBd,
                  prim['indices'] as int,
                )
              : List<int>.generate(positions.length, (i) => i);
          final color = _materialColor(rawMaterials, prim['material'] as int?);

          final worldPositions = [
            for (final p in positions) _transformPoint(node.worldMatrix, p),
          ];
          for (var i = 0; i + 2 < indices.length; i += 3) {
            final i0 = indices[i];
            final i1 = indices[i + 1];
            final i2 = indices[i + 2];
            if (i0 >= worldPositions.length ||
                i1 >= worldPositions.length ||
                i2 >= worldPositions.length) {
              continue;
            }
            final v0 = worldPositions[i0];
            final v1 = worldPositions[i1];
            final v2 = worldPositions[i2];
            final n = _faceNormal(v0, v1, v2);
            triangles.add(
              GlbTriangle(
                nodeIndex: node.index,
                v0: v0,
                v1: v1,
                v2: v2,
                normal: n,
                color: color,
              ),
            );
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
    final mat = materials[matIdx];
    if (mat is! Map<String, dynamic>) return const Color(0xFF90A4AE);
    final pbr = mat['pbrMetallicRoughness'];
    if (pbr is Map<String, dynamic> && pbr['baseColorFactor'] is List) {
      final f = pbr['baseColorFactor'] as List;
      if (f.length >= 3) {
        final r = ((f[0] as num).toDouble().clamp(0.0, 1.0) * 255).round();
        final g = ((f[1] as num).toDouble().clamp(0.0, 1.0) * 255).round();
        final b = ((f[2] as num).toDouble().clamp(0.0, 1.0) * 255).round();
        return Color.fromARGB(255, r, g, b);
      }
    }
    return const Color(0xFF90A4AE);
  }

  static List<GlbVec3> _readVec3(
    List<dynamic> accessors,
    List<dynamic> views,
    Uint8List bin,
    ByteData bd,
    int accIdx,
  ) {
    if (accIdx < 0 || accIdx >= accessors.length) return const [];
    final acc = accessors[accIdx] as Map<String, dynamic>;
    if (acc['componentType'] != 5126 || acc['type'] != 'VEC3') return const [];
    final viewIdx = acc['bufferView'] as int?;
    if (viewIdx == null || viewIdx < 0 || viewIdx >= views.length) {
      return const [];
    }
    final view = views[viewIdx] as Map<String, dynamic>;
    final count = (acc['count'] as int?) ?? 0;
    final viewOffset = (view['byteOffset'] as int?) ?? 0;
    final accOffset = (acc['byteOffset'] as int?) ?? 0;
    final stride = (view['byteStride'] as int?) ?? 12;
    final out = <GlbVec3>[];
    for (var i = 0; i < count; i++) {
      final base = viewOffset + accOffset + i * stride;
      if (base + 12 > bin.length) break;
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

  static List<int> _readIndices(
    List<dynamic> accessors,
    List<dynamic> views,
    Uint8List bin,
    ByteData bd,
    int accIdx,
  ) {
    if (accIdx < 0 || accIdx >= accessors.length) return const [];
    final acc = accessors[accIdx] as Map<String, dynamic>;
    final viewIdx = acc['bufferView'] as int?;
    if (viewIdx == null || viewIdx < 0 || viewIdx >= views.length) {
      return const [];
    }
    final view = views[viewIdx] as Map<String, dynamic>;
    final count = (acc['count'] as int?) ?? 0;
    final comp = acc['componentType'] as int?;
    final viewOffset = (view['byteOffset'] as int?) ?? 0;
    final accOffset = (acc['byteOffset'] as int?) ?? 0;
    final base = viewOffset + accOffset;
    final out = <int>[];
    if (comp == 5121) {
      for (var i = 0; i < count && base + i < bin.length; i++) {
        out.add(bin[base + i]);
      }
    } else if (comp == 5123) {
      for (var i = 0; i < count && base + i * 2 + 2 <= bin.length; i++) {
        out.add(bd.getUint16(base + i * 2, Endian.little));
      }
    } else if (comp == 5125) {
      for (var i = 0; i < count && base + i * 4 + 4 <= bin.length; i++) {
        out.add(bd.getUint32(base + i * 4, Endian.little));
      }
    }
    return out;
  }

  static Float64List _identityMat4() => Float64List.fromList([
    1, 0, 0, 0,
    0, 1, 0, 0,
    0, 0, 1, 0,
    0, 0, 0, 1,
  ]);

  static Float64List _nodeLocalMatrix(Map<String, dynamic> node) {
    if (node['matrix'] is List && (node['matrix'] as List).length == 16) {
      return Float64List.fromList([
        for (final v in node['matrix'] as List) (v as num).toDouble(),
      ]);
    }
    final t = (node['translation'] as List?) ?? const [0, 0, 0];
    final r = (node['rotation'] as List?) ?? const [0, 0, 0, 1];
    final s = (node['scale'] as List?) ?? const [1, 1, 1];
    final tx = (t[0] as num).toDouble();
    final ty = (t[1] as num).toDouble();
    final tz = (t[2] as num).toDouble();
    final x = (r[0] as num).toDouble();
    final y = (r[1] as num).toDouble();
    final z = (r[2] as num).toDouble();
    final w = (r[3] as num).toDouble();
    final sx = (s[0] as num).toDouble();
    final sy = (s[1] as num).toDouble();
    final sz = (s[2] as num).toDouble();

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

/// Interactive 3D viewer for glTF 2.0 `.glb` assemblies with named-node highlighting and visibility.
class GlbViewer extends StatefulWidget {
  const GlbViewer({super.key, required this.bytes, this.filename});

  final Uint8List bytes;
  final String? filename;

  @override
  State<GlbViewer> createState() => _GlbViewerState();
}

class _GlbViewerState extends State<GlbViewer> {
  GlbAsset? _asset;
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
      _asset = GlbAsset.parse(widget.bytes);
      _error = null;
    } catch (e) {
      _asset = null;
      _error = e.toString();
    }
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
                      triangles: asset.triangles,
                      hiddenNodes: _hiddenNodes,
                      selectedNode: _selectedNode,
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
                    tooltip: 'Zoom in',
                    icon: const Icon(AppIcons.add),
                    onPressed: () =>
                        setState(() => _zoom = (_zoom * 1.25).clamp(0.3, 5.0)),
                  ),
                  IconButton(
                    tooltip: 'Zoom out',
                    icon: const Icon(Icons.remove),
                    onPressed: () =>
                        setState(() => _zoom = (_zoom / 1.25).clamp(0.3, 5.0)),
                  ),
                  IconButton(
                    tooltip: 'Reset view',
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
    required this.selectedNode,
    required this.highlightColor,
    required this.yaw,
    required this.pitch,
    required this.zoom,
  });

  final List<GlbTriangle> triangles;
  final Set<int> hiddenNodes;
  final int? selectedNode;
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
      if (selectedNode != null) {
        base = t.nodeIndex == selectedNode
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
      old.selectedNode != selectedNode ||
      old.hiddenNodes.length != hiddenNodes.length ||
      old.triangles != triangles;
}
