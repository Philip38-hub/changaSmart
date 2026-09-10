import 'dart:convert';

import 'package:changasmart/models/mpesa_sms.dart';
import 'package:changasmart/screens/mpesa_inbox/mpesa_inbox_screen.dart';
import 'package:changasmart/services/api_service.dart';
import 'package:changasmart/services/sms_inbox_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Test double for SmsInboxService -- never touches the real SMS/
/// permission platform channels. See MpesaInboxScreen.smsService.
class FakeSmsInboxService extends SmsInboxService {
  SmsAccessState accessState;
  final List<MpesaSmsResult> messages;
  final Object? loadError;

  FakeSmsInboxService({
    this.accessState = SmsAccessState.granted,
    this.messages = const [],
    this.loadError,
  });

  @override
  Future<SmsAccessState> checkPermission() async => accessState;

  @override
  Future<SmsAccessState> requestPermission() async {
    accessState = SmsAccessState.granted;
    return accessState;
  }

  @override
  Future<List<MpesaSmsResult>> loadMpesaMessages({int count = 500}) async {
    if (loadError != null) throw loadError!;
    return messages;
  }
}

http.Response _json(Object body, {int statusCode = 200}) => http.Response(
      jsonEncode(body),
      statusCode,
      headers: {'content-type': 'application/json'},
    );

Map<String, dynamic> _txnJson(String code, String sender, int amount, {String status = 'CONFIRMED'}) => {
      'id': 'txn_$code',
      'collection_id': 'coll_1',
      'mpesa_code': code,
      'sender_name': sender,
      'sender_phone': null,
      'amount': amount,
      'timestamp': '2026-09-04T10:00:00Z',
      'raw_message': null,
      'status': status,
      'matched_contributor_id': null,
      'paid_by_name': null,
      'confidence': null,
      'review_reason': null,
    };

Map<String, dynamic> _collectionJson() => {
      'id': 'coll_1',
      'project_id': 'proj_1',
      'type': 'MAIN',
      'name': 'Main Contribution',
      'target_amount': null,
      'status': 'ACTIVE',
      'date': null,
      'created_at': '2026-09-01T10:00:00Z',
      'period': 'WEEKLY',
      'period_anchor': '2026-09-01',
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
      'contributor_breakdown': [],
    };

MpesaSmsResult _incoming({
  required String id,
  required String code,
  required String sender,
  required int amount,
  DateTime? timestamp,
}) =>
    MpesaSmsResult(
      id: id,
      rawBody: '$code Confirmed. You have received Ksh$amount from $sender on 4/9/26 at 8:00 AM.',
      address: 'MPESA',
      timestamp: timestamp ?? DateTime(2026, 9, 4, 8),
      kind: MpesaSmsKind.incomingPayment,
      transactionCode: code,
      senderName: sender,
      amount: amount,
    );

