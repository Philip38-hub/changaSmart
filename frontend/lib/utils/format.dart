import 'package:intl/intl.dart';

final NumberFormat _kshNumberFormat = NumberFormat.decimalPattern('en_US');

/// Formats a whole-shilling integer amount as "KSh 5,000" -- never
/// "5000.0" or a bare number. Amounts in this app are always whole
/// shillings (see backend/app/models.py: amounts are `int`).
String formatKsh(int amount) => 'KSh ${_kshNumberFormat.format(amount)}';

/// Same as [formatKsh] but returns null for a null amount, so callers can
/// decide how to render "no target set" without repeating the null check.
String? formatKshOrNull(int? amount) => amount == null ? null : formatKsh(amount);

String formatPercent(double ratio) => '${(ratio * 100).toStringAsFixed(1)}%';

final DateFormat _dateTimeFormat = DateFormat('d MMM yyyy, h:mm a');
final DateFormat _dateFormat = DateFormat('d MMM yyyy');

String formatDateTime(DateTime dt) => _dateTimeFormat.format(dt.toLocal());
String formatDate(DateTime dt) => _dateFormat.format(dt.toLocal());
