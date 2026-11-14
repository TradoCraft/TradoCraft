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
  });

  final Future<List<T>> Function(String query) search;
  final String label;
  final String Function(T) display;
  final void Function(T) onSelected;
  final T? initial;
  final bool clearOnSelect;

  /// Called whenever the typed text changes (also when a selection is written into the field).
  final void Function(String text)? onTextChanged;

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
        return TextField(
          controller: controller,
          focusNode: focusNode,
          onChanged: onTextChanged,
          onSubmitted: (_) => onSubmitted(),
          decoration: InputDecoration(
            labelText: label,
            prefixIcon: const Icon(AppIcons.search),
          ),
        );
      },
    );
  }
}
