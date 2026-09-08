import 'package:flutter/services.dart';
import '../../../core/network/api_client.dart';

/// Android notification-listener bridge. No-ops on tests / iOS.
class BankCapture {
  static const channel = MethodChannel('com.filla.wealthtrack/bank_capture');

  static Future<bool> isEnabled() async {
    try {
      return await channel.invokeMethod<bool>('isEnabled') ?? false;
    } on MissingPluginException {
      return true;
    } on PlatformException {
      return false;
    }
  }

  static Future<void> openSettings() async {
    try {
      await channel.invokeMethod('openSettings');
    } on MissingPluginException {
      return;
    } on PlatformException {
      return;
    }
  }

  static Future<List<Map<String, dynamic>>> drain() async {
    try {
      final raw = await channel.invokeMethod('drain');
      if (raw is! List) return [];
      return raw
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    } on MissingPluginException {
      return [];
    } on PlatformException {
      return [];
    }
  }

  static Future<void> flushToServer(ApiClient api) async {
    final items = await drain();
    for (final item in items) {
      try {
        await api.post('/bank-inbox', data: {
          'package': item['package'] ?? '',
          'title': item['title'] ?? '',
          'text': item['text'] ?? '',
          'posted_at': item['posted_at'] ?? '',
        });
      } catch (_) {
        // Keep going; leftover queue items are gone after drain.
      }
    }
  }
}
