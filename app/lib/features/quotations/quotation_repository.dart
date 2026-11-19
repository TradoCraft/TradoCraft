import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/api.dart';
import '../../framework/data/repository.dart';

/// Quotations over the generated sales client. The list holds summaries, a single read the full
/// quotation. Workflow calls (send, accept, revise, convert) stay on the sales client for now.
class QuotationRepository
    implements
        ListSource<QuotationSummary>,
        GetSource<Quotation, String>,
        CreateSink<Quotation, QuotationInput>,
        UpdateSink<Quotation, String, QuotationInput> {
  const QuotationRepository(this._sales);
  final SalesClient _sales;

  /// The `status` filter holds API values of `QuotationStatus` (none selected: all).
  @override
  Future<Page<QuotationSummary>> list(ListQuery query) async {
    final page = await _sales.listQuotations(
      q: query.q,
      status: query.csv('status'),
      sort: query.sort,
      offset: query.offset,
      limit: query.limit,
    );
    return Page(page.items, total: page.total);
  }

  @override
  Future<Quotation> get(String id) => _sales.getQuotation(id: id);

  @override
  Future<Quotation> create(QuotationInput input) =>
      _sales.createQuotation(body: input);

  @override
  Future<Quotation> update(String id, QuotationInput input) =>
      _sales.updateQuotation(id: id, body: input);
}

final quotationRepositoryProvider = Provider<QuotationRepository>(
  (ref) => QuotationRepository(ref.watch(apiProvider).sales),
);
