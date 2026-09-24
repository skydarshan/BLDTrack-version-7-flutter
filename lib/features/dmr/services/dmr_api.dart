import '../../../core/network/api_client.dart';
import '../../../core/network/api_helpers.dart';

class DmrApi {
  DmrApi(this._client);
  final ApiClient _client;

  Future<PaginatedResult> listOrders([Map<String, dynamic>? params]) async {
    final res = await _client.get<Map<String, dynamic>>(
      '/dmr-requisition-orders',
      queryParameters: cleanQuery(params),
    );
    return PaginatedResult(
      items: asMapList(unwrapDataList(res.data)),
      pagination: unwrapPagination(res.data),
    );
  }

  Future<Map<String, dynamic>> orderStatusCounts([Map<String, dynamic>? params]) async {
    final res = await _client.get<Map<String, dynamic>>(
      '/dmr-requisition-orders/status-counts',
      queryParameters: cleanQuery(params),
    );
    return unwrapDataMap(res.data);
  }

  Future<List<Map<String, dynamic>>> listOpenOrders([Map<String, dynamic>? params]) async {
    final res = await _client.get<Map<String, dynamic>>(
      '/dmr-requisition-orders/open',
      queryParameters: cleanQuery(params),
    );
    return asMapList(unwrapDataList(res.data));
  }

  Future<Map<String, dynamic>> getOrder(String id) async {
    final res = await _client.get<Map<String, dynamic>>('/dmr-requisition-orders/$id');
    return unwrapDataMap(res.data);
  }

  Future<Map<String, dynamic>> closeOrder(String id, Map<String, dynamic> data) async {
    final res = await _client.patch<Map<String, dynamic>>(
      '/dmr-requisition-orders/$id/close',
      data: data,
    );
    return unwrapDataMap(res.data);
  }

  Future<Map<String, dynamic>> varianceApproval(String id, Map<String, dynamic> data) async {
    final res = await _client.patch<Map<String, dynamic>>(
      '/dmr-requisition-orders/$id/variance-approval',
      data: data,
    );
    return unwrapDataMap(res.data);
  }

  Future<Map<String, dynamic>> createOrder(Map<String, dynamic> data) async {
    final res = await _client.post<Map<String, dynamic>>('/dmr-requisition-orders', data: data);
    return unwrapDataMap(res.data);
  }

  Future<Map<String, dynamic>> updateOrder(String id, Map<String, dynamic> data) async {
    final res = await _client.put<Map<String, dynamic>>('/dmr-requisition-orders/$id', data: data);
    return unwrapDataMap(res.data);
  }

  Future<void> deleteOrder(String id) =>
      _client.delete<Map<String, dynamic>>('/dmr-requisition-orders/$id');

  Future<List<int>> downloadOrderDocs(String id) =>
      _client.downloadBytes('/dmr-requisition-orders/$id/download-docs');

  Future<PaginatedResult> listEntries([Map<String, dynamic>? params]) async {
    final res = await _client.get<Map<String, dynamic>>(
      '/dmr-entries',
      queryParameters: cleanQuery(params),
    );
    return PaginatedResult(
      items: asMapList(unwrapDataList(res.data)),
      pagination: unwrapPagination(res.data),
    );
  }

  Future<Map<String, dynamic>> getEntry(String id) async {
    final res = await _client.get<Map<String, dynamic>>('/dmr-entries/$id');
    return unwrapDataMap(res.data);
  }

  Future<Map<String, dynamic>> nextEntryNumber([Map<String, dynamic>? params]) async {
    final res = await _client.get<Map<String, dynamic>>(
      '/dmr-entries/next-entry-number',
      queryParameters: cleanQuery(params),
    );
    return unwrapDataMap(res.data);
  }

  Future<Map<String, dynamic>> entryTotals([Map<String, dynamic>? params]) async {
    final res = await _client.get<Map<String, dynamic>>(
      '/dmr-entries/entry-totals',
      queryParameters: cleanQuery(params),
    );
    return unwrapDataMap(res.data);
  }

  Future<Map<String, dynamic>> validateGateEntryNumber([Map<String, dynamic>? params]) async {
    final res = await _client.get<Map<String, dynamic>>(
      '/dmr-entries/validate-gate-entry-number',
      queryParameters: cleanQuery(params),
    );
    return unwrapDataMap(res.data);
  }

  Future<Map<String, dynamic>> checkEntryDuplicacy([Map<String, dynamic>? params]) async {
    final res = await _client.get<Map<String, dynamic>>(
      '/dmr-entries/check-entry-duplicacy',
      queryParameters: cleanQuery(params),
    );
    return unwrapDataMap(res.data);
  }

  Future<List<Map<String, dynamic>>> openChallan([Map<String, dynamic>? params]) async {
    final res = await _client.get<Map<String, dynamic>>(
      '/dmr-entries/open-challan',
      queryParameters: cleanQuery(params),
    );
    return asMapList(unwrapDataList(res.data));
  }

  Future<Map<String, dynamic>> updateEntry(String id, Map<String, dynamic> data) async {
    final res = await _client.put<Map<String, dynamic>>('/dmr-entries/$id', data: data);
    return unwrapDataMap(res.data);
  }

  Future<void> deleteEntry(String id) =>
      _client.delete<Map<String, dynamic>>('/dmr-entries/$id');

  Future<List<int>> downloadEntryPdf(String id) =>
      _client.downloadBytes('/dmr-entries/$id/download-pdf');

  Future<Map<String, dynamic>> docSubmission(Map<String, dynamic> data) async {
    final res = await _client.patch<Map<String, dynamic>>(
      '/dmr-entries/doc-submission',
      data: data,
    );
    return unwrapDataMap(res.data);
  }

