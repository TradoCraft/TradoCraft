import 'package:material_ui/material_ui.dart';

import '../../l10n/l10n.dart';
import 'actions.dart';
import 'key_hint.dart';

/// What a button is for, judged by its (localized) label. Extend the lists in [classifyLabel] to
/// teach the generic shortcuts a new label; see ADR 0060.
enum ButtonRole {
  /// Not a standard action.
  none,

  /// Save, Save changes, Save draft (Save and ...): Ctrl+S.
  save,

  /// Cancel, Close: Esc.
  cancel,

  /// Confirm, OK, Yes, Apply, Send, Create, Delete, Discard changes: Ctrl+Enter in a dialog.
  confirm,

  /// New, New something: Ctrl+N.
  create,
}

const _accents = {
  'à': 'a', 'á': 'a', 'â': 'a', 'ã': 'a', 'ä': 'a', 'å': 'a', 'ā': 'a', //
  'ç': 'c', 'ć': 'c', 'č': 'c', //
  'è': 'e', 'é': 'e', 'ê': 'e', 'ë': 'e', 'ē': 'e', 'ę': 'e', //
  'ì': 'i', 'í': 'i', 'î': 'i', 'ï': 'i', //
  'ñ': 'n', 'ń': 'n', //
  'ò': 'o', 'ó': 'o', 'ô': 'o', 'õ': 'o', 'ö': 'o', 'ø': 'o', //
  'ù': 'u', 'ú': 'u', 'û': 'u', 'ü': 'u', //
  'ý': 'y', 'ÿ': 'y', 'ß': 's', 'æ': 'a', 'œ': 'o', 'š': 's', 'ž': 'z', //
};

/// Lower case, accents folded, everything but a-z and digits turned into single spaces.
String normalizeLabel(String s) {
  final b = StringBuffer();
  for (final r in s.toLowerCase().runes) {
    final ch = String.fromCharCode(r);
    final c = _accents[ch] ?? ch;
    final u = c.codeUnitAt(0);
    final ok = c.length == 1 && ((u >= 97 && u <= 122) || (u >= 48 && u <= 57));
    b.write(ok ? c : ' ');
  }
  return b.toString().trim().replaceAll(RegExp(' +'), ' ');
}

bool _isLetter(String c) => c.codeUnitAt(0) >= 97 && c.codeUnitAt(0) <= 122;

/// One letter per label, a-z, unique, never one of [reserved]. The first letter of the first word
/// that is still free; else the next free letter of the label; else the next free letter at all.
/// A label with no letter gets none. Labels in [priority] (indexes) choose first, so Save and
/// Cancel get their natural letters wherever they sit. Deterministic.
List<String?> assignLetters(
  List<String> labels, {
  Set<String> reserved = const {},
  Set<int> priority = const {},
}) {
  final taken = {...reserved};
  final out = List<String?>.filled(labels.length, null);
  final order = [
    for (var i = 0; i < labels.length; i++)
      if (priority.contains(i)) i,
    for (var i = 0; i < labels.length; i++)
      if (!priority.contains(i)) i,
  ];
  const alphabet = 'abcdefghijklmnopqrstuvwxyz';
  for (final i in order) {
    final norm = normalizeLabel(labels[i]);
    if (!norm.split('').any(_isLetter)) continue;
    final words = norm.split(' ');
    String? pick;
    for (final w in words) {
      if (_isLetter(w[0]) && !taken.contains(w[0])) {
        pick = w[0];
        break;
      }
    }
    pick ??= norm
        .split('')
        .where((c) => _isLetter(c) && !taken.contains(c))
        .firstOrNull;
    pick ??= alphabet.split('').where((c) => !taken.contains(c)).firstOrNull;
    if (pick != null) {
      taken.add(pick);
      out[i] = pick;
    }
  }
  return out;
}

