import 'package:material_ui/material_ui.dart';

import '../../core/theme/tokens.dart';
import '../../l10n/l10n.dart';
import '../../shared/app_icons.dart';

/// One column of a [One2ManyLineEditor].
class One2ManyColumn<T> {
  /// Defines a column with [label] and a [cell] builder.
  ///
  /// When [width] is null the column expands using [flex] in wide layouts.
  const One2ManyColumn({
    required this.label,
    required this.cell,
    this.width,
    this.flex = 1,
    this.numeric = false,
  });

  final String label;
  final Widget Function(BuildContext context, int index, T row) cell;
  final double? width;
  final int flex;
  final bool numeric;
}

/// Reusable tabular editor for one-to-many child lines inside `RecordFormView` or dialogs.
///
/// Renders a framed surface with a tinted column header band, hairline row dividers, tabular
/// figures on numeric cells, an optional per-row delete action, and an add-line footer.
/// Falls back to a wrapping layout below [narrowBreakpoint] so narrow viewports never overflow.
class One2ManyLineEditor<T> extends StatelessWidget {
  const One2ManyLineEditor({
    super.key,
    required this.rows,
    required this.columns,
    this.onAdd,
    this.onRemove,
    this.addLabel,
    this.addButtonKey,
    this.removeTooltip,
    this.removeKeyBuilder,
    this.emptyText,
    this.readOnly = false,
    this.narrowBreakpoint = 560,
    this.narrowBuilder,
    this.footer,
  });

  final List<T> rows;
  final List<One2ManyColumn<T>> columns;
  final VoidCallback? onAdd;
  final void Function(int index, T row)? onRemove;
  final String? addLabel;
  final Key? addButtonKey;
  final String? removeTooltip;
  final Key Function(int index, T row)? removeKeyBuilder;
  final String? emptyText;
  final bool readOnly;
  final double narrowBreakpoint;
  final Widget Function(
    BuildContext context,
    int index,
    T row,
    VoidCallback? remove,
  )?
  narrowBuilder;
  final Widget? footer;

  static const _tabular = TextStyle(
    fontFeatures: [FontFeature.tabularFigures()],
  );

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final headerStyle = theme.textTheme.labelLarge?.copyWith(
      color: scheme.onSurfaceVariant,
    );
    final canRemove = !readOnly && onRemove != null;
    final showAdd = !readOnly && onAdd != null;

    Widget wrapCell(One2ManyColumn<T> col, Widget child, {bool expand = true}) {
      final styled = col.numeric
          ? DefaultTextStyle.merge(style: _tabular, child: child)
          : child;
      if (col.width != null) {
        return SizedBox(width: col.width, child: styled);
      }
      return expand ? Expanded(flex: col.flex, child: styled) : styled;
    }

    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: Radii.medium,
        border: Border.all(color: scheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= narrowBreakpoint;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (wide) ...[
                Container(
                  color: scheme.surfaceContainerHigh,
                  padding: const EdgeInsets.symmetric(
                    horizontal: Space.md,
                    vertical: Space.sm,
                  ),
                  child: Row(
                    children: [
                      for (var c = 0; c < columns.length; c++) ...[
                        if (c > 0) const SizedBox(width: Space.sm),
                        wrapCell(
                          columns[c],
                          Text(
                            columns[c].label,
                            style: headerStyle,
                            textAlign: columns[c].numeric
                                ? TextAlign.right
                                : TextAlign.left,
                          ),
                        ),
                      ],
                      if (canRemove) ...[
                        const SizedBox(width: Space.sm),
                        const SizedBox(width: 40),
                      ],
                    ],
                  ),
                ),
                const Divider(height: 1),
              ],
              if (rows.isEmpty && emptyText != null)
                Padding(
                  padding: const EdgeInsets.all(Space.md),
                  child: Text(
                    emptyText!,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              for (var i = 0; i < rows.length; i++) ...[
                if (i > 0) const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: Space.md,
                    vertical: Space.sm,
                  ),
                  child: wide
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            for (var c = 0; c < columns.length; c++) ...[
                              if (c > 0) const SizedBox(width: Space.sm),
                              wrapCell(
                                columns[c],
                                columns[c].cell(context, i, rows[i]),
                              ),
                            ],
                            if (canRemove) ...[
                              const SizedBox(width: Space.sm),
                              IconButton(
                                key: removeKeyBuilder?.call(i, rows[i]),
                                tooltip: removeTooltip ?? l.remove,
                                icon: const Icon(AppIcons.delete),
                                onPressed: () => onRemove!(i, rows[i]),
                              ),
                            ],
                          ],
                        )
                      : narrowBuilder != null
                      ? narrowBuilder!(
                          context,
                          i,
                          rows[i],
                          canRemove ? () => onRemove!(i, rows[i]) : null,
                        )
                      : Wrap(
                          spacing: Space.sm,
                          runSpacing: Space.sm,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            for (final col in columns)
                              wrapCell(
                                col,
                                col.cell(context, i, rows[i]),
                                expand: false,
                              ),
                            if (canRemove)
                              IconButton(
                                key: removeKeyBuilder?.call(i, rows[i]),
                                tooltip: removeTooltip ?? l.remove,
                                icon: const Icon(AppIcons.delete),
                                onPressed: () => onRemove!(i, rows[i]),
                              ),
                          ],
                        ),
                ),
              ],
              if (showAdd || footer != null) ...[
                if (rows.isNotEmpty || emptyText != null || wide)
                  const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: Space.sm,
                    vertical: Space.xs,
                  ),
                  child: Row(
                    children: [
                      if (showAdd)
                        TextButton.icon(
                          key: addButtonKey,
                          icon: const Icon(AppIcons.add),
                          label: Text(addLabel ?? l.purchAddLine),
                          onPressed: onAdd,
                        ),
                      if (footer != null) Expanded(child: footer!),
                    ],
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}
