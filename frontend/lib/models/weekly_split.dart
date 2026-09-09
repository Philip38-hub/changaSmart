import 'transaction.dart';

class SplitInstallment {
  final DateTime periodStart;
  final DateTime periodEnd;
  final int amount;

  SplitInstallment({required this.periodStart, required this.periodEnd, required this.amount});

  factory SplitInstallment.fromJson(Map<String, dynamic> json) {
    return SplitInstallment(
      periodStart: DateTime.parse(json['period_start'] as String),
      periodEnd: DateTime.parse(json['period_end'] as String),
      amount: json['amount'] as int,
    );
  }
}

/// What a catch-up payment (e.g. KSh 200 covering 2 missed periods of a
/// KSh 100 recurring amount) would split into, computed entirely
/// server-side -- nothing is written until it's confirmed via [SplitResult].
class SplitPreview {
  final String contributorId;
  final int periodAmount;
  final List<SplitInstallment> installments;

  SplitPreview({
    required this.contributorId,
    required this.periodAmount,
    required this.installments,
  });

  factory SplitPreview.fromJson(Map<String, dynamic> json) {
    return SplitPreview(
      contributorId: json['contributor_id'] as String,
      periodAmount: json['period_amount'] as int,
      installments: (json['installments'] as List)
          .map((e) => SplitInstallment.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

class SplitResult {
  final Transaction originalTransaction;
  final List<Transaction> createdTransactions;

  SplitResult({required this.originalTransaction, required this.createdTransactions});

  factory SplitResult.fromJson(Map<String, dynamic> json) {
    return SplitResult(
      originalTransaction: Transaction.fromJson(json['original_transaction'] as Map<String, dynamic>),
      createdTransactions: (json['created_transactions'] as List)
          .map((e) => Transaction.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}
