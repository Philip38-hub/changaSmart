import '../models/mpesa_sms.dart';

/// Local, on-device M-PESA SMS detector/parser. Pure Dart, no platform
/// dependency -- takes an already-read SMS (body/address/timestamp) and
/// classifies it, extracting a transaction candidate when possible.
///
/// This is the ONLY place SMS content is interpreted. It never invents a
/// field it couldn't find, and it is never given the whole SMS inbox to
/// forward anywhere -- callers decide, per message, what (if anything)
/// crosses into a TransactionCandidate sent to the backend.
class MpesaSmsParser {
  // Amount: "Ksh", "Ksh.", "KSh", "KES" (any case), optional space/dot,
  // digits with optional thousands separators and optional cents.
  static final RegExp _amountWithValuePattern = RegExp(
    r'(?:ksh\.?|kes)\s*([0-9]{1,3}(?:,[0-9]{3})*(?:\.[0-9]{1,2})?|[0-9]+(?:\.[0-9]{1,2})?)',
    caseSensitive: false,
  );

  // "from JOHN KAMAU", "from MARY WAMBUI KAMAU 254712345678" -- stops
  // naturally at the first token that doesn't start with an uppercase
  // letter (a phone number, "on", punctuation, ...).
  static final RegExp _senderPattern = RegExp(
    r"from\s+([A-Z][A-Za-z'\-]*(?:\s+[A-Z][A-Za-z'\-]*){0,4})",
  );

  // A Kenyan phone number as it appears in M-PESA SMS: 9-12 digits,
  // optionally starting with 0 or 254.
  static final RegExp _phonePattern = RegExp(r'\b(0|254)\d{8,9}\b');

  static const _incomingKeywords = ['received'];

  static const _exclusionKeywordReasons = <String, String>{
    'withdraw': 'Withdrawal, not an incoming payment',
    'you have sent': 'Outgoing payment (sent), not an incoming payment',
    'paid to': 'Outgoing payment (paid to a till/merchant)',
    'airtime': 'Airtime purchase',
    'bundles': 'Bundle purchase',
    'buy goods': 'Outgoing payment (buy goods)',
    'agent': 'Agent transaction',
    'reversed': 'Reversal notice',
    'fuliza': 'Fuliza / loan message',
    'loan': 'Loan message',
    'balance was': 'Balance enquiry',
    'you can now': 'Promotional message',
    'offer': 'Promotional message',
    'congratulations': 'Promotional message',
    'bonus': 'Promotional message',
  };

  /// Classifies one already-read SMS. [id] is an opaque, caller-supplied
  /// identifier (e.g. the platform SMS row id) carried through unchanged.
  static MpesaSmsResult classify({
    required String id,
    required String body,
    required String? address,
    required DateTime timestamp,
  }) {
    final normalizedAddress = (address ?? '').toLowerCase();
    final lowerBody = body.toLowerCase();

    final looksLikeMpesa =
        normalizedAddress.contains('mpesa') || lowerBody.contains('m-pesa') || lowerBody.contains('mpesa');

    if (!looksLikeMpesa) {
      return MpesaSmsResult(
        id: id,
        rawBody: body,
        address: address,
        timestamp: timestamp,
        kind: MpesaSmsKind.notMpesa,
      );
    }

    // "received" alone is enough to route this into the incoming-payment
    // path (amount pattern is deliberately NOT required here): if an
    // amount can't be found either, that's a missing field the
    // "unparsed" branch below surfaces for human review -- not a reason
    // to silently drop a message that might still be a real receipt.
    final isIncomingShaped = _incomingKeywords.any(lowerBody.contains);

    if (!isIncomingShaped) {
      final reason = _exclusionKeywordReasons.entries
          .firstWhere(
            (e) => lowerBody.contains(e.key),
            orElse: () => const MapEntry('', 'Not an incoming payment message'),
          )
          .value;
      return MpesaSmsResult(
        id: id,
        rawBody: body,
        address: address,
        timestamp: timestamp,
        kind: MpesaSmsKind.excludedOther,
        reason: reason,
      );
    }

    final amount = _extractAmount(body);
    final senderName = _extractSenderName(body);
    final senderPhone = _extractSenderPhone(body);
    final transactionCode = _extractTransactionCode(body);

    if (amount != null && senderName != null && transactionCode != null) {
      return MpesaSmsResult(
        id: id,
        rawBody: body,
        address: address,
        timestamp: timestamp,
        kind: MpesaSmsKind.incomingPayment,
        transactionCode: transactionCode,
        senderName: senderName,
        senderPhone: senderPhone,
        amount: amount,
      );
    }

    final missing = <String>[
      if (transactionCode == null) 'transaction code',
      if (senderName == null) 'sender name',
      if (amount == null) 'amount',
    ].join(', ');

    return MpesaSmsResult(
      id: id,
      rawBody: body,
      address: address,
      timestamp: timestamp,
      kind: MpesaSmsKind.unparsed,
      transactionCode: transactionCode,
      senderName: senderName,
      senderPhone: senderPhone,
      amount: amount,
      reason: 'Could not reliably extract: $missing',
    );
  }

  static int? _extractAmount(String body) {
    final match = _amountWithValuePattern.firstMatch(body);
    if (match == null) return null;
    final raw = match.group(1)?.replaceAll(',', '');
    if (raw == null) return null;
    final value = double.tryParse(raw);
    if (value == null || value <= 0) return null;
    return value.round();
  }

  static String? _extractSenderName(String body) {
    final match = _senderPattern.firstMatch(body);
    final name = match?.group(1)?.trim();
    if (name == null || name.isEmpty) return null;
    return name;
  }

  static String? _extractSenderPhone(String body) {
    final match = _phonePattern.firstMatch(body);
    return match?.group(0);
  }

  static String? _extractTransactionCode(String body) {
    final tokens = body.trim().split(RegExp(r'\s+'));
    // M-PESA transaction codes are always shown in caps, mix letters and
    // digits, and are 8-12 characters with no attached punctuation --
    // this rules out ordinary capitalized words and stray "Confirmed."
    // style tokens.
    bool looksLikeCode(String token) {
      if (token.length < 8 || token.length > 12) return false;
      if (token != token.toUpperCase()) return false;
      if (!RegExp(r'^[A-Z0-9]+$').hasMatch(token)) return false;
      final hasDigit = RegExp(r'[0-9]').hasMatch(token);
      final hasLetter = RegExp(r'[A-Z]').hasMatch(token);
      return hasDigit && hasLetter;
    }

    if (tokens.isNotEmpty && looksLikeCode(tokens.first)) {
      return tokens.first;
    }
    for (final token in tokens) {
      if (looksLikeCode(token)) return token;
    }
    return null;
  }
}
