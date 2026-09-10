/// How a raw SMS was classified by the local M-PESA parser. Everything
/// here happens on-device -- see services/mpesa_sms_parser.dart -- before
/// anything is ever shown to the user or sent anywhere.
enum MpesaSmsKind {
  /// Looks like, and was successfully parsed as, an incoming M-PESA
  /// payment: has a transaction code, sender name, and amount. This is
  /// the only kind that can be imported.
  incomingPayment,

  /// Looks like an incoming-payment M-PESA message (mentions "received"
  /// and a Ksh amount) but one or more required fields could not be
  /// extracted reliably. Shown for transparency, never importable --
  /// the parser never fabricates a missing field.
  unparsed,

  /// Recognizably M-PESA, but not an incoming payment (airtime,
  /// withdrawal, balance check, outgoing payment, promotional, etc).
  /// Excluded from the inbox list entirely.
  excludedOther,

  /// Not an M-PESA message at all.
  notMpesa,
}

/// The result of running one raw SMS through the local M-PESA parser.
/// [rawBody] and [timestamp] are always present (from the SMS itself);
/// everything else is only populated when [kind] is [MpesaSmsKind.incomingPayment]
/// or partially populated for [MpesaSmsKind.unparsed].
class MpesaSmsResult {
  final String id;
  final String rawBody;
  final String? address;
  final DateTime timestamp;
  final MpesaSmsKind kind;
  final String? transactionCode;
  final String? senderName;
  final String? senderPhone;
  final int? amount;

  /// Best-effort extraction of a Paybill "for account `<text>`" clause,
  /// where a payer sometimes types a group/chama name as their account
  /// reference. Null whenever the SMS has no such clause -- never
  /// fabricated, same philosophy as every other field here. Used by the
  /// real-time alert to help identify which collection an SMS is for; it
  /// has no bearing on [isImportable].
  final String? accountReference;

  /// Human-readable reason for [MpesaSmsKind.unparsed] or
  /// [MpesaSmsKind.excludedOther] -- e.g. "Airtime purchase", "Could not
  /// find a transaction code". Null for incomingPayment/notMpesa.
  final String? reason;

  const MpesaSmsResult({
    required this.id,
    required this.rawBody,
    required this.address,
    required this.timestamp,
    required this.kind,
    this.transactionCode,
    this.senderName,
    this.senderPhone,
    this.amount,
    this.accountReference,
    this.reason,
  });

  bool get isImportable =>
      kind == MpesaSmsKind.incomingPayment &&
      transactionCode != null &&
      senderName != null &&
      amount != null;
}
