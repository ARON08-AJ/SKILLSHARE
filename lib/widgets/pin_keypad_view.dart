import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class PinKeypadView extends StatefulWidget {
  const PinKeypadView({
    super.key,
    required this.onComplete,
    this.pinLength = 4,
    this.maxDigits = 6,
    this.isError = false,
    this.primaryColor = const Color(0xFF1E88E5),
    this.errorColor = const Color(0xFFE53935),
    this.onChanged,
  });

  final ValueChanged<String> onComplete;
  final int pinLength;
  final int maxDigits;
  final bool isError;
  final Color primaryColor;
  final Color errorColor;
  final ValueChanged<String>? onChanged;

  @override
  State<PinKeypadView> createState() => PinKeypadViewState();
}

class PinKeypadViewState extends State<PinKeypadView>
    with SingleTickerProviderStateMixin {
  final List<String> _digits = [];
  late AnimationController _shakeCtrl;

  @override
  void initState() {
    super.initState();
    _shakeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
  }

  @override
  void didUpdateWidget(covariant PinKeypadView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isError && !oldWidget.isError) {
      _triggerShake();
    }
  }

  @override
  void dispose() {
    _shakeCtrl.dispose();
    super.dispose();
  }

  void _triggerShake() {
    HapticFeedback.mediumImpact();
    _shakeCtrl.forward(from: 0.0).then((_) {
      _shakeCtrl.reverse();
    });
  }

  void clear() {
    if (mounted) {
      setState(() {
        _digits.clear();
      });
      widget.onChanged?.call('');
    }
  }

  void _onKeyPress(String key) {
    HapticFeedback.lightImpact();
    setState(() {
      if (widget.isError || _digits.length >= widget.pinLength) {
        _digits.clear();
      }
      _digits.add(key);
    });

    final currentPin = _digits.join();
    widget.onChanged?.call(currentPin);

    // Auto-complete if reached pinLength
    if (_digits.length == widget.pinLength) {
      widget.onComplete(currentPin);
    }
  }

  void _onBackspace() {
    if (_digits.isEmpty) return;
    HapticFeedback.lightImpact();
    setState(() {
      _digits.removeLast();
    });
    final currentPin = _digits.join();
    widget.onChanged?.call(currentPin);
  }

  void _onClear() {
    if (_digits.isEmpty) return;
    HapticFeedback.lightImpact();
    clear();
  }

  @override
  Widget build(BuildContext context) {
    final activeColor = widget.isError ? widget.errorColor : widget.primaryColor;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // PIN dot indicators with shake animation
        AnimatedBuilder(
          animation: _shakeCtrl,
          builder: (context, child) {
            final offset = sin(_shakeCtrl.value * pi * 4) * 10;
            return Transform.translate(
              offset: Offset(offset, 0),
              child: child,
            );
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(widget.pinLength, (index) {
                final isFilled = index < _digits.length;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  margin: const EdgeInsets.symmetric(horizontal: 10),
                  width: isFilled ? 18 : 16,
                  height: isFilled ? 18 : 16,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isFilled ? activeColor : Colors.transparent,
                    border: Border.all(
                      color: isFilled
                          ? activeColor
                          : (widget.isError
                              ? widget.errorColor
                              : const Color(0xFFCBD5E1)),
                      width: 2.0,
                    ),
                    boxShadow: isFilled
                        ? [
                            BoxShadow(
                              color: activeColor.withValues(alpha: 0.3),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            )
                          ]
                        : null,
                  ),
                );
              }),
            ),
          ),
        ),

        const SizedBox(height: 12),

        // Keypad grid
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 300),
          child: Column(
            children: [
              _buildRow(['1', '2', '3']),
              const SizedBox(height: 14),
              _buildRow(['4', '5', '6']),
              const SizedBox(height: 14),
              _buildRow(['7', '8', '9']),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildActionButton(
                    icon: Icons.clear_rounded,
                    label: 'Clear',
                    onTap: _digits.isNotEmpty ? _onClear : null,
                  ),
                  _buildNumberButton('0'),
                  _buildActionButton(
                    icon: Icons.backspace_outlined,
                    label: 'Delete',
                    onTap: _digits.isNotEmpty ? _onBackspace : null,
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildRow(List<String> keys) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: keys.map((key) => _buildNumberButton(key)).toList(),
    );
  }

  Widget _buildNumberButton(String number) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _onKeyPress(number),
        customBorder: const CircleBorder(),
        splashColor: widget.primaryColor.withValues(alpha: 0.15),
        highlightColor: widget.primaryColor.withValues(alpha: 0.08),
        child: Container(
          width: 68,
          height: 68,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFFF8FAFC),
            border: Border.all(color: const Color(0xFFE2E8F0), width: 1.2),
            boxShadow: const [
              BoxShadow(
                color: Color(0x0A000000),
                blurRadius: 4,
                offset: Offset(0, 2),
              ),
            ],
          ),
          alignment: Alignment.center,
          child: Text(
            number,
            style: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w600,
              color: Color(0xFF0F172A),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
  }) {
    final isEnabled = onTap != null;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Container(
          width: 68,
          height: 68,
          alignment: Alignment.center,
          child: Icon(
            icon,
            size: 26,
            color: isEnabled
                ? const Color(0xFF475569)
                : const Color(0xFFCBD5E1),
          ),
        ),
      ),
    );
  }
}
