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
(String, String) getCycleRangeForMonth(String month, int cycleOn) {
  final parts = month.split('-');
  final year = int.parse(parts[0]);
  final mon = int.parse(parts[1]);

  if (cycleOn == 1) {
    final start = DateTime(year, mon, 1);
    final end = DateTime(year, mon + 1, 0);
    return (DateFormat('dd MMM').format(start), DateFormat('dd MMM').format(end));
  }

  // Cycle starts at cycleOn of previous month
  final prevYear = mon == 1 ? year - 1 : year;
  final prevMon = mon == 1 ? 12 : mon - 1;
  final startDay = cycleOn.clamp(1, DateTime(prevYear, prevMon + 1, 0).day);
  final start = DateTime(prevYear, prevMon, startDay);

  final endDayCap = DateTime(year, mon + 1, 0).day;
  final endDay = cycleOn > endDayCap ? endDayCap : cycleOn;
  final end = DateTime(year, mon, endDay).subtract(const Duration(days: 1));

  return (DateFormat('dd MMM').format(start), DateFormat('dd MMM').format(end));
}
