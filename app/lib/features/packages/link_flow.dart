import 'package:dio/dio.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/api.dart';
import '../../l10n/l10n.dart';
import '../../shared/photos.dart' show newClientId;

/// The explicit confirm step of matching a parcel with an announced repair. Nothing is linked until
/// the person presses "Confirm and link"; when the customers differ they must also say that is
/// intended. Returns true when the parcel was linked. Callers reload their data afterwards either
/// way: a 409 means the repair changed under our feet.
Future<bool> confirmAndLink(
  BuildContext context,
  WidgetRef ref, {
  required Package pkg,
  required Repair repair,
}) async {
  final mismatch =
      pkg.customerId != null && pkg.customerId != repair.customerId;
  final confirmed = await _askConfirm(context, pkg, repair, mismatch);
  if (confirmed == null || !context.mounted) return false;
  return _link(context, ref, pkg, repair, confirmed);
}

Future<bool?> _askConfirm(
  BuildContext context,
  Package pkg,
  Repair repair,
  bool mismatch,
) => showDialog<bool>(
  context: context,
  builder: (_) =>
      _ConfirmLinkDialog(pkg: pkg, repair: repair, mismatch: mismatch),
);

Future<bool> _link(
  BuildContext context,
  WidgetRef ref,
  Package pkg,
  Repair repair,
  bool mismatchConfirmed,
) async {
  final l = context.l10n;
  final messenger = ScaffoldMessenger.of(context);
  try {
    await ref
        .read(apiProvider)
        .repairs
        .linkPackageRepair(
          id: pkg.id,
          body: PackageRepairLinkInput(
            repairId: repair.id,
            clientId: newClientId(),
            expectedStatus: repair.status,
            confirmCustomerMismatch: mismatchConfirmed ? true : null,
          ),
        );
    messenger.showSnackBar(SnackBar(content: Text(l.parcelLinked)));
    return true;
  } catch (e) {
    if (e is DioException && e.response?.statusCode == 409) {
      final message = errorMessage(e);
      // The server refuses a customer mismatch with a 409 too: ask again, with the warning.
      if (!mismatchConfirmed && errorCode(e) == 'customer_mismatch') {
        if (!context.mounted) return false;
        final again = await _askConfirm(context, pkg, repair, true);
        if (again == null || !context.mounted) return false;
        return _link(context, ref, pkg, repair, true);
      }
      messenger.showSnackBar(
        SnackBar(
          content: Text('${l.linkConflict} ($message)'),
          backgroundColor: Colors.red.shade700,
        ),
      );
      return false;
    }
    messenger.showSnackBar(
      SnackBar(
        content: Text(errorMessage(e)),
        backgroundColor: Colors.red.shade700,
      ),
    );
    return false;
  }
}

class _ConfirmLinkDialog extends StatefulWidget {
  const _ConfirmLinkDialog({
    required this.pkg,
    required this.repair,
    required this.mismatch,
  });
  final Package pkg;
  final Repair repair;
  final bool mismatch;

  @override
  State<_ConfirmLinkDialog> createState() => _ConfirmLinkDialogState();
}

class _ConfirmLinkDialogState extends State<_ConfirmLinkDialog> {
  bool _ack = false;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final ok = !widget.mismatch || _ack;
    return AlertDialog(
      title: Text(l.confirmLinkTitle),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l.confirmLinkBody(widget.pkg.number, widget.repair.number)),
            if (widget.mismatch) ...[
              const SizedBox(height: 12),
              Text(
                l.customerMismatchWarning,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              Text(
                '${widget.pkg.customerName} / ${widget.repair.customerName}',
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _ack,
                title: Text(l.confirmCustomerMismatch),
                onChanged: (v) => setState(() => _ack = v ?? false),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l.cancel),
        ),
        FilledButton(
          onPressed: ok ? () => Navigator.pop(context, widget.mismatch) : null,
          child: Text(l.confirmLink),
        ),
      ],
    );
  }
}
