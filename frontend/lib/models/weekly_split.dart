import 'transaction.dart';

class WeeklySplitInstallment {
  final DateTime weekStart;
  final DateTime weekEnd;
  final int amount;

  WeeklySplitInstallment({required this.weekStart, required this.weekEnd, required this.amount});

  factory WeeklySplitInstallment.fromJson(Map<String, dynamic> json) {
    return WeeklySplitInstallment(
      weekStart: DateTime.parse(json['week_start'] as String),
      weekEnd: DateTime.parse(json['week_end'] as String),
      amount: json['amount'] as int,
    );
  }
}

/// What a catch-up payment (e.g. KSh 200 covering 2 missed weeks of a
/// KSh 100 weekly amount) would split into, computed entirely server-side
/// -- nothing is written until it's confirmed via [WeeklySplitResult].
class WeeklySplitPreview {
  final String contributorId;
  final int weeklyAmount;
  final List<WeeklySplitInstallment> installments;

  WeeklySplitPreview({
    required this.contributorId,
    required this.weeklyAmount,
    required this.installments,
  });

  factory WeeklySplitPreview.fromJson(Map<String, dynamic> json) {
    return WeeklySplitPreview(
      contributorId: json['contributor_id'] as String,
      weeklyAmount: json['weekly_amount'] as int,
      installments: (json['installments'] as List)
          .map((e) => WeeklySplitInstallment.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

class WeeklySplitResult {
  final Transaction originalTransaction;
  final List<Transaction> createdTransactions;

  WeeklySplitResult({required this.originalTransaction, required this.createdTransactions});

  factory WeeklySplitResult.fromJson(Map<String, dynamic> json) {
    return WeeklySplitResult(
      originalTransaction: Transaction.fromJson(json['original_transaction'] as Map<String, dynamic>),
      createdTransactions: (json['created_transactions'] as List)
          .map((e) => Transaction.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}
