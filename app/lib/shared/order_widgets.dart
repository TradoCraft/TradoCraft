import 'package:material_ui/material_ui.dart';

import '../l10n/l10n.dart';
import 'app_icons.dart';

/// Chip with the state of an order. The portal passes [portal] to word it from the customer's side.
class OrderStatusChip extends StatelessWidget {
  const OrderStatusChip(this.status, {super.key, this.portal = false});
  final String status;
  final bool portal;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    return Chip(
      label: Text(portal ? l.portalOrderStatus(status) : l.orderStatus(status)),
      backgroundColor: switch (status) {
        'sent' => scheme.tertiaryContainer,
        'confirmed' => scheme.primaryContainer,
        'cancelled' => scheme.errorContainer,
        _ => null,
      },
      visualDensity: VisualDensity.compact,
    );
  }
}

/// Priority of an order: expedite stands out, low is muted, normal is plain text.
class PriorityIndicator extends StatelessWidget {
  const PriorityIndicator(this.priority, {super.key});
  final String priority;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final label = context.l10n.orderPriority(priority);
    return switch (priority) {
      'expedite' => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(AppIcons.priorityHigh, size: 18, color: scheme.error),
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: scheme.error,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
      'low' => Text(label, style: TextStyle(color: scheme.outline)),
      _ => Text(label),
    };
  }
}