/// The Alt letters that belong to the fixed chords in effect and so are never given to a button:
/// the letter chords of the primary modifier (Shift variants are different keys).
Set<String> reservedAltLetters({required bool web}) => {
  for (final a in ShortcutAction.values)
    if (a.chordFor(web: web).mod == ChordMod.primary &&
        !a.chordFor(web: web).shift &&
        a.chordFor(web: web).key.keyLabel.length == 1 &&
        _isLetter(a.chordFor(web: web).key.keyLabel.toLowerCase()))
      a.chordFor(web: web).key.keyLabel.toLowerCase(),
};

/// The role of a button with this [label] in the language of [l].
ButtonRole classifyLabel(String label, AppLocalizations l) {
  final n = normalizeLabel(label);
  if (n.isEmpty) return ButtonRole.none;
  bool exact(Iterable<String> words) => words.map(normalizeLabel).contains(n);
  bool starts(String word) {
    final w = normalizeLabel(word);
    return n == w || n.startsWith('$w ');
  }

  // "Save draft" does not start with the word "Save" in every language (Dutch "Concept opslaan",
  // German "Entwurf speichern"), so it is matched on its own.
  if (exact([l.saveDraft]) || starts(l.save)) return ButtonRole.save;
  if (exact([l.cancel, l.close])) return ButtonRole.cancel;
  if (exact([
    l.confirm,
    l.ok,
    l.yes,
    l.apply,
    l.send,
    l.create,
    l.delete,
    l.discardChanges,
  ])) {
    return ButtonRole.confirm;
  }
  if (starts(l.newItem)) return ButtonRole.create;
  return ButtonRole.none;
}

/// A button found in the tree.
class ScanTarget {
  /// Creates a target.
  ScanTarget(this.element, this.label, this.role, this.filled, this.route);

  /// The element of the button widget.
  final Element element;

  /// The label (text, tooltip or semantic label).
  final String label;

  /// What the label says it is for.
  final ButtonRole role;

  /// Whether it is a [FilledButton], the primary action of a dialog.
  final bool filled;

  /// The route the button is on.
  final ModalRoute<dynamic>? route;

  /// The press handler as of now; null when the button is gone or disabled.
  VoidCallback? get onPressed {
    if (!element.mounted) return null;
    final w = element.widget;
    if (w is ButtonStyleButton) return w.onPressed;
    if (w is IconButton) return w.onPressed;
    return null;
  }

  /// Presses the button, as a tap would.
  void press() => onPressed?.call();

  /// The button's rectangle in global coordinates; null when it is not painted.
  Rect? get globalRect => _rectOf(element);
}

Rect? _rectOf(Element e) {
  if (!e.mounted) return null;
  final ro = e.renderObject;
  if (ro is! RenderBox || !ro.attached || !ro.hasSize || ro.size.isEmpty) {
    return null;
  }
  return ro.localToGlobal(Offset.zero) & ro.size;
}

/// What the topmost layer (the topmost dialog or sheet, else the visible page) offers.
class ScanResult {
  /// Creates a result.
  ScanResult({
    required this.targets,
    required this.searchFields,
    required this.dialog,
    required this.popup,
    required this.l10n,
    required Set<String> reserved,
  }) {
    final priority = <int>{
      for (var i = 0; i < targets.length; i++)
        if (targets[i].role == ButtonRole.save ||
            targets[i].role == ButtonRole.cancel)
          i,
    };
    final letters = assignLetters(
      [for (final t in targets) t.label],
      reserved: reserved,
      priority: priority,
    );
    for (var i = 0; i < targets.length; i++) {
      final c = letters[i];
      if (c != null) byLetter[c] = targets[i];
    }
  }

  /// The enabled buttons of the layer, in tree order, without those that already carry a
  /// [KeyHint].
  final List<ScanTarget> targets;

  /// Search fields of the layer, best first.
  final List<Element> searchFields;

  /// Whether a dialog, sheet or menu is on top.
  final bool dialog;

  /// The topmost popup route that holds buttons, if any.
  final ModalRoute<dynamic>? popup;

  /// The strings of the app, when known.
  final AppLocalizations? l10n;

  /// The Alt letter of each button.
  final byLetter = <String, ScanTarget>{};

