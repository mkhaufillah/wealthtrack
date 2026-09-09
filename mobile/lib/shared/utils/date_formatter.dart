import '../../core/ui/copy_fallback.dart';

const monthShortId = [
  'Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun',
  'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des'
];

const monthShortEn = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
];

const weekdayShortId = ['Sen', 'Sel', 'Rab', 'Kam', 'Jum', 'Sab', 'Min'];
const weekdayShortEn = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

/// Alias kept so older call sites compile. Prefer [localizedMonthShort].
const idMonthShort = monthShortId;

List<String> get localizedMonthShort =>
    activeUiLocale.startsWith('en') ? monthShortEn : monthShortId;

List<String> get localizedWeekdayShort =>
    activeUiLocale.startsWith('en') ? weekdayShortEn : weekdayShortId;

String _monthName(DateTime d) => localizedMonthShort[d.month - 1];

/// dd MMM yyyy → 07 Sep 2026
String formatDate(String isoDate) {
  final date = DateTime.tryParse(isoDate);
  if (date == null) return isoDate;
  return '${date.day} ${_monthName(date)} ${date.year}';
}

String formatDateRelative(String isoDate) {
  final date = DateTime.tryParse(isoDate);
  if (date == null) return isoDate;

  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final target = DateTime(date.year, date.month, date.day);
  final diff = today.difference(target).inDays;

  if (diff == 0) return t('date.today');
  if (diff == 1) return t('date.yesterday');
  if (diff < 7) return t('date.days_ago').replaceAll('{n}', '$diff');
  return '${date.day} ${_monthName(date)}';
}

String formatMonthYear(DateTime d) => '${_monthName(d)} ${d.year}';

String formatDayMonth(DateTime d) => '${d.day} ${_monthName(d)}';

String formatWeekday(DateTime d) => localizedWeekdayShort[d.weekday - 1];

/// Mirror of backend's get_cycle_range_for_month.
/// Returns (startDate, endDate) for a budget month label + cycle day.
(DateTime, DateTime) getCycleRangeForMonth(String month, int cycleOn) {
  final parts = month.split('-');
  final year = int.parse(parts[0]);
  final mon = int.parse(parts[1]);

  if (cycleOn == 1) {
    final start = DateTime(year, mon, 1);
    final end = DateTime(year, mon + 1, 0);
    return (start, end);
  }

  // Mirror backend: cycle starts at cycleOn of PREVIOUS month,
  // ends at cycleOn of CURRENT month - 1
  final prevYear = mon == 1 ? year - 1 : year;
  final prevMon = mon == 1 ? 12 : mon - 1;
  final startDay = cycleOn.clamp(1, DateTime(prevYear, prevMon + 1, 0).day);
  final start = DateTime(prevYear, prevMon, startDay);

  final currEndDayCap = DateTime(year, mon + 1, 0).day;
  final endDay = cycleOn > currEndDayCap ? currEndDayCap : cycleOn;
  final end = DateTime(year, mon, endDay).subtract(const Duration(days: 1));

  return (start, end);
}
