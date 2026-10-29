import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class PatternLockView extends StatefulWidget {
  const PatternLockView({
    super.key,
    required this.onComplete,
    this.minDots = 4,
    this.dimension = 280,
    this.isError = false,
    this.onStart,
    this.primaryColor = const Color(0xFF1E88E5),
    this.errorColor = const Color(0xFFE53935),
    this.dotColor = const Color(0xFFCBD5E1),
  });

  final ValueChanged<String> onComplete;
  final int minDots;
  final double dimension;
  final bool isError;
  final VoidCallback? onStart;
  final Color primaryColor;
  final Color errorColor;
  final Color dotColor;

  @override
  State<PatternLockView> createState() => PatternLockViewState();
}

class PatternLockViewState extends State<PatternLockView> {
  final List<int> _selectedDots = [];
  Offset? _currentDragPosition;
  bool _internalError = false;

  void clear() {
    if (mounted) {
      setState(() {
        _selectedDots.clear();
        _currentDragPosition = null;
        _internalError = false;
      });
    }
  }

  Offset _getDotCenter(int dotNumber, double size) {
    // dotNumber is 1 to 9
    // row: 0, 1, 2; col: 0, 1, 2
    final row = (dotNumber - 1) ~/ 3;
    final col = (dotNumber - 1) % 3;
    final cell = size / 3;
    return Offset(
      col * cell + cell / 2,
      row * cell + cell / 2,
    );
  }

  int? _findHitDot(Offset touchPoint, double size) {
    final cell = size / 3;
    final hitRadius = cell * 0.42;

    for (int i = 1; i <= 9; i++) {
      final center = _getDotCenter(i, size);
      final distance = (touchPoint - center).distance;
      if (distance <= hitRadius) {
        return i;
      }
    }
    return null;
  }

  int? _getIntermediateDot(int a, int b) {
    final pair = a < b ? '$a-$b' : '$b-$a';
    switch (pair) {
      case '1-3':
        return 2;
      case '4-6':
        return 5;
      case '7-9':
        return 8;
      case '1-7':
        return 4;
      case '2-8':
        return 5;
      case '3-9':
        return 6;
      case '1-9':
        return 5;
      case '3-7':
        return 5;
      default:
        return null;
    }
  }

  void _handleTouch(Offset localPosition) {
    final dot = _findHitDot(localPosition, widget.dimension);
    if (dot != null && !_selectedDots.contains(dot)) {
      if (_selectedDots.isNotEmpty) {
        final lastDot = _selectedDots.last;
        final intermediate = _getIntermediateDot(lastDot, dot);
        if (intermediate != null && !_selectedDots.contains(intermediate)) {
          _selectedDots.add(intermediate);
          HapticFeedback.lightImpact();
        }
      }
      _selectedDots.add(dot);
      HapticFeedback.lightImpact();
    }
    setState(() {
      _currentDragPosition = localPosition;
    });
  }

  void _onPanStart(DragStartDetails details) {
    widget.onStart?.call();
    setState(() {
      _selectedDots.clear();
      _internalError = false;
      _currentDragPosition = details.localPosition;
    });
    _handleTouch(details.localPosition);
  }

  void _onPanUpdate(DragUpdateDetails details) {
    _handleTouch(details.localPosition);
  }

  void _onPanEnd(DragEndDetails details) {
    setState(() {
      _currentDragPosition = null;
    });

    if (_selectedDots.isEmpty) return;

    if (_selectedDots.length < widget.minDots) {
      HapticFeedback.mediumImpact();
      setState(() {
        _internalError = true;
      });
      Future.delayed(const Duration(milliseconds: 700), () {
        if (mounted && _internalError) {
          clear();
        }
      });
      return;
    }

    final pattern = _selectedDots.join();
    widget.onComplete(pattern);
  }

  @override
  Widget build(BuildContext context) {
    final effectiveError = widget.isError || _internalError;
    final activeColor = effectiveError ? widget.errorColor : widget.primaryColor;

    return Center(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: _onPanStart,
        onPanUpdate: _onPanUpdate,
        onPanEnd: _onPanEnd,
        child: SizedBox(
          width: widget.dimension,
          height: widget.dimension,
          child: CustomPaint(
            painter: _PatternPainter(
              selectedDots: _selectedDots,
              currentDragPosition: _currentDragPosition,
              activeColor: activeColor,
              dotColor: widget.dotColor,
              isError: effectiveError,
              getDotCenter: (dot) => _getDotCenter(dot, widget.dimension),
            ),
          ),
        ),
      ),
    );
  }
}

class _PatternPainter extends CustomPainter {
  _PatternPainter({
    required this.selectedDots,
    required this.currentDragPosition,
    required this.activeColor,
    required this.dotColor,
    required this.isError,
    required this.getDotCenter,
  });

  final List<int> selectedDots;
  final Offset? currentDragPosition;
  final Color activeColor;
  final Color dotColor;
  final bool isError;
  final Offset Function(int dot) getDotCenter;

  @override
  void paint(Canvas canvas, Size size) {
    // 1. Draw connecting lines between selected dots
    if (selectedDots.length > 1) {
      final linePaint = Paint()
        ..color = activeColor.withValues(alpha: 0.8)
        ..strokeWidth = 4.0
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;

      final path = Path();
      final start = getDotCenter(selectedDots.first);
      path.moveTo(start.dx, start.dy);

      for (int i = 1; i < selectedDots.length; i++) {
        final p = getDotCenter(selectedDots[i]);
        path.lineTo(p.dx, p.dy);
      }
      canvas.drawPath(path, linePaint);
    }

    // 2. Draw line from last dot to current touch position
    if (selectedDots.isNotEmpty && currentDragPosition != null) {
      final linePaint = Paint()
        ..color = activeColor.withValues(alpha: 0.5)
        ..strokeWidth = 3.5
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;

      final lastCenter = getDotCenter(selectedDots.last);
      canvas.drawLine(lastCenter, currentDragPosition!, linePaint);
    }

    // 3. Draw all 9 dots
    for (int i = 1; i <= 9; i++) {
      final center = getDotCenter(i);
      final isSelected = selectedDots.contains(i);

      if (isSelected) {
        // Outer halo
        final haloPaint = Paint()
          ..color = activeColor.withValues(alpha: 0.2)
          ..style = PaintingStyle.fill;
        canvas.drawCircle(center, 26, haloPaint);

        // Outer ring stroke
        final ringPaint = Paint()
          ..color = activeColor.withValues(alpha: 0.8)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0;
        canvas.drawCircle(center, 26, ringPaint);

        // Solid inner dot
        final innerDotPaint = Paint()
          ..color = activeColor
          ..style = PaintingStyle.fill;
        canvas.drawCircle(center, 8, innerDotPaint);
      } else {
        // Default unselected dot
        final dotPaint = Paint()
          ..color = dotColor
          ..style = PaintingStyle.fill;
        canvas.drawCircle(center, 6, dotPaint);

        // Subtle outer border ring
        final outerRing = Paint()
          ..color = dotColor.withValues(alpha: 0.35)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5;
        canvas.drawCircle(center, 14, outerRing);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _PatternPainter oldDelegate) {
    return true;
  }
}
