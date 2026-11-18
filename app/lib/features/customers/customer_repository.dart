import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/api.dart';
import '../../framework/data/repository.dart';

/// Customers over the generated CRM client. The API has no delete (customers are deactivated).
class CustomerRepository
    implements
        Repository<Customer, String>,
        CreateSink<Customer, CustomerInput>,
        UpdateSink<Customer, String, CustomerInput> {
  const CustomerRepository(this._crm);
  final CrmClient _crm;

  @override
  Future<Page<Customer>> list(ListQuery query) async {
    final page = await _crm.listCustomers(
      q: query.q,
      sort: query.sort,
      offset: query.offset,
      limit: query.limit,
    );
    return Page(page.items, total: page.total);
  }

  @override
  Future<Customer> get(String id) => _crm.getCustomer(id: id);

  @override
  Future<Customer> create(CustomerInput input) =>
      _crm.createCustomer(body: input);

  @override
  Future<Customer> update(String id, CustomerInput input) =>
      _crm.updateCustomer(id: id, body: input);
}

final customerRepositoryProvider = Provider<CustomerRepository>(
  (ref) => CustomerRepository(ref.watch(apiProvider).crm),
);
