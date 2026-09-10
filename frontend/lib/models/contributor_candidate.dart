/// One possible contributor match for a not-yet-created transaction shape,
/// as returned by the read-only GET /collections/{id}/candidates preview.
/// Mirrors backend/app/models.py's ContributorCandidate exactly -- used by
/// the real-time SMS alert to decide whether/how confidently to notify.
class ContributorCandidate {
  final String contributorId;
  final String name;
  final int? expectedAmount;
  final double nameSimilarity;
  final bool amountMatch;

  /// Whether the SMS's account reference (e.g. a Paybill "for account
  /// `<text>`" field) fuzzy-matched this collection's or its project's
  /// name -- see backend build_candidates. Purely informational: never
  /// changes nameSimilarity/amountMatch or backend auto-match rules.
  final bool groupNameMatch;
  final String? notes;

  ContributorCandidate({
    required this.contributorId,
    required this.name,
    required this.expectedAmount,
    required this.nameSimilarity,
    required this.amountMatch,
    required this.groupNameMatch,
    required this.notes,
  });

  factory ContributorCandidate.fromJson(Map<String, dynamic> json) {
    return ContributorCandidate(
      contributorId: json['contributor_id'] as String,
      name: json['name'] as String,
      expectedAmount: json['expected_amount'] as int?,
      nameSimilarity: (json['name_similarity'] as num).toDouble(),
      amountMatch: json['amount_match'] as bool,
      groupNameMatch: json['group_name_match'] as bool? ?? false,
      notes: json['notes'] as String?,
    );
  }
}
