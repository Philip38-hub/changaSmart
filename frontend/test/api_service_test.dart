import 'dart:convert';

import 'package:changasmart/services/api_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

http.Response _json(Object body, {int statusCode = 200}) => http.Response(
      jsonEncode(body),
      statusCode,
      headers: {'content-type': 'application/json'},
    );

Map<String, dynamic> _txnJson() => {
      'id': 'txn_1',
      'collection_id': 'coll_1',
      'mpesa_code': 'MANUAL-abc123',
      'sender_name': 'Apilo',
      'sender_phone': null,
      'amount': 100,
      'timestamp': '2026-08-17T12:00:00Z',
      'raw_message': null,
      'status': 'CONFIRMED',
      'matched_contributor_id': 'contrib_1',
      'paid_by_name': 'Apilo',
      'confidence': 1.0,
      'review_reason': null,
      'effective_date': null,
    };

Map<String, dynamic> _candidateJson({bool groupNameMatch = false}) => {
      'contributor_id': 'contrib_1',
      'name': 'Jane Wanjiku',
      'expected_amount': 3000,
      'name_similarity': 0.95,
      'amount_match': true,
      'group_name_match': groupNameMatch,
      'notes': null,
    };

Map<String, dynamic> _projectJson() => {
      'id': 'proj_1',
      'name': 'Test Project',
      'target_amount': null,
      'status': 'CLOSED',
      'created_at': '2026-08-17T12:00:00Z',
    };

void main() {
  group('getCandidates', () {
    test('sends sender_name, amount, and account_reference as query params', () async {
      http.Request? captured;
      final api = ApiService(
        baseUrl: 'http://test.local',
        client: MockClient((request) async {
          captured = request;
          return _json([_candidateJson(groupNameMatch: true)]);
        }),
      );

      final candidates = await api.getCandidates(
        collectionId: 'coll_1',
        senderName: 'Aaron Ochieng',
        amount: 100,
        accountReference: 'Omosh Welfare',
      );

      expect(candidates, hasLength(1));
      expect(candidates.first.contributorId, 'contrib_1');
      expect(candidates.first.groupNameMatch, isTrue);
      expect(captured!.url.path, '/collections/coll_1/candidates');
      expect(captured!.url.queryParameters['sender_name'], 'Aaron Ochieng');
      expect(captured!.url.queryParameters['amount'], '100');
      expect(captured!.url.queryParameters['account_reference'], 'Omosh Welfare');
    });

    test('omits account_reference when not provided', () async {
      http.Request? captured;
      final api = ApiService(
        baseUrl: 'http://test.local',
        client: MockClient((request) async {
          captured = request;
          return _json([]);
        }),
      );

      await api.getCandidates(collectionId: 'coll_1', senderName: 'Anne', amount: 100);

      expect(captured!.url.queryParameters.containsKey('account_reference'), isFalse);
    });
  });

  group('reverseTransaction', () {
    test('posts to the reverse endpoint and returns the updated transaction', () async {
      http.Request? captured;
      final api = ApiService(
        baseUrl: 'http://test.local',
        client: MockClient((request) async {
          captured = request;
          return _json({..._txnJson(), 'status': 'IGNORED', 'matched_contributor_id': null});
        }),
      );

      final result = await api.reverseTransaction('txn_1');

      expect(captured!.method, 'POST');
      expect(captured!.url.path, '/transactions/txn_1/reverse');
      expect(result.status.name, 'ignored');
    });
  });

  group('closeProject', () {
    test('posts to the project close endpoint', () async {
      http.Request? captured;
      final api = ApiService(
        baseUrl: 'http://test.local',
        client: MockClient((request) async {
          captured = request;
          return _json(_projectJson());
        }),
      );

      final result = await api.closeProject('proj_1');

      expect(captured!.method, 'POST');
      expect(captured!.url.path, '/projects/proj_1/close');
      expect(result.status.name, 'closed');
    });
  });

  group('recordManualContribution', () {
    test('a local-midnight date is not shifted to the previous day', () async {
      // Regression test: previously this called timestamp.toUtc(), which
      // for any positive-offset local timezone (e.g. Kenya, UTC+3) turns
      // local midnight on a given date into 21:00 the PREVIOUS day in UTC
      // -- silently moving a "Monday" week-start date onto the Sunday of
      // the prior week and corrupting weekly-report bucketing. Caught via
      // real phone testing where every backfilled week landed one bucket
      // early.
      http.Request? captured;
      final api = ApiService(
        baseUrl: 'http://test.local',
        client: MockClient((request) async {
          captured = request;
          return _json(_txnJson());
        }),
      );

      // A bare local DateTime at midnight -- exactly what
      // ContributorListParser._parseDdMmYy and showDatePicker produce.
      final localMidnight = DateTime(2026, 8, 17);

      await api.recordManualContribution(
        collectionId: 'coll_1',
        contributorId: 'contrib_1',
        amount: 100,
        timestamp: localMidnight,
      );

      expect(captured, isNotNull);
      final body = jsonDecode(captured!.body) as Map<String, dynamic>;
      expect(body['timestamp'], startsWith('2026-08-17'));
    });
  });
}
