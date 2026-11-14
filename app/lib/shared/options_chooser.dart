import 'package:material_ui/material_ui.dart';

import '../app/api.dart';
import '../l10n/l10n.dart';
import 'format.dart';

/// Offers the options of a product when it is added to a quotation. Required options are ticked
/// and cannot be unticked; the others are the user's choice. Returns the options to add (the
/// required ones plus the ticked ones), or null when the dialog is dismissed.
Future<List<ProductOption>?> showOptionsChooser(
  BuildContext context, {
  required Product product,
  required List<ProductOption> options,
}) => showDialog<List<ProductOption>>(
  context: context,
  builder: (_) => OptionsChooser(product: product, options: options),
);

/// Dialog body listing the options of a product to add to the quotation; required ones start ticked.
class OptionsChooser extends StatefulWidget {
  const OptionsChooser({
    super.key,
    required this.product,
    required this.options,
  });

  final Product product;
  final List<ProductOption> options;

  @override
  State<OptionsChooser> createState() => _OptionsChooserState();
}

/// State of [OptionsChooser]: the set of ticked options.
class _OptionsChooserState extends State<OptionsChooser> {
  late final Set<String> _ticked = {
    for (final o in widget.options)
      if (o.requiredValue) o.optionProductId,
  };

  List<ProductOption> get _result => [
    for (final o in widget.options)
      if (_ticked.contains(o.optionProductId)) o,
  ];

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return AlertDialog(
      key: const ValueKey('options-chooser'),
      title: Text(
        l.optionsChooseTitle('${widget.product.code} · ${widget.product.name}'),
      ),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l.optionsChooseHelp),
            const SizedBox(height: 8),
            for (final o in widget.options)
              CheckboxListTile(
                key: ValueKey('choose-option-${o.optionProductId}'),
                dense: true,
                controlAffinity: ListTileControlAffinity.leading,
                value: _ticked.contains(o.optionProductId),
                onChanged: o.requiredValue
                    ? null
                    : (v) => setState(() {
                        if (v ?? false) {
                          _ticked.add(o.optionProductId);
                        } else {
                          _ticked.remove(o.optionProductId);
                        }
                      }),
                title: Text('${o.optionCode} · ${o.optionName}'),
                subtitle: Text(
                  [
                    '× ${number(o.defaultQuantity)}',
                    if (o.requiredValue) l.optionRequired,
                  ].join(' · '),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const ValueKey('options-skip'),
          onPressed: () => Navigator.pop(context, [
            for (final o in widget.options)
              if (o.requiredValue) o,
          ]),
          child: Text(l.optionsSkip),
        ),
        FilledButton(
          key: const ValueKey('options-add'),
          onPressed: () => Navigator.pop(context, _result),
          child: Text(l.optionsAddSelected),
        ),
      ],
    );
  }
}
