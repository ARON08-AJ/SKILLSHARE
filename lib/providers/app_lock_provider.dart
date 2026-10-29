import 'package:flutter/foundation.dart';

import '../services/app_lock_service.dart';

class AppLockProvider extends ChangeNotifier {
  AppLockProvider({
    AppLockService? service,
    AppLockConfig? initialConfig,
  }) : _service = service ?? AppLockService() {
    if (initialConfig != null) {
      _enabled = initialConfig.enabled;
      _type = initialConfig.type;
      _secretHash = initialConfig.secretHash;
      _sessionUnlocked = !_enabled;
      _initialized = true;
    }
  }

  final AppLockService _service;

  bool _initialized = false;
  bool _enabled = false;
  String _type = AppLockService.typeNone;
  String? _secretHash;
  bool _sessionUnlocked = false;

  bool get initialized => _initialized;
  bool get enabled => _enabled;
  String get type => _type;
  bool get isPin => _type == AppLockService.typePin;
  bool get isPattern => _type == AppLockService.typePattern;
  bool get requiresUnlock =>
      _initialized ? (_enabled && !_sessionUnlocked) : false;

  Future<void> initialize() async {
    final config = await _service.loadConfig();
    _enabled = config.enabled;
    _type = config.type;
    _secretHash = config.secretHash;
    if (!_initialized) {
      _sessionUnlocked = !_enabled;
    } else if (!_enabled) {
      _sessionUnlocked = true;
    }
    _initialized = true;
    notifyListeners();
  }

  Future<void> refresh() async {
    final config = await _service.loadConfig();
    _enabled = config.enabled;
    _type = config.type;
    _secretHash = config.secretHash;
    if (!_enabled) {
      _sessionUnlocked = true;
    }
    notifyListeners();
  }

  void lockNow() {
    if (!_enabled) return;
    if (_sessionUnlocked) {
      _sessionUnlocked = false;
      notifyListeners();
    }
  }

  Future<void> disable() async {
    await _service.disableLock();
    _enabled = false;
    _type = AppLockService.typeNone;
    _secretHash = null;
    _sessionUnlocked = true;
    notifyListeners();
  }

  Future<void> enablePin(String pin) async {
    await _service.setPinLock(pin);
    final config = await _service.loadConfig();
    _enabled = true;
    _type = AppLockService.typePin;
    _secretHash = config.secretHash;
    _sessionUnlocked = true;
    notifyListeners();
  }

  Future<void> enablePattern(String pattern) async {
    await _service.setPatternLock(pattern);
    final config = await _service.loadConfig();
    _enabled = true;
    _type = AppLockService.typePattern;
    _secretHash = config.secretHash;
    _sessionUnlocked = true;
    notifyListeners();
  }

  bool tryUnlockWithSecret(String value) {
    final ok = _service.verifySecret(input: value, secretHash: _secretHash);
    if (ok) {
      _sessionUnlocked = true;
      notifyListeners();
    }
    return ok;
  }
}