  Future<List<Map<String, dynamic>>> entriesByRo([Map<String, dynamic>? params]) async {
    final res = await _client.get<Map<String, dynamic>>(
      '/dmr-entries/by-ro-number',
      queryParameters: cleanQuery(params),
    );
    return asMapList(unwrapDataList(res.data));
  }

  Future<Map<String, dynamic>> createChallan(
    Map<String, dynamic> payload, {
    MultipartFileEntry? document,
  }) async {
    if (document == null) {
      final res = await _client.postNamedMultipart<Map<String, dynamic>>(
        '/dmr-entries/challan',
        payload: payload,
      );
      return unwrapDataMap(res.data);
    }
    final res = await _client.postNamedMultipart<Map<String, dynamic>>(
      '/dmr-entries/challan',
      payload: payload,
      namedFiles: {'invoice_or_challan_doc': document},
    );
    return unwrapDataMap(res.data);
  }

  Future<Map<String, dynamic>> createInvoice(
    Map<String, dynamic> payload, {
    MultipartFileEntry? document,
  }) async {
    final res = await _client.postNamedMultipart<Map<String, dynamic>>(
      '/dmr-entries/invoice',
      payload: payload,
      namedFiles: {
        'invoice_or_challan_doc': ?document,
      },
    );
    return unwrapDataMap(res.data);
  }

  Future<PaginatedResult> listImprest([Map<String, dynamic>? params]) async {
    final res = await _client.get<Map<String, dynamic>>(
      '/imperest-dmr-entries',
      queryParameters: cleanQuery(params),
    );
    return PaginatedResult(
      items: asMapList(unwrapDataList(res.data)),
      pagination: unwrapPagination(res.data),
    );
  }

  Future<Map<String, dynamic>> createImprest(
    Map<String, dynamic> payload, {
    MultipartFileEntry? document,
  }) async {
    final res = await _client.postNamedMultipart<Map<String, dynamic>>(
      '/imperest-dmr-entries',
      payload: payload,
      namedFiles: {
        'invoice_or_challan_doc': ?document,
      },
    );
    return unwrapDataMap(res.data);
  }

  Future<Map<String, dynamic>> nextImprestNumber([Map<String, dynamic>? params]) async {
    final res = await _client.get<Map<String, dynamic>>(
      '/imperest-dmr-entries/next-order-number',
      queryParameters: cleanQuery(params),
    );
    return unwrapDataMap(res.data);
  }

  Future<Map<String, dynamic>> checkImprestInvoiceDuplicacy([Map<String, dynamic>? params]) async {
    final res = await _client.get<Map<String, dynamic>>(
      '/imperest-dmr-entries/check-invoice-duplicacy',
      queryParameters: cleanQuery(params),
    );
    return unwrapDataMap(res.data);
  }

  Future<Map<String, dynamic>> getImprest(String id) async {
    final res = await _client.get<Map<String, dynamic>>('/imperest-dmr-entries/$id');
    return unwrapDataMap(res.data);
  }

  Future<List<int>> downloadImprestPdf(String id) =>
      _client.downloadBytes('/imperest-dmr-entries/$id/download-pdf');

  Future<Map<String, dynamic>> imprestDocSubmission(Map<String, dynamic> data) async {
    final res = await _client.patch<Map<String, dynamic>>(
      '/imperest-dmr-entries/imperest-doc-submission',
      data: data,
    );
    return unwrapDataMap(res.data);
  }

  Future<List<Map<String, dynamic>>> debitInvoiceEntries([Map<String, dynamic>? params]) async {
    final res = await _client.get<Map<String, dynamic>>(
      '/debit-notes/invoice-entries',
      queryParameters: cleanQuery(params),
    );
    return asMapList(unwrapDataList(res.data));
  }

  Future<Map<String, dynamic>> nextDebitNumber([Map<String, dynamic>? params]) async {
    final res = await _client.get<Map<String, dynamic>>(
      '/debit-notes/next-number',
      queryParameters: cleanQuery(params),
    );
    return unwrapDataMap(res.data);
  }

  Future<List<int>> downloadDebitPdf(String id) =>
      _client.downloadBytes('/debit-notes/$id/download-pdf');

  Future<List<Map<String, dynamic>>> debitNotes([Map<String, dynamic>? params]) async {
    final res = await _client.get<Map<String, dynamic>>(
      '/debit-notes',
      queryParameters: cleanQuery(params),
    );
    return asMapList(unwrapDataList(res.data));
  }

  Future<Map<String, dynamic>> createDebitNote(Map<String, dynamic> data) async {
    final res = await _client.post<Map<String, dynamic>>('/debit-notes', data: data);
    return unwrapDataMap(res.data);
  }

  Future<List<Map<String, dynamic>>> creditNotes([Map<String, dynamic>? params]) async {
    final res = await _client.get<Map<String, dynamic>>(
      '/credit-notes',
      queryParameters: cleanQuery(params),
    );
    return asMapList(unwrapDataList(res.data));
  }

  Future<Map<String, dynamic>> getCreditNote(String id) async {
    final res = await _client.get<Map<String, dynamic>>('/credit-notes/$id');
    return unwrapDataMap(res.data);
  }

  Future<Map<String, dynamic>> createCreditNote(
    Map<String, dynamic> payload, {
    MultipartFileEntry? document,
  }) async {
    final res = await _client.postNamedMultipart<Map<String, dynamic>>(
      '/credit-notes',
      payload: payload,
      namedFiles: {
        'invoice_or_challan_doc': ?document,
      },
    );
    return unwrapDataMap(res.data);
  }

  Future<List<int>> downloadCreditDocs([Map<String, dynamic>? params]) =>
      _client.downloadBytes('/credit-notes/download-docs', queryParameters: cleanQuery(params));
}
