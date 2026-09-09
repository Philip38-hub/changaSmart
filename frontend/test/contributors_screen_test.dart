import 'dart:convert';

import 'package:changasmart/screens/contributors/contributors_screen.dart';
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

Map<String, dynamic> _breakdownEntry(
  String contributorId,
  String name, {
  int? expectedAmount,
  int? currentTargetAmount,
  required int totalPaid,
}) =>
    {
      'contributor_id': contributorId,
      'name': name,
      'expected_amount': expectedAmount,
      'current_target_amount': currentTargetAmount,
      'total_paid': totalPaid,
      'status': 'EXPECTED',
    };

Map<String, dynamic> _reportJson(List<Map<String, dynamic>> breakdown) => {
      'collection_id': 'coll_1',
      'name': 'Main Contribution',
      'type': 'MAIN',
      'status': 'ACTIVE',
      'target_amount': null,
      'total_received': 700,
      'remaining_amount': null,
      'confirmed_contributor_count': 2,
      'pending_review_count': 0,
      'contributor_breakdown': breakdown,
    };

Future<void> _pump(WidgetTester tester, ApiService api) async {
  await tester.pumpWidget(
    MaterialApp(
      home: ContributorsScreen(api: api, collectionId: 'coll_1'),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows the running target scaled by weeks recorded, not the flat weekly amount', (tester) async {
    final api = ApiService(
      baseUrl: 'http://test.local',
      client: MockClient((request) async {
        if (request.method == 'GET' && request.url.path.endsWith('/report')) {
          return _json(_reportJson([
            _breakdownEntry('contrib_apilo', 'Apilo', expectedAmount: 100, currentTargetAmount: 400, totalPaid: 400),
            _breakdownEntry('contrib_esco', 'Esco', expectedAmount: 100, currentTargetAmount: 400, totalPaid: 300),
          ]));
        }
        return _json({}, statusCode: 404);
      }),
    );

    await _pump(tester, api);

    expect(find.text('KSh 400 of KSh 400'), findsOneWidget);
    expect(find.text('KSh 300 of KSh 400'), findsOneWidget);
  });

  testWidgets('falls back to the flat weekly amount before any week is recorded', (tester) async {
    final api = ApiService(
      baseUrl: 'http://test.local',
      client: MockClient((request) async {
        if (request.method == 'GET' && request.url.path.endsWith('/report')) {
          return _json(_reportJson([
            _breakdownEntry('contrib_mose', 'Mose', expectedAmount: 100, currentTargetAmount: null, totalPaid: 0),
          ]));
        }
        return _json({}, statusCode: 404);
      }),
    );

    await _pump(tester, api);

    expect(find.text('KSh 0 of KSh 100'), findsOneWidget);
  });

  testWidgets('shows just the amount paid when there is no expected amount at all', (tester) async {
    final api = ApiService(
      baseUrl: 'http://test.local',
      client: MockClient((request) async {
        if (request.method == 'GET' && request.url.path.endsWith('/report')) {
          return _json(_reportJson([
            _breakdownEntry('contrib_sarcastic', 'Sarcastic', totalPaid: 0),
          ]));
        }
        return _json({}, statusCode: 404);
      }),
    );

    await _pump(tester, api);

    expect(find.text('KSh 0'), findsOneWidget);
  });
}
