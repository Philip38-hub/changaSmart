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

void main() {
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
