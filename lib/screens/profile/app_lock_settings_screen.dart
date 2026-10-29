import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../providers/app_lock_provider.dart';
import '../../services/app_lock_service.dart';
import '../../widgets/pattern_lock_view.dart';
import '../../widgets/pin_keypad_view.dart';

class AppLockSettingsScreen extends StatefulWidget {
  const AppLockSettingsScreen({super.key});

  @override
  State<AppLockSettingsScreen> createState() => _AppLockSettingsScreenState();
}

class _AppLockSettingsScreenState extends State<AppLockSettingsScreen> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final lock = context.watch<AppLockProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('App Lock'),
        centerTitle: false,
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        children: [
          // Informational Card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFCBD5E1)),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.security_rounded,
                  color: Color(0xFF1E88E5),
                  size: 26,
                ),
                SizedBox(width: 14),
                Expanded(
                  child: Text(
                    'Protect your SkillShare app with a PIN or Pattern lock. Once enabled, the lock screen will appear whenever you open or switch back to the app.',
                    style: TextStyle(
                      color: Color(0xFF334155),
                      fontSize: 14,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Enable / Disable switch tile
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: SwitchListTile.adaptive(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              title: const Text(
                'Enable App Lock',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                  color: Color(0xFF0F172A),
                ),
              ),
              subtitle: Text(
                lock.enabled ? _subtitleForType(lock.type) : 'App lock is disabled',
                style: TextStyle(
                  color: lock.enabled
                      ? const Color(0xFF16A34A)
                      : const Color(0xFF64748B),
                  fontWeight:
                      lock.enabled ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
              value: lock.enabled,
              onChanged: _busy
                  ? null
                  : (enabled) async {
                      if (!enabled) {
                        setState(() => _busy = true);
                        await lock.disable();
                        if (!context.mounted) return;
                        setState(() => _busy = false);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('App lock disabled'),
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                        return;
                      }
                      if (!context.mounted) return;
                      await _chooseAndEnable(context, lock);
                    },
            ),
          ),

          const SizedBox(height: 24),

          // Lock type choices
          const Text(
            'LOCK METHODS',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Color(0xFF64748B),
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 10),

          // PIN Lock option
          _buildMethodCard(
            title: 'PIN Lock (Number)',
            subtitle: 'Unlock with a 4 to 6 digit numeric code',
            icon: Icons.pin_rounded,
            isSelected: lock.enabled && lock.isPin,
            isEnabled: !_busy,
            onTap: () => _setupPinLock(lock),
          ),

          const SizedBox(height: 12),

          // Pattern Lock option
          _buildMethodCard(
            title: 'Pattern Lock',
            subtitle: 'Unlock by connecting dots on a 3x3 grid',
            icon: Icons.gesture_rounded,
            isSelected: lock.enabled && lock.isPattern,
            isEnabled: !_busy,
            onTap: () => _setupPatternLock(lock),
          ),

          const SizedBox(height: 24),

          // Lock Now / Test Lock button
          if (lock.enabled) ...[
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                side: const BorderSide(color: Color(0xFF1D4ED8), width: 1.5),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: () {
                lock.lockNow();
                Navigator.of(context).pop();
              },
              icon: const Icon(Icons.lock_clock_rounded,
                  color: Color(0xFF1D4ED8)),
              label: const Text(
                'Lock App Now (Test Lock Screen)',
                style: TextStyle(
                  color: Color(0xFF1D4ED8),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMethodCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required bool isSelected,
    required bool isEnabled,
    required VoidCallback onTap,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: isSelected ? const Color(0xFFEFF6FF) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color:
              isSelected ? const Color(0xFF3B82F6) : const Color(0xFFE2E8F0),
          width: isSelected ? 1.8 : 1.0,
        ),
      ),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        enabled: isEnabled,
        onTap: onTap,
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: isSelected
                ? const Color(0xFFDBEAFE)
                : const Color(0xFFF1F5F9),
            shape: BoxShape.circle,
          ),
          child: Icon(
            icon,
            color: isSelected
                ? const Color(0xFF1D4ED8)
                : const Color(0xFF475569),
          ),
        ),
        title: Text(
          title,
          style: TextStyle(
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
            fontSize: 15,
            color: const Color(0xFF0F172A),
          ),
        ),
        subtitle: Text(
          subtitle,
          style: const TextStyle(
            color: Color(0xFF64748B),
            fontSize: 13,
          ),
        ),
        trailing: isSelected
            ? const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.check_circle_rounded,
                      color: Color(0xFF2563EB), size: 22),
                  SizedBox(width: 6),
                  Text(
                    'Active',
                    style: TextStyle(
                      color: Color(0xFF2563EB),
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                ],
              )
            : const Icon(Icons.chevron_right_rounded,
                color: Color(0xFF94A3B8)),
      ),
    );
  }

  String _subtitleForType(String type) {
    if (type == AppLockService.typePin) return 'Active: PIN Lock';
    if (type == AppLockService.typePattern) return 'Active: Pattern Lock';
    return 'Off';
  }

  Future<void> _chooseAndEnable(
      BuildContext context, AppLockProvider lock) async {
    final mode = await showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  child: Text(
                    'Select App Lock Method',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                ),
                const Divider(),
                ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: Color(0xFFEFF6FF),
                    child: Icon(Icons.pin_rounded, color: Color(0xFF1D4ED8)),
                  ),
                  title: const Text(
                    'PIN Lock (Number)',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: const Text('Enter a 4-6 digit numeric code'),
                  onTap: () => Navigator.pop(ctx, AppLockService.typePin),
                ),
                ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: Color(0xFFEFF6FF),
                    child:
                        Icon(Icons.gesture_rounded, color: Color(0xFF1D4ED8)),
                  ),
                  title: const Text(
                    'Pattern Lock',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: const Text('Draw a pattern on a 3x3 dot grid'),
                  onTap: () => Navigator.pop(ctx, AppLockService.typePattern),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );

    if (!mounted || mode == null) return;
    if (mode == AppLockService.typePin) {
      await _setupPinLock(lock);
    } else if (mode == AppLockService.typePattern) {
      await _setupPatternLock(lock);
    }
  }

  Future<void> _setupPinLock(AppLockProvider lock) async {
    final pin = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => const _PinSetupSheet(),
    );

    if (pin == null || !mounted) return;

    setState(() => _busy = true);
    await lock.enablePin(pin);
    if (!mounted || !context.mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('PIN lock enabled successfully'),
        backgroundColor: Color(0xFF16A34A),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _setupPatternLock(AppLockProvider lock) async {
    final pattern = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => const _PatternSetupSheet(),
    );

    if (pattern == null || !mounted) return;

    setState(() => _busy = true);
    await lock.enablePattern(pattern);
    if (!mounted || !context.mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Pattern lock enabled successfully'),
        backgroundColor: Color(0xFF16A34A),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Interactive PIN Setup Modal Sheet
// ---------------------------------------------------------------------------
class _PinSetupSheet extends StatefulWidget {
  const _PinSetupSheet();

  @override
  State<_PinSetupSheet> createState() => _PinSetupSheetState();
}

class _PinSetupSheetState extends State<_PinSetupSheet> {
  final GlobalKey<PinKeypadViewState> _keypadKey =
      GlobalKey<PinKeypadViewState>();

  int _step = 1; // 1 = First entry, 2 = Confirm
  String _firstPin = '';
  String? _errorMessage;
  bool _isError = false;

  void _onPinComplete(String pin) {
    if (_step == 1) {
      setState(() {
        _firstPin = pin;
        _step = 2;
        _errorMessage = null;
        _isError = false;
      });
      _keypadKey.currentState?.clear();
    } else {
      if (pin == _firstPin) {
        Navigator.pop(context, pin);
      } else {
        HapticFeedback.heavyImpact();
        setState(() {
          _isError = true;
          _errorMessage = 'PINs did not match. Please start over.';
        });
        Future.delayed(const Duration(milliseconds: 900), () {
          if (mounted) {
            setState(() {
              _step = 1;
              _firstPin = '';
              _isError = false;
              _errorMessage = null;
            });
            _keypadKey.currentState?.clear();
          }
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _step == 1 ? 'Set New PIN' : 'Confirm Your PIN',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF0F172A),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              _step == 1
                  ? 'Enter a 4-digit PIN for app lock'
                  : 'Re-enter the same 4-digit PIN to confirm',
              style: const TextStyle(color: Color(0xFF64748B), fontSize: 14),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 24,
              child: _errorMessage != null
                  ? Text(
                      _errorMessage!,
                      style: const TextStyle(
                        color: Color(0xFFE53935),
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    )
                  : null,
            ),
            PinKeypadView(
              key: _keypadKey,
              pinLength: 4,
              isError: _isError,
              onComplete: _onPinComplete,
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Interactive Pattern Setup Modal Sheet
// ---------------------------------------------------------------------------
class _PatternSetupSheet extends StatefulWidget {
  const _PatternSetupSheet();

  @override
  State<_PatternSetupSheet> createState() => _PatternSetupSheetState();
}

class _PatternSetupSheetState extends State<_PatternSetupSheet> {
  final GlobalKey<PatternLockViewState> _patternKey =
      GlobalKey<PatternLockViewState>();

  int _step = 1; // 1 = First entry, 2 = Confirm
  String _firstPattern = '';
  String? _errorMessage;
  bool _isError = false;

  void _onPatternComplete(String pattern) {
    if (_step == 1) {
      setState(() {
        _firstPattern = pattern;
        _step = 2;
        _errorMessage = null;
        _isError = false;
      });
      _patternKey.currentState?.clear();
    } else {
      if (pattern == _firstPattern) {
        Navigator.pop(context, pattern);
      } else {
        HapticFeedback.heavyImpact();
        setState(() {
          _isError = true;
          _errorMessage = 'Patterns did not match. Please start over.';
        });
        Future.delayed(const Duration(milliseconds: 900), () {
          if (mounted) {
            setState(() {
              _step = 1;
              _firstPattern = '';
              _isError = false;
              _errorMessage = null;
            });
            _patternKey.currentState?.clear();
          }
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _step == 1 ? 'Draw Unlock Pattern' : 'Confirm Unlock Pattern',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF0F172A),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              _step == 1
                  ? 'Connect at least 4 dots to create your pattern'
                  : 'Draw the pattern again to confirm',
              style: const TextStyle(color: Color(0xFF64748B), fontSize: 14),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 24,
              child: _errorMessage != null
                  ? Text(
                      _errorMessage!,
                      style: const TextStyle(
                        color: Color(0xFFE53935),
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    )
                  : null,
            ),
            PatternLockView(
              key: _patternKey,
              dimension: 280,
              minDots: 4,
              isError: _isError,
              onStart: () {
                if (_errorMessage != null) {
                  setState(() {
                    _isError = false;
                    _errorMessage = null;
                  });
                }
              },
              onComplete: _onPatternComplete,
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}
