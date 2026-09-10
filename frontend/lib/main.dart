import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'screens/home/home_screen.dart';
import 'screens/mpesa_inbox/mpesa_inbox_screen.dart';
import 'screens/mpesa_inbox/select_collection_for_alert_screen.dart';
import 'screens/transactions/transactions_screen.dart';
import 'services/api_service.dart';
import 'services/sms_inbox_service.dart';
import 'theme/app_theme.dart';
import 'widgets/review_action_card.dart';

/// Lets a real-time SMS alert notification tap navigate into the app
/// (see _handleNotificationPayload) from outside the widget tree -- the
/// tap can arrive before HomeScreen (or anything else) has built.
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final api = ApiService();
  final notifications = FlutterLocalNotificationsPlugin();
  await notifications.initialize(
    settings: const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    ),
    onDidReceiveNotificationResponse: (response) {
      _handleNotificationPayload(response.payload, api);
    },
  );

  // Real-time SMS alerts (see SmsAlertService) survive an app restart on
  // the platform side, but another_telephony's own registration doesn't
  // -- so if permission was already granted in a previous session,
  // (re)arm the listener on every boot rather than waiting for the user
  // to revisit the M-PESA Inbox screen.
  final smsService = SmsInboxService();
  if (await smsService.checkPermission() == SmsAccessState.granted) {
    smsService.startRealtimeAlerts();
  }

  // The app itself may have been cold-started by tapping a notification
  // (process was fully killed) -- capture that now, before runApp, since
  // getNotificationAppLaunchDetails only ever reports it once.
  final launchDetails = await notifications.getNotificationAppLaunchDetails();
  final launchPayload = (launchDetails?.didNotificationLaunchApp ?? false)
      ? launchDetails?.notificationResponse?.payload
      : null;

  runApp(ChangaSmartApp(api: api));

  if (launchPayload != null) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _handleNotificationPayload(launchPayload, api);
    });
  }
}

/// Decodes a real-time SMS alert's notification payload (see
/// SmsAlertService) and opens the right screen: straight to the
/// collection's M-PESA Inbox or Transactions list when the alert already
/// resolved which collection the message belongs to, or a picker when it
/// genuinely tied across more than one active collection.
void _handleNotificationPayload(String? payload, ApiService api) {
  if (payload == null) return;
  final navigator = navigatorKey.currentState;
  if (navigator == null) return;

  final Map<String, dynamic> data;
  try {
    data = jsonDecode(payload) as Map<String, dynamic>;
  } catch (_) {
    return;
  }

  final collectionId = data['collectionId'] as String?;
  final kind = data['kind'] as String?;

  if (collectionId == null) {
    navigator.push(
      MaterialPageRoute(
        builder: (_) => SelectCollectionForAlertScreen(
          api: api,
          highlightTransactionCode: data['transactionCode'] as String?,
        ),
      ),
    );
    return;
  }

  if (kind == 'autoImported') {
    navigator.push(
      MaterialPageRoute(
        builder: (_) => TransactionsScreen(
          api: api,
          collectionId: collectionId,
          highlightTransactionId: data['transactionId'] as String?,
        ),
      ),
    );
  } else {
    navigator.push(
      MaterialPageRoute(
        builder: (_) => MpesaInboxScreen(
          api: api,
          collectionId: collectionId,
          highlightTransactionCode: data['transactionCode'] as String?,
        ),
      ),
    );
  }
}

class ChangaSmartApp extends StatelessWidget {
  final ApiService api;

  const ChangaSmartApp({super.key, required this.api});

  @override
  Widget build(BuildContext context) {
    return ApiServiceProvider(
      api: api,
      child: MaterialApp(
        navigatorKey: navigatorKey,
        title: 'ChangaSmart',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        home: HomeScreen(api: api),
      ),
    );
  }
}
