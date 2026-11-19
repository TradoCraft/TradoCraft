import 'package:material_ui/material_ui.dart';

import 'app_icons.dart';

/// Type-ahead picker backed by a server search.
class SearchPicker<T extends Object> extends StatelessWidget {
  const SearchPicker({
    super.key,
    required this.search,
    required this.label,
    required this.display,
    required this.onSelected,
    this.initial,
    this.clearOnSelect = false,
    this.onTextChanged,
    this.validator,
    this.enabled = true,
    this.suffix,
  });

  final Future<List<T>> Function(String query) search;
  final String label;
  final String Function(T) display;
  final void Function(T) onSelected;
  final T? initial;
  final bool clearOnSelect;

  /// Called whenever the typed text changes (also when a selection is written into the field).
  final void Function(String text)? onTextChanged;

  /// Checks the typed text when the enclosing `Form` validates (ADR 0085's `Many2OneField`).
  final String? Function(String text)? validator;
  final bool enabled;

  /// Shown at the end of the field (a clear or open button).
  final Widget? suffix;

  @override
  Widget build(BuildContext context) {
    TextEditingController? field;
    return Autocomplete<T>(
      initialValue: initial == null
          ? null
          : TextEditingValue(text: display(initial as T)),
      displayStringForOption: display,
      optionsBuilder: (value) async {
        final q = value.text.trim();
        if (q.isEmpty) return const [];
        try {
          return await search(q);
        } catch (_) {
          return const [];
        }
      },
      onSelected: (item) {
        onSelected(item);
        // Clear after Autocomplete has written the selection into the field.
        if (clearOnSelect) {
          WidgetsBinding.instance.addPostFrameCallback((_) => field?.clear());
        }
      },
      fieldViewBuilder: (context, controller, focusNode, onSubmitted) {
        field = controller;
        return TextFormField(
          controller: controller,
          focusNode: focusNode,
          enabled: enabled,
          onChanged: onTextChanged,
          onFieldSubmitted: (_) => onSubmitted(),
          validator: validator == null ? null : (v) => validator!(v ?? ''),
          decoration: InputDecoration(
            labelText: label,
            prefixIcon: const Icon(AppIcons.search),
            suffixIcon: suffix,
          ),
        );
      },
    );
  }
}
