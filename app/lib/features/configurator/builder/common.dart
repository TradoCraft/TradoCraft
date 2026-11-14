import 'package:material_ui/material_ui.dart';

import '../../../l10n/l10n.dart';
import '../../../shared/app_icons.dart';
import 'draft.dart';

/// Disables the property editors below it (a revision that is not a draft).
class ReadOnlyScope extends InheritedWidget {
  const ReadOnlyScope({
    super.key,
    required this.readOnly,
    required super.child,
  });
  final bool readOnly;

  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ReadOnlyScope>()?.readOnly ??
      false;

  @override
  bool updateShouldNotify(ReadOnlyScope old) => old.readOnly != readOnly;
}

/// A text property: keeps its own controller and only takes a new value from outside while it
/// does not have the focus (so typing is never disturbed by the rebuild it causes).
class PropText extends StatefulWidget {
  const PropText({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.hint,
    this.helper,
    this.errorText,
    this.monospace = false,
    this.maxLines = 1,
    this.keyboardType,
    this.width,
    this.highlight = false,
  });

  final String label;
  final String value;
  final ValueChanged<String> onChanged;
  final String? hint;
  final String? helper;
  final String? errorText;
  final bool monospace;
  final int maxLines;
  final TextInputType? keyboardType;
  final double? width;

  /// Drawn with an outline in the error colour (an error navigation pointed here).
  final bool highlight;

  @override
  State<PropText> createState() => _PropTextState();
}

class _PropTextState extends State<PropText> {
  late final _controller = TextEditingController(text: widget.value);
  final _focus = FocusNode();

  @override
  void didUpdateWidget(PropText old) {
    super.didUpdateWidget(old);
    if (widget.value != _controller.text && !_focus.hasFocus) {
      _controller.text = widget.value;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final error = Theme.of(context).colorScheme.error;
    final field = TextField(
      controller: _controller,
      focusNode: _focus,
      enabled: !ReadOnlyScope.of(context),
      minLines: 1,
      maxLines: widget.maxLines,
      keyboardType: widget.keyboardType,
      style: widget.monospace ? const TextStyle(fontFamily: 'monospace') : null,
      decoration: InputDecoration(
        labelText: widget.label,
        hintText: widget.hint,
        helperText: widget.helper,
        errorText: widget.errorText,
        errorMaxLines: 3,
        isDense: true,
        enabledBorder: widget.highlight
            ? OutlineInputBorder(borderSide: BorderSide(color: error, width: 2))
            : null,
        border: const OutlineInputBorder(),
      ),
      onChanged: widget.onChanged,
    );
    return widget.width == null
        ? field
        : SizedBox(width: widget.width, child: field);
  }
}

/// A number property (empty clears it).
class PropNumber extends StatelessWidget {
  const PropNumber({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.integer = false,
    this.width = 140,
    this.errorText,
  });

  final String label;
  final Object? value;
  final ValueChanged<Object?> onChanged;
  final bool integer;
  final double? width;
  final String? errorText;

  @override
  Widget build(BuildContext context) => PropText(
    label: label,
    value: numberText(value),
    width: width,
    errorText: errorText,
    keyboardType: const TextInputType.numberWithOptions(
      decimal: true,
      signed: true,
    ),
    onChanged: (t) {
      final v = parseNumberText(t);
      if (integer && v is double) {
        onChanged(v.round());
      } else {
        onChanged(v);
      }
    },
  );
}

/// A choice between a few values; [allowNone] adds an empty entry (null).
class PropDropdown<T> extends StatelessWidget {
  const PropDropdown({
    super.key,
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
    this.allowNone = false,
    this.width = 220,
    this.helper,
  });

  final String label;
  final T? value;
  final Map<T, String> items;
  final ValueChanged<T?> onChanged;
  final bool allowNone;
  final double? width;

  /// Help text under the field.
  final String? helper;

