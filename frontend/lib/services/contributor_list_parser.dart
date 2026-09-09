/// Parses a pasted contributor list -- either a WhatsApp-style list (one
/// name per line, optionally numbered/bulleted, e.g. "1. Apilo-100") or a
/// pasted CSV ("name,expected_amount,phone") -- into structured rows.
///
/// This is the only place free-text contributor lists are interpreted.
/// Everything downstream (preview, the bulk-import API call) works on
/// already-structured data, mirroring how MpesaSmsParser is the sole place
/// raw SMS text is interpreted elsewhere in this app.
class ParsedContributorRow {
  final String name;
  final int? expectedAmount;
  final String? phone;
  final String rawLine;

  ParsedContributorRow({
    required this.name,
    this.expectedAmount,
    this.phone,
    required this.rawLine,
  });
}

/// One week's recorded amount for a contributor, extracted from a
/// "Week N `<date>`" block in the pasted text -- e.g. `1. Apilo-100` under
/// `Week 1 17/08/26` becomes `(name: "Apilo", weekStart: 2026-08-17,
/// amount: 100)`. Only produced when the paste actually contains week
/// headers; a flat list produces none of these.
class ParsedWeeklyEntry {
  final String name;
  final DateTime weekStart;
  final int amount;

  ParsedWeeklyEntry({
    required this.name,
    required this.weekStart,
    required this.amount,
  });
}

class ContributorListParseResult {
  final List<ParsedContributorRow> contributors;
  final List<ParsedWeeklyEntry> weeklyEntries;
  final bool hasWeeklyData;

  /// If a clear majority of the per-week amounts in the paste agree on one
  /// figure (e.g. everyone paying KSh 100 most weeks), this is very likely
  /// the group's actual weekly contribution -- even though no one ever
  /// set an expected_amount explicitly (bulk-imported contributors
  /// deliberately don't get one, see ContributorListParser). Null when
  /// there's no weekly data, too little of it, or no clear agreement.
  final int? detectedWeeklyAmount;

  ContributorListParseResult({
    required this.contributors,
    required this.weeklyEntries,
    required this.hasWeeklyData,
    this.detectedWeeklyAmount,
  });
}

class ContributorListParser {
  static final RegExp _numberedPrefix = RegExp(r'^\s*\d+[.)]\s*');
  static final RegExp _bulletPrefix = RegExp(r'^\s*[-*•]\s*');
  static final RegExp _trailingDashAmount = RegExp(r'^(.*?)-\s*(\d*)\s*$');
  static final RegExp _weekHeader = RegExp(
    r'week\s+\d+.*?(\d{1,2})/(\d{1,2})/(\d{2,4})',
    caseSensitive: false,
  );

  static ContributorListParseResult parse(String text) {
    final lines = text.split(RegExp(r'\r\n|\r|\n'));
    final isNumberedList = lines.any((l) => _numberedPrefix.hasMatch(l));

    final contributors = <ParsedContributorRow>[];
    final weeklyEntries = <ParsedWeeklyEntry>[];
    final seenNames = <String>{};
    DateTime? currentWeekStart;
    var hasWeeklyData = false;

    for (final rawLine in lines) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;

      final weekMatch = _weekHeader.firstMatch(line);
      if (weekMatch != null) {
        currentWeekStart = _parseDdMmYy(
          weekMatch.group(1)!,
          weekMatch.group(2)!,
          weekMatch.group(3)!,
        );
        hasWeeklyData = true;
        continue;
      }

      final isNumberedLine = _numberedPrefix.hasMatch(line);
      if (isNumberedList && !isNumberedLine) {
        // Numbered-list mode: anything that isn't itself a numbered entry
        // is noise (a header, a running total, a standalone label line)
        // and is silently dropped.
        continue;
      }

      final content = line
          .replaceFirst(_numberedPrefix, '')
          .replaceFirst(_bulletPrefix, '')
          .trim();
      if (content.isEmpty) continue;

      final entry = _parseEntryContent(content);
      if (entry.name.isEmpty) continue;

      if (seenNames.add(entry.name.toLowerCase())) {
        contributors.add(
          ParsedContributorRow(
            name: entry.name,
            expectedAmount: entry.csvAmount,
            phone: entry.phone,
            rawLine: rawLine,
          ),
        );
      }

      if (currentWeekStart != null && entry.dashAmount != null) {
        weeklyEntries.add(
          ParsedWeeklyEntry(
            name: entry.name,
            weekStart: currentWeekStart,
            amount: entry.dashAmount!,
          ),
        );
      }
    }

    return ContributorListParseResult(
      contributors: contributors,
      weeklyEntries: weeklyEntries,
      hasWeeklyData: hasWeeklyData,
      detectedWeeklyAmount: _detectCommonWeeklyAmount(weeklyEntries),
    );
  }

  /// A clear majority (>=60%) of the recorded weekly amounts agreeing on
  /// one figure is treated as the group's real weekly contribution.
  /// Requires at least a couple of data points so a single contributor's
  /// one-off week can't be mistaken for a group-wide pattern.
  static int? _detectCommonWeeklyAmount(List<ParsedWeeklyEntry> entries) {
    if (entries.length < 2) return null;
    final counts = <int, int>{};
    for (final entry in entries) {
      counts[entry.amount] = (counts[entry.amount] ?? 0) + 1;
    }
    final mostCommon = counts.entries.reduce((a, b) => a.value >= b.value ? a : b);
    return mostCommon.value / entries.length >= 0.6 ? mostCommon.key : null;
  }

  static ({String name, int? csvAmount, int? dashAmount, String? phone})
      _parseEntryContent(String content) {
    if (content.contains(',')) {
      final parts = content.split(',').map((p) => p.trim()).toList();
      final name = parts[0];
      int? amount;
      if (parts.length > 1 && parts[1].isNotEmpty) {
        amount = int.tryParse(parts[1].replaceAll(RegExp(r'[^0-9]'), ''));
      }
      final phone = parts.length > 2 && parts[2].isNotEmpty ? parts[2] : null;
      return (name: name, csvAmount: amount, dashAmount: null, phone: phone);
    }

    // Informal "Name-100" / "Name-" weekly-note style. The trailing number
    // is never treated as a stable expected_amount (that's a per-week
    // actual, not a pledge) -- it's only ever surfaced as a weekly-history
    // entry when a week header is in effect. Only strip when what follows
    // the last "-" is purely digits or empty, so a genuinely hyphenated
    // name (e.g. "Mary-Jane") is left untouched.
    final dashMatch = _trailingDashAmount.firstMatch(content);
    if (dashMatch != null && dashMatch.group(1)!.trim().isNotEmpty) {
      final name = dashMatch.group(1)!.trim();
      final amountText = dashMatch.group(2) ?? '';
      final dashAmount = amountText.isNotEmpty ? int.tryParse(amountText) : null;
      return (name: name, csvAmount: null, dashAmount: dashAmount, phone: null);
    }

    return (name: content, csvAmount: null, dashAmount: null, phone: null);
  }

  static DateTime _parseDdMmYy(String d, String m, String y) {
    var year = int.parse(y);
    if (year < 100) year += 2000;
    return DateTime(year, int.parse(m), int.parse(d));
  }
}
