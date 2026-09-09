import 'enums.dart';

class ContributorBreakdownEntry {
  final String contributorId;
  final String name;
  final int? expectedAmount;

  /// expectedAmount scaled by how many weeks the collection has actually
  /// recorded so far -- e.g. a KSh 100 weekly amount across 4 recorded
  /// weeks is a KSh 400 running target, not KSh 100. Null until at least
  /// one week has been recorded, or when expectedAmount itself isn't set.
  final int? currentTargetAmount;
  final int totalPaid;
  final ContributorStatus status;

  ContributorBreakdownEntry({
    required this.contributorId,
    required this.name,
    required this.expectedAmount,
    required this.currentTargetAmount,
    required this.totalPaid,
    required this.status,
  });

  bool get hasPaid => totalPaid > 0;

  factory ContributorBreakdownEntry.fromJson(Map<String, dynamic> json) {
    return ContributorBreakdownEntry(
      contributorId: json['contributor_id'] as String,
      name: json['name'] as String,
      expectedAmount: json['expected_amount'] as int?,
      currentTargetAmount: json['current_target_amount'] as int?,
      totalPaid: json['total_paid'] as int,
      status: contributorStatusFromJson(json['status'] as String),
    );
  }
}

/// Deterministic financial report for one collection. Every figure here
/// was computed by backend Python arithmetic, never by the LLM.
class CollectionReport {
  final String collectionId;
  final String name;
  final CollectionType type;
  final CollectionStatus status;
  final int? targetAmount;
  final int totalReceived;
  final int? remainingAmount;
  final int confirmedContributorCount;
  final int pendingReviewCount;
  final List<ContributorBreakdownEntry> contributorBreakdown;

  CollectionReport({
    required this.collectionId,
    required this.name,
    required this.type,
    required this.status,
    required this.targetAmount,
    required this.totalReceived,
    required this.remainingAmount,
    required this.confirmedContributorCount,
    required this.pendingReviewCount,
    required this.contributorBreakdown,
  });

  double get progress {
    if (targetAmount == null || targetAmount == 0) return 0;
    final ratio = totalReceived / targetAmount!;
    return ratio.clamp(0.0, 1.0);
  }

  int get pendingContributorCount =>
      contributorBreakdown.where((c) => !c.hasPaid).length;

  factory CollectionReport.fromJson(Map<String, dynamic> json) {
    return CollectionReport(
      collectionId: json['collection_id'] as String,
      name: json['name'] as String,
      type: collectionTypeFromJson(json['type'] as String),
      status: collectionStatusFromJson(json['status'] as String),
      targetAmount: json['target_amount'] as int?,
      totalReceived: json['total_received'] as int,
      remainingAmount: json['remaining_amount'] as int?,
      confirmedContributorCount: json['confirmed_contributor_count'] as int,
      pendingReviewCount: json['pending_review_count'] as int,
      contributorBreakdown: (json['contributor_breakdown'] as List)
          .map((e) => ContributorBreakdownEntry.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}
