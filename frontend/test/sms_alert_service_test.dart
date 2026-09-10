import 'package:changasmart/models/models.dart';
import 'package:changasmart/services/sms_alert_service.dart';
import 'package:flutter_test/flutter_test.dart';

Collection _collection(String id, {String name = 'Main Contribution'}) => Collection(
      id: id,
      projectId: 'proj_1',
      type: CollectionType.main,
      name: name,
      targetAmount: null,
      status: CollectionStatus.active,
      date: null,
      createdAt: DateTime(2026, 9, 1),
      period: PeriodType.weekly,
      periodAnchor: DateTime(2026, 9, 1),
    );

ContributorCandidate _candidate({
  double nameSimilarity = 0.0,
  bool amountMatch = false,
  bool groupNameMatch = false,
  String name = 'Jane Wanjiku',
}) =>
    ContributorCandidate(
      contributorId: 'contrib_1',
      name: name,
      expectedAmount: 3000,
      nameSimilarity: nameSimilarity,
      amountMatch: amountMatch,
      groupNameMatch: groupNameMatch,
      notes: null,
    );

void main() {
  group('tierFor', () {
    test('near-exact name match alone is strong', () {
      expect(SmsAlertService.tierFor(_candidate(nameSimilarity: 0.95)), SmsAlertTier.strong);
    });

    test('amount-only match (the Aaron/Omosh case) is weak, never strong', () {
      final candidate = _candidate(nameSimilarity: 0.2, amountMatch: true);
      expect(SmsAlertService.isStrong(candidate), isFalse);
      expect(SmsAlertService.isWeak(candidate), isTrue);
      expect(SmsAlertService.tierFor(candidate), SmsAlertTier.weak);
    });

    test('group-name-only match is weak', () {
      final candidate = _candidate(nameSimilarity: 0.1, groupNameMatch: true);
      expect(SmsAlertService.tierFor(candidate), SmsAlertTier.weak);
    });

    test('name AND amount AND group name together is the auto-import tier', () {
      final candidate = _candidate(nameSimilarity: 0.98, amountMatch: true, groupNameMatch: true);
      expect(SmsAlertService.tierFor(candidate), SmsAlertTier.autoImported);
    });

    test('strong name match without amount or group match stays strong, not auto-import', () {
      final candidate = _candidate(nameSimilarity: 0.98);
      expect(SmsAlertService.tierFor(candidate), SmsAlertTier.strong);
    });

    test('mid-range similarity with nothing else is weak', () {
      final candidate = _candidate(nameSimilarity: 0.6);
      expect(SmsAlertService.tierFor(candidate), SmsAlertTier.weak);
    });
  });

  group('resolveMatch', () {
    test('no active collection has any signal -- no alert at all', () {
      final result = SmsAlertService.resolveMatch([
        CollectionMatch(_collection('coll_1'), _candidate(nameSimilarity: 0.1)),
      ]);
      expect(result, isNull);
    });

    test('a single qualifying collection resolves directly', () {
      final result = SmsAlertService.resolveMatch([
        CollectionMatch(_collection('coll_1'), _candidate(nameSimilarity: 0.95)),
      ]);
      expect(result, isNotNull);
      expect(result!.resolvedCollectionId, 'coll_1');
      expect(result.tier, SmsAlertTier.strong);
    });

    test('a group-name match wins outright over a merely higher-similarity collection', () {
      final result = SmsAlertService.resolveMatch([
        CollectionMatch(_collection('coll_strong'), _candidate(nameSimilarity: 0.99)),
        CollectionMatch(
          _collection('coll_group'),
          _candidate(nameSimilarity: 0.5, groupNameMatch: true),
        ),
      ]);
      expect(result!.resolvedCollectionId, 'coll_group');
    });

    test('two different collections tied on the same weak evidence resolve as unresolved', () {
      final result = SmsAlertService.resolveMatch([
        CollectionMatch(_collection('coll_1'), _candidate(nameSimilarity: 0.2, amountMatch: true)),
        CollectionMatch(_collection('coll_2'), _candidate(nameSimilarity: 0.2, amountMatch: true)),
      ]);
      expect(result, isNotNull);
      expect(result!.resolvedCollectionId, isNull);
    });

    test('a clear winner among several candidates is not treated as a tie', () {
      final result = SmsAlertService.resolveMatch([
        CollectionMatch(_collection('coll_1'), _candidate(nameSimilarity: 0.95)),
        CollectionMatch(_collection('coll_2'), _candidate(nameSimilarity: 0.5, amountMatch: true)),
      ]);
      expect(result!.resolvedCollectionId, 'coll_1');
      expect(result.tier, SmsAlertTier.strong);
    });
  });
}