  /// The letter of [t], if it has one.
  String? letterOf(ScanTarget t) =>
      byLetter.entries.where((e) => identical(e.value, t)).firstOrNull?.key;

  /// Whether every element of the result is still part of the tree.
  bool get alive =>
      targets.every((t) => t.element.mounted) &&
      searchFields.every((e) => e.mounted);

  /// The first enabled button with [role]; for Save the one labelled exactly "Save" wins.
  ScanTarget? pick(ButtonRole role) {
    final list = targets.where((t) => t.role == role).toList();
    if (list.isEmpty) return null;
    final l = l10n;
    if (role == ButtonRole.save && l != null) {
      final plain = normalizeLabel(l.save);
      for (final t in list) {
        if (normalizeLabel(t.label) == plain) return t;
      }
    }
    return list.first;
  }

  /// What Ctrl+S presses.
  ScanTarget? get saveTarget => pick(ButtonRole.save);

  /// What Esc presses.
  ScanTarget? get cancelTarget => pick(ButtonRole.cancel);

  /// What Ctrl+N presses.
  ScanTarget? get createTarget => pick(ButtonRole.create);

  /// What Ctrl+Enter presses: in a dialog Save, else its last filled button, else a confirming
  /// word; on a page only Save (a page has no single primary action to guess).
  ScanTarget? get confirmTarget {
    if (!dialog) return pick(ButtonRole.save);
    return pick(ButtonRole.save) ??
        targets.where((t) => t.filled).lastOrNull ??
        pick(ButtonRole.confirm);
  }
}

/// Walks the element tree below [root] once and collects the buttons of the topmost layer.
///
/// Reads `ButtonStyleButton` (Text, Filled, Elevated, Outlined buttons) and `IconButton`. The label
/// is the button's `Text`, else the tooltip, the nearest `Tooltip` or `Semantics` label, or the
/// icon's semantic label. Parts of the tree that are off stage, have tickers off (hidden tabs, the
/// main area behind a tab) or lie under a [KeyHint] are skipped, and so is every route that is
/// not the current one of its navigator.
ScanResult scanTree(
  Element root, {
  required bool dialogOpen,
  bool web = false,
  AppLocalizations? l10n,
}) {
  final found = <(ScanTarget, bool)>[]; // target, enabled
  final fields = <(Element, ModalRoute<dynamic>?, int)>[];
  AppLocalizations? l = l10n;

  AppLocalizations? loc(Element e) =>
      l ??= Localizations.of<AppLocalizations>(e, AppLocalizations);

  String? textOf(Element e) {
    String? text;
    void visit(Element c) {
      if (text != null) return;
      final w = c.widget;
      if (w is Text) {
        final t = (w.data ?? w.textSpan?.toPlainText() ?? '').trim();
        if (t.isNotEmpty) text = t;
        return;
      }
      if (w is Icon && (w.semanticLabel ?? '').isNotEmpty) {
        text = w.semanticLabel;
        return;
      }
      c.visitChildren(visit);
    }

    e.visitChildren(visit);
    return text;
  }

  void visit(Element e, bool hinted, String? ambient) {
    final w = e.widget;
    if (w is Offstage && w.offstage) return;
    if (w is TickerMode && !w.enabled) return;
    if (w is KeyHint) hinted = true;
    if (w is Tooltip && (w.message ?? '').isNotEmpty) ambient = w.message;
    if (w is Semantics && (w.properties.label ?? '').isNotEmpty) {
      ambient = w.properties.label;
    }
    if (w is ButtonStyleButton || w is IconButton) {
      final onPressed = w is ButtonStyleButton
          ? w.onPressed
          : (w as IconButton).onPressed;
      if (hinted || onPressed == null) return;
      final tooltip = w is IconButton ? w.tooltip : null;
      final label =
          (w is IconButton && (tooltip ?? '').isNotEmpty
                  ? tooltip
                  : textOf(e) ?? tooltip ?? ambient)
              ?.trim() ??
          '';
      if (label.isEmpty) return;
      final strings = loc(e);
      final role = strings == null
          ? ButtonRole.none
          : classifyLabel(label, strings);
      found.add((
        ScanTarget(e, label, role, w is FilledButton, ModalRoute.of(e)),
        true,
      ));
      return;
    }
    if (w is TextField) {
      final d = w.decoration;
      final strings = loc(e);
      final hint = normalizeLabel(d?.hintText ?? d?.labelText ?? '');
      final p = d?.prefixIcon;
      final searchIcon = p is Icon && p.icon == Icons.search;
      final exact = strings != null && hint == normalizeLabel(strings.search);
      if (exact || searchIcon) {
        fields.add((e, ModalRoute.of(e), exact ? 0 : 1));
      }
    }
    e.visitChildren((c) => visit(c, hinted, ambient));
  }

  visit(root, false, null);

  // The topmost layer: a current popup route if there is one, else the current page routes.
  bool current(ModalRoute<dynamic>? r) => r == null || (r.isCurrent && r.isActive);
  final live = found.where((f) => current(f.$1.route)).map((f) => f.$1).toList();
  final popups = live.where((t) => t.route is PopupRoute).toList();
  ModalRoute<dynamic>? popup;
  List<ScanTarget> layer;
  List<(Element, ModalRoute<dynamic>?, int)> layerFields;
  if (popups.isNotEmpty) {
    popup = popups.last.route;
    layer = popups.where((t) => t.route == popup).toList();
    layerFields = fields.where((f) => f.$2 == popup).toList();
  } else if (dialogOpen) {
    // A dialog without an enabled, labelled button (only fields, or only disabled buttons) is
    // still the layer: its search field counts, the page behind it does not.
    final dialogFields = fields
        .where((f) => f.$2 is PopupRoute && current(f.$2))
        .toList();
    popup = dialogFields.lastOrNull?.$2;
    layer = [];
    layerFields = popup == null
        ? []
        : dialogFields.where((f) => f.$2 == popup).toList();
  } else {
    layer = live;
    layerFields = fields.where((f) => current(f.$2)).toList();
  }
  layerFields.sort((a, b) => a.$3.compareTo(b.$3));
  return ScanResult(
    targets: layer,
    searchFields: [for (final f in layerFields) f.$1],
    dialog: dialogOpen || popup != null,
    popup: popup,
    l10n: l,
    reserved: reservedAltLetters(web: web),
  );
}

