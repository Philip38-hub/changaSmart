import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import '../models/models.dart';

/// Thrown for any failed API call, with a message already safe to show a
/// user (never a raw stack trace -- the backend doesn't return those
/// either, see app/main.py's ValueError handler).
class ApiException implements Exception {
  final String message;
  ApiException(this.message);

  @override
  String toString() => message;
}

/// Thin wrapper around the ChangaSmart backend HTTP API. One method per
/// endpoint, matching backend/app/main.py exactly -- see that file for the
/// authoritative contract. No business logic here: the backend (in
/// AGENT_MODE=mock or =bedrock) is the single source of truth.
class ApiService {
  final String baseUrl;
  final http.Client _client;
  static const _timeout = Duration(seconds: 15);

  ApiService({String? baseUrl, http.Client? client})
      : baseUrl = baseUrl ?? ApiConfig.baseUrl,
        _client = client ?? http.Client();

  Uri _uri(String path) => Uri.parse('$baseUrl$path');

  Map<String, String> get _headers => const {'Content-Type': 'application/json'};

  Future<dynamic> _get(String path) => _send(() => _client.get(_uri(path)));

  Future<dynamic> _post(String path, [Map<String, dynamic>? body]) => _send(
        () => _client.post(
          _uri(path),
          headers: _headers,
          body: body == null ? null : jsonEncode(body),
        ),
      );

  Future<dynamic> _send(Future<http.Response> Function() request) async {
    http.Response response;
    try {
      response = await request().timeout(_timeout);
    } on TimeoutException {
      throw ApiException(
        'The backend took too long to respond. Check that it is running '
        'and reachable at $baseUrl.',
      );
    } on SocketException {
      throw ApiException(
        'Could not reach the backend at $baseUrl. Check that it is '
        'running and that your phone is on the same network.',
      );
    } on http.ClientException catch (e) {
      throw ApiException('Network error: ${e.message}');
    }

    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (response.body.isEmpty) return null;
      return jsonDecode(response.body);
    }

