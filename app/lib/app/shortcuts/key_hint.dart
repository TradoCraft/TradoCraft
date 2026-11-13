import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/l10n.dart';
import 'actions.dart';
import 'registry.dart';

/// Shows the shortcut letter of [action] in a small badge on the corner of [child] while the
/// primary modifier is held and the action does something in the current scope. It never changes
/// layout (the badge floats outside the child's box), takes no pointer events and is hidden from
/// screen readers (which get the shortcut as a semantic hint instead).
///
/// Do not wrap an `Expanded` or `Positioned` directly; wrap what is inside it.
class KeyHint extends ConsumerWidget {
  /// Creates a hint for [action] around [child].
  const KeyHint({super.key, required this.action, required this.child});

  /// The shortcut the badge announces.
  final ShortcutAction action;

  /// The widget the shortcut acts on.
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final registry = ref.watch(shortcutRegistryProvider);
    return ListenableBuilder(
      listenable: Listenable.merge([registry, registry.modifierHeld]),
      builder: (context, _) {
        final enabled = registry.isEnabled(action);
        final show = enabled && registry.modifierHeld.value;
        Widget content = Stack(
          clipBehavior: Clip.none,
          fit: StackFit.passthrough,
          children: [
            child,
            if (show)
              Positioned(
                top: -6,
                right: -8,
                child: IgnorePointer(
                  child: ExcludeSemantics(child: _Badge(action.hintLabel)),
                ),
              ),
          ],
        );
        if (enabled) {
          content = Semantics(
            hint: context.l10n.shortcutHint(action.describe()),
            child: content,
          );
        }
        return content;
      },
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      key: const ValueKey('key-hint-badge'),
      decoration: BoxDecoration(
        color: scheme.inverseSurface,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 10,
            height: 1.2,
            fontWeight: FontWeight.w700,
            color: scheme.onInverseSurface,
            decoration: TextDecoration.none,
          ),
        ),
      ),
    );
  }
}
