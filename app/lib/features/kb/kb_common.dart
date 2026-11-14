import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/api.dart';
import '../../l10n/l10n.dart';

final kbCategoriesProvider = FutureProvider.autoDispose<List<Category>>(
  (ref) => ref.watch(apiProvider).kb.listKbCategories(),
);

const kbStatuses = ['draft', 'published', 'archived'];
const kbAudiences = ['internal', 'portal', 'public'];

String kbStatusLabel(AppLocalizations l, String s) => switch (s) {
  'draft' => l.statusDraft,
  'published' => l.kbStatusPublished,
  'archived' => l.kbStatusArchived,
  _ => s,
};

String kbAudienceLabel(AppLocalizations l, String v) => switch (v) {
  'internal' => l.kbAudienceInternal,
  'portal' => l.kbAudiencePortal,
  'public' => l.kbAudiencePublic,
  _ => v,
};

/// A name in the wanted language, else English, else the first one.
String pickName(List<CategoryName> names, String language) {
  if (names.isEmpty) return '';
  return (names.where((n) => n.language == language).firstOrNull ??
          names.where((n) => n.language == 'en').firstOrNull ??
          names.first)
      .name;
}

/// Categories in tree order with their label ("Parent › Child").
List<(Category, String)> categoryTree(List<Category> all, String language) {
  final out = <(Category, String)>[];
  final parents = all.where((c) => c.parentId == null);
  for (final p in parents) {
    final name = pickName(p.names, language);
    out.add((p, name));
    for (final c in all.where((c) => c.parentId == p.id)) {
      out.add((c, '$name › ${pickName(c.names, language)}'));
    }
  }
  return out;
}

String? categoryLabel(List<Category> all, String? id, String language) {
  if (id == null) return null;
  for (final (c, label) in categoryTree(all, language)) {
    if (c.id == id) return label;
  }
  return null;
}

Color kbStatusColor(BuildContext context, String status) {
  final scheme = Theme.of(context).colorScheme;
  return switch (status) {
    'published' => scheme.primaryContainer,
    'archived' => scheme.surfaceContainerHighest,
    _ => scheme.tertiaryContainer,
  };
}
