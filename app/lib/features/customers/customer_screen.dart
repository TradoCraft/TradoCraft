import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/api.dart';
import '../../app/workspace.dart';
import '../../shared/load_failed.dart';
import '../todo/object_todos_button.dart';
import 'customer_form.dart';
import 'customer_repository.dart';

/// One customer as a page of its own (a workspace tab, `/customers/:id`), so other places (a
/// to-do, a link) can open it. It loads the customer and shows the same form as the list's dialog;
/// the list keeps opening its dialog.
class CustomerScreen extends ConsumerStatefulWidget {
  const CustomerScreen({super.key, required this.id});

  final String id;

  @override
  ConsumerState<CustomerScreen> createState() => _CustomerScreenState();
}

class _CustomerScreenState extends ConsumerState<CustomerScreen> {
  Customer? _customer;
  String? _error;
  bool _missing = false;
  int _version = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final c = await ref.read(customerRepositoryProvider).get(widget.id);
      if (!mounted) return;
      setState(() {
        _customer = c;
        _error = null;
      });
      TabScope.reportTitle(context, c.name);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = errorMessage(e);
        _missing = errorStatus(e) == 404;
      });
    }
  }

  void _close() => context.canPop() ? context.pop() : context.go('/customers');

  @override
  Widget build(BuildContext context) {
    final c = _customer;
    if (c == null) {
      return Scaffold(
        body: _error == null
            ? const Center(child: CircularProgressIndicator())
            : LoadFailedView(
                message: _error!,
                leaveTo: '/customers',
                notFound: _missing,
                todoKind: TodoLinkKind.customer,
                todoId: widget.id,
              ),
      );
    }
    final canWrite = can(ref, 'customers.write');
    // The form is a RecordFormView (ADR 0085): it draws the header with the back button.
    return Scaffold(
      body: CustomerForm(
        // A saved customer rebuilds the form with the new values.
        key: ValueKey(_version),
        customer: c,
        readOnly: !canWrite,
        screen: true,
        titleExtras: [
          ObjectTodosButton(
            kind: TodoLinkKind.customer,
            id: c.id,
            label: c.name,
          ),
        ],
        onDone: (saved) {
          if (saved == null) {
            _close();
          } else {
            setState(() {
              _customer = saved;
              _version++;
            });
            TabScope.reportTitle(context, saved.name);
          }
        },
      ),
    );
  }
}
