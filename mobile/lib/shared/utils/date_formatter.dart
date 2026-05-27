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
