import 'enums.dart';

class Transaction {
  final String id;
  final String collectionId;
  final String mpesaCode;
  /// The actual M-PESA sender -- "paid by". Never overwritten by
  /// reconciliation, even when credited to a different contributor.
  final String senderName;
  final String? senderPhone;
  final int amount;
  final DateTime timestamp;
  final String? rawMessage;
  final TransactionStatus status;

  /// Who the payment is credited to (a contributor id). May differ from
  /// the sender when someone pays on behalf of another contributor.
  final String? matchedContributorId;
  final String? paidByName;
  final double? confidence;
  final String? reviewReason;

  Transaction({
    required this.id,
    required this.collectionId,
    required this.mpesaCode,
    required this.senderName,
    required this.senderPhone,
    required this.amount,
    required this.timestamp,
    required this.rawMessage,
    required this.status,
    required this.matchedContributorId,
    required this.paidByName,
    required this.confidence,
    required this.reviewReason,
  });

  bool get needsReview => status == TransactionStatus.needsReview;

  factory Transaction.fromJson(Map<String, dynamic> json) {
    return Transaction(
      id: json['id'] as String,
      collectionId: json['collection_id'] as String,
      mpesaCode: json['mpesa_code'] as String,
      senderName: json['sender_name'] as String,
      senderPhone: json['sender_phone'] as String?,
      amount: json['amount'] as int,
      timestamp: DateTime.parse(json['timestamp'] as String),
      rawMessage: json['raw_message'] as String?,
      status: transactionStatusFromJson(json['status'] as String),
      matchedContributorId: json['matched_contributor_id'] as String?,
      paidByName: json['paid_by_name'] as String?,
      confidence: (json['confidence'] as num?)?.toDouble(),
      reviewReason: json['review_reason'] as String?,
    );
  }
}
