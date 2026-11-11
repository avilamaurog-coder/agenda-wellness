import 'package:intl/intl.dart';

abstract final class Fmt {
  static final _money = NumberFormat.currency(locale: 'es_AR', symbol: r'$', decimalDigits: 0);
  static final _compactMoney = NumberFormat.compactCurrency(locale: 'es_AR', symbol: r'$');
  static final _date = DateFormat('dd/MM/yyyy', 'es_AR');
  static final _shortDate = DateFormat('EEE d MMM', 'es_AR');
  static final _longDate = DateFormat("EEEE d 'de' MMMM", 'es_AR');
  static final _time = DateFormat('HH:mm', 'es_AR');
  static final _monthYear = DateFormat('MMMM yyyy', 'es_AR');

  static String money(num? v) => _money.format(v ?? 0);
  static String compactMoney(num? v) => _compactMoney.format(v ?? 0);
  static String date(DateTime d) => _date.format(d.toLocal());
  static String shortDate(DateTime d) => _capitalize(_shortDate.format(d.toLocal()));
  static String longDate(DateTime d) => _capitalize(_longDate.format(d.toLocal()));
  static String time(DateTime d) => _time.format(d.toLocal());
  static String monthYear(DateTime d) => _capitalize(_monthYear.format(d.toLocal()));
  static String timeRange(DateTime a, DateTime b) => '${time(a)} – ${time(b)}';

  static String duration(int minutes) {
    if (minutes < 60) return '$minutes min';
    final h = minutes ~/ 60, m = minutes % 60;
    return m == 0 ? '$h h' : '$h h $m min';
  }

  static String initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    return (parts.first[0] + (parts.length > 1 ? parts.last[0] : '')).toUpperCase();
  }

  static String _capitalize(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}

extension DateTimeX on DateTime {
  DateTime get dateOnly => DateTime(year, month, day);
  bool isSameDay(DateTime o) => year == o.year && month == o.month && day == o.day;
  DateTime get startOfWeek => dateOnly.subtract(Duration(days: weekday - 1));
}
