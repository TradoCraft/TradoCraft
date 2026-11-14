/// Pure logic behind the admin module tree: building the display tree from the flat catalogue and
/// dependency-aware switching. No Flutter imports, so it is unit-tested on its own.
library;

/// One row of the module tree. A module with several requirements appears once under each of
/// them; only the first occurrence has [repeat] false.
class ModuleTreeNode {
  /// Creates a node.
  ModuleTreeNode({
    required this.code,
    required this.depth,
    required this.parent,
    required this.repeat,
    required this.otherRequires,
    required this.requires,
  });

  /// The module code.
  final String code;

  /// Zero for roots.
  final int depth;

  /// The module this row is listed under; null for roots.
  final String? parent;

  /// True when the module was already listed elsewhere in the tree.
  final bool repeat;

  /// Direct requirements other than [parent].
  final List<String> otherRequires;

  /// All direct requirements, in catalogue order.
  final List<String> requires;

  /// Modules that require this one (empty on repeats, whose subtree is shown at the first
  /// occurrence).
  final List<ModuleTreeNode> children = [];

  /// A stable widget key and expansion-state id: the code for the first occurrence.
  String get id => repeat ? '$code-under-$parent' : code;
}

/// Builds the forest from [requires] (module code -> direct requirements; iteration order is the
/// catalogue order). Roots have no requirements; children are the modules that require the parent.
/// Requirements on unknown codes are ignored. Cycles cannot occur in the catalogue, but if one
/// does the modules in it are still listed (as extra roots) and nothing loops.
List<ModuleTreeNode> buildModuleTree(Map<String, List<String>> requires) {
  final order = requires.keys.toList();
  final known = order.toSet();
  List<String> reqs(String c) => [
    for (final o in order)
      if (requires[c]!.contains(o)) o,
  ];
  final dependents = <String, List<String>>{
    for (final c in order)
      c: [
        for (final o in order)
          if (requires[o]!.contains(c) && o != c) o,
      ],
  };
  final seen = <String>{};

  ModuleTreeNode make(
    String code,
    int depth,
    String? parent,
    Set<String> path,
  ) {
    final repeat = seen.contains(code);
    seen.add(code);
    final r = reqs(code);
    final node = ModuleTreeNode(
      code: code,
      depth: depth,
      parent: parent,
      repeat: repeat,
      otherRequires: [
        for (final o in r)
          if (o != parent) o,
      ],
      requires: r,
    );
    if (!repeat) {
      final next = {...path, code};
      for (final child in dependents[code]!) {
        if (next.contains(child)) continue;
        node.children.add(make(child, depth + 1, code, next));
      }
    }
    return node;
  }

  final roots = <ModuleTreeNode>[];
  for (final c in order) {
    if (reqs(c).isEmpty) roots.add(make(c, 0, null, {}));
  }
  // Defensive: anything not reached (only possible with a cycle) becomes a root.
  for (final c in order) {
    if (known.contains(c) && !seen.contains(c)) roots.add(make(c, 0, null, {}));
  }
  return roots;
}

/// Everything reachable from [start] by following [edges] (excluding [start] itself unless a cycle
/// leads back to it), in no particular order. Terminates on cycles.
Set<String> _closure(String start, Map<String, Iterable<String>> edges) {
  final out = <String>{};
  final todo = [start];
  while (todo.isNotEmpty) {
    for (final n in edges[todo.removeLast()] ?? const <String>[]) {
      if (out.add(n)) todo.add(n);
    }
  }
  out.remove(start);
  return out;
}

/// The result of one switch: the new disabled set and which other modules moved with it.
class ModuleToggle {
  /// Creates a result.
  const ModuleToggle(this.disabled, this.alsoChanged);

  /// The new set of disabled module codes.
  final Set<String> disabled;

  /// Other modules (not the one tapped) whose state changed, in catalogue order.
  final List<String> alsoChanged;
}

/// Switches [code] on or off in [disabled] and keeps the server's rule true: switching off also
/// switches off every module that (transitively) requires it; switching on also switches on every
/// module it (transitively) requires. [requires] is the catalogue in catalogue order. The input
/// set is not modified.
ModuleToggle toggleModule(
  Map<String, List<String>> requires,
  Set<String> disabled,
  String code,
  bool on,
) {
  final Map<String, Iterable<String>> edges;
  if (on) {
    edges = requires;
  } else {
    edges = {
      for (final c in requires.keys)
        c: [
          for (final o in requires.keys)
            if (requires[o]!.contains(c)) o,
        ],
    };
  }
  final affected = _closure(code, edges);
  final next = {...disabled};
  final also = <String>[];
  if (on) {
    next.remove(code);
  } else {
    next.add(code);
  }
  for (final c in requires.keys) {
    if (!affected.contains(c)) continue;
    if (on ? next.remove(c) : next.add(c)) also.add(c);
  }
  return ModuleToggle(next, also);
}