    throw ApiException(_extractErrorMessage(response));
  }

  String _extractErrorMessage(http.Response response) {
    try {
      final decoded = jsonDecode(response.body);
      final detail = decoded is Map ? decoded['detail'] : null;
      if (detail is String) return detail;
      if (detail is List && detail.isNotEmpty) {
        // FastAPI/Pydantic 422 validation error shape.
        return detail
            .map((e) => e is Map ? '${e['loc']?.last}: ${e['msg']}' : e.toString())
            .join('; ');
      }
    } catch (_) {
      // fall through to generic message
    }
    return 'Request failed (${response.statusCode}).';
  }

  // ---------------------------------------------------------------------
  // Health
  // ---------------------------------------------------------------------

  Future<bool> checkHealth() async {
    try {
      final result = await _get('/health');
      return result is Map && result['status'] == 'ok';
    } catch (_) {
      return false;
    }
  }

  // ---------------------------------------------------------------------
  // Projects
  // ---------------------------------------------------------------------

  Future<List<Project>> listProjects() async {
    final result = await _get('/projects');
    return (result as List).map((e) => Project.fromJson(e)).toList();
  }

  Future<Project> getProject(String projectId) async {
    final result = await _get('/projects/$projectId');
    return Project.fromJson(result);
  }

  Future<Project> createProject({required String name, int? targetAmount}) async {
    final result = await _post('/projects', {
      'name': name,
      if (targetAmount != null) 'target_amount': targetAmount,
    });
    return Project.fromJson(result);
  }

  // ---------------------------------------------------------------------
  // Collections
  // ---------------------------------------------------------------------

  Future<List<Collection>> listCollections(String projectId) async {
    final result = await _get('/projects/$projectId/collections');
    return (result as List).map((e) => Collection.fromJson(e)).toList();
  }

  Future<Collection> getCollection(String collectionId) async {
    final result = await _get('/collections/$collectionId');
    return Collection.fromJson(result);
  }

  Future<Collection> createCollection({
    required String projectId,
    required CollectionType type,
    required String name,
    int? targetAmount,
    DateTime? date,
  }) async {
    final result = await _post('/projects/$projectId/collections', {
      'type': collectionTypeToJson(type),
      'name': name,
      if (targetAmount != null) 'target_amount': targetAmount,
      if (date != null) 'date': _dateOnly(date),
    });
    return Collection.fromJson(result);
  }

  Future<Collection> closeCollection(String collectionId) async {
    final result = await _post('/collections/$collectionId/close');
    return Collection.fromJson(result);
  }

  // ---------------------------------------------------------------------
  // Contributors
  // ---------------------------------------------------------------------

  Future<List<Contributor>> listContributors(String collectionId) async {
    final result = await _get('/collections/$collectionId/contributors');
    return (result as List).map((e) => Contributor.fromJson(e)).toList();
  }

  Future<Contributor> createContributor({
    required String collectionId,
    required String name,
    int? expectedAmount,
    String? phone,
  }) async {
    final result = await _post('/collections/$collectionId/contributors', {
      'name': name,
      if (expectedAmount != null) 'expected_amount': expectedAmount,
      if (phone != null && phone.isNotEmpty) 'phone': phone,
    });
    return Contributor.fromJson(result);
  }

  /// Creates many contributors at once from an already-parsed list (see
  /// ContributorListParser) -- one HTTP call, not a loop. Rows whose name
  /// already exists in the collection are skipped and reported back rather
  /// than duplicated.
  Future<ContributorBulkImportResult> bulkImportContributors({
    required String collectionId,
    required List<({String name, int? expectedAmount, String? phone})> rows,
  }) async {
    final result = await _post('/collections/$collectionId/contributors/bulk', {
      'contributors': rows
          .map((r) => {
                'name': r.name,
                if (r.expectedAmount != null) 'expected_amount': r.expectedAmount,
                if (r.phone != null) 'phone': r.phone,
              })
          .toList(),
    });
    return ContributorBulkImportResult.fromJson(result as Map<String, dynamic>);
  }

  /// Records a historical contribution with no M-PESA message behind it
  /// (e.g. backfilling weeks from a group's existing manual tracker).
  /// Confirmed immediately -- there's no ambiguity to reconcile since the
  /// contributor is named directly.
  Future<Transaction> recordManualContribution({
    required String collectionId,
    required String contributorId,
    required int amount,
    required DateTime timestamp,
  }) async {
    // Deliberately NOT `timestamp.toUtc()`: this is meant to represent a
    // calendar date (which week this counts toward), not a real moment in
    // time. `timestamp` is often built as a bare local midnight (e.g. from
    // ContributorListParser's week-header dates); converting that to UTC
    // in any positive-offset timezone (e.g. Kenya, UTC+3) subtracts hours
    // and lands on the *previous* day -- which, for a Monday date, silently
    // shifts the whole entry into the prior week's bucket. Sending the
    // date components directly at a fixed UTC time-of-day sidesteps any
    // such conversion entirely. Caught via real phone testing.
    final datePart = '${timestamp.year.toString().padLeft(4, '0')}-'
        '${timestamp.month.toString().padLeft(2, '0')}-'
        '${timestamp.day.toString().padLeft(2, '0')}';
    final result = await _post(
      '/collections/$collectionId/contributors/$contributorId/manual-contributions',
      {'amount': amount, 'timestamp': '${datePart}T12:00:00Z'},
    );
    return Transaction.fromJson(result);
  }

  // ---------------------------------------------------------------------
  // Transactions
  // ---------------------------------------------------------------------

  Future<List<Transaction>> listTransactions(String collectionId) async {
    final result = await _get('/collections/$collectionId/transactions');
    return (result as List).map((e) => Transaction.fromJson(e)).toList();
  }

  /// Records a structured transaction candidate -- as a future mobile app
  /// would after parsing an M-PESA SMS locally. For now this is manual
  /// entry, mirroring how a harambee secretary records a payment today.
  Future<Transaction> createTransaction({
    required String collectionId,
    required String mpesaCode,
    required String senderName,
    required int amount,
    String? senderPhone,
    DateTime? timestamp,
  }) async {
    final result = await _post('/collections/$collectionId/transactions', {
      'mpesa_code': mpesaCode,
      'sender_name': senderName,
      'amount': amount,
      'timestamp': (timestamp ?? DateTime.now()).toUtc().toIso8601String(),
      if (senderPhone != null && senderPhone.isNotEmpty) 'sender_phone': senderPhone,
    });
    return Transaction.fromJson(result);
  }

  // ---------------------------------------------------------------------
  // Reconciliation
  // ---------------------------------------------------------------------

  Future<List<ReconciliationDecision>> reconcile(String collectionId) async {
    final result = await _post('/collections/$collectionId/reconcile');
    return (result as List)
        .map((e) => ReconciliationDecision.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<Transaction> resolveReview({
    required String transactionId,
    required HumanReviewAction action,
    String? contributorId,
    String? newContributorName,
    DateTime? effectiveDate,
  }) async {
    final result = await _post('/transactions/$transactionId/resolve-review', {
      'action': humanReviewActionToJson(action),
      if (contributorId != null) 'contributor_id': contributorId,
      if (newContributorName != null) 'new_contributor_name': newContributorName,
      if (effectiveDate != null) 'effective_date': _dateOnly(effectiveDate),
    });
    return Transaction.fromJson(result);
  }

  // ---------------------------------------------------------------------
  // Reporting
  // ---------------------------------------------------------------------

  Future<CollectionReport> getReport(String collectionId) async {
    final result = await _get('/collections/$collectionId/report');
    return CollectionReport.fromJson(result);
  }

  /// kind: one of full | paid | pending | review | harambee | weekly
  Future<String> getWhatsappText(String collectionId, String kind) async {
    final result = await _get('/collections/$collectionId/whatsapp/$kind');
    return result['text'] as String;
  }

  /// All-weeks report by default; pass weekStart/weekEnd to restrict to one
  /// week or a range, for a recurring collection's filter-by-time view.
  Future<WeeklyCollectionReport> getWeeklyReport(
    String collectionId, {
    DateTime? weekStart,
    DateTime? weekEnd,
  }) async {
    final params = <String>[
      if (weekStart != null) 'week_start=${_dateOnly(weekStart)}',
      if (weekEnd != null) 'week_end=${_dateOnly(weekEnd)}',
    ];
    final query = params.isEmpty ? '' : '?${params.join('&')}';
    final result = await _get('/collections/$collectionId/report/weekly$query');
    return WeeklyCollectionReport.fromJson(result as Map<String, dynamic>);
  }

  /// Weeks where someone else in this collection has a confirmed
  /// contribution but this contributor doesn't -- used to nudge a freshly
  /// auto-matched payment toward an earlier week it might actually belong
  /// to, without ever blocking or double-counting it.
  Future<List<DateTime>> getMissingWeeks({
    required String collectionId,
    required String contributorId,
  }) async {
    final result = await _get(
      '/collections/$collectionId/contributors/$contributorId/missing-weeks',
    );
    return (result as List).map((e) => DateTime.parse(e as String)).toList();
  }

  /// Corrects which period an already-resolved transaction counts toward
  /// in reporting -- never touches its real message timestamp or credited
  /// contributor, only which week it's bucketed into.
  Future<Transaction> setTransactionEffectiveDate({
    required String transactionId,
    required DateTime effectiveDate,
  }) async {
    final result = await _post('/transactions/$transactionId/effective-date', {
      'effective_date': _dateOnly(effectiveDate),
    });
    return Transaction.fromJson(result);
  }

  /// Shows what splitting `transactionId` into weekly contributions to
  /// `contributorId` would look like -- e.g. a KSh 200 catch-up payment
  /// from someone who missed 2 weeks of a KSh 100 weekly amount. Read-only;
  /// nothing is written until [splitIntoWeeks] is called.
  Future<WeeklySplitPreview> getSplitPreview({
    required String transactionId,
    required String contributorId,
  }) async {
    final result = await _get(
      '/transactions/$transactionId/split-preview?contributor_id=$contributorId',
    );
    return WeeklySplitPreview.fromJson(result as Map<String, dynamic>);
  }

  /// Commits a split previewed via [getSplitPreview]: the original
  /// transaction becomes IGNORED and one new CONFIRMED transaction is
  /// created per week it covers.
  Future<WeeklySplitResult> splitIntoWeeks({
    required String transactionId,
    required String contributorId,
  }) async {
    final result = await _post('/transactions/$transactionId/split-into-weeks', {
      'contributor_id': contributorId,
    });
    return WeeklySplitResult.fromJson(result as Map<String, dynamic>);
  }

  String _dateOnly(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}
