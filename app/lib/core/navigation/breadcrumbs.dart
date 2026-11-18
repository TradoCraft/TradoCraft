import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/workspace.dart';
import '../theme/tokens.dart';

/// One step of a breadcrumb trail. A crumb with [onTap] is a link; the last one is plain text.
class Crumb {
  const Crumb(this.label, {this.onTap});
  final String label;
  final VoidCallback? onTap;
}

/// The trails that screens reported, per tab id (0 = the main area).
class BreadcrumbTrails extends Notifier<Map<int, List<Crumb>>> {
  @override
  Map<int, List<Crumb>> build() => const {};

  void set(int tab, List<Crumb> crumbs) {
    state = {...state, tab: crumbs};
  }
}

final breadcrumbTrailsProvider =
    NotifierProvider<BreadcrumbTrails, Map<int, List<Crumb>>>(
      BreadcrumbTrails.new,
    );

abstract final class Breadcrumbs {
  /// Tells the bar the steps below the section for the screen in this tab (a sub-page of a
  /// record); does nothing outside a [ProviderScope]. Mirrors [TabScope.reportTitle].
  static void report(BuildContext context, List<Crumb> crumbs) {
    final scope = context.getInheritedWidgetOfExactType<TabScope>();
    final container = ProviderScope.containerOf(context, listen: false);
    // The main area has no record below the section: nothing to report there.
    if (scope == null) return;
    final id = scope.id;
    // Screens report from load callbacks, possibly inside a frame: apply after it.
    scheduleMicrotask(
      () => container.read(breadcrumbTrailsProvider.notifier).set(id, crumbs),
    );
  }
}

/// The bar of the shell: the section, then what the focused tab reported (or its title). Hidden
/// while only the section is known (list pages).
class SectionBreadcrumbs extends ConsumerWidget {
  const SectionBreadcrumbs({
    super.key,
    required this.section,
    required this.onSection,
  });

  /// The label of the active destination.
  final String section;

  /// Goes to the section (the shell focuses the main area).
  final VoidCallback onSection;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tab = ref.watch(workspaceProvider).activeTab;
    if (tab == null) return const SizedBox.shrink();
    final reported = ref.watch(breadcrumbTrailsProvider)[tab.id];
    final title = tab.title;
    final rest =
        reported ?? [if (title != null && title.isNotEmpty) Crumb(title)];
    if (rest.isEmpty) return const SizedBox.shrink();
    return BreadcrumbBar(
      crumbs: [
        Crumb(section, onTap: onSection),
        ...rest,
      ],
    );
  }
}

/// The slim bar: `Section > record title`. The section crumb navigates to the section.
class BreadcrumbBar extends StatelessWidget {
  const BreadcrumbBar({super.key, required this.crumbs});

  final List<Crumb> crumbs;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.bodySmall;
    final children = <Widget>[];
    for (var i = 0; i < crumbs.length; i++) {
      final c = crumbs[i];
      final last = i == crumbs.length - 1;
      if (i > 0) {
        children.add(
          Icon(
            Icons.chevron_right,
            size: 16,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        );
      }
      final text = Text(
        c.label,
        style: last ? style?.copyWith(fontWeight: FontWeight.w600) : style,
        overflow: TextOverflow.ellipsis,
      );
      children.add(
        Flexible(
          child: c.onTap == null || last
              ? text
              : InkWell(
                  onTap: c.onTap,
                  borderRadius: Radii.small,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: Space.xs),
                    child: text,
                  ),
                ),
        ),
      );
    }
    return Semantics(
      container: true,
      child: Container(
        key: const ValueKey('breadcrumbs'),
        height: 32,
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: Space.md),
        child: Row(children: children),
      ),
    );
  }
}
