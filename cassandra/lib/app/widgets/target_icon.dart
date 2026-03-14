import 'dart:math' as math;
import 'package:flutter/material.dart';

/// A filled bullseye target with arrow icon.
class TargetIcon extends StatelessWidget {
  const TargetIcon({super.key, this.size = 28, this.color});

  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _TargetPainter(
          color: color ?? IconTheme.of(context).color ?? Colors.white,
        ),
      ),
    );
  }
}

class _TargetPainter extends CustomPainter {
  const _TargetPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final r = size.width / 2;

    final fill = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final sw = size.width * 0.10; // ring thickness

    final ring = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = sw;

    // Outer ring
    canvas.drawCircle(Offset(cx, cy), r * 0.88, ring);
    // Middle ring
    canvas.drawCircle(Offset(cx, cy), r * 0.58, ring);
    // Inner filled circle
    canvas.drawCircle(Offset(cx, cy), r * 0.22, fill);

    // Arrow shaft — thick filled line from top-right into center
    final arrowPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.10
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final tipX = cx + r * 0.05;
    final tipY = cy - r * 0.05;
    final tailX = cx + r * 0.78;
    final tailY = cy - r * 0.78;

    canvas.drawLine(Offset(tailX, tailY), Offset(tipX, tipY), arrowPaint);

    // Arrow head — filled triangle
    const headAngle = 0.45;
    final shaftAngle = math.atan2(tailY - tipY, tailX - tipX);
    final headLen = r * 0.35;

    final h1x = tipX + headLen * math.cos(shaftAngle + headAngle);
    final h1y = tipY + headLen * math.sin(shaftAngle + headAngle);
    final h2x = tipX + headLen * math.cos(shaftAngle - headAngle);
    final h2y = tipY + headLen * math.sin(shaftAngle - headAngle);

    final headPath = Path()
      ..moveTo(tipX, tipY)
      ..lineTo(h1x, h1y)
      ..lineTo(h2x, h2y)
      ..close();
    canvas.drawPath(headPath, fill);
  }

  @override
  bool shouldRepaint(covariant _TargetPainter oldDelegate) =>
      color != oldDelegate.color;
}
