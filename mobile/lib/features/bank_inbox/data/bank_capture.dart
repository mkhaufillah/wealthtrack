import 'package:flutter/services.dart';
import '../../../core/constants.dart';
import '../../../core/network/api_client.dart';
import '../../../core/storage/secure_storage.dart';
import '../../../core/vault/vault_store.dart';

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
      return raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
    } on MissingPluginException {
      return [];
    } on PlatformException {
      return [];
    }
  }

  static Future<List<Map<String, dynamic>>> listApps() async {
    try {
      final raw = await channel.invokeMethod('listApps');
      if (raw is! List) return [];
      return raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
    } on MissingPluginException {
      return [];
    } on PlatformException {
      return [];
    }
  }

  static Future<List<String>> getListenPackages() async {
    try {
      final raw = await channel.invokeMethod('getListenPackages');
      if (raw is! List) return [];
      return raw.map((e) => e.toString()).toList();
    } on MissingPluginException {
      return [];
    } on PlatformException {
      return [];
    }
  }

  static Future<void> syncSession(
    ApiClient api,
    String? token, {
    SecureStorage? storage,
  }) async {
    if (token == null || token.isEmpty) {
      try {
        await channel.invokeMethod('clearSession');
      } on MissingPluginException {
        return;
      } on PlatformException {
        return;
      }
      return;
    }
    int lainnya = 0;
    try {
      final res = await api.get('/categories');
      for (final c in (res.data as List).whereType<Map>()) {
        if (c['name'].toString().toLowerCase() != 'lainnya') continue;
        lainnya = (c['id'] as num?)?.toInt() ?? 0;
        if (c['type'] == 'expense') break;
      }
    } catch (_) {}
    try {
      String vaultKey = '';
      if (storage != null) {
        vaultKey = await VaultStore.getDekB64(storage) ?? '';
      }
      await channel.invokeMethod('setSession', {
        'base': AppConstants.apiBaseUrl,
        'token': token,
        'lainnya_id': lainnya,
        'vault_key': vaultKey,
      });
    } on MissingPluginException {
      return;
    } on PlatformException {
      return;
    }
  }

  static Future<void> requestNotify() async {
    try {
      await channel.invokeMethod('requestNotify');
    } on MissingPluginException {
      return;
    } on PlatformException {
      return;
    }
  }

  static const packageSlugs = <String, String>{
    'com.bca': 'bca',
    'id.bmri.livin': 'mandiri',
    'id.co.bri.brimo': 'bri',
    'com.jago.digitalBanking': 'jago',
    'id.co.bankfama.android': 'superbank',
    'com.krom.android': 'krom',
    'id.co.btn.mobilebanking.android': 'btn',
    'id.co.bankbkemobile.digitalbank': 'seabank',
    'com.bibit.bibitid': 'bibit',
    'com.stockbit.android': 'stockbit',
    'com.telkom.mwallet': 'linkaja',
    'id.flip': 'flip',
    'ovo.id': 'ovo',
    'com.gojek.gopay': 'gopay',
    'id.dana': 'dana',
    'com.shopeepay.id': 'shopeepay',
  };

  static bool hasAmount(String blob) => parseAmount(blob) != null;

  /// Keep in sync with `bank_parser.parse_amount` and Kotlin `AmountDetect`.
  static int? parseAmount(String blob) {
    const patterns = [
      r'(?:rp\.?|idr|rupiah|usd|us\$|\$)\s*([0-9][0-9.\s,]*)',
      r'([0-9][0-9.\s,]*)\s*(?:rp\.?|idr|rupiah|usd|us\$|\$)',
      r'(?:debit|kredit|nominal|sebesar|amount|paid|received|transfer|qris|bayar|pembelian|pembayaran)\s*:?\s*([0-9][0-9.\s,]*)',
      r'(?<![0-9.])([1-9][0-9]{0,2}(?:[.,\s][0-9]{3}){1,4})(?![0-9])',
    ];
    for (final p in patterns) {
      for (final m in RegExp(p, caseSensitive: false).allMatches(blob)) {
        if (m.end < blob.length && blob[m.end] == '%') continue;
        final v = _normalizeNumber(m.group(1) ?? '');
        if (v != null) return v;
      }
    }
    return null;
  }

  static int? _normalizeNumber(String raw) {
    var s = raw.replaceAll('\u00a0', ' ').trim();
    s = s.replaceFirst(RegExp(r',-+$'), '');
    s = s.replaceAll(' ', '');
    if (s.isEmpty || !RegExp(r'\d').hasMatch(s)) return null;
    if (s.startsWith('0')) return null;
    if (s.contains(',') && s.contains('.')) {
      s = s.lastIndexOf(',') > s.lastIndexOf('.')
          ? s.split(',').first.replaceAll('.', '')
          : s.split('.').first.replaceAll(',', '');
    } else if (s.contains(',')) {
      final parts = s.split(',');
      s = (parts.length == 2 && parts[1].length >= 1 && parts[1].length <= 2)
          ? parts[0]
          : s.replaceAll(',', '');
    } else if (s.contains('.')) {
      final parts = s.split('.');
      s = (parts.length == 2 && parts[1].length >= 1 && parts[1].length <= 2)
          ? parts[0]
          : s.replaceAll('.', '');
    }
    final value = int.tryParse(s);
    if (value == null || value <= 0 || value > 10000000000) return null;
    return value;
  }

  static String slugForPackage(String pkg) {
    final known = packageSlugs[pkg];
    if (known != null) return known;
    final last = pkg.split('.').last.replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '').toLowerCase();
    return last.isEmpty ? 'other' : last;
  }

  static Future<void> setListenPackages(List<String> packages) async {
    try {
      await channel.invokeMethod('setListenPackages', packages);
    } on MissingPluginException {
      return;
    } on PlatformException {
      return;
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
      } catch (_) {}
    }
  }

  static Future<void> applyPendingAction(ApiClient api) async {
    await flushToServer(api);
    Map<String, dynamic>? pending;
    try {
      final raw = await channel.invokeMethod('takePendingAction');
      if (raw is Map) pending = Map<String, dynamic>.from(raw);
    } on MissingPluginException {
      return;
    } on PlatformException {
      return;
    }
    if (pending == null) return;
    final action = pending['action']?.toString();
    if (action == null || action.isEmpty) return;
    try {
      final res = await api.get('/bank-inbox');
      final items = ((res.data as Map)['items'] as List? ?? [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .where((e) => e['status'] == 'pending')
          .toList();
      if (items.isEmpty) return;
      final pkg = pending['package']?.toString();
      final match = items.firstWhere(
        (e) => pkg == null || pkg.isEmpty || e['package'] == pkg,
        orElse: () => items.first,
      );
      final id = match['id'];
      if (action == 'confirm') {
        await api.post('/bank-inbox/$id/confirm', data: {});
      } else if (action == 'reject') {
        await api.post('/bank-inbox/$id/reject', data: {});
      } else if (action == 'delete') {
        await api.delete('/bank-inbox/$id');
      }
    } catch (_) {}
  }
}
