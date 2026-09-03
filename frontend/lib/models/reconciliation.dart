import 'enums.dart';

/// Result of one transaction going through /collections/{id}/reconcile.
/// A batch reconcile call returns a list of these (one per PENDING
/// transaction it touched). An "ERROR" entry (agent call failed, e.g. no
/// Bedrock access) carries no reason/confidence -- the transaction is left
/// untouched (still PENDING) for a retry.
class ReconciliationDecision {
  final ReconciliationDecisionType decision;
  final String transactionId;
  final String? suggestedContributorId;
  final String? paidBy;
  final String? reason;
  final double? confidence;
  final String? error;

  ReconciliationDecision({
    required this.decision,
    required this.transactionId,
    required this.suggestedContributorId,
    required this.paidBy,
    required this.reason,
    required this.confidence,
    required this.error,
  });

  bool get isAutoMatched => decision == ReconciliationDecisionType.autoMatched;
  bool get needsReview => decision == ReconciliationDecisionType.needsHumanReview;
  bool get isError => decision == ReconciliationDecisionType.error;

  factory ReconciliationDecision.fromJson(Map<String, dynamic> json) {
    return ReconciliationDecision(
      decision: reconciliationDecisionTypeFromJson(json['decision'] as String),
      transactionId: json['transaction_id'] as String,
      suggestedContributorId: json['suggested_contributor_id'] as String?,
      paidBy: json['paid_by'] as String?,
      reason: json['reason'] as String?,
      confidence: (json['confidence'] as num?)?.toDouble(),
      error: json['error'] as String?,
    );
  }
}
