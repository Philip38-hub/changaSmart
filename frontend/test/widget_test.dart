import 'dart:convert';

import 'package:changasmart/main.dart';
import 'package:changasmart/services/api_service.dart';
import 'package:changasmart/utils/format.dart';
import 'package:changasmart/widgets/async_data_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

http.Response _json(Object body, {int statusCode = 200}) => http.Response(
      jsonEncode(body),
      statusCode,
      headers: {'content-type': 'application/json'},
    );

void main() {
  test('formatKsh formats whole shillings with thousands separators', () {
    expect(formatKsh(5000), 'KSh 5,000');
    expect(formatKsh(0), 'KSh 0');
    expect(formatKsh(150000), 'KSh 150,000');
  });

  testWidgets('Home screen shows an empty state when there are no projects', (tester) async {
    final client = MockClient((request) async {
      if (request.url.path == '/projects') return _json([]);
      return http.Response('not found', 404);
    });
    final api = ApiService(baseUrl: 'http://test.local', client: client);

    await tester.pumpWidget(ChangaSmartApp(api: api));
    await tester.pumpAndSettle();

    expect(find.text('ChangaSmart'), findsOneWidget);
    expect(find.text('No projects yet'), findsOneWidget);
    expect(find.text('New Project'), findsOneWidget);
  });

  testWidgets('Home screen shows a project card with formatted amounts', (tester) async {
    final client = MockClient((request) async {
      if (request.url.path == '/projects') {
        return _json([
          {
            'id': 'proj_1',
            'name': "Mama Jane Medical Fund",
            'target_amount': 150000,
            'status': 'ACTIVE',
            'created_at': '2026-09-01T10:00:00Z',
          }
        ]);
      }
      if (request.url.path == '/projects/proj_1/collections') {
        return _json([
          {
            'id': 'coll_1',
            'project_id': 'proj_1',
            'type': 'MAIN',
            'name': 'Main Contribution',
            'target_amount': 150000,
            'status': 'ACTIVE',
            'date': null,
            'created_at': '2026-09-01T10:00:00Z',
          }
        ]);
      }
      if (request.url.path == '/collections/coll_1/report') {
        return _json({
          'collection_id': 'coll_1',
          'name': 'Main Contribution',
          'type': 'MAIN',
          'status': 'ACTIVE',
          'target_amount': 150000,
          'total_received': 82000,
          'remaining_amount': 68000,
          'confirmed_contributor_count': 2,
          'pending_review_count': 0,
          'contributor_breakdown': [],
        });
      }
      return http.Response('not found', 404);
    });
    final api = ApiService(baseUrl: 'http://test.local', client: client);

    await tester.pumpWidget(ChangaSmartApp(api: api));
    await tester.pumpAndSettle();

    expect(find.text('Mama Jane Medical Fund'), findsOneWidget);
    expect(find.text('KSh 82,000'), findsOneWidget);
    expect(find.text('of KSh 150,000'), findsOneWidget);
  });

  testWidgets('Home screen shows an error state with retry when the backend is unreachable', (tester) async {
    final client = MockClient((request) async => http.Response('Internal Server Error', 500));
    final api = ApiService(baseUrl: 'http://test.local', client: client);

    await tester.pumpWidget(ChangaSmartApp(api: api));
    await tester.pumpAndSettle();

    expect(find.text('Retry'), findsOneWidget);
  });

  // Regression test for a real bug caught during manual device testing:
  // AsyncDataViewState.reload() used to be `setState(() => _future = ...)`,
  // an arrow body whose *value* is the assigned Future -- which trips
  // Flutter's "setState callback returned a Future" debug assertion. That
  // assertion fires *after* the callback runs (so the fetch still happens)
  // but *before* markNeedsBuild(), so the screen silently never redraws.
  // Every reload() call in the app (pull-to-refresh, "refresh after
  // returning from a child screen") went through this exact method.
  testWidgets('AsyncDataView.reload() actually rebuilds with fresh data', (tester) async {
    final key = GlobalKey<AsyncDataViewState<int>>();
    var value = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: AsyncDataView<int>(
          key: key,
          loader: () async => value,
          builder: (context, data, refresh) => Text('value: $data'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('value: 0'), findsOneWidget);

    value = 1;
    key.currentState!.reload();
    await tester.pumpAndSettle();

    expect(find.text('value: 1'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
