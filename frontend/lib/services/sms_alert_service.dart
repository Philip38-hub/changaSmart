import 'dart:convert';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';
import '../models/mpesa_sms.dart';
import '../utils/format.dart';
import 'api_service.dart';
import 'mpesa_sms_parser.dart';

/// SharedPreferences key for the triple-match auto-import kill switch --
/// default ON. See SmsAlertService._autoImportEnabled.
const String kAutoImportPreferenceKey = 'sms_alert_auto_import_enabled';

const String _channelId = 'changasmart_contribution_alerts';
const String _channelName = 'Contribution alerts';
const String _channelDescription =
    "Alerts when an M-PESA message looks like a contribution to one of your collections.";

/// Kinds of real-time alert this service can raise for one incoming SMS.
/// Mirrors the tiers in reconciliation.build_candidates: `strong` and
/// `weak` map to its two candidate tiers (near-exact name match vs.
/// amount/group-only evidence); `autoImported` is the stricter
/// name-AND-amount-AND-group triple match that gets imported unattended.
enum SmsAlertTier { strong, weak, autoImported }

/// Decides whether/how to alert on a newly-arrived M-PESA SMS, and -- for
/// the strongest evidence -- imports and reconciles it fully unattended.
///
/// Called identically from the foreground SMS listener and the background
/// top-level handler (see sms_inbox_service.dart/main.dart) -- this is
/// fully self-contained (its own ApiService, its own notifications plugin
/// instance) since a background isolate shares no state with the running
/// app. A message with no match signal at all is left alone entirely: it
/// still shows up in the M-PESA Inbox's All/Unimported tabs as before,
/// just without a push alert.
class SmsAlertService {
  // Mirrors backend/app/services/reconciliation.py's thresholds exactly
  // -- see that module for why these specific values.
  static const double _exactMatchSimilarity = 0.92;
  static const double _minCandidateSimilarity = 0.4;

  static Future<void> process({
    required String? body,
    required String? address,
    required int? timestampMillis,
  }) async {
    if (body == null || body.isEmpty) return;
    final timestamp = timestampMillis == null
        ? DateTime.now()
        : DateTime.fromMillisecondsSinceEpoch(timestampMillis);

    final sms = MpesaSmsParser.classify(
      id: '${address ?? ''}-${timestamp.millisecondsSinceEpoch}',
      body: body,
      address: address,
      timestamp: timestamp,
    );
    if (sms.kind != MpesaSmsKind.incomingPayment) return;

    final api = ApiService();
    MatchOutcome? outcome;
    try {
      outcome = await _findBestMatch(api, sms);
    } catch (_) {
      // A network hiccup finding candidates must never crash the SMS
      // listener -- the message is still safely sitting in the Inbox for
      // manual import either way.
      return;
    }
    if (outcome == null) return;

    final plugin = FlutterLocalNotificationsPlugin();
    await _initPlugin(plugin);

    if (outcome.tier == SmsAlertTier.autoImported && outcome.resolvedCollectionId != null) {
      await _autoImport(api, plugin, outcome, sms);
    } else {
      await _notifyTapToImport(plugin, outcome, sms);
    }
  }

  static Future<MatchOutcome?> _findBestMatch(ApiService api, MpesaSmsResult sms) async {
    final projects = await api.listProjects();
    final activeCollections = <Collection>[];
    for (final project in projects) {
      if (project.status != ProjectStatus.active) continue;
      final collections = await api.listCollections(project.id);
      activeCollections.addAll(collections.where((c) => c.status == CollectionStatus.active));
    }
    if (activeCollections.isEmpty) return null;

    final topCandidates = <CollectionMatch>[];
    for (final collection in activeCollections) {
      List<ContributorCandidate> candidates;
      try {
        candidates = await api.getCandidates(
          collectionId: collection.id,
          senderName: sms.senderName!,
          amount: sms.amount!,
          accountReference: sms.accountReference,
        );
      } catch (_) {
        continue;
      }
      if (candidates.isEmpty) continue;
      // build_candidates already ranks its own output best-first.
      topCandidates.add(CollectionMatch(collection, candidates.first));
    }
    return resolveMatch(topCandidates);
  }

  /// Pure decision logic, isolated from network/plugin I/O so it's directly
  /// unit-testable: given each active collection's best candidate (already
  /// fetched), decides whether there's a match worth alerting on, at what
  /// tier, and for which collection -- or leaves it genuinely unresolved
  /// when more than one collection ties with no group-name signal to break
  /// it (see SmsAlertTier and the "tie" case in the design notes above).
  static MatchOutcome? resolveMatch(List<CollectionMatch> topCandidatesByCollection) {
    final qualifying = topCandidatesByCollection
        .where((m) => isStrong(m.candidate) || isWeak(m.candidate))
        .toList();
    if (qualifying.isEmpty) return null;

    final groupWinners = qualifying.where((m) => m.candidate.groupNameMatch).toList()
      ..sort(_compareMatches);
    if (groupWinners.isNotEmpty) {
      final winner = groupWinners.first;
      return MatchOutcome(
        tier: tierFor(winner.candidate),
        resolvedCollectionId: winner.collection.id,
        match: winner,
      );
    }

    qualifying.sort(_compareMatches);
    final best = qualifying.first;
    final tied = qualifying
        .skip(1)
        .any((m) => m.collection.id != best.collection.id && _scoresEqual(m, best));

    return MatchOutcome(
      tier: tierFor(best.candidate),
      // A genuine tie across different collections, with no group-name
      // signal to break it, is left for the user to resolve on tap --
      // never guessed.
      resolvedCollectionId: tied ? null : best.collection.id,
      match: best,
    );
  }

