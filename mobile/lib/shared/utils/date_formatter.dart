import 'package:intl/intl.dart';

String formatDate(String isoDate) {
  final date = DateTime.tryParse(isoDate);
  if (date == null) return isoDate;
  return DateFormat('MMM dd, yyyy').format(date);
}

String formatDateRelative(String isoDate) {
  final date = DateTime.tryParse(isoDate);
  if (date == null) return isoDate;

  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final target = DateTime(date.year, date.month, date.day);
  final diff = today.difference(target).inDays;

  if (diff == 0) return 'Today';
  if (diff == 1) return 'Yesterday';
  if (diff < 7) return '$diff days ago';
  return DateFormat('MMM dd').format(date);
}

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

  // Cycle starts at cycleOn of THIS month
  final startDay = cycleOn.clamp(1, DateTime(year, mon + 1, 0).day);
  final start = DateTime(year, mon, startDay);

  // ends at cycleOn of NEXT month - 1
  final nextYear = mon == 12 ? year + 1 : year;
  final nextMon = mon == 12 ? 1 : mon + 1;
  final endDayCap = DateTime(nextYear, nextMon + 1, 0).day;
  final endDay = cycleOn > endDayCap ? endDayCap : cycleOn;
  final end = DateTime(nextYear, nextMon, endDay).subtract(const Duration(days: 1));

  return (start, end);
}
