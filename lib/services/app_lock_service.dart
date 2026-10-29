import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppLockConfig {
  const AppLockConfig({
    required this.enabled,
    required this.type,
    this.secretHash,
  });

  final bool enabled;
  final String type;
  final String? secretHash;
}

class AppLockService {
  static const String typeNone = 'none';
  static const String typePin = 'pin';
  static const String typePattern = 'pattern';

  static const _enabledKey = 'app_lock_enabled';
  static const _typeKey = 'app_lock_type';
  static const _secretHashKey = 'app_lock_secret_hash';
  static const _hashVersionPrefix = 'v2';
  static const _hashRounds = 2048;

  Future<SharedPreferences?> _safePrefs() async {
    try {
      return await SharedPreferences.getInstance();
    } catch (_) {
      return null;
    }
  }

  Future<AppLockConfig> loadConfig() async {
    final prefs = await _safePrefs();
    final enabled = prefs?.getBool(_enabledKey) ?? false;
    final type = prefs?.getString(_typeKey) ?? typeNone;
    final secretHash = prefs?.getString(_secretHashKey);

    // If type was legacy biometric or invalid, clean up and return disabled
    if (type == 'biometric' || (type != typePin && type != typePattern)) {
      if (enabled) {
        await prefs?.setBool(_enabledKey, false);
        await prefs?.setString(_typeKey, typeNone);
        await prefs?.remove(_secretHashKey);
      }
      return const AppLockConfig(
        enabled: false,
        type: typeNone,
        secretHash: null,
      );
    }

    // Require valid secret hash if enabled
    final isEffectivelyEnabled =
        enabled && secretHash != null && secretHash.isNotEmpty;

    return AppLockConfig(
      enabled: isEffectivelyEnabled,
      type: isEffectivelyEnabled ? type : typeNone,
      secretHash: secretHash,
    );
  }

  Future<void> disableLock() async {
    final prefs = await _safePrefs();
    if (prefs == null) return;
    await prefs.setBool(_enabledKey, false);
    await prefs.setString(_typeKey, typeNone);
    await prefs.remove(_secretHashKey);
  }

  Future<void> setPinLock(String pin) async {
    final prefs = await _safePrefs();
    if (prefs == null) return;
    final cleanPin = pin.trim();
    await prefs.setBool(_enabledKey, true);
    await prefs.setString(_typeKey, typePin);
    await prefs.setString(_secretHashKey, _buildSecretHash(cleanPin));
  }

  Future<void> setPatternLock(String pattern) async {
    final prefs = await _safePrefs();
    if (prefs == null) return;
    final cleanPattern = pattern.trim();
    await prefs.setBool(_enabledKey, true);
    await prefs.setString(_typeKey, typePattern);
    await prefs.setString(_secretHashKey, _buildSecretHash(cleanPattern));
  }

  bool verifySecret({
    required String input,
    required String? secretHash,
  }) {
    if (secretHash == null || secretHash.isEmpty) return false;

    final normalizedInput = input.trim();
    if (secretHash.startsWith('$_hashVersionPrefix:')) {
      final parts = secretHash.split(':');
      if (parts.length != 3) return false;

      final salt = parts[1];
      final storedHash = parts[2];
      return _hashWithSalt(normalizedInput, salt) == storedHash;
    }

    // Backward compatibility for previously stored unsalted hashes.
    return _legacyHash(normalizedInput) == secretHash;
  }

  String _buildSecretHash(String value) {
    final salt = _generateSalt();
    final hash = _hashWithSalt(value, salt);
    return '$_hashVersionPrefix:$salt:$hash';
  }

  String _generateSalt() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return base64UrlEncode(bytes);
  }

  String _hashWithSalt(String value, String salt) {
    var hash = sha256.convert(utf8.encode('$salt:$value')).toString();
    for (var i = 0; i < _hashRounds; i++) {
      hash = sha256.convert(utf8.encode('$hash:$salt')).toString();
    }
    return hash;
  }

  String _legacyHash(String value) {
    return sha256.convert(utf8.encode(value)).toString();
  }
}
