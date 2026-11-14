import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/workspace.dart';
import 'link_kinds.dart';

/// A record a new to-do can be linked to, with the name to show for it.
class LinkTarget {
  const LinkTarget(this.ref, {this.label});

  /// Kind and id of the record.
  final LinkRef ref;

  /// What the screen calls the record (a quotation number); null until the screen has loaded.
  final String? label;

  /// The location to jump to (built from kind and id, see [LinkKindInfo.locationFor]).
  String get location => ref.location;
}

/// What the user is working on right now.
class CurrentContext {
  const CurrentContext({required this.location, this.title, this.target});

  /// The effective location: the focused workspace tab's, else the main area's. Empty when the
  /// app does not know yet.
  final String location;

  /// The title the screen reported (`TabScope.reportTitle`, stored in `WorkTab.title`).
  final String? title;

  /// The record on screen, or null when the screen has no object (a list, a settings page).
  final LinkTarget? target;
}

/// The location the user is working on, resolved through the link registry.
///
/// Same recipe as the tutorial's `TutorialHost._located`: a focused workspace tab shows its own
/// location, otherwise the main area is where the router is (`WorkspaceNotifier.homeLocation`, kept
/// by the shell). The tutorial is not involved.
///
/// The main area's location is not observable: read this provider when you need the answer (as
/// the quick-add dialog does), do not keep a watch on it for main-area navigation. It is
/// auto-disposed, so every read made while nobody listens computes afresh.
final currentContextProvider = Provider.autoDispose<CurrentContext>((ref) {
  final ws = ref.watch(workspaceProvider);
  final tab = ws.activeTab;
  final location =
      tab?.location ?? ref.read(workspaceProvider.notifier).homeLocation;
  final title = tab?.title;
  final r = parseLinkLocation(location);
  return CurrentContext(
    location: location,
    title: title,
    target: r == null
        ? null
        : LinkTarget(r, label: title == null || title.isEmpty ? null : title),
  );
});
