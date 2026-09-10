import 'dart:convert';
import 'dart:math';
import '../storage/secure_storage.dart';

const kVaultDekKey = 'vault_dek_v1';

class VaultStore {
  static String? _mem;

  static Future<String?> getDekB64(SecureStorage storage) async {
    if (_mem != null && _mem!.isNotEmpty) return _mem;
    final v = await storage.getSecure(kVaultDekKey);
    if (v != null && v.isNotEmpty) _mem = v;
    return _mem;
  }

  static Future<String> ensureDek(SecureStorage storage) async {
    final existing = await getDekB64(storage);
    if (existing != null && existing.isNotEmpty) return existing;
    final rng = Random.secure();
    final bytes = List<int>.generate(32, (_) => rng.nextInt(256));
    final b64 = base64Encode(bytes);
    await storage.saveSecure(kVaultDekKey, b64);
    _mem = b64;
    return b64;
  }

  static Future<void> clear() async {
    _mem = null;
  }
}