void main() {
  testWidgets('shows a permission request card when SMS access is denied', (tester) async {
    final api = ApiService(baseUrl: 'http://test.local', client: MockClient((r) async => _json([])));
    final sms = FakeSmsInboxService(accessState: SmsAccessState.denied);

    await tester.pumpWidget(MaterialApp(
      home: MpesaInboxScreen(api: api, collectionId: 'coll_1', smsService: sms),
    ));
    await tester.pumpAndSettle();

    expect(find.text('SMS permission needed'), findsOneWidget);
    expect(find.text('Grant SMS Permission'), findsOneWidget);
  });

  testWidgets('shows an "open settings" card when permission is permanently denied', (tester) async {
    final api = ApiService(baseUrl: 'http://test.local', client: MockClient((r) async => _json([])));
    final sms = FakeSmsInboxService(accessState: SmsAccessState.permanentlyDenied);

    await tester.pumpWidget(MaterialApp(
      home: MpesaInboxScreen(api: api, collectionId: 'coll_1', smsService: sms),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Open Settings'), findsOneWidget);
  });

  testWidgets('shows "No phone SMS available" when granted but inbox is empty', (tester) async {
    final api = ApiService(
      baseUrl: 'http://test.local',
      client: MockClient((r) async {
        if (r.url.path.endsWith('/transactions')) return _json([]);
        return _json({});
      }),
    );
    final sms = FakeSmsInboxService(accessState: SmsAccessState.granted, messages: const []);

    await tester.pumpWidget(MaterialApp(
      home: MpesaInboxScreen(api: api, collectionId: 'coll_1', smsService: sms),
    ));
    await tester.pumpAndSettle();

    expect(find.text('No phone SMS available'), findsOneWidget);
  });

  testWidgets('shows an error with retry when reading the inbox fails', (tester) async {
    final api = ApiService(baseUrl: 'http://test.local', client: MockClient((r) async => _json([])));
    final sms = FakeSmsInboxService(loadError: Exception('boom'));

    await tester.pumpWidget(MaterialApp(
      home: MpesaInboxScreen(api: api, collectionId: 'coll_1', smsService: sms),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('lists messages and marks an existing transaction code as already imported', (tester) async {
    final api = ApiService(
      baseUrl: 'http://test.local',
      client: MockClient((r) async {
        if (r.method == 'GET' && r.url.path.endsWith('/transactions')) {
          return _json([_txnJson('EXIST001', 'JOHN KAMAU', 5000)]);
        }
        return _json({});
      }),
    );
    final sms = FakeSmsInboxService(messages: [
      _incoming(id: 's1', code: 'EXIST001', sender: 'JOHN KAMAU', amount: 5000),
      _incoming(id: 's2', code: 'NEW002', sender: 'ANNE OTIENO', amount: 3000),
    ]);

    await tester.pumpWidget(MaterialApp(
      home: MpesaInboxScreen(api: api, collectionId: 'coll_1', smsService: sms),
    ));
    await tester.pumpAndSettle();

    expect(find.text('2 M-PESA messages found'), findsOneWidget);
    expect(find.text('Already imported'), findsOneWidget);
    expect(find.text('Not imported'), findsOneWidget);
  });

  testWidgets('an unparsed message is shown as Needs review and is not selectable', (tester) async {
    final api = ApiService(
      baseUrl: 'http://test.local',
      client: MockClient((r) async {
        if (r.url.path.endsWith('/transactions')) return _json([]);
        return _json({});
      }),
    );
    final sms = FakeSmsInboxService(messages: [
      MpesaSmsResult(
        id: 'u1',
        rawBody: 'Confirmed. You have received Ksh3,000 today.',
        address: 'MPESA',
        timestamp: DateTime(2026, 9, 4, 8),
        kind: MpesaSmsKind.unparsed,
        amount: 3000,
        reason: 'Could not reliably extract: transaction code, sender name',
      ),
    ]);

    await tester.pumpWidget(MaterialApp(
      home: MpesaInboxScreen(api: api, collectionId: 'coll_1', smsService: sms),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Needs review'), findsOneWidget);

    // Enter selection mode -- the unparsed message's checkbox must stay
    // disabled (never selectable, since it has no code/sender/amount to
    // safely send).
    await tester.tap(find.text('Select'));
    await tester.pumpAndSettle();
    final checkbox = tester.widget<Checkbox>(find.byType(Checkbox));
    expect(checkbox.onChanged, isNull);
  });

  testWidgets('selecting and importing a message posts a transaction and reconciles', (tester) async {
    final createdCodes = <String>[];
    var reconcileCalled = false;

    final api = ApiService(
      baseUrl: 'http://test.local',
      client: MockClient((r) async {
        if (r.method == 'GET' && r.url.path.endsWith('/transactions')) {
          return _json(createdCodes.map((c) => _txnJson(c, 'ANNE OTIENO', 3000)).toList());
        }
        if (r.method == 'POST' && r.url.path.endsWith('/transactions')) {
          final body = jsonDecode(r.body) as Map<String, dynamic>;
          createdCodes.add(body['mpesa_code'] as String);
          return _json(_txnJson(body['mpesa_code'] as String, body['sender_name'] as String, body['amount'] as int));
        }
        if (r.method == 'POST' && r.url.path.endsWith('/reconcile')) {
          reconcileCalled = true;
          return _json([
            {
              'decision': 'NEEDS_HUMAN_REVIEW',
              'transaction_id': 'txn_NEW002',
              'suggested_contributor_id': null,
              'paid_by': 'ANNE OTIENO',
              'reason': 'test',
              'confidence': 0.5,
              'error': null,
            }
          ]);
        }
        if (r.method == 'GET' && r.url.path.endsWith('/report')) {
          return _json(_reportJson());
        }
        if (r.method == 'GET' && r.url.path.endsWith('/coll_1')) {
          return _json(_collectionJson());
        }
        return _json({});
      }),
    );
    final sms = FakeSmsInboxService(messages: [
      _incoming(id: 's1', code: 'NEW002', sender: 'ANNE OTIENO', amount: 3000),
    ]);

    await tester.pumpWidget(MaterialApp(
      home: MpesaInboxScreen(api: api, collectionId: 'coll_1', smsService: sms),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Select'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Checkbox).first);
    await tester.pumpAndSettle();

    expect(find.text('Import Selected (1)'), findsOneWidget);
    await tester.tap(find.text('Import Selected (1)'));
    await tester.pumpAndSettle();

    // Confirmation dialog.
    expect(find.text('Import 1 M-PESA transaction?'), findsOneWidget);
    await tester.tap(find.text('Import'));
    await tester.pumpAndSettle();

    expect(createdCodes, ['NEW002']);
    expect(reconcileCalled, isTrue);
    // Landed on the existing ReconciliationResultScreen -- no second
    // reconciliation UI was built for this feature.
    expect(find.text('Reconciliation Result'), findsOneWidget);
    expect(find.text('Needs your confirmation'), findsOneWidget);
  });

  testWidgets('highlightTransactionCode scrolls to and visually marks that message', (tester) async {
    final api = ApiService(
      baseUrl: 'http://test.local',
      client: MockClient((r) async {
        if (r.url.path.endsWith('/transactions')) return _json([]);
        return _json({});
      }),
    );
    final sms = FakeSmsInboxService(messages: [
      _incoming(id: 's1', code: 'AAA111', sender: 'JOHN KAMAU', amount: 1000),
      _incoming(id: 's2', code: 'HIGHLIGHT002', sender: 'ANNE OTIENO', amount: 3000),
    ]);

    await tester.pumpWidget(MaterialApp(
      home: MpesaInboxScreen(
        api: api,
        collectionId: 'coll_1',
        smsService: sms,
        highlightTransactionCode: 'HIGHLIGHT002',
      ),
    ));
    await tester.pumpAndSettle();

    final highlightedCard = tester.widget<Card>(
      find.ancestor(of: find.text('From: ANNE OTIENO'), matching: find.byType(Card)),
    );
    final side = (highlightedCard.shape as RoundedRectangleBorder).side;
    expect(side.width, 1.5);
  });

  testWidgets('a failed import is reported without crashing', (tester) async {
    final api = ApiService(
      baseUrl: 'http://test.local',
      client: MockClient((r) async {
        if (r.method == 'GET' && r.url.path.endsWith('/transactions')) return _json([]);
        if (r.method == 'POST' && r.url.path.endsWith('/transactions')) {
          return http.Response(jsonEncode({'detail': 'boom'}), 500);
        }
        return _json({});
      }),
    );
    final sms = FakeSmsInboxService(messages: [
      _incoming(id: 's1', code: 'FAIL001', sender: 'JOHN KAMAU', amount: 1000),
    ]);

    await tester.pumpWidget(MaterialApp(
      home: MpesaInboxScreen(api: api, collectionId: 'coll_1', smsService: sms),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Select'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Checkbox).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Import Selected (1)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Import'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Could not import any transactions. Check your connection and try again.'), findsOneWidget);
  });
}
