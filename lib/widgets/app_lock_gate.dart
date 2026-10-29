import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../providers/app_lock_provider.dart';
import '../services/app_lock_service.dart';
import 'pattern_lock_view.dart';
import 'pin_keypad_view.dart';

class AppLockGate extends StatefulWidget {
  const AppLockGate({super.key, required this.child});

  final Widget child;

  @override
  State<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends State<AppLockGate>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final provider = context.read<AppLockProvider>();
      if (!provider.initialized) {
        provider.initialize();
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted) return;
    final provider = context.read<AppLockProvider>();
    if (!provider.enabled) return;

    // Lock whenever app leaves the foreground (minimized, app switcher, home)
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.inactive) {
      provider.lockNow();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppLockProvider>(
      builder: (context, lock, _) {
        final isLocked = lock.requiresUnlock;

        return Stack(
          children: [
            // Keep app child offstage while locked so zero content or touch leaks
            Offstage(
              offstage: isLocked,
              child: widget.child,
            ),
            if (isLocked)
              Positioned.fill(
                child: PopScope(
                  canPop: false,
                  child: AppLockFullScreen(lock: lock),
                ),
              ),
          ],
        );
      },
    );
  }
}

class AppLockFullScreen extends StatefulWidget {
  const AppLockFullScreen({super.key, required this.lock});

  final AppLockProvider lock;

  @override
  State<AppLockFullScreen> createState() => _AppLockFullScreenState();
}

class _AppLockFullScreenState extends State<AppLockFullScreen> {
  final GlobalKey<PatternLockViewState> _patternKey =
      GlobalKey<PatternLockViewState>();
  final GlobalKey<PinKeypadViewState> _pinKey =
      GlobalKey<PinKeypadViewState>();

  String? _errorMessage;
  bool _isError = false;

  void _onPatternSubmit(String pattern) {
    final ok = widget.lock.tryUnlockWithSecret(pattern);
    if (!ok) {
      HapticFeedback.heavyImpact();
      setState(() {
        _isError = true;
        _errorMessage = 'Incorrect pattern. Please try again.';
      });
      Future.delayed(const Duration(milliseconds: 800), () {
        if (mounted) {
          setState(() {
            _isError = false;
            _errorMessage = null;
          });
          _patternKey.currentState?.clear();
        }
      });
    } else {
      setState(() {
        _isError = false;
        _errorMessage = null;
      });
    }
  }

  void _onPinSubmit(String pin) {
    final ok = widget.lock.tryUnlockWithSecret(pin);
    if (!ok) {
      HapticFeedback.heavyImpact();
      setState(() {
        _isError = true;
        _errorMessage = 'Incorrect PIN. Please try again.';
      });
      Future.delayed(const Duration(milliseconds: 800), () {
        if (mounted) {
          setState(() {
            _isError = false;
            _errorMessage = null;
          });
          _pinKey.currentState?.clear();
        }
      });
    } else {
      setState(() {
        _isError = false;
        _errorMessage = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isPattern = widget.lock.type == AppLockService.typePattern;

    return Material(
      color: Colors.white,
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return Center(
              child: SingleChildScrollView(
                physics: const ClampingScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 380),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Lock icon avatar
                      Container(
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: const Color(0xFFEFF6FF),
                          border: Border.all(
                            color: const Color(0xFFBFDBFE),
                            width: 1.5,
                          ),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x142563EB),
                              blurRadius: 16,
                              offset: Offset(0, 4),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.lock_rounded,
                          size: 34,
                          color: Color(0xFF1D4ED8),
                        ),
                      ),
                      const SizedBox(height: 18),

                      // Title
                      const Text(
                        'SkillShare',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF0F172A),
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: 6),

                      // Instructions
                      Text(
                        isPattern
                            ? 'Draw your pattern to unlock'
                            : 'Enter your PIN to unlock',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF64748B),
                        ),
                      ),
                      const SizedBox(height: 8),

                      // Error message container (fixed height to prevent layout jumps)
                      SizedBox(
                        height: 24,
                        child: _errorMessage != null
                            ? Text(
                                _errorMessage!,
                                style: const TextStyle(
                                  color: Color(0xFFE53935),
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              )
                            : null,
                      ),
                      const SizedBox(height: 12),

                      // Pattern grid or PIN keypad
                      if (isPattern)
                        PatternLockView(
                          key: _patternKey,
                          dimension: 290,
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
                          onComplete: _onPatternSubmit,
                        )
                      else
                        PinKeypadView(
                          key: _pinKey,
                          pinLength: 4,
                          maxDigits: 4,
                          isError: _isError,
                          onChanged: (pin) {
                            if (_errorMessage != null) {
                              setState(() {
                                _isError = false;
                                _errorMessage = null;
                              });
                            }
                          },
                          onComplete: _onPinSubmit,
                        ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
