import 'dart:io' show Platform;

import 'package:another_telephony/telephony.dart' as telephony;
import 'package:flutter_sms_inbox/flutter_sms_inbox.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/mpesa_sms.dart';
import 'mpesa_sms_parser.dart';
import 'sms_alert_service.dart';

/// Entry point for a newly-arrived SMS while ChangaSmart is running (in
/// the foreground or backgrounded but not killed). Delegates entirely to
/// SmsAlertService -- this function only adapts another_telephony's
/// message shape to it.
Future<void> _handleIncomingSms(telephony.SmsMessage message) {
  return SmsAlertService.process(
    body: message.body,
    address: message.address,
    timestampMillis: message.date,
  );
}

/// Entry point for a newly-arrived SMS while the app process is fully
/// killed. Must be a genuine top-level function (not a closure or
/// instance method) so another_telephony can resolve it via a
/// PluginUtilities callback handle and re-invoke it in a fresh background
/// isolate -- see startBackgroundService in that package. `vm:entry-point`
/// stops AOT tree-shaking from stripping it since nothing in this app
/// calls it directly.
@pragma('vm:entry-point')
Future<void> handleIncomingSmsInBackground(telephony.SmsMessage message) {
  return _handleIncomingSms(message);
}

/// Mirrors permission_handler's PermissionStatus plus a device-capability
/// case, so the UI can render each state distinctly (see task section 4:
/// granted / denied / permanently denied / SMS unavailable on device).
enum SmsAccessState { granted, denied, permanentlyDenied, unavailable }

/// How many inbox messages to pull from the platform per read. M-PESA
/// messages are usually a small fraction of a phone's total SMS history;
/// this is generous enough to find them without an unbounded read. Not a
/// "poll" -- this only runs when the user opens/refreshes the screen.
const int _defaultQueryCount = 500;

/// Reads the Android SMS inbox that already exists on the device (via
/// flutter_sms_inbox, which queries the platform's SMS content provider
/// directly) and classifies each message locally via [MpesaSmsParser].
/// [loadMpesaMessages] itself is still pull-only, run on demand when the
/// M-PESA Inbox screen opens/refreshes -- but [startRealtimeAlerts] (see
/// below) separately watches for new SMS as they arrive, even while the
/// app is closed, and hands each one to [SmsAlertService]. This class is
/// the ONLY boundary between the phone's SMS inbox and the rest of the
/// app: everything downstream only ever sees the classified, structured
/// result -- never the full inbox.
class SmsInboxService {
  final SmsQuery _query = SmsQuery();

  bool get isPlatformSupported {
    try {
      return Platform.isAndroid;
    } catch (_) {
      // Platform.isAndroid throws on web; this app doesn't target web,
      // but fail safe rather than crash if it's ever run there.
      return false;
    }
  }

  Future<SmsAccessState> checkPermission() async {
    if (!isPlatformSupported) return SmsAccessState.unavailable;
    final status = await Permission.sms.status;
    return _mapStatus(status);
  }

  Future<SmsAccessState> requestPermission() async {
    if (!isPlatformSupported) return SmsAccessState.unavailable;
    final status = await Permission.sms.request();
    final result = _mapStatus(status);
    if (result == SmsAccessState.granted) startRealtimeAlerts();
    return result;
  }

  SmsAccessState _mapStatus(PermissionStatus status) {
    if (status.isGranted || status.isLimited) return SmsAccessState.granted;
    if (status.isPermanentlyDenied) return SmsAccessState.permanentlyDenied;
    return SmsAccessState.denied;
  }

  /// Starts watching for new M-PESA-shaped SMS as they arrive -- in the
  /// foreground via [handleIncomingSmsInBackground]'s sibling
  /// [_handleIncomingSms], and even while the app is fully closed via
  /// that same top-level background entry point (see
  /// another_telephony's listenIncomingSms). Safe to call more than once
  /// (e.g. on every app boot where permission is already granted, and
  /// again right after the user grants it) -- another_telephony just
  /// re-registers the same handlers. Requires SMS permission to already
  /// be granted; callers should check [checkPermission] first.
  void startRealtimeAlerts() {
    if (!isPlatformSupported) return;
    telephony.Telephony.instance.listenIncomingSms(
      onNewMessage: _handleIncomingSms,
      onBackgroundMessage: handleIncomingSmsInBackground,
    );
  }

  /// Reads the existing inbox and returns messages relevant to Mchango:
  /// incoming payments (importable) and unparsed-but-M-PESA-shaped
  /// messages (shown for transparency, never importable). Plain unrelated
  /// SMS and obviously-irrelevant M-PESA messages (airtime, withdrawals,
  /// balance checks, promotional, ...) are dropped immediately and never
  /// held onto or returned -- see task section 6.
  Future<List<MpesaSmsResult>> loadMpesaMessages({int count = _defaultQueryCount}) async {
    final messages = await _query.querySms(
      count: count,
      kinds: const [SmsQueryKind.inbox],
    );

    final results = <MpesaSmsResult>[];
    for (final message in messages) {
      final body = message.body;
      if (body == null || body.isEmpty) continue;
      final timestamp = message.date ?? DateTime.now();
      final result = MpesaSmsParser.classify(
        id: '${message.id ?? message.hashCode}',
        body: body,
        address: message.address,
        timestamp: timestamp,
      );
      if (result.kind != MpesaSmsKind.incomingPayment && result.kind != MpesaSmsKind.unparsed) {
        continue;
      }
      results.add(result);
    }

    results.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return results;
  }
}
