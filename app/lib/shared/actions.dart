import 'package:material_ui/material_ui.dart';

import '../app/api.dart';
import '../l10n/l10n.dart';

/// Runs a server action and shows its error, if any, as a snack bar. Returns true on success.
Future<bool> runAction(
  BuildContext context,
  Future<void> Function() action, {
  String? success,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    await action();
    if (success != null) {
      messenger.showSnackBar(SnackBar(content: Text(success)));
    }
    return true;
  } catch (e) {
    messenger.showSnackBar(
      SnackBar(
        content: Text(errorMessage(e)),
        backgroundColor: Colors.red.shade700,
      ),
    );
    return false;
  }
}

/// Asks for a line of text (e.g. a reason). Returns null when cancelled.
Future<String?> askText(
  BuildContext context, {
  required String title,
  required String label,
}) {
  final controller = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        decoration: InputDecoration(labelText: label),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.l10n.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, controller.text.trim()),
          child: const Text('OK'),
        ),
      ],
    ),
  );
}

/// Small label/value pair used on detail screens.
class InfoItem extends StatelessWidget {
  const InfoItem(this.label, this.value, {super.key});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(right: 32, bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
          Text(value.isEmpty ? '—' : value, style: theme.textTheme.bodyLarge),
        ],
      ),
    );
  }
}