/// Where a badge goes and what it says.
class BadgeSpec {
  /// Creates a badge description.
  const BadgeSpec(this.rect, this.text);

  /// The rectangle of the thing the badge belongs to, in global coordinates.
  final Rect rect;

  /// The letter or word.
  final String text;

  @override
  bool operator ==(Object other) =>
      other is BadgeSpec && other.rect == rect && other.text == text;

  @override
  int get hashCode => Object.hash(rect, text);
}

/// The Alt letters of [r]'s buttons, with their rectangles.
List<BadgeSpec> altBadges(ScanResult r) {
  final out = <BadgeSpec>[];
  for (final e in r.byLetter.entries) {
    final rect = e.value.globalRect;
    if (rect != null) out.add(BadgeSpec(rect, e.key.toUpperCase()));
  }
  return out;
}

/// The standard-chord badges of [r]: S on the Save button, Enter on the confirming one, Esc on
/// Cancel, N on New (not on the web, where Ctrl+N belongs to the browser) and F on the search
/// field.
List<BadgeSpec> standardBadges(ScanResult r, {required bool web}) {
  final out = <BadgeSpec>[];
  void add(ScanTarget? t, String text) {
    final rect = t?.globalRect;
    if (rect != null) out.add(BadgeSpec(rect, text));
  }

  final save = r.saveTarget;
  add(save, 'S');
  final confirm = r.confirmTarget;
  if (confirm != null && !identical(confirm, save)) add(confirm, 'Enter');
  add(r.cancelTarget, 'Esc');
  if (!web) add(r.createTarget, 'N');
  final field = r.searchFields.firstOrNull;
  final rect = field == null ? null : _rectOf(field);
  if (rect != null) out.add(BadgeSpec(rect, 'F'));
  return out;
}
