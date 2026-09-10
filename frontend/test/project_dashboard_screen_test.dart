import 'dart:convert';

import 'package:changasmart/models/models.dart';
import 'package:changasmart/screens/project/project_dashboard_screen.dart';
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

Project _project({String status = 'ACTIVE'}) => Project(
      id: 'proj_1',
      name: 'Test Project',
      targetAmount: null,
      status: projectStatusFromJson(status),
      createdAt: DateTime(2026, 9, 1),
    );

Map<String, dynamic> _projectJson(String status) => {
      'id': 'proj_1',
      'name': 'Test Project',
      'target_amount': null,
      'status': status,
      'created_at': '2026-09-01T10:00:00Z',
    };

void main() {
  testWidgets('shows Close Project for an active project and hides it once closed',
      (tester) async {
    var closeCalled = false;
    final api = ApiService(
      baseUrl: 'http://test.local',
      client: MockClient((r) async {
        if (r.method == 'POST' && r.url.path.endsWith('/close')) {
          closeCalled = true;
          return _json(_projectJson('CLOSED'));
        }
        if (r.url.path.endsWith('/collections')) return _json([]);
        return _json({});
      }),
    );

    await tester.pumpWidget(MaterialApp(
      home: ProjectDashboardScreen(api: api, project: _project()),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Close Project'), findsOneWidget);

    await tester.tap(find.text('Close Project'));
    await tester.pumpAndSettle();

    expect(find.text('Close Project?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Close'));
    await tester.pumpAndSettle();

    expect(closeCalled, isTrue);
    expect(find.text('Close Project'), findsNothing);
  });

  testWidgets('an already-closed project has no Close Project button', (tester) async {
    final api = ApiService(
      baseUrl: 'http://test.local',
      client: MockClient((r) async {
        if (r.url.path.endsWith('/collections')) return _json([]);
        return _json({});
      }),
    );

    await tester.pumpWidget(MaterialApp(
      home: ProjectDashboardScreen(api: api, project: _project(status: 'CLOSED')),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Close Project'), findsNothing);
  });
}
