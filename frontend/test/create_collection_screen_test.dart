import 'dart:convert';

import 'package:changasmart/screens/collection/create_collection_screen.dart';
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

Map<String, dynamic> _collectionJson() => {
      'id': 'coll_1',
      'project_id': 'proj_1',
      'type': 'MAIN',
      'name': 'Main Contribution',
      'target_amount': null,
      'status': 'ACTIVE',
      'date': null,
      'created_at': '2026-09-01T10:00:00Z',
      'period': 'MONTHLY',
      'period_anchor': '2026-09-01',
    };

void main() {
  testWidgets('picking a period includes it in the create-collection request', (tester) async {
    http.Request? createRequest;
    final api = ApiService(
      baseUrl: 'http://test.local',
      client: MockClient((request) async {
        if (request.method == 'POST' && request.url.path.endsWith('/collections')) {
          createRequest = request;
          return _json(_collectionJson());
        }
        return _json({}, statusCode: 404);
      }),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: CreateCollectionScreen(api: api, projectId: 'proj_1', suggestMain: true),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).first, 'Main Contribution');
    await tester.tap(find.text('Monthly'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Create Collection'));
    await tester.pumpAndSettle();

    expect(createRequest, isNotNull);
    final body = jsonDecode(createRequest!.body) as Map<String, dynamic>;
    expect(body['period'], 'MONTHLY');
  });

  testWidgets('defaults to weekly when left untouched', (tester) async {
    http.Request? createRequest;
    final api = ApiService(
      baseUrl: 'http://test.local',
      client: MockClient((request) async {
        if (request.method == 'POST' && request.url.path.endsWith('/collections')) {
          createRequest = request;
          return _json(_collectionJson());
        }
        return _json({}, statusCode: 404);
      }),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: CreateCollectionScreen(api: api, projectId: 'proj_1', suggestMain: true),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).first, 'Main Contribution');
    await tester.tap(find.text('Create Collection'));
    await tester.pumpAndSettle();

    expect(createRequest, isNotNull);
    final body = jsonDecode(createRequest!.body) as Map<String, dynamic>;
    expect(body['period'], 'WEEKLY');
  });

  testWidgets('period picker is hidden for a Harambee session', (tester) async {
    final api = ApiService(baseUrl: 'http://test.local', client: MockClient((r) async => _json({})));

    await tester.pumpWidget(
      MaterialApp(
        home: CreateCollectionScreen(api: api, projectId: 'proj_1', suggestMain: false),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('How often does this group contribute?'), findsNothing);
    expect(find.text('Date'), findsOneWidget);
  });
}
