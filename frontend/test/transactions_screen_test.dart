import 'dart:convert';

import 'package:changasmart/screens/transactions/transactions_screen.dart';
import 'package:changasmart/services/api_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

http.Response _json(Object body, {int statusCode = 200}) => http.Response(
      jsonEncode(body),
      statusCode,
      headers: {'content-type': 'application/json'},
    );

Map<String, dynamic> _txnJson({
  required String id,
  required String code,
  required String sender,
  required int amount,
  String status = 'CONFIRMED',
  String? matchedContributorId,
  bool autoImportedUnattended = false,
}) =>
    {
      'id': id,
      'collection_id': 'coll_1',
      'mpesa_code': code,
      'sender_name': sender,
      'sender_phone': null,
      'amount': amount,
      'timestamp': '2026-09-04T10:00:00Z',
      'raw_message': null,
      'status': status,
      'matched_contributor_id': matchedContributorId,
      'paid_by_name': sender,
      'confidence': 1.0,
      'review_reason': null,
      'auto_imported_unattended': autoImportedUnattended,
    };

Map<String, dynamic> _reportJson() => {
      'collection_id': 'coll_1',
      'name': 'Main Contribution',
      'type': 'MAIN',
      'status': 'ACTIVE',
      'target_amount': null,
      'total_received': 0,
      'remaining_amount': null,
      'confirmed_contributor_count': 0,
      'pending_review_count': 0,
      'contributor_breakdown': [
        {
          'contributor_id': 'contrib_1',
          'name': 'Jane Wanjiku',
          'expected_amount': 3000,
          'current_target_amount': 3000,
          'total_paid': 3000,
          'status': 'PAID',
        },
      ],
    };

void main() {
  testWidgets('an auto-imported transaction shows the Auto-imported badge and an Undo action',
      (tester) async {
    final api = ApiService(
      baseUrl: 'http://test.local',
      client: MockClient((r) async {
        if (r.url.path.endsWith('/transactions')) {
          return _json([
            _txnJson(
              id: 'txn_1',
              code: 'AUTO001',
              sender: 'Jane Wanjiku',
              amount: 3000,
              matchedContributorId: 'contrib_1',
              autoImportedUnattended: true,
            ),
          ]);
        }
        if (r.url.path.endsWith('/report')) return _json(_reportJson());
        return _json({});
      }),
    );

    await tester.pumpWidget(MaterialApp(
      home: TransactionsScreen(api: api, collectionId: 'coll_1'),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Auto-imported'), findsOneWidget);
    expect(find.text('Undo'), findsOneWidget);
  });

  testWidgets('a manually-imported transaction has no Undo action', (tester) async {
    final api = ApiService(
      baseUrl: 'http://test.local',
      client: MockClient((r) async {
        if (r.url.path.endsWith('/transactions')) {
          return _json([
            _txnJson(id: 'txn_1', code: 'MAN001', sender: 'Jane Wanjiku', amount: 3000),
          ]);
        }
        if (r.url.path.endsWith('/report')) return _json(_reportJson());
        return _json({});
      }),
    );

    await tester.pumpWidget(MaterialApp(
      home: TransactionsScreen(api: api, collectionId: 'coll_1'),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Auto-imported'), findsNothing);
    expect(find.text('Undo'), findsNothing);
  });

  testWidgets('tapping Undo confirms, calls reverseTransaction, and reloads', (tester) async {
    var reverseCalled = false;
    var status = 'CONFIRMED';

    final api = ApiService(
      baseUrl: 'http://test.local',
      client: MockClient((r) async {
        if (r.method == 'POST' && r.url.path.endsWith('/reverse')) {
          reverseCalled = true;
          status = 'IGNORED';
          return _json(_txnJson(
            id: 'txn_1',
            code: 'AUTO001',
            sender: 'Jane Wanjiku',
            amount: 3000,
            status: status,
            autoImportedUnattended: true,
          ));
        }
        if (r.url.path.endsWith('/transactions')) {
          return _json([
            _txnJson(
              id: 'txn_1',
              code: 'AUTO001',
              sender: 'Jane Wanjiku',
              amount: 3000,
              status: status,
              matchedContributorId: status == 'CONFIRMED' ? 'contrib_1' : null,
              autoImportedUnattended: true,
            ),
          ]);
        }
        if (r.url.path.endsWith('/report')) return _json(_reportJson());
        return _json({});
      }),
    );

    await tester.pumpWidget(MaterialApp(
      home: TransactionsScreen(api: api, collectionId: 'coll_1'),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();

    expect(find.text('Undo automatic import?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Undo'));
    await tester.pumpAndSettle();

    expect(reverseCalled, isTrue);
    // After reload, the transaction is IGNORED so Undo is no longer offered.
    expect(find.text('Undo'), findsNothing);
  });

  testWidgets('highlightTransactionId visually marks the matching transaction', (tester) async {
    final api = ApiService(
      baseUrl: 'http://test.local',
      client: MockClient((r) async {
        if (r.url.path.endsWith('/transactions')) {
          return _json([
            _txnJson(id: 'txn_1', code: 'AAA111', sender: 'John Kamau', amount: 1000),
            _txnJson(id: 'txn_2', code: 'BBB222', sender: 'Anne Otieno', amount: 2000),
          ]);
        }
        if (r.url.path.endsWith('/report')) return _json(_reportJson());
        return _json({});
      }),
    );

    await tester.pumpWidget(MaterialApp(
      home: TransactionsScreen(api: api, collectionId: 'coll_1', highlightTransactionId: 'txn_2'),
    ));
    await tester.pumpAndSettle();

    final highlightedCard = tester.widget<Card>(
      find.ancestor(of: find.text('Anne Otieno'), matching: find.byType(Card)),
    );
    final side = (highlightedCard.shape as RoundedRectangleBorder).side;
    expect(side.width, 1.5);
  });
}
