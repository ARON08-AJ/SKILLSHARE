import 'package:flutter/material.dart';

/// Centralized animated dialogs used across the app.
class AppDialog {
  AppDialog._();

  static Future<void> success(
    BuildContext context,
    String message, {
    String? title,
    String buttonText = 'Great!',
    VoidCallback? onDismiss,
  }) {
    return _show(
      context,
      title: title ?? 'Success',
      message: message,
      buttonText: buttonText,
      gradientColors: const [Color(0xFF43A047), Color(0xFF00ACC1)],
      icon: Icons.check_circle_rounded,
      onDismiss: onDismiss,
    );
  }

  static Future<void> error(
    BuildContext context,
    String message, {
    String? title,
    String? detail,
    String buttonText = 'Got it',
  }) {
    final body =
        detail != null && detail.isNotEmpty ? '$message\n\n$detail' : message;
    return _show(
      context,
      title: title ?? 'Oops!',
      message: body,
      buttonText: buttonText,
      gradientColors: const [Color(0xFFE53935), Color(0xFFFF6F61)],
      icon: Icons.error_outline_rounded,
    );
  }

  static Future<void> info(
    BuildContext context,
    String message, {
    String? title,
    String buttonText = 'OK',
  }) {
    return _show(
      context,
      title: title ?? 'Heads up',
      message: message,
      buttonText: buttonText,
      gradientColors: const [Color(0xFF0288D1), Color(0xFF26C6DA)],
      icon: Icons.info_outline_rounded,
    );
  }

  static Future<void> warning(
    BuildContext context,
    String message, {
    String? title,
    String buttonText = 'Understood',
    VoidCallback? onDismiss,
  }) {
    return _show(
      context,
      title: title ?? 'Attention Required',
      message: message,
      buttonText: buttonText,
      gradientColors: const [Color(0xFFF57C00), Color(0xFFFFB300)],
      icon: Icons.warning_amber_rounded,
      onDismiss: onDismiss,
    );
  }

  static Future<bool?> confirm(
    BuildContext context, {
    required String title,
    required String message,
    required String confirmText,
    String cancelText = 'Cancel',
    required List<Color> gradientColors,
    required IconData icon,
  }) {
    return showDialog<bool>(
      context: context,
      barrierColor: Colors.black54,
      builder: (ctx) => TweenAnimationBuilder<double>(
        tween: Tween(begin: 0.82, end: 1.0),
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutBack,
        builder: (_, scale, child) =>
            Transform.scale(scale: scale, child: child),
        child: _DialogShell(
          gradientColors: gradientColors,
          header: _DialogHeader(
            title: title,
            icon: icon,
            gradientColors: gradientColors,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _DialogBody(message: message, gradientColors: gradientColors),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          backgroundColor: const Color(0xFFF8FAFC),
                          foregroundColor: const Color(0xFF475569),
                          side: const BorderSide(
                            color: Color(0xFFCBD5E1),
                            width: 1.2,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 13),
                        ),
                        onPressed: () => Navigator.of(ctx).pop(false),
                        child: Text(
                          cancelText,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _GradientButton(
                        label: confirmText,
                        gradientColors: gradientColors,
                        onPressed: () => Navigator.of(ctx).pop(true),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Future<void> _show(
    BuildContext context, {
    required String title,
    required String message,
    required String buttonText,
    required List<Color> gradientColors,
    required IconData icon,
    VoidCallback? onDismiss,
  }) {
    return showDialog<void>(
      context: context,
      barrierColor: Colors.black54,
      builder: (ctx) => TweenAnimationBuilder<double>(
        tween: Tween(begin: 0.82, end: 1.0),
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutBack,
        builder: (_, scale, child) =>
            Transform.scale(scale: scale, child: child),
        child: _DialogShell(
          gradientColors: gradientColors,
          header: _DialogHeader(
            title: title,
            icon: icon,
            gradientColors: gradientColors,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _DialogBody(message: message, gradientColors: gradientColors),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                child: SizedBox(
                  width: double.infinity,
                  child: _GradientButton(
                    label: buttonText,
                    gradientColors: gradientColors,
                    onPressed: () {
                      Navigator.of(ctx).pop();
                      onDismiss?.call();
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DialogShell extends StatelessWidget {
  const _DialogShell({
    required this.gradientColors,
    required this.header,
    required this.child,
  });

  final List<Color> gradientColors;
  final Widget header;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: const Color(0xFFE2E8F0), width: 1.2),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.12),
                blurRadius: 36,
                offset: const Offset(0, 16),
              ),
              BoxShadow(
                color: gradientColors.first.withValues(alpha: 0.08),
                blurRadius: 20,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [header, child],
            ),
          ),
        ),
      ),
    );
  }
}

class _DialogHeader extends StatelessWidget {
  const _DialogHeader({
    required this.title,
    required this.icon,
    required this.gradientColors,
  });

  final String title;
  final IconData icon;
  final List<Color> gradientColors;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 8),
      color: Colors.white,
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  gradientColors.first.withValues(alpha: 0.14),
                  gradientColors.last.withValues(alpha: 0.08),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              shape: BoxShape.circle,
              border: Border.all(
                color: gradientColors.first.withValues(alpha: 0.28),
                width: 1.5,
              ),
            ),
            child: Icon(icon, color: gradientColors.first, size: 30),
          ),
          const SizedBox(height: 14),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFF1E293B),
              fontSize: 20,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.2,
            ),
          ),
        ],
      ),
    );
  }
}

class _DialogBody extends StatelessWidget {
  const _DialogBody({
    required this.message,
    required this.gradientColors,
  });

  final String message;
  final List<Color> gradientColors;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(24, 6, 24, 20),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontSize: 14.5,
          color: Color(0xFF475569),
          height: 1.55,
        ),
      ),
    );
  }
}

class _GradientButton extends StatelessWidget {
  const _GradientButton({
    required this.label,
    required this.gradientColors,
    required this.onPressed,
  });

  final String label;
  final List<Color> gradientColors;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: gradientColors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: gradientColors.first.withValues(alpha: 0.32),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          foregroundColor: Colors.white,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          padding: const EdgeInsets.symmetric(vertical: 13),
          elevation: 0,
        ),
        onPressed: onPressed,
        child: Text(
          label,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
        ),
      ),
    );
  }
}
