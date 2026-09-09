import 'package:changasmart/models/mpesa_sms.dart';
import 'package:changasmart/services/mpesa_sms_parser.dart';
import 'package:flutter_test/flutter_test.dart';

MpesaSmsResult _classify(String body, {String? address, DateTime? timestamp}) {
  return MpesaSmsParser.classify(
    id: 'test-id',
    body: body,
    address: address ?? 'MPESA',
    timestamp: timestamp ?? DateTime(2026, 9, 4, 20, 42),
  );
}

void main() {
  group('incoming payment -- exact match', () {
    test('classic "You have received" template', () {
      final r = _classify(
        'QKJ7ABC123 Confirmed. You have received Ksh3,000.00 from JOHN KAMAU '
        '254712345678 on 4/9/26 at 8:42 PM. New M-PESA balance is Ksh15,230.00.',
      );
      expect(r.kind, MpesaSmsKind.incomingPayment);
      expect(r.amount, 3000);
      expect(r.senderName, 'JOHN KAMAU');
      expect(r.transactionCode, 'QKJ7ABC123');
      expect(r.senderPhone, '254712345678');
      expect(r.isImportable, isTrue);
    });

    test('"A payment of ... has been received" template', () {
      final r = _classify(
        'QEI2AB3XYZ Confirmed. A payment of Ksh3,000 has been received from '
        'JOHN KAMAU 254712345678 on 4/9/26 at 2:15 PM. New M-PESA balance is '
        'Ksh10,300.00.',
      );
      expect(r.kind, MpesaSmsKind.incomingPayment);
      expect(r.amount, 3000);
      expect(r.senderName, 'JOHN KAMAU');
    });
  });

  group('amount formatting variations', () {
    test('comma-separated amount', () {
      final r = _classify(
        'QAX1AAA111 Confirmed. You have received Ksh 10,000 from JANE '
        'WANJIKU 254711000002 on 4/9/26 at 9:00 AM.',
      );
      expect(r.amount, 10000);
    });

    test('amount with decimals', () {
      final r = _classify(
        'QAX1BBB222 Confirmed. You have received Ksh5,250.50 from PETER '
        'OTIENO on 4/9/26 at 9:05 AM.',
      );
      expect(r.amount, 5251); // rounds to nearest whole shilling
    });

    test('"KSh." with a period', () {
      final r = _classify(
        'QAX1CCC333 Confirmed. You have received KSh. 2,000 from MARY '
        'AKINYI on 4/9/26 at 9:10 AM.',
      );
      expect(r.amount, 2000);
    });

    test('KES prefix', () {
      final r = _classify(
        'QAX1DDD444 Confirmed. You have received KES 4,500 from DAVID '
        'MWANGI on 4/9/26 at 9:15 AM.',
      );
      expect(r.amount, 4500);
    });

    test('lowercase ksh', () {
      final r = _classify(
        'QAX1EEE555 Confirmed. you have received ksh1,200 from ANNE '
        'OTIENO on 4/9/26 at 9:20 AM.',
      );
      expect(r.amount, 1200);
    });
  });

  group('multi-word sender names', () {
    test('three-word name preserved in full', () {
      final r = _classify(
        'QAX1FFF666 Confirmed. You have received Ksh1,000 from MARY WAMBUI '
        'KAMAU 254722000000 on 4/9/26 at 10:00 AM.',
      );
      expect(r.senderName, 'MARY WAMBUI KAMAU');
    });
  });

  group('duplicate transaction codes', () {
    test('same code parses identically both times (dedup happens at import time)', () {
      const body = 'QAX1GGG777 Confirmed. You have received Ksh500 from '
          'PETER OTIENO on 4/9/26 at 11:00 AM.';
      final first = _classify(body);
      final second = _classify(body);
      expect(first.transactionCode, second.transactionCode);
      expect(first.transactionCode, 'QAX1GGG777');
    });
  });

  group('non-M-PESA / excluded messages are never treated as incoming payments', () {
    test('promotional message', () {
      final r = _classify(
        'Dear customer, congratulations! You have been selected for a '
        'special Fuliza offer. Reply YES to activate.',
        address: 'MPESA',
      );
      expect(r.kind, isNot(MpesaSmsKind.incomingPayment));
    });

    test('airtime purchase', () {
      final r = _classify(
        'QAX1HHH888 Confirmed. You bought Ksh100.00 of airtime on 4/9/26 '
        'at 11:30 AM.',
      );
      expect(r.kind, isNot(MpesaSmsKind.incomingPayment));
    });

    test('withdrawal', () {
      final r = _classify(
        'QAX1III999 Confirmed. You have withdrawn Ksh2,000.00 from '
        'agent 123456 on 4/9/26 at 11:45 AM.',
      );
      expect(r.kind, isNot(MpesaSmsKind.incomingPayment));
    });

    test('outgoing payment (sent to someone)', () {
      final r = _classify(
        'QAX1JJJ000 Confirmed. Ksh500.00 sent to JANE DOE 254700000000 on '
        '4/9/26 at 12:00 PM.',
      );
      expect(r.kind, isNot(MpesaSmsKind.incomingPayment));
    });

    test('balance enquiry', () {
      final r = _classify('Your M-PESA balance was Ksh1,000.00 on 4/9/26.');
      expect(r.kind, isNot(MpesaSmsKind.incomingPayment));
    });

    test('completely unrelated SMS is not M-PESA at all', () {
      final r = _classify(
        'Your OTP is 123456. Do not share this code with anyone.',
        address: '+254700000000',
      );
      expect(r.kind, MpesaSmsKind.notMpesa);
    });
  });

  group('malformed SMS -- never fabricate data', () {
    test('mentions received/Ksh but no discernible sender is left unparsed, not fabricated', () {
      final r = _classify('Confirmed. You have received Ksh3,000 today.');
      expect(r.kind, MpesaSmsKind.unparsed);
      expect(r.senderName, isNull);
      expect(r.amount, 3000);
      expect(r.isImportable, isFalse);
    });

    test('mentions received but no amount is left unparsed, not fabricated', () {
      final r = _classify('Confirmed. You have received money from JOHN KAMAU.');
      expect(r.kind, MpesaSmsKind.unparsed);
      expect(r.amount, isNull);
      expect(r.isImportable, isFalse);
    });

    test('empty-ish garbage M-PESA-flagged text does not crash and is not importable', () {
      final r = _classify('M-PESA received', address: 'MPESA');
      expect(r.isImportable, isFalse);
    });
  });

  group('real-world messages found via phone testing', () {
    test('lowercase sender name with a partially masked phone number is still parsed', () {
      final r = _classify(
        'UI8J065WQX Confirmed.You have received Ksh100.00 from perister  '
        'mokua 0745***915 on 8/9/26 at 9:00 AM  New M-PESA balance is '
        'Ksh100.00. Invest & earn daily interest with ZIIDI on https://saf.cx/cF6ir',
      );
      expect(r.kind, MpesaSmsKind.incomingPayment);
      expect(r.amount, 100);
      expect(r.senderName, 'perister  mokua');
      expect(r.transactionCode, 'UI8J065WQX');
      expect(r.isImportable, isTrue);
    });

    test('a plain (non-comma-separated) 4-digit amount is not truncated', () {
      final r = _classify(
        'QAX1LLL222 Confirmed. You have received Ksh3550 from JOHN KAMAU '
        'on 4/9/26 at 9:00 AM.',
      );
      expect(r.amount, 3550);
    });

    test('a plain 5-digit amount with KES prefix is not truncated', () {
      final r = _classify(
        'QAX1MMM333 Confirmed. You have received KES 12000 from JOHN KAMAU '
        'on 4/9/26 at 9:00 AM.',
      );
      expect(r.amount, 12000);
    });
  });

  group('sender vs. eventual credited contributor', () {
    test('parser only ever reports the literal SMS sender, never a contributor name', () {
      // The parser has no concept of "expected contributors" at all --
      // this test documents that invariant: whatever name appears after
      // "from" is reported verbatim, independent of any reconciliation
      // concern that happens later in the pipeline.
      final r = _classify(
        'QAX1KKK111 Confirmed. You have received Ksh3,000 from ANNE '
        'OTIENO 254733000000 on 4/9/26 at 1:00 PM.',
      );
      expect(r.senderName, 'ANNE OTIENO');
      expect(r.senderName, isNot('JANE WANJIKU'));
    });
  });
}
