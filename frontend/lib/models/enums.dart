// Enums mirroring backend/app/models.py exactly. Kept as plain strings on
// the wire (StrEnum on the backend), parsed defensively so an unexpected
// value degrades to a safe "unknown" case instead of crashing the app.

enum ProjectStatus { active, closed, archived, unknown }

ProjectStatus projectStatusFromJson(String value) {
  switch (value) {
    case 'ACTIVE':
      return ProjectStatus.active;
    case 'CLOSED':
      return ProjectStatus.closed;
    case 'ARCHIVED':
      return ProjectStatus.archived;
    default:
      return ProjectStatus.unknown;
  }
}

enum CollectionType { main, harambee, unknown }

CollectionType collectionTypeFromJson(String value) {
  switch (value) {
    case 'MAIN':
      return CollectionType.main;
    case 'HARAMBEE':
      return CollectionType.harambee;
    default:
      return CollectionType.unknown;
  }
}

String collectionTypeToJson(CollectionType type) {
  switch (type) {
    case CollectionType.main:
      return 'MAIN';
    case CollectionType.harambee:
      return 'HARAMBEE';
    case CollectionType.unknown:
      return 'MAIN';
  }
}

enum CollectionStatus { active, closed, unknown }

CollectionStatus collectionStatusFromJson(String value) {
  switch (value) {
    case 'ACTIVE':
      return CollectionStatus.active;
    case 'CLOSED':
      return CollectionStatus.closed;
    default:
      return CollectionStatus.unknown;
  }
}

enum ContributorStatus { expected, partial, paid, unknown }

ContributorStatus contributorStatusFromJson(String value) {
  switch (value) {
    case 'EXPECTED':
      return ContributorStatus.expected;
    case 'PARTIAL':
      return ContributorStatus.partial;
    case 'PAID':
      return ContributorStatus.paid;
    default:
      return ContributorStatus.unknown;
  }
}

enum TransactionStatus {
  pending,
  matched,
  needsReview,
  confirmed,
  ignored,
  unknown,
}

TransactionStatus transactionStatusFromJson(String value) {
  switch (value) {
    case 'PENDING':
      return TransactionStatus.pending;
    case 'MATCHED':
      return TransactionStatus.matched;
    case 'NEEDS_REVIEW':
      return TransactionStatus.needsReview;
    case 'CONFIRMED':
      return TransactionStatus.confirmed;
    case 'IGNORED':
      return TransactionStatus.ignored;
    default:
      return TransactionStatus.unknown;
  }
}

enum ReconciliationDecisionType {
  autoMatched,
  needsHumanReview,
  duplicate,
  unknownSender,
  error,
  unknown,
}

ReconciliationDecisionType reconciliationDecisionTypeFromJson(String value) {
  switch (value) {
    case 'AUTO_MATCHED':
      return ReconciliationDecisionType.autoMatched;
    case 'NEEDS_HUMAN_REVIEW':
      return ReconciliationDecisionType.needsHumanReview;
    case 'DUPLICATE':
      return ReconciliationDecisionType.duplicate;
    case 'UNKNOWN_SENDER':
      return ReconciliationDecisionType.unknownSender;
    case 'ERROR':
      return ReconciliationDecisionType.error;
    default:
      return ReconciliationDecisionType.unknown;
  }
}

/// Actions a human reviewer can take on a NEEDS_REVIEW transaction, sent to
/// POST /transactions/{id}/resolve-review.
enum HumanReviewAction { creditSuggestedContributor, creditSenderAsContributor, ignore }

String humanReviewActionToJson(HumanReviewAction action) {
  switch (action) {
    case HumanReviewAction.creditSuggestedContributor:
      return 'CREDIT_SUGGESTED_CONTRIBUTOR';
    case HumanReviewAction.creditSenderAsContributor:
      return 'CREDIT_SENDER_AS_CONTRIBUTOR';
    case HumanReviewAction.ignore:
      return 'IGNORE';
  }
}
