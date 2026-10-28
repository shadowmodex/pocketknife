import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// Pocketknife brand mark — a deep-navy rounded tile with a stylised blade.
/// Painted so it works fully offline with no image asset.
class BrandLogo extends StatelessWidget {
  final double size;
  const BrandLogo({super.key, this.size = 84});

  @override
  Widget build(BuildContext context) {
    final radius = size * 0.28;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1E2E4A), AppColors.primary],
        ),
        borderRadius: BorderRadius.circular(radius),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.32),
            blurRadius: size * 0.28,
            offset: Offset(0, size * 0.12),
          ),
        ],
      ),
      child: CustomPaint(painter: _BladePainter(), size: Size(size, size)),
    );
  }
}

class _BladePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final pivot = Offset(w * 0.30, h * 0.70);

    // Blade — a leaf shape from the pivot up to the top-right.
    final blade = Path()
      ..moveTo(pivot.dx, pivot.dy)
      ..quadraticBezierTo(w * 0.42, h * 0.20, w * 0.76, h * 0.26)
      ..quadraticBezierTo(w * 0.60, h * 0.44, pivot.dx, pivot.dy)
      ..close();
    canvas.drawPath(blade, Paint()..color = Colors.white);

    // Accent spine along the blade's edge.
    final spine = Paint()
      ..color = AppColors.accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.045
      ..strokeCap = StrokeCap.round;
    final spinePath = Path()
      ..moveTo(pivot.dx, pivot.dy)
      ..quadraticBezierTo(w * 0.42, h * 0.20, w * 0.76, h * 0.26);
    canvas.drawPath(spinePath, spine);

    // Pivot rivet.
    canvas.drawCircle(pivot, w * 0.07, Paint()..color = AppColors.accent);
    canvas.drawCircle(pivot, w * 0.028, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
