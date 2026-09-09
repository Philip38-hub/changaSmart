import 'dart:convert';

import 'package:changasmart/screens/contributors/import_contributors_screen.dart';
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

Map<String, dynamic> _contributorJson(String name) => {
      'id': 'contrib_${name.toLowerCase()}',
      'collection_id': 'coll_1',
      'name': name,
      'expected_amount': null,
      'phone': null,
      'status': 'EXPECTED',
      'aliases': [],
    };

Future<void> _pushImportScreen(WidgetTester tester, ApiService api) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => Navigator.of(context).push<bool>(
                MaterialPageRoute(
                  builder: (_) => ImportContributorsScreen(api: api, collectionId: 'coll_1'),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('paste, parse, and import posts the parsed rows to the bulk endpoint', (tester) async {
    http.Request? bulkRequest;
    final api = ApiService(
      baseUrl: 'http://test.local',
      client: MockClient((request) async {
        if (request.method == 'GET' && request.url.path.endsWith('/contributors')) {
          return _json([]);
        }
        if (request.method == 'POST' && request.url.path.endsWith('/contributors/bulk')) {
          bulkRequest = request;
          return _json({
            'created': [_contributorJson('Apilo'), _contributorJson('Omosh')],
            'skipped_names': [],
          });
        }
        return _json({}, statusCode: 404);
      }),
    );

    await _pushImportScreen(tester, api);

    await tester.enterText(find.byType(TextField), '1. Apilo-100\n2. Omosh-100');
    await tester.pump();
    await tester.tap(find.text('Parse'));
    await tester.pumpAndSettle();

    expect(find.text('Apilo'), findsOneWidget);
    expect(find.text('Omosh'), findsOneWidget);

    await tester.tap(find.text('Import (2)'));
    await tester.pumpAndSettle();

    expect(bulkRequest, isNotNull);
    final body = jsonDecode(bulkRequest!.body) as Map<String, dynamic>;
    final contributors = body['contributors'] as List;
    expect(contributors, hasLength(2));
    expect(contributors[0]['name'], 'Apilo');
    expect(contributors[0].containsKey('expected_amount'), isFalse);
    expect(contributors[1]['name'], 'Omosh');

    expect(find.text('2 contributors added'), findsOneWidget);
  });

  testWidgets('excluding a row removes it from the import request', (tester) async {
    http.Request? bulkRequest;
    final api = ApiService(
      baseUrl: 'http://test.local',
      client: MockClient((request) async {
        if (request.method == 'GET' && request.url.path.endsWith('/contributors')) {
          return _json([]);
        }
        if (request.method == 'POST' && request.url.path.endsWith('/contributors/bulk')) {
          bulkRequest = request;
          return _json({'created': [_contributorJson('Apilo')], 'skipped_names': []});
        }
        return _json({}, statusCode: 404);
      }),
    );

    await _pushImportScreen(tester, api);

    await tester.enterText(find.byType(TextField), 'Apilo\nOmosh');
    await tester.pump();
    await tester.tap(find.text('Parse'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(CheckboxListTile, 'Omosh'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Import (1)'));
    await tester.pumpAndSettle();

    final body = jsonDecode(bulkRequest!.body) as Map<String, dynamic>;
    expect((body['contributors'] as List), hasLength(1));
    expect((body['contributors'] as List).single['name'], 'Apilo');
  });
}