  @override
  Widget build(BuildContext context) {
    final readOnly = ReadOnlyScope.of(context);
    final known = value == null || items.containsKey(value);
    final field = DropdownButtonFormField<T?>(
      key: ValueKey('$label=$value'),
      initialValue: known ? value : null,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        helperText: helper,
        helperMaxLines: 6,
        isDense: true,
        border: const OutlineInputBorder(),
      ),
      items: [
        if (allowNone || value == null)
          const DropdownMenuItem(value: null, child: Text('—')),
        for (final e in items.entries)
          DropdownMenuItem(
            value: e.key,
            child: Text(e.value, overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: readOnly ? null : onChanged,
    );
    return width == null ? field : SizedBox(width: width, child: field);
  }
}

class PropSwitch extends StatelessWidget {
  const PropSwitch({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.subtitle,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  final String? subtitle;

  @override
  Widget build(BuildContext context) => SwitchListTile(
    contentPadding: EdgeInsets.zero,
    dense: true,
    title: Text(label),
    subtitle: subtitle == null ? null : Text(subtitle!),
    value: value,
    onChanged: ReadOnlyScope.of(context) ? null : onChanged,
  );
}

/// A row of property editors that wraps on narrow screens.
class PropRow extends StatelessWidget {
  const PropRow({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Wrap(
      spacing: 12,
      runSpacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: children,
    ),
  );
}

/// A full-width property editor with space below.
class PropBlock extends StatelessWidget {
  const PropBlock({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) =>
      Padding(padding: const EdgeInsets.only(bottom: 12), child: child);
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.trailing});
  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 8, bottom: 8),
    child: Row(
      children: [
        Expanded(
          child: Text(text, style: Theme.of(context).textTheme.titleSmall),
        ),
        ?trailing,
      ],
    ),
  );
}

/// The languages definitions can be translated into.
const builderLanguages = ['en', 'nl', 'fr', 'de', 'es'];

/// Label (and help) per language: `{nl: {label, help}}`. With [plain], one text per language
/// (`{nl: 'text'}`, the messages of validations).
class TranslationsEditor extends StatelessWidget {
  const TranslationsEditor({
    super.key,
    required this.value,
    required this.onChanged,
    this.help = true,
    this.plain = false,
  });

  final Object? value;
  final ValueChanged<Json> onChanged;
  final bool help;
  final bool plain;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final map = asJson(value);
    void set(String lang, String key, String text) {
      final next = asJson(deepCopy(map));
      if (plain) {
        setProp(next, lang, text);
      } else {
        final t = mutableMap(next, lang);
        setProp(t, key, text);
        if (key == 'help' || t.isNotEmpty) {
          // `label` is always written when a language has an entry.
          t.putIfAbsent('label', () => '');
        }
        if (t.values.every((v) => v == '')) next.remove(lang);
      }
      onChanged(next);
    }

    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      leading: const Icon(AppIcons.translate, size: 20),
      title: Text(l10n.cfgbTranslations),
      subtitle: map.isEmpty
          ? null
          : Text(
              map.keys.join(', '),
              style: Theme.of(context).textTheme.bodySmall,
            ),
      children: [
        for (final lang in builderLanguages)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 36,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text(lang.toUpperCase()),
                  ),
                ),
                Expanded(
                  child: PropText(
                    key: ValueKey('tr-$lang-label'),
                    label: plain ? l10n.cfgbMessage : l10n.cfgbLabel,
                    value: plain
                        ? str(map[lang]) ?? ''
                        : str(asJson(map[lang])['label']) ?? '',
                    onChanged: (t) => set(lang, 'label', t),
                  ),
                ),
                if (help && !plain) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: PropText(
                      key: ValueKey('tr-$lang-help'),
                      label: l10n.cfgbHelp,
                      value: str(asJson(map[lang])['help']) ?? '',
                      onChanged: (t) => set(lang, 'help', t),
                    ),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

/// A list with a selection, drag handles to reorder, and add/remove actions.
class EditableList extends StatelessWidget {
  const EditableList({
    super.key,
    required this.titles,
    required this.selected,
    required this.onSelect,
    required this.onReorder,
    this.onAdd,
    this.addLabel,
    this.onRemove,
    this.subtitles,
    this.errorAt,
    this.listKey,
  });

  final List<String> titles;
  final List<String>? subtitles;
  final int? selected;
  final ValueChanged<int> onSelect;
  final void Function(int from, int to) onReorder;
  final VoidCallback? onAdd;
  final String? addLabel;
  final ValueChanged<int>? onRemove;

  /// Whether an item has problems (an error marker is shown).
  final bool Function(int i)? errorAt;
  final String? listKey;

  @override
  Widget build(BuildContext context) {
    final readOnly = ReadOnlyScope.of(context);
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ReorderableListView.builder(
          key: listKey == null ? null : ValueKey(listKey),
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          buildDefaultDragHandles: false,
          itemCount: titles.length,
          onReorderItem: (from, to) {
            if (!readOnly) onReorder(from, to);
          },
          itemBuilder: (context, i) => Material(
            key: ValueKey('${listKey ?? 'item'}-$i-${titles[i]}'),
            color: i == selected
                ? theme.colorScheme.secondaryContainer
                : Colors.transparent,
            child: ListTile(
              dense: true,
              leading: readOnly
                  ? null
                  : ReorderableDragStartListener(
                      index: i,
                      child: const Icon(AppIcons.dragHandle),
                    ),
              title: Text(
                titles[i].isEmpty ? '—' : titles[i],
                style: const TextStyle(fontFamily: 'monospace'),
              ),
              subtitle: subtitles == null || subtitles![i].isEmpty
                  ? null
                  : Text(
                      subtitles![i],
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (errorAt?.call(i) ?? false)
                    Icon(
                      AppIcons.error,
                      size: 18,
                      color: theme.colorScheme.error,
                    ),
                  if (onRemove != null && !readOnly)
                    IconButton(
                      tooltip: context.l10n.remove,
                      icon: const Icon(AppIcons.delete, size: 18),
                      onPressed: () => onRemove!(i),
                    ),
                ],
              ),
              onTap: () => onSelect(i),
            ),
          ),
        ),
        if (onAdd != null && !readOnly)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: onAdd,
              icon: const Icon(AppIcons.add),
              label: Text(addLabel ?? context.l10n.add),
            ),
          ),
      ],
    );
  }
}

