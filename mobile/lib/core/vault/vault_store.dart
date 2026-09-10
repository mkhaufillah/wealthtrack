import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import '../storage/secure_storage.dart';

const kVaultDekKey = 'vault_dek_v1';
const kdfParams = 'argon2id:m=65536,t=3,p=1';

class VaultWrap {
  final String wrapped;
  final String salt;
  VaultWrap(this.wrapped, this.salt);
}

class VaultStore {
  static String? _mem;
  static const _argon = Argon2id(
    parallelism: 1,
    memory: 65536,
    iterations: 3,
    hashLength: 32,
  );
  static final _aes = AesGcm.with256bits();

  static Future<String?> getDekB64(SecureStorage storage) async {
    if (_mem != null && _mem!.isNotEmpty) return _mem;
    final v = await storage.getSecure(kVaultDekKey);
    if (v != null && v.isNotEmpty) _mem = v;
    return _mem;
  }

  static Future<void> saveDekB64(SecureStorage storage, String b64) async {
    await storage.saveSecure(kVaultDekKey, b64);
    _mem = b64;
  }

  static Future<String> newDekB64() async {
    final rng = Random.secure();
    return base64Encode(List<int>.generate(32, (_) => rng.nextInt(256)));
  }

  static Uint8List randomSalt() {
    final rng = Random.secure();
    return Uint8List.fromList(List<int>.generate(16, (_) => rng.nextInt(256)));
  }

  static Future<List<int>> _kek(String password, List<int> salt) async {
    final key = await _argon.deriveKey(
      secretKey: SecretKey(utf8.encode(password)),
      nonce: salt,
    );
    return key.extractBytes();
  }

  static Future<VaultWrap> wrapDek(String password, String dekB64) async {
    final salt = randomSalt();
    final kek = SecretKey(await _kek(password, salt));
    final nonce = _aes.newNonce();
    final box = await _aes.encrypt(
      base64Decode(dekB64),
      secretKey: kek,
      nonce: nonce,
    );
    final wrapped = base64Encode(<int>[
      ...nonce,
      ...box.cipherText,
      ...box.mac.bytes,
    ]);
    return VaultWrap(wrapped, base64Encode(salt));
  }

  static Future<String> unwrapDek({
    required String password,
    required String wrappedDek,
    required String saltB64,
  }) async {
    final salt = base64Decode(saltB64);
    final raw = base64Decode(wrappedDek);
    if (raw.length < 12 + 16) {
      throw StateError('wrap corrupt');
    }
    final nonce = raw.sublist(0, 12);
    final mac = raw.sublist(raw.length - 16);
    final ct = raw.sublist(12, raw.length - 16);
    final kek = SecretKey(await _kek(password, salt));
    final clear = await _aes.decrypt(
      SecretBox(ct, nonce: nonce, mac: Mac(mac)),
      secretKey: kek,
    );
    return base64Encode(clear);
  }

  static Future<void> clear() async {
    _mem = null;
  }
}
