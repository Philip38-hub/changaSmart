import 'dart:convert';

import 'package:changasmart/models/models.dart';
import 'package:changasmart/services/api_service.dart';
import 'package:changasmart/widgets/review_action_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

http.Response _json(Object body, {int statusCode = 200}) => http.Response(
      jsonEncode(body),
      statusCode,
      headers: {'content-type': 'application/json'},
    );

Map<String, dynamic> _contributorJson(String id, String name) => {
      'id': id,
      'collection_id': 'coll_1',
      'name': name,
      'expected_amount': null,
      'phone': null,
      'status': 'EXPECTED',
      'aliases': [],
    };

Map<String, dynamic> _txnJson() => {
      'id': 'txn_1',
      'collection_id': 'coll_1',
      'mpesa_code': 'UI8J065WQX',
      'sender_name': 'perister  mokua',
      'sender_phone': null,
      'amount': 100,
      'timestamp': '2026-09-08T09:00:00Z',
      'raw_message': null,
      'status': 'NEEDS_REVIEW',
      'matched_contributor_id': null,
      'paid_by_name': 'perister  mokua',
      'confidence': 0.2,
      'review_reason': 'No strong evidence to match transaction to any expected contributor.',
      'effective_date': null,
    };

Transaction _txn() => Transaction.fromJson(_txnJson());

Future<void> _pump(WidgetTester tester, ApiService api) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ApiServiceProvider(
          api: api,
          child: ReviewActionCard(
            collectionId: 'coll_1',
            transaction: _txn(),
            suggestedContributorName: null,
            onResolved: (_) {},
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('choosing a different contributor posts the picked contributor id', (tester) async {
    http.Request? resolveRequest;
    final api = ApiService(
      baseUrl: 'http://test.local',
      client: MockClient((request) async {
        if (request.method == 'GET' && request.url.path.endsWith('/contributors')) {
          return _json([_contributorJson('contrib_mose', 'Mose'), _contributorJson('contrib_apilo', 'Apilo')]);
        }
        if (request.method == 'POST' && request.url.path.endsWith('/resolve-review')) {
          resolveRequest = request;
          return _json(_txnJson());
        }
        return _json({}, statusCode: 404);
      }),
    );

    await _pump(tester, api);

    await tester.tap(find.text('Choose a different contributor'));
    await tester.pumpAndSettle();

    expect(find.text('Mose'), findsOneWidget);
    expect(find.text('Apilo'), findsOneWidget);

    await tester.tap(find.text('Mose'));
    await tester.pumpAndSettle();

    expect(resolveRequest, isNotNull);
    final body = jsonDecode(resolveRequest!.body) as Map<String, dynamic>;
    expect(body['action'], 'CREDIT_SUGGESTED_CONTRIBUTOR');
    expect(body['contributor_id'], 'contrib_mose');
    expect(body.containsKey('effective_date'), isFalse);
  });

  testWidgets('already-recorded button ignores the payment but still posts a contributor id', (tester) async {
    http.Request? resolveRequest;
    final api = ApiService(
      baseUrl: 'http://test.local',
      client: MockClient((request) async {
        if (request.method == 'GET' && request.url.path.endsWith('/contributors')) {
          return _json([_contributorJson('contrib_mose', 'Mose')]);
        }
        if (request.method == 'POST' && request.url.path.endsWith('/resolve-review')) {
          resolveRequest = request;
          return _json(_txnJson());
        }
        return _json({}, statusCode: 404);
      }),
    );

    await _pump(tester, api);

    await tester.tap(find.text('Already recorded -- just remember this name'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mose'));
    await tester.pumpAndSettle();

    expect(resolveRequest, isNotNull);
    final body = jsonDecode(resolveRequest!.body) as Map<String, dynamic>;
    expect(body['action'], 'IGNORE');
    expect(body['contributor_id'], 'contrib_mose');
  });

  testWidgets('picking a different date includes effective_date in the resolve request', (tester) async {
    http.Request? resolveRequest;
    final api = ApiService(
      baseUrl: 'http://test.local',
      client: MockClient((request) async {
        if (request.method == 'POST' && request.url.path.endsWith('/resolve-review')) {
          resolveRequest = request;
          return _json(_txnJson());
        }
        return _json({}, statusCode: 404);
      }),
    );

    await _pump(tester, api);

    await tester.tap(find.text('Change'));
    await tester.pumpAndSettle();

    // Confirm the date picker's default "OK" action to accept the
    // preselected date (the transaction's own timestamp) without needing
    // to interact with the calendar grid itself.
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    expect(find.text('Reset'), findsOneWidget);

    await tester.tap(find.text('Credit perister  mokua'));
    await tester.pumpAndSettle();

    expect(resolveRequest, isNotNull);
    final body = jsonDecode(resolveRequest!.body) as Map<String, dynamic>;
    expect(body['action'], 'CREDIT_SENDER_AS_CONTRIBUTOR');
    expect(body['effective_date'], '2026-09-08');
  });
}
