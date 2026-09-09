class WeeklyContributionEntry {
  final String contributorId;
  final String name;
  final int amount;

  WeeklyContributionEntry({required this.contributorId, required this.name, required this.amount});

  factory WeeklyContributionEntry.fromJson(Map<String, dynamic> json) {
    return WeeklyContributionEntry(
      contributorId: json['contributor_id'] as String,
      name: json['name'] as String,
      amount: json['amount'] as int,
    );
  }
}

class WeeklyBreakdownEntry {
  final DateTime weekStart;
  final DateTime weekEnd;
  final List<WeeklyContributionEntry> contributions;
  final int weeklyTotal;

  WeeklyBreakdownEntry({
    required this.weekStart,
    required this.weekEnd,
    required this.contributions,
    required this.weeklyTotal,
  });

  factory WeeklyBreakdownEntry.fromJson(Map<String, dynamic> json) {
    return WeeklyBreakdownEntry(
      weekStart: DateTime.parse(json['week_start'] as String),
      weekEnd: DateTime.parse(json['week_end'] as String),
      contributions: (json['contributions'] as List)
          .map((e) => WeeklyContributionEntry.fromJson(e as Map<String, dynamic>))
          .toList(),
      weeklyTotal: json['weekly_total'] as int,
    );
  }
}

class WeeklyCollectionReport {
  final String collectionId;
  final String name;
  final List<WeeklyBreakdownEntry> weeks;
  final int grandTotal;

  WeeklyCollectionReport({
    required this.collectionId,
    required this.name,
    required this.weeks,
    required this.grandTotal,
  });

  factory WeeklyCollectionReport.fromJson(Map<String, dynamic> json) {
    return WeeklyCollectionReport(
      collectionId: json['collection_id'] as String,
      name: json['name'] as String,
      weeks: (json['weeks'] as List)
          .map((e) => WeeklyBreakdownEntry.fromJson(e as Map<String, dynamic>))
          .toList(),
      grandTotal: json['grand_total'] as int,
    );
  }
}