/// Moves an element of [list] from [from] to [to] (both indexes in the list after removal).
void moveInList(List<Object?> list, int from, int to) {
  if (from == to || from < 0 || from >= list.length) return;
  final e = list.removeAt(from);
  list.insert(to.clamp(0, list.length), e);
}

/// A list/detail layout: the list on the left, the editor on the right (stacked when narrow).
class MasterDetail extends StatelessWidget {
  const MasterDetail({
    super.key,
    required this.master,
    required this.detail,
    this.masterWidth = 320,
  });

  final Widget master;
  final Widget detail;
  final double masterWidth;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) {
      if (c.maxWidth < 760) {
        return ListView(
          padding: const EdgeInsets.all(12),
          children: [master, const Divider(height: 24), detail],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: masterWidth,
            child: ListView(
              padding: const EdgeInsets.all(12),
              children: [master],
            ),
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [detail],
            ),
          ),
        ],
      );
    },
  );
}

/// The problems of an element, listed above its editor.
class ProblemsBox extends StatelessWidget {
  const ProblemsBox({super.key, required this.messages});
  final List<String> messages;

  @override
  Widget build(BuildContext context) {
    if (messages.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final m in messages)
            Text(
              m,
              style: TextStyle(color: theme.colorScheme.onErrorContainer),
            ),
        ],
      ),
    );
  }
}
