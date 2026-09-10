import 'package:flutter/material.dart';

/// Shows an animated center-screen popup instead of a bottom snackbar.
///
/// Usage:
/// ```dart
/// AppPopup.show(context, message: 'Item added to cart!', type: PopupType.success);
/// ```
enum PopupType { success, error, info, warning }

class AppPopup {
  static OverlayEntry? _currentEntry;

  static void _safeRemove(OverlayEntry? entry) {
    if (entry == null) return;
    try {
      entry.remove();
    } catch (_) {
      // Entry may already be detached; ignore repeated remove calls.
    }
  }

  static void show(
    BuildContext context, {
    required String message,
    PopupType type = PopupType.info,
    Duration duration = const Duration(seconds: 3),
    IconData? icon,
  }) {
    // Remove any existing popup
    _safeRemove(_currentEntry);
    _currentEntry = null;

    final overlay = Overlay.of(context, rootOverlay: true);

    late OverlayEntry entry;
    var dismissed = false;

    void dismissOnce() {
      if (dismissed) return;
      dismissed = true;
      _safeRemove(entry);
      if (_currentEntry == entry) _currentEntry = null;
    }

    entry = OverlayEntry(
      builder: (_) => _AnimatedPopupWidget(
        message: message,
        type: type,
        icon: icon,
        duration: duration,
        onDismiss: dismissOnce,
      ),
    );

    _currentEntry = entry;
    overlay.insert(entry);
  }

  static void dismiss() {
    _safeRemove(_currentEntry);
    _currentEntry = null;
  }
}

class _AnimatedPopupWidget extends StatefulWidget {
  final String message;
  final PopupType type;
  final IconData? icon;
  final Duration duration;
  final VoidCallback onDismiss;

  const _AnimatedPopupWidget({
    required this.message,
    required this.type,
    this.icon,
    required this.duration,
    required this.onDismiss,
  });

  @override
  State<_AnimatedPopupWidget> createState() => _AnimatedPopupWidgetState();
}

class _AnimatedPopupWidgetState extends State<_AnimatedPopupWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _opacityAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );

    _scaleAnimation = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.elasticOut),
    );
    _opacityAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeIn),
    );

    _controller.forward();

    // Auto dismiss after duration
    Future.delayed(widget.duration, () {
      if (mounted) {
        _controller.reverse().then((_) => widget.onDismiss());
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Color get _accentColor {
    switch (widget.type) {
      case PopupType.success:
        return const Color(0xFF10B981);
      case PopupType.error:
        return const Color(0xFFEF4444);
      case PopupType.warning:
        return const Color(0xFFF59E0B);
      case PopupType.info:
        return const Color(0xFF3B82F6);
    }
  }

  IconData get _defaultIcon {
    switch (widget.type) {
      case PopupType.success:
        return Icons.check_circle_rounded;
      case PopupType.error:
        return Icons.error_outline_rounded;
      case PopupType.warning:
        return Icons.warning_amber_rounded;
      case PopupType.info:
        return Icons.info_outline_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: GestureDetector(
        onTap: () => _controller.reverse().then((_) => widget.onDismiss()),
        behavior: HitTestBehavior.translucent,
        child: Center(
          child: AnimatedBuilder(
            animation: _controller,
            builder: (_, child) => Opacity(
              opacity: _opacityAnimation.value,
              child: Transform.scale(
                scale: _scaleAnimation.value,
                child: child,
              ),
            ),
            child: GestureDetector(
              onTap: () {}, // Prevent tapping inside from dismissing
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 28),
                constraints: const BoxConstraints(maxWidth: 420),
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 16,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(
                    color: const Color(0xFFE2E8F0),
                    width: 1.2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.12),
                      blurRadius: 32,
                      offset: const Offset(0, 12),
                    ),
                    BoxShadow(
                      color: _accentColor.withValues(alpha: 0.12),
                      blurRadius: 18,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: _accentColor.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: _accentColor.withValues(alpha: 0.28),
                          width: 1.2,
                        ),
                      ),
                      child: Icon(
                        widget.icon ?? _defaultIcon,
                        color: _accentColor,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Flexible(
                      child: Text(
                        widget.message,
                        style: const TextStyle(
                          color: Color(0xFF1E293B),
                          fontSize: 14.5,
                          fontWeight: FontWeight.w600,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
