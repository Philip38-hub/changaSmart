import 'enums.dart';

class PeriodContributionEntry {
  final String contributorId;
  final String name;
  final int amount;

  PeriodContributionEntry({required this.contributorId, required this.name, required this.amount});

  factory PeriodContributionEntry.fromJson(Map<String, dynamic> json) {
    return PeriodContributionEntry(
      contributorId: json['contributor_id'] as String,
      name: json['name'] as String,
      amount: json['amount'] as int,
    );
  }
}

class PeriodBreakdownEntry {
  final DateTime periodStart;
  final DateTime periodEnd;
  final List<PeriodContributionEntry> contributions;
  final int periodTotal;

  PeriodBreakdownEntry({
    required this.periodStart,
    required this.periodEnd,
    required this.contributions,
    required this.periodTotal,
  });

  factory PeriodBreakdownEntry.fromJson(Map<String, dynamic> json) {
    return PeriodBreakdownEntry(
      periodStart: DateTime.parse(json['period_start'] as String),
      periodEnd: DateTime.parse(json['period_end'] as String),
      contributions: (json['contributions'] as List)
          .map((e) => PeriodContributionEntry.fromJson(e as Map<String, dynamic>))
          .toList(),
      periodTotal: json['period_total'] as int,
    );
  }
}

/// A recurring collection's contributions grouped by its configured
/// period (weekly, fortnightly, or monthly -- see Collection.period).
class PeriodCollectionReport {
  final String collectionId;
  final String name;
  final PeriodType period;
  final List<PeriodBreakdownEntry> periods;
  final int grandTotal;

  PeriodCollectionReport({
    required this.collectionId,
    required this.name,
    required this.period,
    required this.periods,
    required this.grandTotal,
  });

  factory PeriodCollectionReport.fromJson(Map<String, dynamic> json) {
    return PeriodCollectionReport(
      collectionId: json['collection_id'] as String,
      name: json['name'] as String,
      period: periodTypeFromJson(json['period'] as String),
      periods: (json['periods'] as List)
          .map((e) => PeriodBreakdownEntry.fromJson(e as Map<String, dynamic>))
          .toList(),
      grandTotal: json['grand_total'] as int,
    );
  }
}
