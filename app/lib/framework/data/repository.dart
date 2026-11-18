/// Base types of the repository layer (ADR 0077).
///
/// A repository wraps one generated API client for one entity. Screens depend on it instead of
/// calling `ref.watch(apiProvider).<group>.method()`. Each concrete repository implements only the
/// capabilities its API offers.
///
/// Errors: repositories do not catch or wrap. The `DioException` of the client passes through
/// unchanged, so `errorMessage`, `errorStatus`, `errorCode` and `isRecordChangedError` (409
/// `record_changed` with `expected_version`) keep working in every screen.
library;

/// What a list call asks for. [sort] and [filters] are reserved for later phases; no repository
/// reads them yet.
class ListQuery {
  const ListQuery({
    this.search,
    this.offset = 0,
    this.limit = 50,
    this.sort,
    this.filters = const {},
  });

  /// Free-text search; null or empty means no search.
  final String? search;
  final int offset;
  final int limit;

  /// Reserved: sort key.
  final String? sort;

  /// Selected filter values by filter key (`FilterDef.key`); see [csv] and [flag].
  final Map<String, Object?> filters;

  Set<String> _values(String key) {
    final v = filters[key];
    if (v is Iterable) return {for (final e in v) '$e'};
    return v == null ? const {} : {'$v'};
  }

  /// The selected values of filter [key] as the API's comma-separated list; null when none.
  String? csv(String key) {
    final v = _values(key).toList()..sort();
    return v.isEmpty ? null : v.join(',');
  }

  /// A yes/no filter whose options are `true` and `false`: null (no restriction) unless exactly
  /// one of them is selected.
  bool? flag(String key) {
    final v = _values(key);
    if (v.length != 1) return null;
    return switch (v.first) {
      'true' => true,
      'false' => false,
      _ => null,
    };
  }

  /// Search text as the API wants it: null when blank.
  String? get q => (search == null || search!.isEmpty) ? null : search;

  ListQuery copyWith({
    String? search,
    int? offset,
    int? limit,
    String? sort,
    Map<String, Object?>? filters,
  }) => ListQuery(
    search: search ?? this.search,
    offset: offset ?? this.offset,
    limit: limit ?? this.limit,
    sort: sort ?? this.sort,
    filters: filters ?? this.filters,
  );
}

/// One page of a list. [total] is null when the API does not say.
class Page<T> {
  const Page(this.items, {this.total});
  final List<T> items;
  final int? total;

  /// The total, or the number of items when the API gave none.
  int get totalOrCount => total ?? items.length;

  /// The `(items, total)` pair that `EntityList` loaders return.
  (List<T>, int) get asLoaderResult => (items, totalOrCount);
}

/// Lists [T] in pages.
abstract interface class ListSource<T> {
  Future<Page<T>> list(ListQuery query);
}

/// Reads one [T] by [ID].
abstract interface class GetSource<T, ID> {
  Future<T> get(ID id);
}

/// Creates a [T] from an input of type [I].
abstract interface class CreateSink<T, I> {
  Future<T> create(I input);
}

/// Updates the [T] with [ID] from an input of type [I].
abstract interface class UpdateSink<T, ID, I> {
  Future<T> update(ID id, I input);
}

/// Deletes by [ID], where the API supports it.
abstract interface class DeleteSink<ID> {
  Future<void> delete(ID id);
}

/// The common case: list and get. Add [CreateSink], [UpdateSink] and [DeleteSink] as the API allows.
abstract interface class Repository<T, ID>
    implements ListSource<T>, GetSource<T, ID> {}