  static int _compareMatches(CollectionMatch a, CollectionMatch b) {
    if (a.candidate.nameSimilarity != b.candidate.nameSimilarity) {
      return b.candidate.nameSimilarity.compareTo(a.candidate.nameSimilarity);
    }
    if (a.candidate.amountMatch != b.candidate.amountMatch) {
      return a.candidate.amountMatch ? -1 : 1;
    }
    return 0;
  }

  static bool _scoresEqual(CollectionMatch a, CollectionMatch b) =>
      a.candidate.nameSimilarity == b.candidate.nameSimilarity &&
      a.candidate.amountMatch == b.candidate.amountMatch;

  /// Mirrors try_deterministic_match's own condition: a real near-exact
  /// name match, or a remembered alias (which build_candidates already
  /// pins to nameSimilarity 1.0 -- see reconciliation.py) -- either way,
  /// >= EXACT_MATCH_SIMILARITY captures both.
  static bool isStrong(ContributorCandidate c) => c.nameSimilarity >= _exactMatchSimilarity;

  static bool isWeak(ContributorCandidate c) =>
      c.amountMatch ||
      c.groupNameMatch ||
      (c.nameSimilarity >= _minCandidateSimilarity && c.nameSimilarity < _exactMatchSimilarity);

  static SmsAlertTier tierFor(ContributorCandidate c) {
    if (isStrong(c) && c.amountMatch && c.groupNameMatch) return SmsAlertTier.autoImported;
    if (isStrong(c)) return SmsAlertTier.strong;
    return SmsAlertTier.weak;
  }

  static Future<bool> _autoImportEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(kAutoImportPreferenceKey) ?? true;
  }

  static Future<void> _autoImport(
    ApiService api,
    FlutterLocalNotificationsPlugin plugin,
    MatchOutcome outcome,
    MpesaSmsResult sms,
  ) async {
    if (!await _autoImportEnabled()) {
      await _notifyTapToImport(plugin, outcome, sms);
      return;
    }

    try {
      final created = await api.createTransaction(
        collectionId: outcome.resolvedCollectionId!,
        mpesaCode: sms.transactionCode!,
        senderName: sms.senderName!,
        amount: sms.amount!,
        senderPhone: sms.senderPhone,
        timestamp: sms.timestamp,
        autoImportedUnattended: true,
      );
      await api.reconcile(outcome.resolvedCollectionId!);
      final transactions = await api.listTransactions(outcome.resolvedCollectionId!);
      final confirmed = transactions.where((t) => t.id == created.id).firstOrNull ?? created;

      await plugin.show(
        id: _notificationId(sms.transactionCode!),
        title: 'Imported automatically — ${formatKsh(sms.amount!)}',
        body: 'From ${sms.senderName}, credited to ${outcome.match.candidate.name}. '
            'Tap to review or undo.',
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            _channelName,
            channelDescription: _channelDescription,
            importance: Importance.high,
            priority: Priority.high,
          ),
        ),
        payload: jsonEncode({
          'kind': 'autoImported',
          'collectionId': outcome.resolvedCollectionId,
          'transactionId': confirmed.id,
        }),
      );
    } catch (_) {
      // The unattended write failed (e.g. offline) -- fall back to a
      // Strong tap-to-import alert rather than silently doing nothing.
      // The message is still safely sitting in the Inbox either way.
      await _notifyTapToImport(plugin, outcome, sms);
    }
  }

  static Future<void> _notifyTapToImport(
    FlutterLocalNotificationsPlugin plugin,
    MatchOutcome outcome,
    MpesaSmsResult sms,
  ) async {
    final String title;
    final String body;
    switch (outcome.tier) {
      case SmsAlertTier.strong:
      case SmsAlertTier.autoImported: // kill-switch fallback lands here too
        title = 'Likely payment — ${formatKsh(sms.amount!)}';
        body = 'From ${outcome.match.candidate.name} (${sms.senderName}). '
            'Will auto-confirm on import. Tap to review.';
        break;
      case SmsAlertTier.weak:
        title = 'Possible payment — ${formatKsh(sms.amount!)}';
        body = 'From ${sms.senderName}. Matches ${outcome.match.candidate.name}\'s '
            'target, needs review. Tap to review.';
        break;
    }

    await plugin.show(
      id: _notificationId(sms.transactionCode!),
      title: title,
      body: body,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: _channelDescription,
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
      payload: jsonEncode({
        'kind': 'tapToImport',
        'collectionId': outcome.resolvedCollectionId,
        'transactionCode': sms.transactionCode,
      }),
    );
  }

  static int _notificationId(String transactionCode) => transactionCode.hashCode & 0x7fffffff;

  static Future<void> _initPlugin(FlutterLocalNotificationsPlugin plugin) async {
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    await plugin.initialize(settings: const InitializationSettings(android: androidInit));
  }
}

class CollectionMatch {
  final Collection collection;
  final ContributorCandidate candidate;
  CollectionMatch(this.collection, this.candidate);
}

class MatchOutcome {
  final SmsAlertTier tier;
  final String? resolvedCollectionId;
  final CollectionMatch match;
  MatchOutcome({required this.tier, required this.resolvedCollectionId, required this.match});
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
