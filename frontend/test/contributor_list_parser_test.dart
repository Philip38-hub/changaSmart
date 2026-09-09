import 'package:changasmart/services/contributor_list_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('plain lists', () {
    test('one name per line, no numbering', () {
      final result = ContributorListParser.parse('Jane Wanjiku\nPeter Otieno\n\nAnne Otieno');
      expect(result.contributors.map((c) => c.name).toList(), [
        'Jane Wanjiku',
        'Peter Otieno',
        'Anne Otieno',
      ]);
      expect(result.hasWeeklyData, isFalse);
    });

    test('bulleted list', () {
      final result = ContributorListParser.parse('- John\n• Jane\n* Peter');
      expect(result.contributors.map((c) => c.name).toList(), ['John', 'Jane', 'Peter']);
    });

    test('blank and whitespace-only lines are ignored', () {
      final result = ContributorListParser.parse('John\n   \n\nJane\n\t\n');
      expect(result.contributors.map((c) => c.name).toList(), ['John', 'Jane']);
    });

    test('a genuinely hyphenated name survives untouched', () {
      final result = ContributorListParser.parse('Mary-Jane');
      expect(result.contributors.single.name, 'Mary-Jane');
    });

    test('trailing comma is treated as a blank optional column, not an error', () {
      final result = ContributorListParser.parse('John Kamau,');
      expect(result.contributors.single.name, 'John Kamau');
      expect(result.contributors.single.expectedAmount, isNull);
    });
  });

  group('numbered lists', () {
    test('numbered with dot and with paren', () {
      final result = ContributorListParser.parse('1. John Kamau\n2) Jane Wanjiku');
      expect(result.contributors.map((c) => c.name).toList(), ['John Kamau', 'Jane Wanjiku']);
    });

    test('trailing -amount is stripped and not used as expected_amount', () {
      final result = ContributorListParser.parse('1. Apilo-100\n2. Sarcastic-');
      expect(result.contributors[0].name, 'Apilo');
      expect(result.contributors[0].expectedAmount, isNull);
      expect(result.contributors[1].name, 'Sarcastic');
      expect(result.contributors[1].expectedAmount, isNull);
    });

    test('non-numbered noise lines are dropped once numbered mode is active', () {
      final result = ContributorListParser.parse(
        'Pochi 0706452083\n1. Apilo-100\nSome random note\n2. Omosh-100',
      );
      expect(result.contributors.map((c) => c.name).toList(), ['Apilo', 'Omosh']);
    });
  });

  group('csv-style rows', () {
    test('name, amount, phone', () {
      final result = ContributorListParser.parse('Jane Wanjiku,3000,254700000000');
      final row = result.contributors.single;
      expect(row.name, 'Jane Wanjiku');
      expect(row.expectedAmount, 3000);
      expect(row.phone, '254700000000');
    });

    test('name and amount only', () {
      final result = ContributorListParser.parse('Jane Wanjiku,3000');
      expect(result.contributors.single.expectedAmount, 3000);
      expect(result.contributors.single.phone, isNull);
    });

    test('name only, trailing commas empty', () {
      final result = ContributorListParser.parse('Jane Wanjiku,,');
      expect(result.contributors.single.expectedAmount, isNull);
      expect(result.contributors.single.phone, isNull);
    });

    test('non-numeric amount column falls back to null', () {
      final result = ContributorListParser.parse('Jane Wanjiku,tbd');
      expect(result.contributors.single.expectedAmount, isNull);
    });
  });

  group('deduplication within a paste', () {
    test('same name repeated is collapsed to one row, first occurrence kept', () {
      final result = ContributorListParser.parse('Apilo\nOmosh\nApilo\nOmosh');
      expect(result.contributors.map((c) => c.name).toList(), ['Apilo', 'Omosh']);
    });

    test('dedup is case-insensitive', () {
      final result = ContributorListParser.parse('Apilo\napilo\nAPILO');
      expect(result.contributors, hasLength(1));
    });
  });

  group('the real weekly WhatsApp tracker shape', () {
    const list = '''
     Pochi 0706452083

Week 1 17/08/26

1. Apilo-100
2. Omosh-100
3. Sarcastic-
4. Esco-100
5. Mose-100

Weekly total: ksh.400

Week 2 24/08/26
1. Apilo-100
2. Omosh-100
3. Sarcastic-
4. Esco-100
5. Mose-

Weekly total: ksh.300

Week 3 31/08/26
1. Apilo-100
2. Omosh-
3. Sarcastic-
4. Esco-100
5. Mose-

Weekly total: ksh.200

Week 4 7/09/26
1. Apilo-100
2. Omosh-
3. Sarcastic-
4. Esco-
5. Mose-
Weekly total: ksh.100

Total: ksh.1000
''';

    test('extracts exactly the five names, deduped, with no expected amount', () {
      final result = ContributorListParser.parse(list);
      expect(
        result.contributors.map((c) => c.name).toList(),
        ['Apilo', 'Omosh', 'Sarcastic', 'Esco', 'Mose'],
      );
      expect(result.contributors.every((c) => c.expectedAmount == null), isTrue);
    });

    test('drops all header/date/total noise lines', () {
      final result = ContributorListParser.parse(list);
      final names = result.contributors.map((c) => c.name).toSet();
      expect(names, isNot(contains('Pochi 0706452083')));
      expect(names, isNot(contains(matches(RegExp(r'Week \d')))));
      expect(names, isNot(contains(matches(RegExp(r'total', caseSensitive: false)))));
    });

    test('extracts per-week historical amounts, skipping blanks', () {
      final result = ContributorListParser.parse(list);
      expect(result.hasWeeklyData, isTrue);

      int? amountFor(String name, DateTime week) {
        final match = result.weeklyEntries.where(
          (e) => e.name == name && e.weekStart == week,
        );
        return match.isEmpty ? null : match.single.amount;
      }

      final week1 = DateTime(2026, 8, 17);
      final week2 = DateTime(2026, 8, 24);
      final week3 = DateTime(2026, 8, 31);
      final week4 = DateTime(2026, 9, 7);

      expect(amountFor('Apilo', week1), 100);
      expect(amountFor('Apilo', week2), 100);
      expect(amountFor('Apilo', week3), 100);
      expect(amountFor('Apilo', week4), 100);

      expect(amountFor('Sarcastic', week1), isNull);
      expect(amountFor('Sarcastic', week2), isNull);
      expect(amountFor('Sarcastic', week3), isNull);
      expect(amountFor('Sarcastic', week4), isNull);

      expect(amountFor('Mose', week1), 100);
      expect(amountFor('Mose', week2), isNull);
      expect(amountFor('Mose', week3), isNull);
      expect(amountFor('Mose', week4), isNull);
    });

    test('weekly totals reconstructed from entries match the original list', () {
      final result = ContributorListParser.parse(list);
      final totalsByWeek = <DateTime, int>{};
      for (final entry in result.weeklyEntries) {
        totalsByWeek.update(
          entry.weekStart,
          (v) => v + entry.amount,
          ifAbsent: () => entry.amount,
        );
      }
      final sortedWeeks = totalsByWeek.keys.toList()..sort();
      expect(sortedWeeks.map((w) => totalsByWeek[w]).toList(), [400, 300, 200, 100]);
    });
  });
}
